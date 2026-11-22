import type { Context } from "../context.ts";
import type { DeviceKind } from "./access.ts";
import type { Sql } from "../db.ts";
import { CONNECTION_COST, FRAME_OVERHEAD, tripsOfKind } from "./analytics.ts";
import type { TrackPoint } from "./analytics.ts";

// Summary of a device per local day (TIMEZONE): km, driving time, trips with the business /
// personal km of the trip log, resting voltage of the car battery, bytes on the SIM, alarm
// points. The job stores the past days (the last ones again: the offline spool of a tracker
// sends late points), today is computed when asked. It feeds the statistics over months,
// the health of the car battery and the odometer.

/** Days recomputed at every run, for the late points */
const RECOMPUTE_DAYS = 3;
/** First summary of a device: at most this far back */
const BACKFILL_DAYS = 400;
/** Kept for years (small rows); phones (people) for a bit more than a year */
const KEEP_DAYS = { tracker: 3 * 366, vehicle: 3 * 366, phone: 400 };
/** Voltage of a battery at rest: parked for at least this long */
const REST_AFTER_MS = 2 * 3600e3;

export interface DayStats {
	day: string;
	distanceKm: number;
	businessKm: number;
	personalKm: number;
	drivingMin: number;
	trips: number;
	maxSpeed: number;
	restVoltage: number | null;
	minVoltage: number | null;
	trafficBytes: number;
	alarms: number;
}

interface Device {
	id: number;
	kind: DeviceKind;
}

const round = (value: number, digits: number) => Math.round(value * 10 ** digits) / 10 ** digits;

function median (values: number[]): number | null {
	if (values.length === 0) return null;
	const sorted = [...values].sort((a, b) => a - b);
	const middle = Math.floor(sorted.length / 2);
	return sorted.length % 2 ? sorted[middle]! : (sorted[middle - 1]! + sorted[middle]!) / 2;
}

/** Median voltage of the points parked for at least 2 hours since the last movement */
export function restVoltage (points: (TrackPoint & { voltage: number | null })[], lastMovingBefore: Date | null): number | null {
	let lastMoving = lastMovingBefore?.getTime() ?? null;
	const values: number[] = [];
	for (const point of points) {
		if (point.status === 0) lastMoving = point.time.getTime();
		else if (point.voltage !== null && lastMoving !== null && point.time.getTime() - lastMoving >= REST_AFTER_MS) values.push(point.voltage);
	}
	const value = median(values);
	return value === null ? null : round(value, 2);
}

/** Today in the time zone, YYYY-MM-DD */
export async function today (sql: Sql, timeZone: string): Promise<string> {
	const [row] = await sql<{ day: string }[]>`SELECT to_char(now() AT TIME ZONE ${timeZone}, 'YYYY-MM-DD') AS day`;
	return row!.day;
}

export async function computeDay (sql: Sql, timeZone: string, device: Device, day: string): Promise<DayStats> {
	const [bounds] = await sql<{ start: Date; end: Date }[]>`
		SELECT (${day}::date::timestamp AT TIME ZONE ${timeZone}) AS start, ((${day}::date + 1)::timestamp AT TIME ZONE ${timeZone}) AS end`;
	const { start, end } = bounds!;
	const [points, tags, [traffic], [before]] = await Promise.all([
		sql<(TrackPoint & { voltage: number | null; events: number })[]>`
			SELECT time, lat, lon, speed, status, stale, voltage, events FROM positions
			WHERE device_id = ${device.id} AND time >= ${start} AND time < ${end} ORDER BY time`,
		sql<{ start: Date; purpose: string | null }[]>`
			SELECT start, purpose FROM trip_tags WHERE device_id = ${device.id} AND start >= ${start} AND start < ${end}`,
		sql<{ frames: number; bytes: number; connections: number }[]>`
			SELECT (count(*) FILTER (WHERE frame_type <> 0))::int AS frames, COALESCE(sum(bytes), 0)::int AS bytes,
				(count(*) FILTER (WHERE frame_type = 0))::int AS connections
			FROM traffic WHERE device_id = ${device.id} AND time >= ${start} AND time < ${end}`,
		sql<{ time: Date | null }[]>`
			SELECT max(time) AS time FROM positions
			WHERE device_id = ${device.id} AND status = 0 AND time < ${start} AND time > ${start}::timestamptz - interval '3 days'`
	]);
	const trips = tripsOfKind(device.kind, points);
	const purposes = new Map(tags.map(tag => [tag.start.getTime(), tag.purpose]));
	const km = (purpose: string) => round(trips.filter(trip => purposes.get(trip.start.getTime()) === purpose).reduce((sum, trip) => sum + trip.distanceKm, 0), 3);
	const voltages = points.map(point => point.voltage).filter((value): value is number => value !== null);
	return {
		day,
		distanceKm: round(trips.reduce((sum, trip) => sum + trip.distanceKm, 0), 3),
		businessKm: km("business"),
		personalKm: km("personal"),
		drivingMin: trips.reduce((sum, trip) => sum + trip.durationMin, 0),
		trips: trips.length,
		maxSpeed: trips.reduce((max, trip) => Math.max(max, trip.maxSpeed), 0),
		restVoltage: device.kind === "tracker" ? restVoltage(points, before!.time) : null,
		minVoltage: voltages.length ? round(Math.min(...voltages), 2) : null,
		trafficBytes: traffic!.bytes + traffic!.frames * FRAME_OVERHEAD + traffic!.connections * CONNECTION_COST,
		alarms: points.filter(point => point.events !== 0).length
	};
}

export async function storeDay (sql: Sql, deviceId: number, stats: DayStats): Promise<void> {
	await sql`
		INSERT INTO daily_stats (device_id, day, distance_km, business_km, personal_km, driving_min, trips, max_speed,
			rest_voltage, min_voltage, traffic_bytes, alarms)
		VALUES (${deviceId}, ${stats.day}, ${stats.distanceKm}, ${stats.businessKm}, ${stats.personalKm}, ${stats.drivingMin},
			${stats.trips}, ${stats.maxSpeed}, ${stats.restVoltage}, ${stats.minVoltage}, ${stats.trafficBytes}, ${stats.alarms})
		ON CONFLICT (device_id, day) DO UPDATE SET distance_km = excluded.distance_km, business_km = excluded.business_km,
			personal_km = excluded.personal_km, driving_min = excluded.driving_min, trips = excluded.trips,
			max_speed = excluded.max_speed, rest_voltage = excluded.rest_voltage, min_voltage = excluded.min_voltage,
			traffic_bytes = excluded.traffic_bytes, alarms = excluded.alarms`;
}

/** Stores the past days not summarized yet and the last ones again */
export async function updateDailyStats (ctx: Context): Promise<void> {
	const { sql, config } = ctx;
	const current = await today(sql, config.TIMEZONE);
	const devices = await sql<(Device & { last: string | null; first: string | null })[]>`
		SELECT d.id, d.kind,
			(SELECT to_char(max(day), 'YYYY-MM-DD') FROM daily_stats WHERE device_id = d.id) AS last,
			(SELECT to_char(min(time) AT TIME ZONE ${config.TIMEZONE}, 'YYYY-MM-DD') FROM positions
				WHERE device_id = d.id AND time > now() - ${`${BACKFILL_DAYS} days`}::interval) AS first
		FROM devices d WHERE d.registered_at IS NOT NULL AND EXISTS (SELECT 1 FROM device_users WHERE device_id = d.id)`;
	for (const device of devices) {
		if (!device.first) continue;
		const days = await sql<{ day: string }[]>`
			SELECT to_char(day, 'YYYY-MM-DD') AS day FROM generate_series(
				GREATEST(${device.first}::date, COALESCE(${device.last}::date - ${RECOMPUTE_DAYS - 1}::int, ${device.first}::date)),
				${current}::date - 1, interval '1 day') day`;
		for (const { day } of days) await storeDay(sql, device.id, await computeDay(sql, config.TIMEZONE, device, day));
	}
	for (const kind of ["tracker", "vehicle", "phone"] as const) {
		await sql`
			DELETE FROM daily_stats WHERE day < now()::date - ${KEEP_DAYS[kind]}::int
				AND device_id IN (SELECT id FROM devices WHERE kind = ${kind})`;
	}
}

/** Stored days of a period (until today when to is null) and today computed now */
export async function daysOf (sql: Sql, timeZone: string, device: Device, from: string, to: string | null = null): Promise<DayStats[]> {
	const current = await today(sql, timeZone);
	const last = to ?? current;
	const rows = await sql<DayStats[]>`
		SELECT to_char(day, 'YYYY-MM-DD') AS day, distance_km AS "distanceKm", business_km AS "businessKm", personal_km AS "personalKm",
			driving_min AS "drivingMin", trips, max_speed AS "maxSpeed", rest_voltage AS "restVoltage", min_voltage AS "minVoltage",
			traffic_bytes::float AS "trafficBytes", alarms
		FROM daily_stats WHERE device_id = ${device.id} AND day >= ${from}::date AND day <= ${last}::date AND day < ${current}::date
		ORDER BY day`;
	return from <= current && last >= current ? [...rows, await computeDay(sql, timeZone, device, current)] : rows;
}

/** Recomputes a past day after a change of the trip log */
export async function refreshDay (sql: Sql, timeZone: string, device: Device, day: string): Promise<void> {
	if (day < await today(sql, timeZone)) await storeDay(sql, device.id, await computeDay(sql, timeZone, device, day));
}
