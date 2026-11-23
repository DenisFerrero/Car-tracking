import type { Context } from "../context.ts";
import type { Sql } from "../db.ts";
import { STATUS } from "../protocol/protocol.ts";

// Parking of a vehicle: where and since when, the end of the paid time when there is one
// (a ticket or the disc; none when it's paid by the minute, e.g. Telepass), a reminder
// some minutes before the end and a notification at the end, to who set it. It ends when
// the vehicle leaves (a point moving after it started) or by hand. When the ignition of a
// tracker goes off the owners who want it get a proposal to set it.

/** A point older than this (offline queue sent later) doesn't propose a parking */
const PROMPT_MAX_AGE = 10 * 60e3;
/** At most one proposal per vehicle in this time (more ignition offs in a few minutes) */
const PROMPT_EVERY = 10 * 60e3;
/** A point moving at least this fast after the start ends the parking (km/h) */
const LEAVING_SPEED = 10;
const LEAVING_AFTER = "2 minutes";
/** An end passed by more than this (backend down) is not notified any more */
const EXPIRED_NOTIFY_WITHIN = "1 hour";
const KEEP_ENDED = "30 days";

export interface ParkingRow {
	id: number;
	device_id: number;
	user_id: number;
	lat: number | null;
	lon: number | null;
	started_at: Date;
	expires_at: Date | null;
	remind_minutes: number;
	note: string;
}

export const present = (row: ParkingRow) => ({
	id: row.id,
	lat: row.lat,
	lon: row.lon,
	startedAt: row.started_at,
	expiresAt: row.expires_at,
	remindMinutes: row.remind_minutes,
	note: row.note,
	userId: row.user_id
});

export async function activeParking (sql: Sql, deviceId: number): Promise<ParkingRow | null> {
	const [row] = await sql<ParkingRow[]>`
		SELECT id, device_id, user_id, lat, lon, started_at, expires_at, remind_minutes, note FROM parkings
		WHERE device_id = ${deviceId} AND ended_at IS NULL`;
	return row ?? null;
}

const prompted = new Map<number, number>();

/** Points just stored of a tracker: an ignition off proposes a parking to the owners who want it */
export async function promptParking (ctx: Context, deviceId: number, points: { time: Date; status: number; lat: number | null; lon: number | null }[],
	now = Date.now()): Promise<boolean> {
	const off = points.filter(point => point.status === STATUS.ENGINE_OFF && now - point.time.getTime() <= PROMPT_MAX_AGE).at(-1);
	if (!off || now - (prompted.get(deviceId) ?? 0) < PROMPT_EVERY) return false;
	const [device] = await ctx.sql<{ prompt: boolean }[]>`SELECT parking_prompt AS prompt FROM devices WHERE id = ${deviceId}`;
	if (!device?.prompt || await activeParking(ctx.sql, deviceId)) return false;
	prompted.set(deviceId, now);
	const owners = await ctx.sql<{ user_id: number }[]>`SELECT user_id FROM device_users WHERE device_id = ${deviceId} AND role = 'owner'`;
	for (const owner of owners) {
		await ctx.notifier.notifyParking(owner.user_id, deviceId, "parking_prompt", off.time, {}, { lat: off.lat, lon: off.lon });
	}
	return true;
}

/** Job of every minute: parkings ended by leaving, reminders, ends, old parkings removed */
export async function runParkings (ctx: Context): Promise<void> {
	const { sql } = ctx;
	await sql`
		UPDATE parkings p SET ended_at = now() WHERE ended_at IS NULL AND EXISTS (
			SELECT 1 FROM positions x WHERE x.device_id = p.device_id AND x.time > p.started_at + ${LEAVING_AFTER}::interval
				AND x.status = ${STATUS.MOVING} AND x.speed >= ${LEAVING_SPEED})`;

	// Conditional updates: concurrent jobs don't notify twice
	const reminders = await sql<(ParkingRow & { minutes: number })[]>`
		UPDATE parkings SET reminded_at = now()
		WHERE ended_at IS NULL AND reminded_at IS NULL AND remind_minutes > 0 AND expires_at > now()
			AND expires_at - make_interval(mins => remind_minutes) <= now()
		RETURNING id, device_id, user_id, lat, lon, expires_at, CEIL(EXTRACT(EPOCH FROM expires_at - now()) / 60)::int AS minutes`;
	for (const row of reminders) {
		await ctx.notifier.notifyParking(row.user_id, row.device_id, "parking_reminder", row.expires_at!, { minutes: row.minutes }, row);
	}
	const expired = await sql<(ParkingRow & { late: boolean })[]>`
		UPDATE parkings SET expired_notified_at = now()
		WHERE ended_at IS NULL AND expired_notified_at IS NULL AND expires_at <= now()
		RETURNING id, device_id, user_id, lat, lon, expires_at, expires_at < now() - ${EXPIRED_NOTIFY_WITHIN}::interval AS late`;
	for (const row of expired.filter(item => !item.late)) {
		await ctx.notifier.notifyParking(row.user_id, row.device_id, "parking_expired", row.expires_at!, {}, row);
	}
	await sql`DELETE FROM parkings WHERE ended_at < now() - ${KEEP_ENDED}::interval`;
}
