import type { FastifyInstance } from "fastify";
import { z } from "zod";
import type { Context } from "../context.ts";
import { hashToken, randomToken } from "../auth/secrets.ts";
import { badRequest, parse, unauthorized } from "../http/errors.ts";
import { requireDevice, viewerPosition } from "../services/access.ts";
import { idParams } from "./devices.ts";
import { FUEL_TYPES } from "../services/costs.ts";

// Phones: without a tracker, the app shares the position of the phone. The phone is a
// device of its user (kind 'phone'), shared with friends and watched with arrival areas
// like a tracker; it has no commands, alarms or modem data.
//
// The background service of the Android app sends the fixes in batches over HTTPS (also
// those queued while offline) with the upload token of the phone, not with the session
// of the user: the token gives access only to the positions of that phone, a new token
// (sharing started again) replaces the old one and deleting the phone revokes it.
// Replayed batches are skipped by the primary key (device_id, time).
//
// Vehicles: the cars of a user without a tracker (kind 'vehicle'). While driving the phone
// shares "from the vehicle": its fixes carry the id of the vehicle and become the positions
// of the car (trips, costs, odometer, deadlines, areas, shares of the car), not of the
// person. Only the owner of the phone and of the vehicle can do it.

export const MAX_PHONES = 5;
export const MAX_VEHICLES = 10;
const MAX_BATCH = 100;
/** Moving above this speed (km/h), parked below */
const MOVING_SPEED = 5;
/** Fixes less precise than this (m) are shown but don't trigger the arrival areas */
const AREA_ACCURACY = 250;
const FUTURE_TOLERANCE_MS = 5 * 60e3;
/** Pause chosen from the notification: 1 hour, some margin for the clock */
const MAX_PAUSE_MS = 2 * 3600e3;
/** Low battery: notified again after a charge this many points above the threshold of the user */
const RECHARGE_MARGIN = 10;

const fix = z.strictObject({
	time: z.iso.datetime({ offset: true }).transform(value => new Date(value)),
	lat: z.number().min(-90).max(90),
	lon: z.number().min(-180).max(180),
	accuracy: z.number().min(0).max(100000).transform(Math.round),
	speed: z.number().min(0).max(400).transform(Math.round).nullable().default(null),
	altitude: z.number().min(-1000).max(10000).transform(Math.round).nullable().default(null),
	/** Shared from this vehicle of the owner, absent = position of the person */
	vehicleId: z.number().int().positive().optional()
});

export function registerPhoneRoutes (app: FastifyInstance, ctx: Context): void {
	const { sql } = ctx;

	app.post("/api/phones", async (request) => {
		const body = parse(z.strictObject({
			name: z.string().trim().min(1).max(60),
			color: z.string().regex(/^#[0-9A-Fa-f]{6}$/).default("#43A047")
		}), request.body);
		const userId = request.auth!.user.id;
		const id = await sql.begin(async tx => {
			// Serializes the phones of the user (limit)
			await tx`SELECT 1 FROM users WHERE id = ${userId} FOR UPDATE`;
			const [count] = await tx<{ count: number }[]>`
				SELECT count(*)::int AS count FROM device_users du JOIN devices d ON d.id = du.device_id
				WHERE du.user_id = ${userId} AND du.role = 'owner' AND d.kind = 'phone'`;
			if (count!.count >= MAX_PHONES) throw badRequest(`At most ${MAX_PHONES} phones`, "too_many_phones");
			const [device] = await tx<{ id: number }[]>`
				INSERT INTO devices (kind, name, color, model) VALUES ('phone', ${body.name}, ${body.color}, 'phone') RETURNING id`;
			await tx`INSERT INTO device_users (device_id, user_id, role) VALUES (${device!.id}, ${userId}, 'owner')`;
			return device!.id;
		});
		await ctx.hub.refreshUser(userId);
		return { id, uploadToken: await newUploadToken(id) };
	});

	app.post("/api/vehicles", async (request) => {
		const body = parse(z.strictObject({
			name: z.string().trim().min(1).max(60),
			color: z.string().regex(/^#[0-9A-Fa-f]{6}$/).default("#FFB300"),
			model: z.string().trim().max(80).default(""),
			fuelType: z.enum(FUEL_TYPES).nullable().default(null)
		}), request.body);
		const userId = request.auth!.user.id;
		const id = await sql.begin(async tx => {
			await tx`SELECT 1 FROM users WHERE id = ${userId} FOR UPDATE`;
			const [count] = await tx<{ count: number }[]>`
				SELECT count(*)::int AS count FROM device_users du JOIN devices d ON d.id = du.device_id
				WHERE du.user_id = ${userId} AND du.role = 'owner' AND d.kind = 'vehicle'`;
			if (count!.count >= MAX_VEHICLES) throw badRequest(`At most ${MAX_VEHICLES} vehicles`, "too_many_vehicles");
			const [device] = await tx<{ id: number }[]>`
				INSERT INTO devices (kind, name, color, model, vehicle_model, fuel_type)
				VALUES ('vehicle', ${body.name}, ${body.color}, 'vehicle', ${body.model}, ${body.fuelType}) RETURNING id`;
			await tx`INSERT INTO device_users (device_id, user_id, role) VALUES (${device!.id}, ${userId}, 'owner')`;
			return device!.id;
		});
		await ctx.hub.refreshUser(userId);
		return { id };
	});

	/** Low battery for the friends who see the phone, each one with their threshold */
	async function alertBattery (id: number, battery: number): Promise<void> {
		await sql`
			UPDATE device_users SET battery_alerted = false
			WHERE device_id = ${id} AND battery_alerted AND ${battery} >= battery_alert + ${RECHARGE_MARGIN}`;
		// Conditional update: concurrent batches don't notify twice
		const users = await sql<{ user_id: number }[]>`
			UPDATE device_users SET battery_alerted = true
			WHERE device_id = ${id} AND role = 'viewer' AND (expires_at IS NULL OR expires_at > now())
				AND NOT battery_alerted AND ${battery} <= battery_alert
			RETURNING user_id`;
		for (const { user_id } of users) await ctx.notifier.notifyUser(user_id, id, "phone_battery", new Date(), { battery });
	}

	async function newUploadToken (id: number): Promise<string> {
		const token = randomToken();
		await sql`UPDATE devices SET upload_token_hash = ${hashToken(token)} WHERE id = ${id}`;
		return token;
	}

	// Sharing started again (new install, other user before): the old token stops working
	app.post("/api/phones/:id/token", async (request) => {
		const { id } = parse(idParams, request.params);
		const access = await requireDevice(sql, request.auth!.user, id, "owner");
		if (access.kind !== "phone") throw badRequest("Trackers send their positions over their own channel", "not_a_phone");
		return { uploadToken: await newUploadToken(id) };
	});

	app.post("/api/phones/positions", { config: { auth: "none" } }, async (request) => {
		const header = request.headers.authorization ?? "";
		const token = header.startsWith("Bearer ") ? header.slice(7) : "";
		// Positions and/or the state of the phone: battery (%), pause (null = sharing again)
		const body = parse(z.strictObject({
			positions: z.array(fix).max(MAX_BATCH).default([]),
			battery: z.number().int().min(0).max(100).optional(),
			pausedUntil: z.iso.datetime({ offset: true }).transform(value => new Date(value))
				.refine(value => value.getTime() < Date.now() + MAX_PAUSE_MS, "Pause too long").nullable().optional()
		}).refine(value => value.positions.length > 0 || value.battery !== undefined || value.pausedUntil !== undefined, "Nothing to save"), request.body);
		const [phone] = token.length < 20 || token.length > 100 ? [] : await sql<{ id: number }[]>`
			SELECT id FROM devices WHERE upload_token_hash = ${hashToken(token)} AND kind = 'phone'`;
		if (!phone) throw unauthorized("Unknown upload token", "invalid_token");
		const id = phone.id;

		if (body.battery !== undefined || body.pausedUntil !== undefined) {
			const battery = body.battery ?? null;
			const [state] = await sql<{ battery: number | null; paused_until: Date | null }[]>`
				UPDATE devices SET battery = COALESCE(${battery}::int, battery),
					paused_until = ${body.pausedUntil === undefined ? sql`paused_until` : body.pausedUntil}
				WHERE id = ${id} RETURNING battery, paused_until`;
			const event = { type: "device", deviceId: id, battery: state!.battery, pausedUntil: state!.paused_until };
			ctx.hub.toDevice(id, event, event);
			if (battery !== null) await alertBattery(id, battery);
		}

		// Vehicles named by the fixes: owned by the owner of the phone, the others are skipped
		const named = [...new Set(body.positions.flatMap(point => point.vehicleId === undefined ? [] : [point.vehicleId]))];
		const vehicles = new Set(named.length === 0 ? [] : (await sql<{ id: number }[]>`
			SELECT v.device_id AS id FROM device_users v JOIN devices d ON d.id = v.device_id
			JOIN device_users p ON p.user_id = v.user_id AND p.device_id = ${id} AND p.role = 'owner'
			WHERE v.device_id = ANY (${named}) AND v.role = 'owner' AND d.kind = 'vehicle'`).map(row => row.id));

		const now = Date.now();
		// Positions of the person: the shorter retention of the phones
		const oldest = (vehicle: boolean) => now - (vehicle ? ctx.config.RETENTION_DAYS
			: Math.min(ctx.config.PHONE_RETENTION_DAYS, ctx.config.RETENTION_DAYS)) * 86400e3;
		const rows = body.positions
			.filter(point => point.vehicleId === undefined || vehicles.has(point.vehicleId))
			.filter(point => point.time.getTime() > oldest(point.vehicleId !== undefined) && point.time.getTime() < now + FUTURE_TOLERANCE_MS)
			.map(point => ({
				time: point.time,
				device_id: point.vehicleId ?? id,
				lat: point.lat,
				lon: point.lon,
				accuracy: point.accuracy,
				speed: point.speed,
				altitude: point.altitude,
				status: (point.speed ?? 0) >= MOVING_SPEED ? 0 : 1,
				stale: false,
				events: 0
			}));
		if (rows.length === 0) return { accepted: 0 };

		const inserted = await sql<{ time: Date; device_id: number }[]>`
			INSERT INTO positions ${sql(rows)} ON CONFLICT (device_id, time) DO NOTHING RETURNING time, device_id`;
		const fresh = new Set(inserted.map(row => `${row.device_id}/${row.time.getTime()}`));
		const targets = [...new Set(rows.map(row => row.device_id))];
		await sql`UPDATE devices SET last_seen_at = now(), registered_at = COALESCE(registered_at, now()) WHERE id = ANY (${targets})`;

		let accepted = 0;
		for (const target of targets) {
			const added = rows.filter(row => row.device_id === target && fresh.has(`${target}/${row.time.getTime()}`))
				.sort((a, b) => a.time.getTime() - b.time.getTime());
			for (const row of added) {
				ctx.hub.toDevice(target, { type: "position", deviceId: target, position: row }, { type: "position", deviceId: target, position: viewerPosition(row) });
			}
			await ctx.geofences.evaluate(target, added.filter(row => row.accuracy <= AREA_ACCURACY));
			accepted += added.length;
		}
		return { accepted };
	});
}
