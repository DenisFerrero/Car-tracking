import type { FastifyInstance, FastifyRequest } from "fastify";
import type { AuthenticationResponseJSON } from "@simplewebauthn/server";
import { z } from "zod";
import { logAuthEvent } from "../context.ts";
import type { Context } from "../context.ts";
import { ApiError, conflict, notFound, parse, unauthorized } from "../http/errors.ts";
import type { Client, Stage } from "../http/session.ts";
import {
	PASSWORD_MIN_LENGTH, hashPassword, hashRecoveryCode, hashToken, newRecoveryCodes, newTotpSecret,
	totpUri, verifyPassword, verifyTotp
} from "../auth/secrets.ts";

// Login: passkey (complete by itself), or email + password followed by the TOTP code (or
// a recovery code). Accounts without TOTP must enroll it before anything else.

const MAX_FAILURES = 5;
const LOCK_BASE = 15 * 60e3;
const LOCK_MAX = 24 * 3600e3;

const client = z.enum(["web", "app"]).default("web");
const password = z.string().min(PASSWORD_MIN_LENGTH, `at least ${PASSWORD_MIN_LENGTH} characters`).max(256);

interface UserRow {
	id: number;
	email: string;
	password_hash: string | null;
	totp_secret: Buffer | null;
	totp_last_step: number;
	disabled: boolean;
	failed_logins: number;
	locked_until: Date | null;
}

function meta (request: FastifyRequest) {
	return { ip: request.ip, userAgent: request.headers["user-agent"] };
}

export async function registerFailure (ctx: Context, request: FastifyRequest, user: UserRow, event: string): Promise<void> {
	const failures = user.failed_logins + 1;
	const lock = failures >= MAX_FAILURES ? new Date(Date.now() + Math.min(LOCK_BASE * 2 ** (failures - MAX_FAILURES), LOCK_MAX)) : null;
	await ctx.sql`UPDATE users SET failed_logins = ${failures}, locked_until = ${lock} WHERE id = ${user.id}`;
	await logAuthEvent(ctx, lock ? `${event}_locked` : event, { userId: user.id, ...meta(request) });
}

async function loadUser (ctx: Context, id: number): Promise<UserRow> {
	const [user] = await ctx.sql<UserRow[]>`
		SELECT id, email, password_hash, totp_secret, totp_last_step, disabled, failed_logins, locked_until
		FROM users WHERE id = ${id}`;
	if (!user) throw unauthorized();
	return user;
}

function assertNotLocked (user: UserRow): void {
	if (user.locked_until && user.locked_until.getTime() > Date.now()) {
		throw new ApiError(429, "locked", "Too many failed attempts, try again later");
	}
}

/** Verifies the TOTP of a user, storing the step (a code works once) */
export async function checkTotp (ctx: Context, user: UserRow, code: string): Promise<boolean> {
	if (!user.totp_secret) return false;
	const step = verifyTotp(ctx.box.open(user.totp_secret), code, Number(user.totp_last_step));
	if (step === null) return false;
	const updated = await ctx.sql`
		UPDATE users SET totp_last_step = ${step}, failed_logins = 0, locked_until = NULL
		WHERE id = ${user.id} AND totp_last_step < ${step}`;
	return updated.count === 1;
}

export async function createRecoveryCodes (ctx: Context, userId: number): Promise<string[]> {
	const codes = newRecoveryCodes();
	await ctx.sql.begin(async tx => {
		await tx`DELETE FROM recovery_codes WHERE user_id = ${userId}`;
		for (const code of codes) await tx`INSERT INTO recovery_codes (user_id, code_hash) VALUES (${userId}, ${hashRecoveryCode(code)})`;
	});
	return codes;
}

export function loadUserRow (ctx: Context, id: number): Promise<UserRow> {
	return loadUser(ctx, id);
}

export function registerAuthRoutes (app: FastifyInstance, ctx: Context): void {
	// Strict limits on the endpoints that verify secrets, per client address
	const STRICT = { rateLimit: { max: ctx.config.AUTH_RATE_LIMIT, timeWindow: "1 minute" } };

	// The app keeps the token, the browser has the cookie
	const sessionResponse = (stage: Stage, token: string, clientType: Client) =>
		({ stage, ...(clientType === "app" ? { token } : {}) });

	app.post("/api/auth/login", { config: { auth: "none", ...STRICT } }, async (request, reply) => {
		const body = parse(z.strictObject({ email: z.string().max(254), password: z.string().max(256), client }), request.body);
		const [user] = await ctx.sql<UserRow[]>`
			SELECT id, email, password_hash, totp_secret, totp_last_step, disabled, failed_logins, locked_until
			FROM users WHERE email = ${body.email.trim()}`;

		if (user) assertNotLocked(user);
		const valid = await verifyPassword(user?.password_hash ?? null, body.password);
		if (!user || !valid || user.disabled) {
			if (user) await registerFailure(ctx, request, user, "login_failed");
			else await logAuthEvent(ctx, "login_unknown", { email: body.email, ...meta(request) });
			throw unauthorized("Wrong email or password", "invalid_credentials");
		}

		await ctx.sql`UPDATE users SET failed_logins = 0, locked_until = NULL WHERE id = ${user.id}`;
		const stage: Stage = user.totp_secret ? "mfa_pending" : "enroll";
		const token = await ctx.sessions.create(request, reply, user.id, stage, body.client);
		await logAuthEvent(ctx, "password_ok", { userId: user.id, ...meta(request) });
		return sessionResponse(stage, token, body.client);
	});

	app.post("/api/auth/totp", { config: { auth: "mfa_pending", ...STRICT } }, async (request, reply) => {
		const body = parse(z.strictObject({ code: z.string().max(10) }), request.body);
		const user = await loadUser(ctx, request.auth!.user.id);
		assertNotLocked(user);
		if (!(await checkTotp(ctx, user, body.code))) {
			await registerFailure(ctx, request, user, "totp_failed");
			throw unauthorized("Invalid code", "invalid_code");
		}
		const token = await ctx.sessions.upgrade(request, reply, "full");
		await logAuthEvent(ctx, "login", { userId: user.id, ...meta(request) });
		return sessionResponse("full", token, request.auth!.client);
	});

	app.post("/api/auth/recovery", { config: { auth: "mfa_pending", ...STRICT } }, async (request, reply) => {
		const body = parse(z.strictObject({ code: z.string().max(30) }), request.body);
		const user = await loadUser(ctx, request.auth!.user.id);
		assertNotLocked(user);
		const used = await ctx.sql`
			UPDATE recovery_codes SET used_at = now()
			WHERE user_id = ${user.id} AND code_hash = ${hashRecoveryCode(body.code)} AND used_at IS NULL`;
		if (used.count !== 1) {
			await registerFailure(ctx, request, user, "recovery_failed");
			throw unauthorized("Invalid recovery code", "invalid_code");
		}
		await ctx.sql`UPDATE users SET failed_logins = 0, locked_until = NULL WHERE id = ${user.id}`;
		const [left] = await ctx.sql<{ remaining: number }[]>`
			SELECT count(*)::int AS remaining FROM recovery_codes WHERE user_id = ${user.id} AND used_at IS NULL`;
		const token = await ctx.sessions.upgrade(request, reply, "full");
		await logAuthEvent(ctx, "login_recovery", { userId: user.id, ...meta(request) });
		return { ...sessionResponse("full", token, request.auth!.client), recoveryCodesLeft: left?.remaining ?? 0 };
	});

	// --- TOTP enrollment, mandatory before using the platform
	app.post("/api/auth/enroll/start", { config: { auth: "enroll" } }, async (request) => {
		const secret = newTotpSecret();
		await ctx.sql`UPDATE users SET totp_pending = ${ctx.box.seal(secret)} WHERE id = ${request.auth!.user.id}`;
		return { secret, uri: totpUri(secret, ctx.config.APP_NAME, request.auth!.user.email) };
	});

	app.post("/api/auth/enroll/confirm", { config: { auth: "enroll", ...STRICT } }, async (request, reply) => {
		const body = parse(z.strictObject({ code: z.string().max(10) }), request.body);
		const userId = request.auth!.user.id;
		const [row] = await ctx.sql<{ totp_pending: Buffer | null }[]>`SELECT totp_pending FROM users WHERE id = ${userId}`;
		if (!row?.totp_pending) throw unauthorized("Start the setup again", "enroll_expired");

		const secret = ctx.box.open(row.totp_pending);
		const step = verifyTotp(secret, body.code, 0);
		if (step === null) throw unauthorized("Invalid code: check the clock of the phone", "invalid_code");

		await ctx.sql`
			UPDATE users SET totp_secret = totp_pending, totp_pending = NULL, totp_last_step = ${step}
			WHERE id = ${userId}`;
		const recoveryCodes = await createRecoveryCodes(ctx, userId);
		const token = await ctx.sessions.upgrade(request, reply, "full");
		await logAuthEvent(ctx, "totp_enrolled", { userId, ...meta(request) });
		return { ...sessionResponse("full", token, request.auth!.client), recoveryCodes };
	});

	// --- Passkeys
	app.post("/api/auth/passkey/options", { config: { auth: "none", ...STRICT } }, async () => {
		return ctx.webauthn.authenticationOptions();
	});

	app.post("/api/auth/passkey/verify", { config: { auth: "none", ...STRICT } }, async (request, reply) => {
		const body = parse(z.strictObject({ response: z.looseObject({ id: z.string(), response: z.looseObject({ clientDataJSON: z.string() }) }), client }), request.body);
		const userId = await ctx.webauthn.authenticate(body.response as unknown as AuthenticationResponseJSON);
		const user = await loadUser(ctx, userId);
		if (user.disabled || !user.totp_secret) throw unauthorized("Inactive account", "invalid_credentials");
		const token = await ctx.sessions.create(request, reply, userId, "full", body.client);
		await logAuthEvent(ctx, "login_passkey", { userId, ...meta(request) });
		return sessionResponse("full", token, body.client);
	});

	app.get("/api/auth/session", { config: { auth: "none" } }, async (request) => {
		if (!request.auth) return { stage: null };
		return { stage: request.auth.stage, user: request.auth.user };
	});

	app.post("/api/auth/logout", { config: { auth: "none" } }, async (request, reply) => {
		if (request.auth) await logAuthEvent(ctx, "logout", { userId: request.auth.user.id, ...meta(request) });
		await ctx.sessions.destroy(request, reply);
		return { ok: true };
	});

	// --- Invites and access reset links
	interface InviteRow { email: string; name: string; is_admin: boolean; user_id: number | null; expires_at: Date }

	async function findInvite (token: string): Promise<InviteRow> {
		const [invite] = await ctx.sql<InviteRow[]>`
			SELECT email, name, is_admin, user_id, expires_at FROM invites WHERE token_hash = ${hashToken(token)}`;
		if (!invite || invite.expires_at.getTime() < Date.now()) throw notFound("Invalid or expired invite");
		return invite;
	}

	app.get("/api/auth/invites/:token", { config: { auth: "none", ...STRICT } }, async (request) => {
		const { token } = parse(z.strictObject({ token: z.string().min(20).max(100) }), request.params);
		const invite = await findInvite(token);
		return { email: invite.email, name: invite.name, reset: invite.user_id !== null };
	});

	app.post("/api/auth/invites/:token", { config: { auth: "none", ...STRICT } }, async (request, reply) => {
		const { token } = parse(z.strictObject({ token: z.string().min(20).max(100) }), request.params);
		const body = parse(z.strictObject({ password, client }), request.body);
		const invite = await findInvite(token);
		const passwordHash = await hashPassword(body.password);

		const userId = await ctx.sql.begin(async tx => {
			const deleted = await tx`DELETE FROM invites WHERE token_hash = ${hashToken(token)}`;
			if (deleted.count !== 1) throw notFound("Invite already used");
			if (invite.user_id !== null) {
				// Access reset: new password, TOTP and passkeys to configure again
				await tx`
					UPDATE users SET password_hash = ${passwordHash}, totp_secret = NULL, totp_pending = NULL,
						failed_logins = 0, locked_until = NULL
					WHERE id = ${invite.user_id}`;
				await tx`DELETE FROM passkeys WHERE user_id = ${invite.user_id}`;
				await tx`DELETE FROM recovery_codes WHERE user_id = ${invite.user_id}`;
				await tx`DELETE FROM sessions WHERE user_id = ${invite.user_id}`;
				return invite.user_id;
			}
			const [existing] = await tx`SELECT 1 FROM users WHERE email = ${invite.email}`;
			if (existing) throw conflict("An account with this email already exists", "email_taken");
			const [user] = await tx<{ id: number }[]>`
				INSERT INTO users (email, name, is_admin, password_hash)
				VALUES (${invite.email}, ${invite.name}, ${invite.is_admin}, ${passwordHash}) RETURNING id`;
			return user!.id;
		});

		const session = await ctx.sessions.create(request, reply, userId, "enroll", body.client);
		await logAuthEvent(ctx, invite.user_id ? "access_reset" : "invite_accepted", { userId, ...meta(request) });
		return sessionResponse("enroll", session, body.client);
	});
}
