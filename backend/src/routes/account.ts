import type { FastifyInstance, FastifyRequest } from "fastify";
import type { RegistrationResponseJSON } from "@simplewebauthn/server";
import { z } from "zod";
import { logAuthEvent } from "../context.ts";
import type { Context } from "../context.ts";
import { ApiError, badRequest, notFound, parse, unauthorized } from "../http/errors.ts";
import { RECENT_AUTH } from "../http/session.ts";
import { PASSWORD_MIN_LENGTH, hashPassword, newTotpSecret, totpUri, verifyPassword, verifyTotp } from "../auth/secrets.ts";
import { LOCALES } from "../i18n.ts";
import { deleteUser } from "../services/accounts.ts";
import { checkTotp, createRecoveryCodes, loadUserRow, registerFailure } from "./auth.ts";

// Account of the logged user: profile, password, passkeys, recovery codes, TOTP,
// sessions, push tokens, export and deletion of the data. Sensitive changes need a
// recent login or a TOTP code.

/** Positions in the export: per device, the most recent ones */
const EXPORT_POSITIONS = 200000;

const code = z.string().max(10).optional();

function meta (request: FastifyRequest) {
	return { ip: request.ip, userAgent: request.headers["user-agent"] };
}

export function registerAccountRoutes (app: FastifyInstance, ctx: Context): void {
	const { sql } = ctx;
	const STRICT = { rateLimit: { max: ctx.config.AUTH_RATE_LIMIT, timeWindow: "1 minute" } };

	/** Recent login, or a valid TOTP code in the request */
	async function requireStepUp (request: FastifyRequest, totp: string | undefined): Promise<void> {
		const auth = request.auth!;
		if (Date.now() - auth.authenticatedAt.getTime() < RECENT_AUTH) return;
		if (!totp) throw new ApiError(401, "step_up_required", "Confirm with the code of the authenticator app");
		const user = await loadUserRow(ctx, auth.user.id);
		if (!(await checkTotp(ctx, user, totp))) {
			await registerFailure(ctx, request, user, "step_up_failed");
			throw unauthorized("Invalid code", "invalid_code");
		}
		await ctx.sessions.markAuthenticated(auth.tokenHash);
	}

	app.get("/api/account", async (request) => {
		const userId = request.auth!.user.id;
		const [passkeys, sessions, recovery] = await Promise.all([
			sql`SELECT id, name, backed_up, created_at, last_used_at FROM passkeys WHERE user_id = ${userId} ORDER BY created_at`,
			sql`SELECT encode(token_hash, 'hex') AS id, client, user_agent, host(ip) AS ip, created_at, last_seen_at,
					token_hash = ${request.auth!.tokenHash} AS current
				FROM sessions WHERE user_id = ${userId} AND stage = 'full' AND expires_at > now() ORDER BY last_seen_at DESC`,
			sql<{ left: number }[]>`SELECT count(*)::int AS left FROM recovery_codes WHERE user_id = ${userId} AND used_at IS NULL`
		]);
		return {
			user: request.auth!.user,
			passkeys,
			sessions,
			recoveryCodesLeft: recovery[0]?.left ?? 0,
			pushEnabled: ctx.notifier.pushEnabled
		};
	});

	/**
	 * Copy of the personal data (GDPR, art. 15 and 20): profile, access history, friends,
	 * devices owned with their positions, areas, notifications. No secrets (password hash,
	 * passkeys, TOTP, tokens), no data of other users besides the names of the friends.
	 */
	app.get("/api/account/export", { config: STRICT }, async (request, reply) => {
		const userId = request.auth!.user.id;
		const [profile] = await sql`
			SELECT id, email, name, locale, is_admin AS "isAdmin", created_at AS "createdAt" FROM users WHERE id = ${userId}`;
		const devices = await sql<{ id: number }[]>`
			SELECT d.id, d.kind, d.imei, d.name, d.color, d.manufacturer, d.model, d.firmware, d.registered_at AS "registeredAt",
				d.last_seen_at AS "lastSeenAt", du.role, du.expires_at AS "shareExpiresAt"
			FROM device_users du JOIN devices d ON d.id = du.device_id WHERE du.user_id = ${userId} ORDER BY d.id`;
		const owned = (devices as unknown as { id: number; role: string }[]).filter(device => device.role === "owner").map(device => device.id);
		const [events, friends, areas, notifications, settings, positions, dailyStats, tripLog, maintenance, maintenanceLog, vehicles, vehicleRates, extraData] = await Promise.all([
			sql`SELECT event, host(ip) AS ip, user_agent AS "userAgent", created_at AS "createdAt" FROM auth_events WHERE user_id = ${userId} ORDER BY created_at`,
			sql`SELECT u.name, f.created_at AS since FROM friendships f JOIN users u ON u.id = f.friend_id WHERE f.user_id = ${userId} ORDER BY u.name`,
			sql`SELECT device_id AS "deviceId", name, lat, lon, radius, schedule, created_at AS "createdAt" FROM geofences WHERE user_id = ${userId} ORDER BY id`,
			sql`SELECT device_id AS "deviceId", kind, data, created_at AS "createdAt" FROM notifications WHERE user_id = ${userId} ORDER BY created_at`,
			sql`SELECT device_id AS "deviceId", kinds FROM notification_settings WHERE user_id = ${userId}`,
			owned.length === 0 ? [] : sql`
				SELECT device_id AS "deviceId", time, lat, lon, altitude, speed, accuracy, satellites, signal, voltage, temperature,
					pressure, status, stale, events
				FROM (SELECT *, row_number() OVER (PARTITION BY device_id ORDER BY time DESC) AS n FROM positions WHERE device_id = ANY (${owned})) p
				WHERE n <= ${EXPORT_POSITIONS} ORDER BY device_id, time`,
			sql`SELECT * FROM daily_stats WHERE device_id = ANY (${owned}) ORDER BY device_id, day`,
			sql`SELECT * FROM trip_tags WHERE device_id = ANY (${owned}) ORDER BY device_id, start`,
			sql`SELECT * FROM maintenance WHERE device_id = ANY (${owned}) ORDER BY device_id, id`,
			sql`SELECT * FROM maintenance_log WHERE device_id = ANY (${owned}) ORDER BY device_id, done_on`,
			sql`
				SELECT id AS "deviceId", vehicle_model AS model, fuel_unit AS "fuelUnit", fuel_type AS "fuelType",
					fuel_price_auto AS "fuelPriceAuto", auto_update AS "autoUpdate"
				FROM devices WHERE id = ANY (${owned}) ORDER BY id`,
			sql`
				SELECT device_id AS "deviceId", kind, to_char(valid_from, 'YYYY-MM-DD') AS "validFrom", value
				FROM vehicle_rates WHERE device_id = ANY (${owned}) ORDER BY device_id, kind, valid_from`,
			sql`SELECT device_id AS "deviceId", time, data FROM device_extra WHERE device_id = ANY (${owned}) ORDER BY device_id, time`
		]);
		const day = new Date().toISOString().slice(0, 10);
		reply.header("content-disposition", `attachment; filename="car-tracking-${day}.json"`);
		return {
			exportedAt: new Date(), profile, authEvents: events, friends, devices, areas, notifications, notificationSettings: settings, positions,
			dailyStats, tripLog, maintenance, maintenanceLog, vehicles, vehicleRates, extraData
		};
	});

	/**
	 * Deletes the account: devices owned (trackers released, phones and all the positions
	 * deleted), shares, friends, areas, sessions. The email confirms the intention.
	 */
	app.delete("/api/account", { config: STRICT }, async (request) => {
		const body = parse(z.strictObject({ email: z.string().max(320), code }), request.body);
		const user = request.auth!.user;
		if (body.email.trim().toLowerCase() !== user.email.toLowerCase()) throw badRequest("The email doesn't match", "email_mismatch");
		await requireStepUp(request, body.code);
		if (user.isAdmin) {
			const [admins] = await sql<{ count: number }[]>`SELECT count(*)::int AS count FROM users WHERE is_admin AND NOT disabled`;
			if (admins!.count <= 1) throw badRequest("The last administrator can't delete the account", "last_admin");
		}
		await logAuthEvent(ctx, "account_deleted", { ip: request.ip, userAgent: request.headers["user-agent"] });
		await deleteUser(ctx, user.id);
		return { ok: true };
	});

	/** Name and language (detected by the app at the first login, then chosen by the user) */
	app.patch("/api/account", async (request) => {
		const body = parse(z.strictObject({ name: z.string().trim().min(1).max(80).optional(), locale: z.enum(LOCALES).optional() }), request.body);
		const userId = request.auth!.user.id;
		if (body.name !== undefined) await sql`UPDATE users SET name = ${body.name} WHERE id = ${userId}`;
		if (body.locale !== undefined) await sql`UPDATE users SET locale = ${body.locale} WHERE id = ${userId}`;
		return { ok: true };
	});

	app.post("/api/account/password", { config: STRICT }, async (request) => {
		const body = parse(z.strictObject({
			current: z.string().max(256),
			password: z.string().min(PASSWORD_MIN_LENGTH, `at least ${PASSWORD_MIN_LENGTH} characters`).max(256),
			code
		}), request.body);
		const user = await loadUserRow(ctx, request.auth!.user.id);
		if (!(await verifyPassword(user.password_hash, body.current))) {
			await registerFailure(ctx, request, user, "password_change_failed");
			throw unauthorized("Wrong current password", "invalid_password");
		}
		await requireStepUp(request, body.code);
		await sql`UPDATE users SET password_hash = ${await hashPassword(body.password)} WHERE id = ${user.id}`;
		// The other sessions may belong to whoever knew the old password
		await ctx.sessions.destroyAll(user.id, request.auth!.tokenHash);
		await logAuthEvent(ctx, "password_changed", { userId: user.id, ...meta(request) });
		return { ok: true };
	});

	// --- Passkeys
	app.post("/api/account/passkeys/options", { config: STRICT }, async (request) => {
		const body = parse(z.strictObject({ code }), request.body ?? {});
		await requireStepUp(request, body.code);
		return ctx.webauthn.registrationOptions(request.auth!.user);
	});

	app.post("/api/account/passkeys", { config: STRICT }, async (request) => {
		const body = parse(z.strictObject({
			name: z.string().trim().min(1).max(60),
			response: z.looseObject({ id: z.string(), response: z.looseObject({ clientDataJSON: z.string() }) })
		}), request.body);
		const id = await ctx.webauthn.register(request.auth!.user.id, body.name, body.response as unknown as RegistrationResponseJSON);
		await logAuthEvent(ctx, "passkey_added", { userId: request.auth!.user.id, ...meta(request) });
		return { id };
	});

	app.patch("/api/account/passkeys/:id", async (request) => {
		const { id } = parse(z.strictObject({ id: z.string().max(1400) }), request.params);
		const body = parse(z.strictObject({ name: z.string().trim().min(1).max(60) }), request.body);
		const updated = await sql`UPDATE passkeys SET name = ${body.name} WHERE id = ${id} AND user_id = ${request.auth!.user.id}`;
		if (updated.count !== 1) throw notFound();
		return { ok: true };
	});

	app.delete("/api/account/passkeys/:id", { config: STRICT }, async (request) => {
		const { id } = parse(z.strictObject({ id: z.string().max(1400) }), request.params);
		const body = parse(z.strictObject({ code }), request.body ?? {});
		await requireStepUp(request, body.code);
		const deleted = await sql`DELETE FROM passkeys WHERE id = ${id} AND user_id = ${request.auth!.user.id}`;
		if (deleted.count !== 1) throw notFound();
		await logAuthEvent(ctx, "passkey_removed", { userId: request.auth!.user.id, ...meta(request) });
		return { ok: true };
	});

	// --- Recovery codes and TOTP
	app.post("/api/account/recovery-codes", { config: STRICT }, async (request) => {
		const body = parse(z.strictObject({ code }), request.body ?? {});
		await requireStepUp(request, body.code);
		const codes = await createRecoveryCodes(ctx, request.auth!.user.id);
		await logAuthEvent(ctx, "recovery_codes_regenerated", { userId: request.auth!.user.id, ...meta(request) });
		return { recoveryCodes: codes };
	});

	/** New authenticator app (phone changed): the old code stays valid until confirmed */
	app.post("/api/account/totp/start", { config: STRICT }, async (request) => {
		const body = parse(z.strictObject({ code }), request.body ?? {});
		await requireStepUp(request, body.code);
		const secret = newTotpSecret();
		await sql`UPDATE users SET totp_pending = ${ctx.box.seal(secret)} WHERE id = ${request.auth!.user.id}`;
		return { secret, uri: totpUri(secret, ctx.config.APP_NAME, request.auth!.user.email) };
	});

	app.post("/api/account/totp/confirm", { config: STRICT }, async (request) => {
		const body = parse(z.strictObject({ code: z.string().max(10) }), request.body);
		const userId = request.auth!.user.id;
		const [row] = await sql<{ totp_pending: Buffer | null }[]>`SELECT totp_pending FROM users WHERE id = ${userId}`;
		if (!row?.totp_pending) throw unauthorized("Start the setup again", "enroll_expired");
		const step = verifyTotp(ctx.box.open(row.totp_pending), body.code, 0);
		if (step === null) throw unauthorized("Invalid code", "invalid_code");
		await sql`UPDATE users SET totp_secret = totp_pending, totp_pending = NULL, totp_last_step = ${step} WHERE id = ${userId}`;
		await logAuthEvent(ctx, "totp_changed", { userId, ...meta(request) });
		return { ok: true };
	});

	// --- Sessions
	app.delete("/api/account/sessions/:id", async (request) => {
		const { id } = parse(z.strictObject({ id: z.string().regex(/^[0-9a-f]{64}$/) }), request.params);
		const deleted = await sql`DELETE FROM sessions WHERE token_hash = ${Buffer.from(id, "hex")} AND user_id = ${request.auth!.user.id}`;
		if (deleted.count !== 1) throw notFound();
		return { ok: true };
	});

	app.post("/api/account/sessions/revoke-others", async (request) => {
		await ctx.sessions.destroyAll(request.auth!.user.id, request.auth!.tokenHash);
		return { ok: true };
	});

	// --- Push notifications (Android app)
	app.post("/api/account/push-tokens", async (request) => {
		const body = parse(z.strictObject({ token: z.string().min(20).max(4096) }), request.body);
		await sql`
			INSERT INTO push_tokens (token, user_id, session_hash) VALUES (${body.token}, ${request.auth!.user.id}, ${request.auth!.tokenHash})
			ON CONFLICT (token) DO UPDATE SET user_id = excluded.user_id, session_hash = excluded.session_hash, created_at = now()`;
		return { ok: true };
	});
}
