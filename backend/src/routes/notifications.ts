import type { FastifyInstance } from "fastify";
import { z } from "zod";
import type { Context } from "../context.ts";
import { parse } from "../http/errors.ts";

export function registerNotificationRoutes (app: FastifyInstance, ctx: Context): void {
	const { sql } = ctx;

	app.get("/api/notifications", async (request) => {
		const query = parse(z.strictObject({
			before: z.coerce.number().int().positive().optional(),
			limit: z.coerce.number().int().min(1).max(100).default(50)
		}), request.query);
		const userId = request.auth!.user.id;
		const [items, unread] = await Promise.all([
			sql`
				SELECT id, device_id AS "deviceId", kind, data, lat, lon, created_at AS "createdAt", read_at AS "readAt"
				FROM notifications
				WHERE user_id = ${userId} ${query.before ? sql`AND id < ${query.before}` : sql``}
				ORDER BY id DESC LIMIT ${query.limit}`,
			sql<{ count: number }[]>`SELECT count(*)::int AS count FROM notifications WHERE user_id = ${userId} AND read_at IS NULL`
		]);
		return { notifications: items, unread: unread[0]?.count ?? 0 };
	});

	app.post("/api/notifications/read", async (request) => {
		const body = parse(z.strictObject({ ids: z.array(z.number().int().positive()).max(500).optional() }), request.body ?? {});
		const userId = request.auth!.user.id;
		if (body.ids) {
			await sql`UPDATE notifications SET read_at = now() WHERE user_id = ${userId} AND id = ANY (${body.ids}) AND read_at IS NULL`;
		} else {
			await sql`UPDATE notifications SET read_at = now() WHERE user_id = ${userId} AND read_at IS NULL`;
		}
		return { ok: true };
	});
}
