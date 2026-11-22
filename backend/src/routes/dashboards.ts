import type { FastifyInstance } from "fastify";
import { z } from "zod";
import type { Context } from "../context.ts";
import { badRequest, notFound, parse } from "../http/errors.ts";
import { computeWidgets, layoutSchema, MAX_WIDGET_DEVICES, METRICS, period, readLayout, widgetList } from "../services/metrics.ts";
import type { Layout } from "../services/metrics.ts";
import { idParams } from "./devices.ts";
import { areFriends } from "./friends.ts";

// Custom dashboards of a user: name and layout (widgets of the catalog of
// src/services/metrics.ts). The values are computed by /api/dashboards/data from the
// widgets sent, saved or not (the editor shows them before saving), with the access to
// every device checked at every request. One dashboard can be the current one (shown by
// the app in the analysis of every vehicle). A layout can be sent to a friend: only the
// widgets, never the vehicles or their data; the friend uses it with its own vehicles.

export const MAX_DASHBOARDS = 20;
/** Layouts received and not used or declined yet */
export const MAX_RECEIVED = 20;

const name = z.string().trim().min(1).max(60);
const body = z.strictObject({ name, layout: layoutSchema });
const id32 = z.number().int().positive().max(2 ** 31 - 1);

interface Row {
	id: number;
	name: string;
	layout: unknown;
	is_current: boolean;
	updated_at: Date;
}

const present = (row: Row) => ({
	id: row.id, name: row.name, current: row.is_current, layout: readLayout(row.layout), updatedAt: row.updated_at
});

/** The layout without the vehicles of its user: every widget on all the vehicles */
const withoutDevices = (layout: Layout): Layout => ({ ...layout, widgets: layout.widgets.map(widget => ({ ...widget, devices: "all" })) });

export function registerDashboardRoutes (app: FastifyInstance, ctx: Context): void {
	const { sql } = ctx;

	/** New dashboard of a user, within the limit */
	const create = (userId: number, dashboardName: string, layout: Layout) => sql.begin(async tx => {
		await tx`SELECT 1 FROM users WHERE id = ${userId} FOR UPDATE`;
		const [count] = await tx<{ count: number }[]>`SELECT count(*)::int AS count FROM dashboards WHERE user_id = ${userId}`;
		if (count!.count >= MAX_DASHBOARDS) throw badRequest(`At most ${MAX_DASHBOARDS} dashboards`, "too_many_dashboards");
		const [created] = await tx<Row[]>`
			INSERT INTO dashboards (user_id, name, layout) VALUES (${userId}, ${dashboardName}, ${tx.json(layout as never)})
			RETURNING id, name, layout, is_current, updated_at`;
		return created!;
	});

	app.get("/api/dashboards", async (request) => {
		const rows = await sql<Row[]>`
			SELECT id, name, layout, is_current, updated_at FROM dashboards WHERE user_id = ${request.auth!.user.id} ORDER BY id`;
		return rows.map(present);
	});

	app.post("/api/dashboards", async (request) => {
		const value = parse(body, request.body);
		return present(await create(request.auth!.user.id, value.name, value.layout));
	});

	app.put("/api/dashboards/:id", async (request) => {
		const { id } = parse(idParams, request.params);
		const value = parse(body, request.body);
		const [row] = await sql<Row[]>`
			UPDATE dashboards SET name = ${value.name}, layout = ${sql.json(value.layout as never)}, updated_at = now()
			WHERE id = ${id} AND user_id = ${request.auth!.user.id} RETURNING id, name, layout, is_current, updated_at`;
		if (!row) throw notFound("Dashboard not found");
		return present(row);
	});

	/** The current dashboard (at most one per user), or none */
	app.put("/api/dashboards/:id/current", async (request) => {
		const { id } = parse(idParams, request.params);
		const { current } = parse(z.strictObject({ current: z.boolean() }), request.body);
		const userId = request.auth!.user.id;
		const row = await sql.begin(async tx => {
			if (current) await tx`UPDATE dashboards SET is_current = false WHERE user_id = ${userId} AND is_current AND id <> ${id}`;
			const [updated] = await tx<Row[]>`
				UPDATE dashboards SET is_current = ${current} WHERE id = ${id} AND user_id = ${userId}
				RETURNING id, name, layout, is_current, updated_at`;
			if (!updated) throw notFound("Dashboard not found");
			return updated;
		});
		return present(row);
	});

	app.delete("/api/dashboards/:id", async (request) => {
		const { id } = parse(idParams, request.params);
		const deleted = await sql`DELETE FROM dashboards WHERE id = ${id} AND user_id = ${request.auth!.user.id}`;
		if (deleted.count === 0) throw notFound("Dashboard not found");
		return { ok: true };
	});

	/** Values of the widgets: { results: { widgetId: { status, ... } } } */
	app.post("/api/dashboards/data", async (request) => {
		const value = parse(z.strictObject({ period: period.default("30d"), widgets: widgetList.min(1) }), request.body);
		return { results: await computeWidgets(sql, ctx.config.TIMEZONE, request.auth!.user.id, value.period, value.widgets) };
	});

	// --- Layouts sent to friends

	/** Sends the layout to a friend; sent again, the friend gets the new version */
	app.post("/api/dashboards/:id/share", async (request) => {
		const { id } = parse(idParams, request.params);
		const { friendId } = parse(z.strictObject({ friendId: id32 }), request.body);
		const user = request.auth!.user;
		const [dashboard] = await sql<Row[]>`SELECT id, name, layout FROM dashboards WHERE id = ${id} AND user_id = ${user.id}`;
		if (!dashboard) throw notFound("Dashboard not found");
		if (!await areFriends(sql, user.id, friendId)) throw notFound("Friend not found");
		const layout = withoutDevices(readLayout(dashboard.layout));
		await sql.begin(async tx => {
			await tx`SELECT 1 FROM users WHERE id = ${friendId} FOR UPDATE`;
			const [count] = await tx<{ count: number }[]>`
				SELECT count(*)::int AS count FROM dashboard_shares WHERE to_id = ${friendId} AND dashboard_id <> ${id}`;
			if (count!.count >= MAX_RECEIVED) throw badRequest(`At most ${MAX_RECEIVED} layouts waiting`, "too_many_dashboard_shares");
			await tx`
				INSERT INTO dashboard_shares (dashboard_id, from_id, to_id, name, layout)
				VALUES (${id}, ${user.id}, ${friendId}, ${dashboard.name}, ${tx.json(layout as never)})
				ON CONFLICT (dashboard_id, to_id) DO UPDATE SET name = excluded.name, layout = excluded.layout, created_at = now()`;
		});
		ctx.hub.toUser(friendId, { type: "dashboardShare", name: user.name, dashboard: dashboard.name });
		return { ok: true };
	});

	/** Layouts received from friends, waiting */
	app.get("/api/dashboards/shares", async (request) => {
		const rows = await sql<{ id: number; from_name: string; name: string; layout: unknown; created_at: Date }[]>`
			SELECT s.id, u.name AS from_name, s.name, s.layout, s.created_at FROM dashboard_shares s
			JOIN users u ON u.id = s.from_id WHERE s.to_id = ${request.auth!.user.id} AND NOT u.disabled ORDER BY s.id DESC`;
		return rows.map(row => ({ id: row.id, from: row.from_name, name: row.name, layout: readLayout(row.layout), createdAt: row.created_at }));
	});

	/**
	 * Uses a layout received: a new dashboard of the user, every widget on the vehicles
	 * chosen ("all", or the ids of devices owned; for each widget the ones of the kinds of
	 * its metric, all of them when none is)
	 */
	app.post("/api/dashboards/shares/:id/accept", async (request) => {
		const { id } = parse(idParams, request.params);
		const value = parse(z.strictObject({
			name,
			devices: z.union([z.literal("all"), z.array(id32).min(1).max(MAX_WIDGET_DEVICES)])
		}), request.body);
		const userId = request.auth!.user.id;
		const [share] = await sql<{ layout: unknown }[]>`SELECT layout FROM dashboard_shares WHERE id = ${id} AND to_id = ${userId}`;
		if (!share) throw notFound("Layout not found");
		const layout = readLayout(share.layout);
		if (value.devices !== "all") {
			const ids = [...new Set(value.devices)];
			const owned = await sql<{ id: number; kind: string }[]>`
				SELECT d.id, d.kind FROM devices d JOIN device_users du ON du.device_id = d.id
				WHERE du.user_id = ${userId} AND du.role = 'owner' AND d.id = ANY (${ids}) ORDER BY d.id`;
			if (owned.length !== ids.length) throw notFound("Device not found");
			layout.widgets = layout.widgets.map(widget => {
				const kinds: readonly string[] = METRICS[widget.metric].kinds;
				const fitting = owned.filter(device => kinds.includes(device.kind)).map(device => device.id);
				return { ...widget, devices: fitting.length > 0 ? fitting : owned.map(device => device.id) };
			});
		}
		const row = await create(userId, value.name, layout);
		await sql`DELETE FROM dashboard_shares WHERE id = ${id}`;
		return present(row);
	});

	/** Declines a layout received; the friend isn't told */
	app.delete("/api/dashboards/shares/:id", async (request) => {
		const { id } = parse(idParams, request.params);
		const deleted = await sql`DELETE FROM dashboard_shares WHERE id = ${id} AND to_id = ${request.auth!.user.id}`;
		if (deleted.count === 0) throw notFound("Layout not found");
		return { ok: true };
	});
}
