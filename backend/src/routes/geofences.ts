import type { FastifyInstance } from "fastify";
import { z } from "zod";
import type { Context } from "../context.ts";
import { badRequest, notFound, parse } from "../http/errors.ts";
import { requireDevice } from "../services/access.ts";
import { MAX_AREAS_PER_DEVICE } from "../services/geofences.ts";
import { scheduleSchema } from "../services/schedule.ts";
import { idParams } from "./devices.ts";

// Arrival areas of the logged user on a device they see (owned or shared): one or more
// circles, notified when the device enters (and optionally leaves) them, always or only in
// some hours of some days (schedule).

const fields = {
	name: z.string().trim().min(1).max(60),
	lat: z.number().min(-90).max(90),
	lon: z.number().min(-180).max(180),
	radius: z.number().int().min(50).max(50000),
	schedule: scheduleSchema.nullable()
};
const newArea = z.strictObject({ ...fields, schedule: fields.schedule.default(null), notifyEnter: z.boolean().default(true), notifyExit: z.boolean().default(false) });
const areaChanges = z.strictObject({ ...fields, notifyEnter: z.boolean(), notifyExit: z.boolean() }).partial();

const COLUMNS = `id, device_id AS "deviceId", name, lat, lon, radius, notify_enter AS "notifyEnter",
	notify_exit AS "notifyExit", schedule, inside, created_at AS "createdAt"`;

export function registerGeofenceRoutes (app: FastifyInstance, ctx: Context): void {
	const { sql } = ctx;

	app.get("/api/devices/:id/geofences", async (request) => {
		const { id } = parse(idParams, request.params);
		await requireDevice(sql, request.auth!.user, id);
		return sql`
			SELECT ${sql.unsafe(COLUMNS)} FROM geofences
			WHERE device_id = ${id} AND user_id = ${request.auth!.user.id} ORDER BY name, id`;
	});

	app.post("/api/devices/:id/geofences", async (request) => {
		const { id } = parse(idParams, request.params);
		const body = parse(newArea, request.body);
		const userId = request.auth!.user.id;
		await requireDevice(sql, request.auth!.user, id);
		const [count] = await sql<{ count: number }[]>`
			SELECT count(*)::int AS count FROM geofences WHERE device_id = ${id} AND user_id = ${userId}`;
		if (count!.count >= MAX_AREAS_PER_DEVICE) throw badRequest(`At most ${MAX_AREAS_PER_DEVICE} areas per device`, "too_many_areas");

		const state = await ctx.geofences.initialState(id, body);
		const [created] = await sql`
			INSERT INTO geofences (user_id, device_id, name, lat, lon, radius, notify_enter, notify_exit, schedule, inside, checked_at)
			VALUES (${userId}, ${id}, ${body.name}, ${body.lat}, ${body.lon}, ${body.radius}, ${body.notifyEnter}, ${body.notifyExit},
				${body.schedule ? sql.json(body.schedule) : null}, ${state.inside}, ${state.checkedAt})
			RETURNING ${sql.unsafe(COLUMNS)}`;
		return created;
	});

	app.patch("/api/geofences/:id", async (request) => {
		const { id } = parse(idParams, request.params);
		const body = parse(areaChanges, request.body);
		const userId = request.auth!.user.id;
		const [current] = await sql<{ device_id: number; lat: number; lon: number; radius: number }[]>`
			SELECT device_id, lat, lon, radius FROM geofences WHERE id = ${id} AND user_id = ${userId}`;
		if (!current) throw notFound("Area not found");
		await requireDevice(sql, request.auth!.user, current.device_id);

		const next = { lat: body.lat ?? current.lat, lon: body.lon ?? current.lon, radius: body.radius ?? current.radius };
		const moved = next.lat !== current.lat || next.lon !== current.lon || next.radius !== current.radius;
		// A moved border starts again from the last position, without notifying
		const state = moved ? await ctx.geofences.initialState(current.device_id, next) : null;
		const [updated] = await sql`
			UPDATE geofences SET
				name = COALESCE(${body.name ?? null}, name),
				lat = ${next.lat}, lon = ${next.lon}, radius = ${next.radius},
				notify_enter = COALESCE(${body.notifyEnter ?? null}, notify_enter),
				notify_exit = COALESCE(${body.notifyExit ?? null}, notify_exit),
				schedule = ${body.schedule === undefined ? sql`schedule` : body.schedule ? sql.json(body.schedule) : null}
				${state ? sql`, inside = ${state.inside}, checked_at = ${state.checkedAt}` : sql``}
			WHERE id = ${id} RETURNING ${sql.unsafe(COLUMNS)}`;
		return updated;
	});

	app.delete("/api/geofences/:id", async (request) => {
		const { id } = parse(idParams, request.params);
		const deleted = await sql`DELETE FROM geofences WHERE id = ${id} AND user_id = ${request.auth!.user.id}`;
		if (deleted.count !== 1) throw notFound("Area not found");
		return { ok: true };
	});
}
