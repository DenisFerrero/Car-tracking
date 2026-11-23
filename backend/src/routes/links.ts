import type { FastifyInstance } from "fastify";
import { z } from "zod";
import type { Context } from "../context.ts";
import { hashToken, randomToken } from "../auth/secrets.ts";
import { badRequest, notFound, parse } from "../http/errors.ts";
import { requireDevice } from "../services/access.ts";
import { deviceName } from "../services/notifier.ts";
import { idParams } from "./devices.ts";

// Temporary links to the live position of a device for who has no account ("I'm on my
// way"): created by the owner for 1-24 hours, revocable, listed while active. The page of
// the link (web app, /#/l/<token>) reads only name, color and latest position: no history,
// no data of the tracker, no account. The token (32 random bytes) is stored as its hash;
// an expired, revoked or unknown token gets the same 404.

export const MAX_ACTIVE_LINKS = 5;
const KEEP_ENDED = "7 days";
/** The last view is written at most this often */
const VIEW_EVERY = "1 minute";

const newLink = z.strictObject({
	hours: z.number().int().min(1).max(24),
	label: z.string().trim().max(40).default("")
});
const tokenParams = z.strictObject({ token: z.string().regex(/^[A-Za-z0-9_-]{32,100}$/) });

export function registerLinkRoutes (app: FastifyInstance, ctx: Context): void {
	const { sql, config } = ctx;
	const url = (token: string) => `${config.PUBLIC_URL}/#/l/${token}`;

	const active = (deviceId: number) => sql`
		SELECT id, label, expires_at AS "expiresAt", created_at AS "createdAt", last_viewed_at AS "lastViewedAt"
		FROM live_links WHERE device_id = ${deviceId} AND revoked_at IS NULL AND expires_at > now() ORDER BY created_at DESC`;

	app.get("/api/devices/:id/links", async (request) => {
		const { id } = parse(idParams, request.params);
		await requireDevice(sql, request.auth!.user, id, "owner");
		return { links: await active(id), max: MAX_ACTIVE_LINKS };
	});

	/** New link: its address is returned only now */
	app.post("/api/devices/:id/links", async (request) => {
		const { id } = parse(idParams, request.params);
		const body = parse(newLink, request.body);
		await requireDevice(sql, request.auth!.user, id, "owner");
		const token = randomToken();
		const [row] = await sql<{ id: number; expiresAt: Date }[]>`
			INSERT INTO live_links (device_id, user_id, token_hash, label, expires_at)
			SELECT ${id}, ${request.auth!.user.id}, ${hashToken(token)}, ${body.label}, now() + make_interval(hours => ${body.hours})
			WHERE (SELECT count(*) FROM live_links WHERE device_id = ${id} AND revoked_at IS NULL AND expires_at > now()) < ${MAX_ACTIVE_LINKS}
			RETURNING id, expires_at AS "expiresAt"`;
		if (!row) throw badRequest(`At most ${MAX_ACTIVE_LINKS} active links`, "too_many_links");
		return { id: row.id, url: url(token), expiresAt: row.expiresAt, links: await active(id) };
	});

	app.delete("/api/links/:id", async (request) => {
		const { id } = parse(idParams, request.params);
		const [link] = await sql<{ device_id: number }[]>`SELECT device_id FROM live_links WHERE id = ${id} AND revoked_at IS NULL`;
		if (!link) throw notFound("Link not found");
		await requireDevice(sql, request.auth!.user, link.device_id, "owner").catch(() => {
			throw notFound("Link not found");
		});
		await sql`UPDATE live_links SET revoked_at = now() WHERE id = ${id}`;
		return { links: await active(link.device_id) };
	});

	/** The page of the link, without an account */
	app.get("/api/public/links/:token", {
		config: { auth: "none", rateLimit: { max: config.AUTH_RATE_LIMIT * 6, timeWindow: "1 minute" } }
	}, async (request) => {
		const params = tokenParams.safeParse(request.params);
		if (!params.success) throw notFound("Link not found");
		const { token } = params.data;
		const [link] = await sql<{ id: number; device_id: number; expires_at: Date; name: string; imei: string | null; color: string; kind: string }[]>`
			UPDATE live_links l SET last_viewed_at = now()
			FROM devices d WHERE d.id = l.device_id AND l.token_hash = ${hashToken(token)} AND l.revoked_at IS NULL AND l.expires_at > now()
				AND (l.last_viewed_at IS NULL OR l.last_viewed_at < now() - ${VIEW_EVERY}::interval)
			RETURNING l.id, l.device_id, l.expires_at, d.name, d.imei, d.color, d.kind`;
		const found = link ?? (await sql<NonNullable<typeof link>[]>`
			SELECT l.id, l.device_id, l.expires_at, d.name, d.imei, d.color, d.kind FROM live_links l JOIN devices d ON d.id = l.device_id
			WHERE l.token_hash = ${hashToken(token)} AND l.revoked_at IS NULL AND l.expires_at > now()`)[0];
		if (!found) throw notFound("Link not found");
		const [position] = await sql<{ lat: number; lon: number; time: Date; speed: number | null; moving: boolean }[]>`
			SELECT lat, lon, time, speed, status = 0 AS moving FROM positions
			WHERE device_id = ${found.device_id} AND time > now() - interval '60 days' AND lat IS NOT NULL
			ORDER BY time DESC LIMIT 1`;
		return {
			name: deviceName(found),
			color: found.color,
			kind: found.kind,
			expiresAt: found.expires_at,
			position: position
				? { lat: position.lat, lon: position.lon, time: position.time, speed: position.moving ? position.speed : null }
				: null
		};
	});
}

/** Job: links ended (expired or revoked) for some days removed */
export async function purgeLinks (ctx: Context): Promise<void> {
	await ctx.sql`DELETE FROM live_links WHERE expires_at < now() - ${KEEP_ENDED}::interval OR revoked_at < now() - ${KEEP_ENDED}::interval`;
}
