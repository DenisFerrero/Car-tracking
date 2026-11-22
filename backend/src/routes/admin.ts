import type { FastifyInstance } from "fastify";
import { z } from "zod";
import { logAuthEvent } from "../context.ts";
import type { Context } from "../context.ts";
import { conflict, forbidden, notFound, parse } from "../http/errors.ts";
import { requireAdmin } from "../http/session.ts";
import { hashToken, randomToken } from "../auth/secrets.ts";
import { deleteUser } from "../services/accounts.ts";
import { backupState } from "../services/backups.ts";

// Administration: users, invites, access resets. There is no public registration: the
// administrator invites the users with a link (no email server needed, the link is
// shared by the administrator).

const INVITE_TTL = 72 * 3600e3;
const idParams = z.strictObject({ id: z.coerce.number().int().positive().max(2 ** 31 - 1) });

export function registerAdminRoutes (app: FastifyInstance, ctx: Context): void {
	const { sql } = ctx;

	app.addHook("onRequest", async (request) => {
		if (request.url.startsWith("/api/admin/")) requireAdmin(request);
	});

	const link = (token: string) => `${ctx.config.PUBLIC_URL}/#/invite/${token}`;

	app.get("/api/admin/backup", async () => backupState(ctx.config.BACKUP_DIR));

	app.get("/api/admin/users", async () => {
		return sql`
			SELECT u.id, u.email, u.name, u.is_admin AS "isAdmin", u.disabled, u.created_at AS "createdAt",
				u.totp_secret IS NOT NULL AS "totpEnabled", u.locked_until AS "lockedUntil",
				(SELECT count(*)::int FROM passkeys p WHERE p.user_id = u.id) AS passkeys,
				(SELECT count(*)::int FROM device_users du WHERE du.user_id = u.id) AS devices,
				(SELECT max(created_at) FROM auth_events e WHERE e.user_id = u.id AND e.event LIKE 'login%') AS "lastLoginAt"
			FROM users u ORDER BY u.name`;
	});

	app.get("/api/admin/invites", async () => {
		return sql`
			SELECT encode(token_hash, 'hex') AS id, email, name, is_admin AS "isAdmin", user_id AS "userId",
				expires_at AS "expiresAt", created_at AS "createdAt"
			FROM invites WHERE expires_at > now() ORDER BY created_at DESC`;
	});

	app.post("/api/admin/invites", async (request) => {
		const body = parse(z.strictObject({
			email: z.email().max(254),
			name: z.string().trim().min(1).max(80),
			isAdmin: z.boolean().default(false)
		}), request.body);
		const [existing] = await sql`SELECT 1 FROM users WHERE email = ${body.email}`;
		if (existing) throw conflict("An account with this email already exists", "email_taken");

		const token = randomToken();
		await sql`
			INSERT INTO invites (token_hash, email, name, is_admin, created_by, expires_at)
			VALUES (${hashToken(token)}, ${body.email}, ${body.name}, ${body.isAdmin}, ${request.auth!.user.id}, ${new Date(Date.now() + INVITE_TTL)})`;
		await logAuthEvent(ctx, "invite_created", { userId: request.auth!.user.id, email: body.email, ip: request.ip });
		return { link: link(token), expiresAt: new Date(Date.now() + INVITE_TTL) };
	});

	app.delete("/api/admin/invites/:id", async (request) => {
		const { id } = parse(z.strictObject({ id: z.string().regex(/^[0-9a-f]{64}$/) }), request.params);
		await sql`DELETE FROM invites WHERE token_hash = ${Buffer.from(id, "hex")}`;
		return { ok: true };
	});

	app.patch("/api/admin/users/:id", async (request) => {
		const { id } = parse(idParams, request.params);
		const body = parse(z.strictObject({ disabled: z.boolean().optional(), isAdmin: z.boolean().optional() }), request.body);
		if (id === request.auth!.user.id) throw forbidden("You can't change your own account here", "self");
		const [user] = await sql`SELECT 1 FROM users WHERE id = ${id}`;
		if (!user) throw notFound();
		if (body.disabled !== undefined) {
			await sql`UPDATE users SET disabled = ${body.disabled} WHERE id = ${id}`;
			if (body.disabled) {
				await ctx.sessions.destroyAll(id);
				ctx.hub.disconnectUser(id);
			}
		}
		if (body.isAdmin !== undefined) await sql`UPDATE users SET is_admin = ${body.isAdmin} WHERE id = ${id}`;
		await logAuthEvent(ctx, "user_updated", { userId: id, ip: request.ip });
		return { ok: true };
	});

	/**
	 * Access reset (lost phone, forgotten password): a link to choose a new password and
	 * enroll the 2FA again. The current access stays valid until the link is used.
	 */
	app.post("/api/admin/users/:id/reset", async (request) => {
		const { id } = parse(idParams, request.params);
		const [user] = await sql<{ email: string; name: string }[]>`SELECT email, name FROM users WHERE id = ${id}`;
		if (!user) throw notFound();
		const token = randomToken();
		await sql`DELETE FROM invites WHERE user_id = ${id}`;
		await sql`
			INSERT INTO invites (token_hash, user_id, email, name, created_by, expires_at)
			VALUES (${hashToken(token)}, ${id}, ${user.email}, ${user.name}, ${request.auth!.user.id}, ${new Date(Date.now() + INVITE_TTL)})`;
		await logAuthEvent(ctx, "reset_link_created", { userId: id, ip: request.ip });
		return { link: link(token), expiresAt: new Date(Date.now() + INVITE_TTL) };
	});

	app.delete("/api/admin/users/:id", async (request) => {
		const { id } = parse(idParams, request.params);
		if (id === request.auth!.user.id) throw forbidden("You can't delete your own account", "self");
		const [user] = await sql`SELECT 1 FROM users WHERE id = ${id}`;
		if (!user) throw notFound();
		await deleteUser(ctx, id);
		return { ok: true };
	});

	app.get("/api/admin/users/:id/events", async (request) => {
		const { id } = parse(idParams, request.params);
		return sql`
			SELECT event, host(ip) AS ip, user_agent AS "userAgent", created_at AS "createdAt"
			FROM auth_events WHERE user_id = ${id} ORDER BY created_at DESC LIMIT 100`;
	});
}
