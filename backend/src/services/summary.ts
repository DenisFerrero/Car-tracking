import type { Context } from "../context.ts";
import type { Sql } from "../db.ts";
import type { DeviceKind } from "./access.ts";
import { hasCosts, sumCosts, tripCost, vehicleProfile } from "./costs.ts";
import type { TripCost } from "./costs.ts";
import { daysOf, today } from "./daily.ts";
import { deviceName } from "./notifier.ts";
import { loadRefuels, measure, summary as refuelSummary } from "./refuels.ts";
import { deadlineState, odometer } from "./vehicle.ts";

// Summary of a month for a user: for each device owned km, driving time, trips, costs of
// the trips, refuels and bytes on the SIM, the totals with the month before, and the
// deadlines coming up. At the start of every month (from SUMMARY_HOUR, local time) the
// users who want it get a notification with the totals of the month just ended; the app
// opens the summary. One notification per user and month (monthly_summaries).

const SUMMARY_HOUR = 8;

export interface DeviceMonth {
	id: number;
	name: string;
	color: string;
	kind: DeviceKind;
	distanceKm: number;
	businessKm: number;
	personalKm: number;
	drivingMin: number;
	trips: number;
	maxSpeed: number;
	/** Costs of the trips, null without consumption or wear */
	cost: TripCost | null;
	refuels: { count: number; litres: number; cost: number | null; consumption: number | null };
	/** Trackers: bytes on the SIM */
	trafficBytes: number | null;
	alarms: number;
}

export interface MonthTotals {
	distanceKm: number;
	drivingMin: number;
	trips: number;
	cost: number | null;
	refuelCost: number | null;
}

const round = (value: number, digits = 1) => Math.round(value * 10 ** digits) / 10 ** digits;
const sumOrNull = (values: (number | null)[]) => {
	const present = values.filter((value): value is number => value !== null);
	return present.length ? round(present.reduce((a, b) => a + b, 0), 2) : null;
};

/** First and last day of a month YYYY-MM */
export function monthDays (month: string): { from: string; to: string } {
	const [year, number] = month.split("-").map(Number) as [number, number];
	return { from: `${month}-01`, to: new Date(Date.UTC(year, number, 0)).toISOString().slice(0, 10) };
}

/** The month before YYYY-MM */
export function previousMonth (month: string): string {
	const [year, number] = month.split("-").map(Number) as [number, number];
	return new Date(Date.UTC(year, number - 2, 1)).toISOString().slice(0, 7);
}

async function devicesMonth (sql: Sql, timeZone: string, devices: { id: number; name: string; imei: string | null; color: string; kind: DeviceKind }[],
	month: string): Promise<DeviceMonth[]> {
	const { from, to } = monthDays(month);
	return Promise.all(devices.map(async device => {
		const days = await daysOf(sql, timeZone, device, from, to);
		const profile = await vehicleProfile(sql, device.id);
		const refuels = measure(await loadRefuels(sql, device.id)).filter(item => item.day >= from && item.day <= to);
		const totals = refuelSummary(refuels);
		const sum = (key: "distanceKm" | "businessKm" | "personalKm" | "drivingMin" | "trips" | "alarms" | "trafficBytes") =>
			days.reduce((total, item) => total + item[key], 0);
		return {
			id: device.id,
			name: deviceName(device),
			color: device.color,
			kind: device.kind,
			distanceKm: round(sum("distanceKm")),
			businessKm: round(sum("businessKm")),
			personalKm: round(sum("personalKm")),
			drivingMin: sum("drivingMin"),
			trips: sum("trips"),
			maxSpeed: days.reduce((max, item) => Math.max(max, item.maxSpeed), 0),
			cost: hasCosts(profile) ? sumCosts(days.map(item => tripCost(item.distanceKm, profile, item.day))) : null,
			refuels: { count: totals.count, litres: totals.litres, cost: totals.cost, consumption: totals.averageConsumption },
			trafficBytes: device.kind === "tracker" ? sum("trafficBytes") : null,
			alarms: sum("alarms")
		};
	}));
}

function totalsOf (devices: DeviceMonth[]): MonthTotals {
	return {
		distanceKm: round(devices.reduce((sum, item) => sum + item.distanceKm, 0)),
		drivingMin: devices.reduce((sum, item) => sum + item.drivingMin, 0),
		trips: devices.reduce((sum, item) => sum + item.trips, 0),
		cost: sumOrNull(devices.map(item => item.cost?.cost ?? null)),
		refuelCost: sumOrNull(devices.map(item => item.refuels.cost))
	};
}

/** Summary of a month of a user: devices owned (not archived), totals, month before, deadlines */
export async function monthSummary (sql: Sql, timeZone: string, userId: number, month: string) {
	const devices = await sql<{ id: number; name: string; imei: string | null; color: string; kind: DeviceKind }[]>`
		SELECT d.id, d.name, d.imei, d.color, d.kind FROM device_users du JOIN devices d ON d.id = du.device_id
		WHERE du.user_id = ${userId} AND du.role = 'owner' AND d.archived_at IS NULL ORDER BY d.name, d.id`;
	const [current, before] = await Promise.all([devicesMonth(sql, timeZone, devices, month), devicesMonth(sql, timeZone, devices, previousMonth(month))]);
	const todayIso = await today(sql, timeZone);
	const cars = devices.filter(device => device.kind !== "phone");
	const deadlines = cars.length === 0 ? [] : await sql<{ device_id: number; kind: string; title: string; due_date: string | null; due_km: number | null;
		remind_days: number; remind_km: number }[]>`
		SELECT device_id, kind, title, to_char(due_date, 'YYYY-MM-DD') AS due_date, due_km, remind_days, remind_km
		FROM maintenance WHERE device_id = ANY (${cars.map(device => device.id)})`;
	const odometers = new Map(await Promise.all(cars.map(async device => [device.id, await odometer(sql, timeZone, device)] as const)));
	const coming = deadlines
		.map(row => ({ deviceId: row.device_id, kind: row.kind, title: row.title, dueDate: row.due_date, dueKm: row.due_km,
			...deadlineState(row, odometers.get(row.device_id) ?? null, todayIso) }))
		.filter(item => item.state !== "ok")
		.sort((a, b) => (a.state === b.state ? 0 : a.state === "due" ? -1 : 1) || (a.remainingDays ?? Infinity) - (b.remainingDays ?? Infinity));
	const { from, to } = monthDays(month);
	return {
		month,
		from,
		to,
		complete: to < todayIso,
		devices: current,
		totals: totalsOf(current),
		previous: totalsOf(before),
		deadlines: coming
	};
}

/**
 * Job: from the first day of the month at SUMMARY_HOUR, the summary of the month just
 * ended to each user who wants it and had any activity in it. Returns the users notified.
 */
export async function sendMonthlySummaries (ctx: Context, now = new Date()): Promise<number> {
	const { sql, config } = ctx;
	const local = Object.fromEntries(new Intl.DateTimeFormat("en-CA", { timeZone: config.TIMEZONE, year: "numeric", month: "2-digit", hour: "2-digit", hourCycle: "h23" })
		.formatToParts(now).map(part => [part.type, part.value]));
	if (Number(local.hour) < SUMMARY_HOUR) return 0;
	const month = previousMonth(`${local.year}-${local.month}`);
	const { from, to } = monthDays(month);
	// Users with a device that drove or was refuelled in the month, not notified yet
	const users = await sql<{ id: number }[]>`
		SELECT u.id FROM users u WHERE u.monthly_summary AND NOT u.disabled
			AND NOT EXISTS (SELECT 1 FROM monthly_summaries s WHERE s.user_id = u.id AND s.month = ${from}::date)
			AND EXISTS (SELECT 1 FROM device_users du JOIN devices d ON d.id = du.device_id
				WHERE du.user_id = u.id AND du.role = 'owner' AND d.archived_at IS NULL AND (
					EXISTS (SELECT 1 FROM daily_stats s WHERE s.device_id = d.id AND s.day BETWEEN ${from}::date AND ${to}::date AND s.distance_km > 0)
					OR EXISTS (SELECT 1 FROM refuels r WHERE r.device_id = d.id AND r.day BETWEEN ${from}::date AND ${to}::date)))`;
	let sent = 0;
	for (const user of users) {
		// Conditional insert: concurrent jobs don't notify twice
		const inserted = await sql`INSERT INTO monthly_summaries (user_id, month) VALUES (${user.id}, ${from}) ON CONFLICT DO NOTHING`;
		if (inserted.count !== 1) continue;
		const { totals } = await monthSummary(sql, config.TIMEZONE, user.id, month);
		await ctx.notifier.notifySummary(user.id, month, totals);
		sent++;
	}
	return sent;
}
