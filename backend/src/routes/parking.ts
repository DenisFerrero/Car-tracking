import type { FastifyInstance } from "fastify";
import { z } from "zod";
import type { Context } from "../context.ts";
import { badRequest, notFound, parse } from "../http/errors.ts";
import { requireTracker, requireVehicle } from "../services/access.ts";
import { activeParking, present } from "../services/parking.ts";
import { idParams } from "./devices.ts";

// Parking of a vehicle of the user (owner, trackers and vehicles): the current one with the
// latest position as the proposed place, start or change (end of the ticket optional,
// reminder), end by hand; the proposal at the ignition off (trackers).

/** The end of a ticket: within a month (season tickets, long stays) */
const MAX_EXPIRY_DAYS = 31;

const parkingBody = z.strictObject({
	/** Where: default the latest position of the vehicle */
	lat: z.number().min(-90).max(90).optional(),
	lon: z.number().min(-180).max(180).optional(),
	expiresAt: z.iso.datetime({ offset: true }).nullable().default(null),
	remindMinutes: z.number().int().min(0).max(120).default(10),
	note: z.string().trim().max(200).default("")
}).refine(body => (body.lat === undefined) === (body.lon === undefined), "lat and lon together");

export function registerParkingRoutes (app: FastifyInstance, ctx: Context): void {
	const { sql } = ctx;

	/** Latest position of the vehicle (last 60 days) */
	const latest = async (deviceId: number) => {
		const [row] = await sql<{ lat: number; lon: number; time: Date }[]>`
			SELECT lat, lon, time FROM positions
			WHERE device_id = ${deviceId} AND time > now() - interval '60 days' AND lat IS NOT NULL
			ORDER BY time DESC LIMIT 1`;
		return row ?? null;
	};

	const state = async (deviceId: number) => {
		const [device] = await sql<{ prompt: boolean }[]>`SELECT parking_prompt AS prompt FROM devices WHERE id = ${deviceId}`;
		const parking = await activeParking(sql, deviceId);
		return { parking: parking && present(parking), position: await latest(deviceId), prompt: device!.prompt };
	};

	app.get("/api/devices/:id/parking", async (request) => {
		const { id } = parse(idParams, request.params);
		await requireVehicle(sql, request.auth!.user, id);
		return state(id);
	});

	/** Starts the parking, or changes the current one (a new end sends the reminder again) */
	app.put("/api/devices/:id/parking", async (request) => {
		const { id } = parse(idParams, request.params);
		const body = parse(parkingBody, request.body);
		await requireVehicle(sql, request.auth!.user, id);
		if (body.expiresAt !== null) {
			const ms = Date.parse(body.expiresAt) - Date.now();
			if (ms <= 0) throw badRequest("The end of the parking has passed", "parking_past");
			if (ms > MAX_EXPIRY_DAYS * 86400e3) throw badRequest(`At most ${MAX_EXPIRY_DAYS} days`, "parking_too_long");
		}
		const current = await activeParking(sql, id);
		const where = body.lat !== undefined ? { lat: body.lat, lon: body.lon! } : current ?? await latest(id);
		if (current) {
			const changed = (current.expires_at?.getTime() ?? null) !== (body.expiresAt === null ? null : Date.parse(body.expiresAt));
			await sql`
				UPDATE parkings SET expires_at = ${body.expiresAt}, remind_minutes = ${body.remindMinutes}, note = ${body.note},
					lat = ${where?.lat ?? null}, lon = ${where?.lon ?? null}
					${changed ? sql`, reminded_at = NULL, expired_notified_at = NULL` : sql``}
				WHERE id = ${current.id}`;
		} else {
			await sql`
				INSERT INTO parkings (device_id, user_id, lat, lon, expires_at, remind_minutes, note)
				VALUES (${id}, ${request.auth!.user.id}, ${where?.lat ?? null}, ${where?.lon ?? null}, ${body.expiresAt}, ${body.remindMinutes}, ${body.note})
				ON CONFLICT (device_id) WHERE ended_at IS NULL DO NOTHING`;
		}
		return state(id);
	});

	app.delete("/api/devices/:id/parking", async (request) => {
		const { id } = parse(idParams, request.params);
		await requireVehicle(sql, request.auth!.user, id);
		const ended = await sql`UPDATE parkings SET ended_at = now() WHERE device_id = ${id} AND ended_at IS NULL`;
		if (ended.count === 0) throw notFound("No parking");
		return state(id);
	});

	/** Proposal of a parking when the ignition goes off */
	app.put("/api/devices/:id/parking/prompt", async (request) => {
		const { id } = parse(idParams, request.params);
		const { enabled } = parse(z.strictObject({ enabled: z.boolean() }), request.body);
		await requireTracker(sql, request.auth!.user, id);
		await sql`UPDATE devices SET parking_prompt = ${enabled} WHERE id = ${id}`;
		return state(id);
	});
}
