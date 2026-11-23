import type { Context } from "../context.ts";
import type { DeviceKind } from "./access.ts";
import type { Sql } from "../db.ts";
import { computeDay, today } from "./daily.ts";

// The car behind a tracker: health of its battery from the resting voltage of the days,
// odometer from the km of the trips, deadlines by date and by km. A deadline by km gets an
// expected date from the average km a day of the last weeks, and is near also when that
// date is within its reminder days.

/** Resting voltage of a lead-acid battery: about 75% charged above, 50% below LOW */
export const BATTERY_GOOD = 12.4;
export const BATTERY_LOW = 12.2;
const BATTERY_ALERT_EVERY = "14 days";
/** Days of the average km a day, the least of them with data, the least km a day to expect a date */
const PACE_DAYS = 60;
const PACE_MIN_DAYS = 14;
const PACE_MIN_KM = 1;
/** An expected date further than this is not a date */
const EXPECTED_MAX_DAYS = 3 * 365;

export type BatteryState = "good" | "fair" | "low" | "unknown";

export interface BatteryHealth {
	state: BatteryState;
	/** Mean resting voltage of the last 7 days with a value */
	average: number | null;
	/** Linear trend of the last 30 days, volts per month */
	trendPerMonth: number | null;
}

/** Health from the daily resting voltages (oldest first) */
export function batteryHealth (days: { day: string; restVoltage: number | null }[]): BatteryHealth {
	const values = days.filter((day): day is { day: string; restVoltage: number } => day.restVoltage !== null);
	const last = values.slice(-7);
	if (last.length < 3) return { state: "unknown", average: null, trendPerMonth: null };
	const average = Math.round(last.reduce((sum, day) => sum + day.restVoltage, 0) / last.length * 100) / 100;
	const recent = values.slice(-30);
	let trendPerMonth: number | null = null;
	if (recent.length >= 7) {
		const x = recent.map(day => Date.parse(day.day) / 86400e3);
		const meanX = x.reduce((a, b) => a + b, 0) / x.length;
		const meanY = recent.reduce((sum, day) => sum + day.restVoltage, 0) / recent.length;
		const num = recent.reduce((sum, day, i) => sum + (x[i]! - meanX) * (day.restVoltage - meanY), 0);
		const den = x.reduce((sum, value) => sum + (value - meanX) ** 2, 0);
		trendPerMonth = Math.round(num / den * 30 * 100) / 100;
	}
	return { state: average >= BATTERY_GOOD ? "good" : average >= BATTERY_LOW ? "fair" : "low", average, trendPerMonth };
}

// --- Odometer

/** Current odometer of a device, null until the owner enters a reading */
export async function odometer (sql: Sql, timeZone: string, device: { id: number; kind: DeviceKind }): Promise<number | null> {
	const [row] = await sql<{ base: number | null; day: string | null; km: number }[]>`
		SELECT d.odometer_base AS base, to_char(d.odometer_day, 'YYYY-MM-DD') AS day,
			COALESCE((SELECT sum(distance_km) FROM daily_stats s WHERE s.device_id = d.id AND s.day >= d.odometer_day
				AND s.day < (now() AT TIME ZONE ${timeZone})::date), 0)::float AS km
		FROM devices d WHERE d.id = ${device.id}`;
	if (!row || row.base === null) return null;
	const current = await today(sql, timeZone);
	const live = row.day! <= current ? (await computeDay(sql, timeZone, device, current)).distanceKm : 0;
	return Math.round(row.base + row.km + live);
}

/** New reading: the km already driven today are subtracted, they are counted again */
export async function setOdometer (sql: Sql, timeZone: string, device: { id: number; kind: DeviceKind }, km: number): Promise<void> {
	const current = await today(sql, timeZone);
	const driven = (await computeDay(sql, timeZone, device, current)).distanceKm;
	await sql`UPDATE devices SET odometer_base = ${km - driven}, odometer_day = ${current} WHERE id = ${device.id}`;
}

// --- Deadlines

export type DeadlineState = "ok" | "soon" | "due";
const STAGE: Record<DeadlineState, number> = { ok: 0, soon: 1, due: 2 };

export interface DeadlineRow {
	id: number;
	device_id: number;
	kind: string;
	title: string;
	due_date: string | null;
	due_km: number | null;
	remind_days: number;
	remind_km: number;
	notified_stage: number;
}

/**
 * Average km a day of a vehicle in the last PACE_DAYS days (days without trips included,
 * from the first day with data), null with too few days or almost still
 */
export async function kmPerDay (sql: Sql, deviceId: number, todayIso: string): Promise<number | null> {
	const [row] = await sql<{ km: number; days: number }[]>`
		SELECT COALESCE(sum(distance_km), 0)::float AS km, (${todayIso}::date - min(day))::int AS days FROM daily_stats
		WHERE device_id = ${deviceId} AND day >= ${todayIso}::date - ${PACE_DAYS}::int AND day < ${todayIso}::date`;
	if (!row || row.days === null || row.days < PACE_MIN_DAYS) return null;
	const pace = row.km / row.days;
	return pace >= PACE_MIN_KM ? Math.round(pace * 10) / 10 : null;
}

/**
 * Days and km left (null when not by date / km or without odometer), date expected for the
 * km at the average km a day, and state
 */
export function deadlineState (item: Pick<DeadlineRow, "due_date" | "due_km" | "remind_days" | "remind_km">, odometerKm: number | null, todayIso: string,
	pace: number | null = null): { remainingDays: number | null; remainingKm: number | null; expectedDate: string | null; state: DeadlineState } {
	const remainingDays = item.due_date === null ? null : Math.round((Date.parse(item.due_date) - Date.parse(todayIso)) / 86400e3);
	const remainingKm = item.due_km === null || odometerKm === null ? null : item.due_km - odometerKm;
	const expectedDays = remainingKm !== null && remainingKm > 0 && pace !== null ? Math.ceil(remainingKm / pace) : null;
	const expectedDate = expectedDays === null || expectedDays > EXPECTED_MAX_DAYS ? null
		: new Date(Date.parse(todayIso) + expectedDays * 86400e3).toISOString().slice(0, 10);
	const due = (remainingDays !== null && remainingDays <= 0) || (remainingKm !== null && remainingKm <= 0);
	const soon = (remainingDays !== null && remainingDays <= item.remind_days) || (remainingKm !== null && remainingKm <= item.remind_km) ||
		(expectedDate !== null && expectedDays! <= item.remind_days);
	return { remainingDays, remainingKm, expectedDate, state: due ? "due" : soon ? "soon" : "ok" };
}

/** Job: deadlines getting close or passed, low resting voltage of the car battery */
export async function checkVehicles (ctx: Context): Promise<void> {
	const { sql, config } = ctx;
	const current = await today(sql, config.TIMEZONE);
	const items = await sql<(DeadlineRow & { device_kind: DeviceKind })[]>`
		SELECT m.id, m.device_id, m.kind, m.title, to_char(m.due_date, 'YYYY-MM-DD') AS due_date, m.due_km, m.remind_days,
			m.remind_km, m.notified_stage, d.kind AS device_kind
		FROM maintenance m JOIN devices d ON d.id = m.device_id`;
	const odometers = new Map<number, number | null>();
	const paces = new Map<number, number | null>();
	for (const item of items) {
		if (!odometers.has(item.device_id)) {
			odometers.set(item.device_id, await odometer(sql, config.TIMEZONE, { id: item.device_id, kind: item.device_kind }));
			paces.set(item.device_id, await kmPerDay(sql, item.device_id, current));
		}
		const { remainingDays, remainingKm, expectedDate, state } = deadlineState(item, odometers.get(item.device_id)!, current, paces.get(item.device_id)!);
		const stage = STAGE[state];
		if (stage === item.notified_stage) continue;
		// Conditional update: concurrent jobs don't notify twice
		const updated = await sql`UPDATE maintenance SET notified_stage = ${stage} WHERE id = ${item.id} AND notified_stage = ${item.notified_stage}`;
		if (updated.count !== 1 || stage < item.notified_stage) continue;
		await ctx.notifier.notifyDevice(item.device_id, "maintenance", new Date(), undefined, {
			title: item.title, maintenance: item.kind, due: state as "soon" | "due",
			...(remainingDays === null ? {} : { days: remainingDays }), ...(remainingKm === null ? {} : { km: remainingKm }),
			...(expectedDate === null ? {} : { expected: expectedDate })
		});
	}

	const trackers = await sql<{ id: number }[]>`
		SELECT id FROM devices WHERE kind = 'tracker' AND registered_at IS NOT NULL
			AND (battery_health_alerted_at IS NULL OR battery_health_alerted_at < now() - ${BATTERY_ALERT_EVERY}::interval)
			AND EXISTS (SELECT 1 FROM device_users WHERE device_id = devices.id)`;
	for (const tracker of trackers) {
		const days = await sql<{ day: string; restVoltage: number | null }[]>`
			SELECT to_char(day, 'YYYY-MM-DD') AS day, rest_voltage AS "restVoltage" FROM daily_stats
			WHERE device_id = ${tracker.id} AND day > now()::date - 30 ORDER BY day`;
		const health = batteryHealth(days);
		if (health.state !== "low") continue;
		await sql`UPDATE devices SET battery_health_alerted_at = now() WHERE id = ${tracker.id}`;
		await ctx.notifier.notifyDevice(tracker.id, "battery_health", new Date(), undefined, { voltage: health.average! });
	}
}
