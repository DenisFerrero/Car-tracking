import type { FastifyInstance } from "fastify";
import { z } from "zod";
import type { Context } from "../context.ts";
import { parse } from "../http/errors.ts";
import { requireTracker } from "../services/access.ts";
import { idParams } from "./devices.ts";

// Extra data of a tracker (src/services/extra.ts), for its owner: the latest value of
// every field with its time, and the readings of a period, newest first.

const query = z.strictObject({
	from: z.iso.datetime({ offset: true }).transform(value => new Date(value)).optional(),
	to: z.iso.datetime({ offset: true }).transform(value => new Date(value)).optional(),
	limit: z.coerce.number().int().min(1).max(500).default(100)
});

export function registerExtraRoutes (app: FastifyInstance, ctx: Context): void {
	const { sql } = ctx;

	app.get("/api/devices/:id/extra", async (request) => {
		const { id } = parse(idParams, request.params);
		const { from, to, limit } = parse(query, request.query);
		await requireTracker(sql, request.auth!.user, id);
		const items = await sql<{ time: Date; data: Record<string, unknown> }[]>`
			SELECT time, data FROM device_extra
			WHERE device_id = ${id} AND time >= ${from ?? new Date(0)} AND time <= ${to ?? new Date(Date.now() + 3600e3)}
			ORDER BY time DESC LIMIT ${limit}`;
		// Each field from its newest reading, even when the last readings don't carry it
		const latest = await sql<{ key: string; value: unknown; time: Date }[]>`
			SELECT DISTINCT ON (f.key) f.key, f.value, e.time
			FROM device_extra e, jsonb_each(e.data) f
			WHERE e.device_id = ${id} AND e.time > now() - interval '90 days'
			ORDER BY f.key, e.time DESC`;
		return { latest, items };
	});
}
