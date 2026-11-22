import type { FastifyInstance } from "fastify";
import { z } from "zod";
import type { Context } from "../context.ts";
import { IMEI_PATTERN } from "../crypto/device.ts";
import { badRequest, conflict, notFound, parse } from "../http/errors.ts";
import { requireDevice, requireTracker, viewerPosition } from "../services/access.ts";
import type { Access, PositionRow } from "../services/access.ts";
import { releaseDevice } from "../services/accounts.ts";
import type { CommandType } from "../services/commands.ts";
import { KINDS, deviceName } from "../services/notifier.ts";

// Devices of the users. A tracker is added with the guided procedure of the app:
//  1. check: IMEI + pairing code of the label (or its QR code)
//  2. claim: the tracker becomes of the user, with name and color
//  3. the app waits for the first contact of the tracker (realtime event "registered")
// The pairing code proves the physical possession: knowing an IMEI is not enough.
//
// The owner can share the position with friends (src/routes/friends.ts), until revoked or
// until a date: the viewers see position, speed and state, nothing else. Phones
// (src/routes/phones.ts) are devices too, without commands and alarms.

export const idParams = z.strictObject({ id: z.coerce.number().int().positive().max(2 ** 31 - 1) });
const userId = z.coerce.number().int().positive().max(2 ** 31 - 1);
const shareParams = idParams.extend({ userId });
const imei = z.string().trim().regex(IMEI_PATTERN, "15 digits");
const color = z.string().regex(/^#[0-9A-Fa-f]{6}$/);
const name = z.string().trim().min(1).max(60);

const MAX_SHARE_DAYS = 366;
const MAX_SHARES = 50;
/** A phone is connected while its positions keep coming */
const PHONE_ONLINE_MS = 10 * 60e3;

/** End of a share: null = until revoked, otherwise between 1 minute and a year from now */
export const shareEnd = z.iso.datetime({ offset: true }).nullable().transform((value, context) => {
	if (value === null) return null;
	const date = new Date(value);
	const delta = date.getTime() - Date.now();
	if (delta < 60e3 || delta > MAX_SHARE_DAYS * 86400e3) {
		context.addIssue({ code: "custom", message: "between 1 minute and 1 year from now" });
		return z.NEVER;
	}
	return date;
});

interface DeviceRow {
	id: number;
	kind: "tracker" | "phone";
	imei: string | null;
	name: string;
	color: string;
	manufacturer: string;
	model: string;
	revision: string;
	firmware: string;
	registered_at: Date | null;
	last_seen_at: Date | null;
	role: "owner" | "viewer";
	expires_at: Date | null;
	owner_name: string | null;
	battery: number | null;
	paused_until: Date | null;
	battery_alert: number | null;
	stop_alert_hours: number | null;
}

export function registerDeviceRoutes (app: FastifyInstance, ctx: Context, isConnected: (imei: string) => boolean): void {
	const { sql } = ctx;
	// Pairing codes have 40 bits: a strict limit makes guessing impossible
	const CLAIM_LIMIT = { rateLimit: { max: ctx.config.AUTH_RATE_LIMIT, timeWindow: "15 minutes" } };

	const latestPositions = async (ids: number[]) => {
		if (ids.length === 0) return new Map<number, PositionRow>();
		const rows = await sql<(PositionRow & { device_id: number })[]>`
			SELECT DISTINCT ON (device_id) device_id, time, lat, lon, speed, altitude, satellites, signal, voltage,
				temperature, status, stale, events, accuracy
			FROM positions WHERE device_id = ANY (${ids}) AND time > now() - interval '60 days'
			ORDER BY device_id, time DESC`;
		return new Map(rows.map(row => [row.device_id, row]));
	};

	const connected = (device: DeviceRow) => device.imei !== null
		? isConnected(device.imei)
		: device.last_seen_at !== null && Date.now() - device.last_seen_at.getTime() < PHONE_ONLINE_MS;

	const present = (device: DeviceRow, position: PositionRow | undefined) => {
		const common = {
			id: device.id,
			kind: device.kind,
			name: deviceName(device),
			color: device.color,
			role: device.role,
			lastSeenAt: device.last_seen_at,
			connected: connected(device),
			// Alerts of this user: long stop; low battery of a phone shared with them
			stopAlertHours: device.stop_alert_hours,
			...(device.kind === "phone" && device.role === "viewer" ? { batteryAlert: device.battery_alert } : {}),
			// Phones: battery of the phone and pause chosen from its notification (friends too)
			...(device.kind === "phone" ? { battery: device.battery, pausedUntil: device.paused_until } : {})
		};
		if (device.role === "viewer") {
			return { ...common, shareExpiresAt: device.expires_at, ownerName: device.owner_name, lastPosition: position ? viewerPosition(position) : null };
		}
		return {
			...common,
			imei: device.imei ?? "",
			model: device.model,
			manufacturer: device.manufacturer,
			revision: device.revision,
			firmware: device.firmware,
			registeredAt: device.registered_at,
			lastPosition: position ?? null
		};
	};

	const selectDevices = (userId: number, deviceId: number | null) => sql<DeviceRow[]>`
		SELECT d.*, du.role, du.expires_at, du.battery_alert, du.stop_alert_hours,
			(SELECT u.name FROM device_users o JOIN users u ON u.id = o.user_id WHERE o.device_id = d.id AND o.role = 'owner') AS owner_name
		FROM devices d JOIN device_users du ON du.device_id = d.id
		WHERE du.user_id = ${userId} AND (du.expires_at IS NULL OR du.expires_at > now())
			${deviceId === null ? sql`` : sql`AND d.id = ${deviceId}`}
		ORDER BY du.role, d.name, d.id`;

	app.get("/api/devices", async (request) => {
		const devices = await selectDevices(request.auth!.user.id, null);
		const positions = await latestPositions(devices.map(device => device.id));
		return devices.map(device => present(device, positions.get(device.id)));
	});

	app.get("/api/devices/:id", async (request) => {
		const { id } = parse(idParams, request.params);
		const access = await requireDevice(sql, request.auth!.user, id);
		const [device] = await selectDevices(request.auth!.user.id, id);
		const positions = await latestPositions([id]);
		const detail = present(device!, positions.get(id));
		return access.role === "owner" && access.kind === "tracker" ? { ...detail, ...(await ctx.commands.state(id)) } : detail;
	});

	// --- Guided procedure
	app.post("/api/devices/claim/check", { config: CLAIM_LIMIT }, async (request) => {
		const body = parse(z.strictObject({ imei, code: z.string().max(20) }), request.body);
		if (!ctx.secrets.verifyPairingCode(body.imei, body.code)) {
			throw badRequest("Wrong IMEI or pairing code", "invalid_pairing");
		}
		const [device] = await sql<{ registered_at: Date | null; owner: number | null }[]>`
			SELECT d.registered_at, (SELECT user_id FROM device_users WHERE device_id = d.id AND role = 'owner') AS owner
			FROM devices d WHERE d.imei = ${body.imei}`;
		return {
			valid: true,
			// Already sent its first HELLO
			registered: Boolean(device?.registered_at),
			// Owned by somebody else: the owner must release it first
			available: !device || device.owner === null,
			mine: device?.owner === request.auth!.user.id
		};
	});

	app.post("/api/devices/claim", { config: CLAIM_LIMIT }, async (request) => {
		const body = parse(z.strictObject({ imei, code: z.string().max(20), name, color: color.default("#1E88E5") }), request.body);
		if (!ctx.secrets.verifyPairingCode(body.imei, body.code)) {
			throw badRequest("Wrong IMEI or pairing code", "invalid_pairing");
		}
		const userId = request.auth!.user.id;
		const deviceId = await sql.begin(async tx => {
			// The device may not exist yet: the procedure can start before the first power on
			const [device] = await tx<{ id: number }[]>`
				INSERT INTO devices (imei, name, color) VALUES (${body.imei}, ${body.name}, ${body.color})
				ON CONFLICT (imei) DO UPDATE SET imei = excluded.imei RETURNING id`;
			const [owner] = await tx`SELECT 1 FROM device_users WHERE device_id = ${device!.id} AND role = 'owner' FOR UPDATE`;
			if (owner) throw conflict("The tracker belongs to another account", "already_claimed");
			await tx`UPDATE devices SET name = ${body.name}, color = ${body.color} WHERE id = ${device!.id}`;
			await tx`
				INSERT INTO device_users (device_id, user_id, role) VALUES (${device!.id}, ${userId}, 'owner')
				ON CONFLICT (device_id, user_id) DO UPDATE SET role = 'owner', expires_at = NULL`;
			return device!.id;
		});
		await ctx.hub.refreshUser(userId);
		request.log.info({ deviceId, userId }, "Device claimed");
		const [device] = await sql<{ registered_at: Date | null }[]>`SELECT registered_at FROM devices WHERE id = ${deviceId}`;
		return { id: deviceId, registered: Boolean(device!.registered_at) };
	});

	// --- Settings of the owner
	app.patch("/api/devices/:id", async (request) => {
		const { id } = parse(idParams, request.params);
		const body = parse(z.strictObject({ name: name.optional(), color: color.optional() }), request.body);
		await requireDevice(sql, request.auth!.user, id, "owner");
		if (body.name !== undefined) await sql`UPDATE devices SET name = ${body.name} WHERE id = ${id}`;
		if (body.color !== undefined) await sql`UPDATE devices SET color = ${body.color} WHERE id = ${id}`;
		const message = { type: "device", deviceId: id, ...body };
		ctx.hub.toDevice(id, message, message);
		return { ok: true };
	});

	/**
	 * Releases the tracker (car sold, tracker moved): shares, areas and history deleted, the
	 * tracker can be added again with its pairing code. A phone is deleted.
	 */
	app.delete("/api/devices/:id", async (request) => {
		const { id } = parse(idParams, request.params);
		const access = await requireDevice(sql, request.auth!.user, id, "owner");
		const users = await releaseDevice(sql, id, access.kind);
		for (const userId of users) await ctx.hub.refreshUser(userId);
		return { ok: true };
	});

	// --- Sharing (view only)
	app.get("/api/devices/:id/shares", async (request) => {
		const { id } = parse(idParams, request.params);
		await requireDevice(sql, request.auth!.user, id, "owner");
		return sql`
			SELECT u.id AS "userId", u.name, du.expires_at AS "expiresAt", du.created_at AS "createdAt"
			FROM device_users du JOIN users u ON u.id = du.user_id
			WHERE du.device_id = ${id} AND du.role = 'viewer' AND (du.expires_at IS NULL OR du.expires_at > now())
			ORDER BY u.name`;
	});

	/** Only with friends: the users of the platform don't see each other */
	app.post("/api/devices/:id/shares", async (request) => {
		const { id } = parse(idParams, request.params);
		const body = parse(z.strictObject({ userId, expiresAt: shareEnd }), request.body);
		await requireDevice(sql, request.auth!.user, id, "owner");
		if (body.userId === request.auth!.user.id) throw badRequest("You already own this device", "share_self");
		const [user] = await sql<{ id: number }[]>`
			SELECT u.id FROM users u JOIN friendships f ON f.friend_id = u.id
			WHERE f.user_id = ${request.auth!.user.id} AND u.id = ${body.userId} AND NOT u.disabled`;
		if (!user) throw notFound("No friend with this id");
		const [count] = await sql<{ count: number }[]>`SELECT count(*)::int AS count FROM device_users WHERE device_id = ${id} AND role = 'viewer'`;
		if (count!.count >= MAX_SHARES) throw badRequest(`At most ${MAX_SHARES} shares`, "too_many_shares");
		await sql`
			INSERT INTO device_users (device_id, user_id, role, expires_at, created_by)
			VALUES (${id}, ${user.id}, 'viewer', ${body.expiresAt}, ${request.auth!.user.id})
			ON CONFLICT (device_id, user_id) DO UPDATE SET expires_at = excluded.expires_at`;
		await ctx.hub.refreshUser(user.id);
		return { ok: true, userId: user.id };
	});

	app.patch("/api/devices/:id/shares/:userId", async (request) => {
		const { id, userId } = parse(shareParams, request.params);
		const body = parse(z.strictObject({ expiresAt: shareEnd }), request.body);
		await requireDevice(sql, request.auth!.user, id, "owner");
		const updated = await sql`
			UPDATE device_users SET expires_at = ${body.expiresAt}
			WHERE device_id = ${id} AND user_id = ${userId} AND role = 'viewer'`;
		if (updated.count !== 1) throw notFound("Share not found");
		await ctx.hub.refreshUser(userId);
		return { ok: true };
	});

	/** The owner revokes a share */
	app.delete("/api/devices/:id/shares/:userId", async (request) => {
		const { id, userId } = parse(shareParams, request.params);
		await requireDevice(sql, request.auth!.user, id, "owner");
		await removeViewer(id, userId);
		return { ok: true };
	});

	/** A viewer stops receiving a shared device */
	app.delete("/api/devices/:id/access", async (request) => {
		const { id } = parse(idParams, request.params);
		const access: Access = await requireDevice(sql, request.auth!.user, id);
		if (access.role === "owner") throw badRequest("The owner removes the tracker instead", "owner_cannot_leave");
		await removeViewer(id, request.auth!.user.id);
		return { ok: true };
	});

	async function removeViewer (deviceId: number, userId: number): Promise<void> {
		const deleted = await sql`DELETE FROM device_users WHERE device_id = ${deviceId} AND user_id = ${userId} AND role = 'viewer'`;
		if (deleted.count !== 1) throw notFound("Share not found");
		await sql`DELETE FROM geofences WHERE device_id = ${deviceId} AND user_id = ${userId}`;
		await sql`DELETE FROM notification_settings WHERE device_id = ${deviceId} AND user_id = ${userId}`;
		await ctx.hub.refreshUser(userId);
	}

	// --- Commands of the owner
	app.get("/api/devices/:id/commands", async (request) => {
		const { id } = parse(idParams, request.params);
		await requireTracker(sql, request.auth!.user, id);
		return { commands: await ctx.commands.recent(id), state: await ctx.commands.state(id) };
	});

	app.post("/api/devices/:id/commands", async (request) => {
		const { id } = parse(idParams, request.params);
		const body = parse(z.strictObject({
			type: z.enum(["live", "antitheft", "locate"]),
			// LIVE up to 2 hours, ANTITHEFT pause up to 30 days; 0 = stop / resume
			seconds: z.number().int().min(0).max(30 * 86400).default(0)
		}), request.body);
		await requireTracker(sql, request.auth!.user, id);
		if (body.type === "live" && body.seconds > 7200) throw badRequest("Live tracking for 2 hours at most", "live_too_long");
		const command = await ctx.commands.create(id, body.type as CommandType, body.seconds, request.auth!.user.id);
		return { command };
	});

	// --- Alerts of the logged user on a device they see (owner or viewer)
	app.patch("/api/devices/:id/alerts", async (request) => {
		const { id } = parse(idParams, request.params);
		const body = parse(z.strictObject({
			// Hours standing still outside the areas of the user, null = off
			stopAlertHours: z.number().int().min(1).max(72).nullable().optional(),
			// Battery (%) of a phone shared with the user, null = off
			batteryAlert: z.number().int().min(5).max(50).nullable().optional()
		}), request.body);
		const userId = request.auth!.user.id;
		const access = await requireDevice(sql, request.auth!.user, id);
		if (body.batteryAlert !== undefined && (access.kind !== "phone" || access.role !== "viewer")) {
			throw badRequest("Only for phones shared with you", "not_a_shared_phone");
		}
		const [row] = await sql<{ stopAlertHours: number | null; batteryAlert: number | null }[]>`
			UPDATE device_users SET
				stop_alert_hours = ${body.stopAlertHours === undefined ? sql`stop_alert_hours` : body.stopAlertHours},
				battery_alert = ${body.batteryAlert === undefined ? sql`battery_alert` : body.batteryAlert},
				battery_alerted = ${body.batteryAlert === undefined ? sql`battery_alerted` : false}
			WHERE device_id = ${id} AND user_id = ${userId}
			RETURNING stop_alert_hours AS "stopAlertHours", battery_alert AS "batteryAlert"`;
		return access.kind === "phone" && access.role === "viewer" ? row : { stopAlertHours: row!.stopAlertHours };
	});

	// --- Alarm notifications of the owner
	app.get("/api/devices/:id/notification-settings", async (request) => {
		const { id } = parse(idParams, request.params);
		await requireTracker(sql, request.auth!.user, id);
		const [row] = await sql<{ kinds: string[] }[]>`
			SELECT kinds FROM notification_settings WHERE user_id = ${request.auth!.user.id} AND device_id = ${id}`;
		return { kinds: row?.kinds ?? [...KINDS], available: KINDS };
	});

	app.put("/api/devices/:id/notification-settings", async (request) => {
		const { id } = parse(idParams, request.params);
		const body = parse(z.strictObject({ kinds: z.array(z.enum(KINDS)).max(KINDS.length) }), request.body);
		await requireTracker(sql, request.auth!.user, id);
		await sql`
			INSERT INTO notification_settings (user_id, device_id, kinds) VALUES (${request.auth!.user.id}, ${id}, ${[...new Set(body.kinds)]})
			ON CONFLICT (user_id, device_id) DO UPDATE SET kinds = excluded.kinds`;
		return { ok: true };
	});
}
