import { z } from "zod";
import type { Sql } from "../db.ts";
import { visibleDevices } from "./access.ts";
import type { DeviceKind } from "./access.ts";
import { bucketFor } from "./analytics.ts";
import { hasCosts, tripCost, vehicleProfile } from "./costs.ts";
import type { TripCost } from "./costs.ts";
import { daysOf, today } from "./daily.ts";
import type { DayStats } from "./daily.ts";
import { deviceName } from "./notifier.ts";
import { loadRefuels, measure } from "./refuels.ts";
import type { MeasuredRefuel } from "./refuels.ts";
import { deadlineState, odometer } from "./vehicle.ts";

// Catalog of the metrics of the dashboards: what a widget can show, from which data, for
// which devices. No free queries: a widget picks a metric of the catalog, a view, the
// devices and a period; the backend checks the access to every device at every request.
//
//  - days: the daily summaries (daily_stats), periods up to 3 years
//  - costs: the km of each day with consumption, price and wear valid on that day
//  - refuels: the refuels of each day (amount, litres, price, consumption measured)
//  - positions / extra: the points of the trackers and their extra data, aggregated in
//    TimescaleDB (time_bucket), periods up to 93 days
//  - odometer, deadlines, status: the current state, no period
//
// Every new value of the platform (a sensor, a daily total, a cost) gets its metric here,
// its texts in the app (lib/screens/dashboards) and its tests.

export const LAYOUT_VERSION = 1;
export const MAX_WIDGETS = 30;
export const MAX_WIDGET_DEVICES = 20;
/** Points of the time series of a device: the bucket grows beyond this */
export const MAX_POINTS = 2000;
export const MAX_SAMPLED_DAYS = 93;
export const MAX_DAYS = 3 * 366;

type Source = "days" | "costs" | "refuels" | "positions" | "extra" | "odometer" | "deadlines" | "status";
type Total = "sum" | "max" | "avg";

interface Metric {
	source: Source;
	/** Kinds of device with this value */
	kinds: readonly DeviceKind[];
	/** How days and vehicles add up (days and costs) */
	total?: Total;
	day?: (day: DayStats) => number | null;
	cost?: keyof TripCost;
	/** Value of the refuels of a day */
	refuel?: (items: MeasuredRefuel[]) => number | null;
	/** Value of a point (positions): a column or an expression of the catalog, never of the request */
	column?: string;
}

const ALL = ["tracker", "vehicle", "phone"] as const;
const CARS = ["tracker", "vehicle"] as const;
const TRACKERS = ["tracker"] as const;

const sumOf = (values: (number | null)[]) => {
	const present = values.filter((value): value is number => value !== null);
	return present.length ? present.reduce((a, b) => a + b, 0) : null;
};
const lastOf = (values: (number | null)[]) => values.filter((value): value is number => value !== null).at(-1) ?? null;

export const METRICS = {
	distance: { source: "days", kinds: ALL, total: "sum", day: day => day.distanceKm },
	businessKm: { source: "days", kinds: ALL, total: "sum", day: day => day.businessKm },
	personalKm: { source: "days", kinds: ALL, total: "sum", day: day => day.personalKm },
	driving: { source: "days", kinds: ALL, total: "sum", day: day => day.drivingMin },
	trips: { source: "days", kinds: ALL, total: "sum", day: day => day.trips },
	maxSpeed: { source: "days", kinds: ALL, total: "max", day: day => day.trips > 0 ? day.maxSpeed : null },
	alarms: { source: "days", kinds: TRACKERS, total: "sum", day: day => day.alarms },
	traffic: { source: "days", kinds: TRACKERS, total: "sum", day: day => day.trafficBytes },
	restVoltage: { source: "days", kinds: TRACKERS, total: "avg", day: day => day.restVoltage },
	cost: { source: "costs", kinds: ALL, total: "sum", cost: "cost" },
	fuelCost: { source: "costs", kinds: ALL, total: "sum", cost: "fuelCost" },
	wearCost: { source: "costs", kinds: ALL, total: "sum", cost: "wearCost" },
	fuel: { source: "costs", kinds: ALL, total: "sum", cost: "fuelL" },
	refuelCost: { source: "refuels", kinds: CARS, total: "sum", refuel: items => sumOf(items.map(item => item.cost)) },
	refuelLitres: { source: "refuels", kinds: CARS, total: "sum", refuel: items => sumOf(items.map(item => item.litres)) },
	refuelPrice: { source: "refuels", kinds: CARS, total: "avg", refuel: items => lastOf(items.map(item => item.pricePerLitre)) },
	realConsumption: { source: "refuels", kinds: CARS, total: "avg", refuel: items => lastOf(items.map(item => item.consumption)) },
	speed: { source: "positions", kinds: ALL, column: "CASE WHEN status = 0 THEN speed END" },
	altitude: { source: "positions", kinds: ALL, column: "altitude" },
	signal: { source: "positions", kinds: TRACKERS, column: "signal" },
	satellites: { source: "positions", kinds: TRACKERS, column: "satellites" },
	voltage: { source: "positions", kinds: TRACKERS, column: "voltage" },
	temperature: { source: "positions", kinds: TRACKERS, column: "temperature" },
	pressure: { source: "positions", kinds: TRACKERS, column: "pressure" },
	extra: { source: "extra", kinds: TRACKERS },
	odometer: { source: "odometer", kinds: CARS },
	deadlines: { source: "deadlines", kinds: CARS },
	status: { source: "status", kinds: ALL }
} satisfies Record<string, Metric>;

export type MetricKey = keyof typeof METRICS;
export const METRIC_KEYS = Object.keys(METRICS) as [MetricKey, ...MetricKey[]];

export const VIEWS = ["number", "line", "bars", "vehicles", "table", "list", "map"] as const;
type View = typeof VIEWS[number];
/** Aggregation of the points (positions, extra data) */
export const AGGS = ["avg", "min", "max", "last"] as const;
export const BUCKETS = ["auto", "hour", "day", "week", "month"] as const;
export const PERIOD_PRESETS = ["today", "7d", "30d", "90d", "12m", "ytd"] as const;

const SERIES_VIEWS: readonly View[] = ["number", "line", "bars", "vehicles", "table"];
const VIEWS_OF: Record<Source, readonly View[]> = {
	days: SERIES_VIEWS,
	costs: SERIES_VIEWS,
	refuels: SERIES_VIEWS,
	positions: SERIES_VIEWS,
	extra: SERIES_VIEWS,
	odometer: ["number", "vehicles", "table"],
	deadlines: ["list"],
	status: ["map", "list"]
};
/** A value for the period, a value per device, a series per device */
type Group = "total" | "vehicle" | "time";
const GROUP: Partial<Record<View, Group>> = { number: "total", vehicles: "vehicle", table: "vehicle", line: "time", bars: "time" };
const SAMPLED: readonly Source[] = ["positions", "extra"];
const DAILY: readonly Source[] = ["days", "costs", "refuels"];

const day = z.string().regex(/^\d{4}-\d{2}-\d{2}$/)
	.refine(value => !Number.isNaN(Date.parse(value)) && value >= "2000-01-01", "invalid date");
export const period = z.union([
	z.enum(PERIOD_PRESETS),
	z.strictObject({ from: day, to: day }).refine(value => value.from <= value.to, "from must precede to")
]);
export type Period = z.output<typeof period>;

const deviceId = z.number().int().positive().max(2 ** 31 - 1);

export const widgetSchema = z.strictObject({
	id: z.string().regex(/^[A-Za-z0-9_-]{1,24}$/),
	metric: z.enum(METRIC_KEYS),
	/** Field of the extra data */
	key: z.string().trim().min(1).max(64).optional(),
	view: z.enum(VIEWS),
	agg: z.enum(AGGS).optional(),
	bucket: z.enum(BUCKETS).optional(),
	devices: z.union([z.literal("all"), z.array(deviceId).min(1).max(MAX_WIDGET_DEVICES)]),
	/** null: the period of the dashboard */
	period: period.nullable().default(null),
	title: z.string().trim().max(60).default(""),
	width: z.number().int().min(1).max(4).default(1),
	height: z.number().int().min(1).max(2).default(1)
}).superRefine((widget, context) => {
	const { source } = METRICS[widget.metric] as Metric;
	const issue = (path: string, message: string) => context.addIssue({ code: "custom", path: [path], message });
	if (!VIEWS_OF[source].includes(widget.view)) issue("view", `not available for ${widget.metric}`);
	if ((source === "extra") !== (widget.key !== undefined)) issue("key", "the field of the extra data, only for extra");
	if (widget.agg !== undefined && !SAMPLED.includes(source)) issue("agg", "only for positions and extra data");
	if (widget.bucket !== undefined && GROUP[widget.view] !== "time") issue("bucket", "only for charts over time");
	if (widget.bucket === "hour" && DAILY.includes(source)) issue("bucket", "hours only for positions and extra data");
	if (Array.isArray(widget.devices) && new Set(widget.devices).size !== widget.devices.length) issue("devices", "repeated");
});
export type Widget = z.output<typeof widgetSchema>;

const uniqueIds = (widgets: Widget[]) => new Set(widgets.map(widget => widget.id)).size === widgets.length;
export const widgetList = z.array(widgetSchema).max(MAX_WIDGETS).refine(uniqueIds, "repeated widget id");

export const layoutSchema = z.strictObject({
	version: z.literal(LAYOUT_VERSION),
	period: period.default("30d"),
	widgets: widgetList
});
export type Layout = z.output<typeof layoutSchema>;

/**
 * A saved layout as it is valid now: the widgets of metrics or options removed from the
 * catalog are dropped, the rest stays. The version is for future conversions.
 */
export function readLayout (stored: unknown): Layout {
	const value = (stored ?? {}) as { period?: unknown; widgets?: unknown };
	const saved = period.safeParse(value.period);
	const widgets = Array.isArray(value.widgets)
		? value.widgets.flatMap(item => {
			const parsed = widgetSchema.safeParse(item);
			return parsed.success ? [parsed.data] : [];
		})
		: [];
	return { version: LAYOUT_VERSION, period: saved.success ? saved.data : "30d", widgets };
}

// --- Periods: local days in the time zone of the platform

const addDays = (iso: string, days: number) => new Date(Date.parse(`${iso}T00:00:00Z`) + days * 86400e3).toISOString().slice(0, 10);
const daysBetween = (from: string, to: string) => Math.round((Date.parse(to) - Date.parse(from)) / 86400e3) + 1;

/** First and last day of a period (YYYY-MM-DD), the last one at most today */
export function resolvePeriod (value: Period, todayIso: string): { from: string; to: string } {
	if (typeof value === "object") return { from: value.from, to: value.to < todayIso ? value.to : todayIso };
	const year = Number(todayIso.slice(0, 4));
	const month = Number(todayIso.slice(5, 7));
	const from = {
		today: todayIso,
		"7d": addDays(todayIso, -6),
		"30d": addDays(todayIso, -29),
		"90d": addDays(todayIso, -89),
		"12m": new Date(Date.UTC(year, month - 12, 1)).toISOString().slice(0, 10),
		ytd: `${year}-01-01`
	}[value];
	return { from, to: todayIso };
}

/** Monday of the ISO week of a day */
export function weekOf (iso: string): string {
	const date = new Date(`${iso}T00:00:00Z`);
	date.setUTCDate(date.getUTCDate() - (date.getUTCDay() + 6) % 7);
	return date.toISOString().slice(0, 10);
}

const round = (value: number) => Math.round(value * 100) / 100;

function total (values: (number | null)[], kind: Total): number | null {
	const present = values.filter((value): value is number => value !== null);
	if (present.length === 0) return null;
	if (kind === "max") return Math.max(...present);
	const sum = present.reduce((a, b) => a + b, 0);
	return round(kind === "sum" ? sum : sum / present.length);
}

// Buckets of the points: the first one with at most MAX_POINTS values
const INTERVALS: [string, number][] = [
	["2 minutes", 120e3], ["10 minutes", 600e3], ["1 hour", 3600e3], ["6 hours", 21600e3],
	["1 day", 86400e3], ["1 week", 7 * 86400e3], ["1 month", 31 * 86400e3]
];
const BUCKET_INTERVAL = { hour: "1 hour", day: "1 day", week: "1 week", month: "1 month" } as const;

function sampledBucket (bucket: typeof BUCKETS[number], start: Date, end: Date): string {
	const wanted = bucket === "auto" ? bucketFor(start, end) : BUCKET_INTERVAL[bucket];
	const span = end.getTime() - start.getTime();
	const index = INTERVALS.findIndex(([name]) => name === wanted);
	return INTERVALS.slice(index).find(([, ms]) => span / ms <= MAX_POINTS)?.[0] ?? "1 month";
}

/** Days grouped by day, week or month: about up to 60 bars */
function dailyBucket (bucket: typeof BUCKETS[number], days: number): "1 day" | "1 week" | "1 month" {
	if (bucket === "day" || (bucket === "auto" && days <= 45)) return "1 day";
	if (bucket === "week" || (bucket === "auto" && days <= 200)) return "1 week";
	return "1 month";
}

const dayKey = { "1 day": (iso: string) => iso, "1 week": weekOf, "1 month": (iso: string) => `${iso.slice(0, 7)}-01` };

/** A widget that can't be computed: its code, the others are computed anyway */
class WidgetError extends Error {
	readonly code: string;

	constructor (code: string) {
		super(code);
		this.code = code;
	}
}

interface DeviceInfo {
	id: number;
	name: string;
	color: string;
	kind: DeviceKind;
	archived: boolean;
}

export type WidgetResult = { status: "error"; error: string } | ({ status: "ok" } & Record<string, unknown>);

/**
 * Values of some widgets for a user. Each device of a widget is checked: deleted, no
 * longer shared, of another kind or only shared (viewers see only the status) → in the
 * "unavailable" list of the widget, never an error and never its data.
 */
export async function computeWidgets (sql: Sql, timeZone: string, userId: number, dashboardPeriod: Period, widgets: Widget[]):
	Promise<Record<string, WidgetResult>> {
	const access = await visibleDevices(sql, userId);
	const rows = await sql<{ id: number; name: string; imei: string | null; color: string; kind: DeviceKind; archived: boolean }[]>`
		SELECT id, name, imei, color, kind, archived_at IS NOT NULL AS archived FROM devices WHERE id = ANY (${[...access.keys()]})`;
	const devices = new Map<number, DeviceInfo>(rows.map(row => [row.id, { ...row, name: deviceName(row) }]));
	const todayIso = await today(sql, timeZone);

	// The same data of a device in more widgets is read once
	const cache = new Map<string, Promise<unknown>>();
	const once = <T>(key: string, load: () => Promise<T>): Promise<T> => {
		if (!cache.has(key)) cache.set(key, load());
		return cache.get(key) as Promise<T>;
	};
	const daysOfDevice = (device: DeviceInfo, from: string, to: string) =>
		once(`days:${device.id}:${from}:${to}`, () => daysOf(sql, timeZone, device, from, to));
	const profileOf = (id: number) => once(`profile:${id}`, () => vehicleProfile(sql, id));
	// All the refuels: an interval can start before the period
	const refuelsOf = (id: number) => once(`refuels:${id}`, async () => measure(await loadRefuels(sql, id)));
	const odometerOf = (device: DeviceInfo) => once(`odometer:${device.id}`, () => odometer(sql, timeZone, device));
	const bounds = (from: string, to: string) => once(`bounds:${from}:${to}`, async () => (await sql<{ start: Date; end: Date }[]>`
		SELECT (${from}::date::timestamp AT TIME ZONE ${timeZone}) AS start,
			LEAST(now(), (${to}::date + 1)::timestamp AT TIME ZONE ${timeZone}) AS end`)[0]!);

	/** Value of each day of a device: daily summary or cost of the km of that day */
	const dayValues = async (metric: Metric, device: DeviceInfo, from: string, to: string) => {
		if (metric.source === "refuels") {
			const byDay = new Map<string, MeasuredRefuel[]>();
			for (const item of await refuelsOf(device.id)) {
				if (item.day >= from && item.day <= to) byDay.set(item.day, [...byDay.get(item.day) ?? [], item]);
			}
			return [...byDay].map(([day, items]) => ({ day, value: metric.refuel!(items) }));
		}
		const days = await daysOfDevice(device, from, to);
		if (metric.source === "days") return days.map(item => ({ day: item.day, value: metric.day!(item) }));
		const profile = await profileOf(device.id);
		const costs = hasCosts(profile);
		return days.map(item => ({ day: item.day, value: costs ? tripCost(item.distanceKm, profile, item.day)[metric.cost!] : null }));
	};

	const daily = async (widget: Widget, metric: Metric, ids: DeviceInfo[], from: string, to: string) => {
		const days = daysBetween(from, to);
		if (days > MAX_DAYS) throw new WidgetError("period_too_long");
		const values = await Promise.all(ids.map(async device => ({ id: device.id, days: await dayValues(metric, device, from, to) })));
		const group = GROUP[widget.view]!;
		if (group === "total") return { value: total(values.flatMap(item => item.days.map(entry => entry.value)), metric.total!) };
		if (group === "vehicle") {
			return { values: values.map(item => ({ deviceId: item.id, value: total(item.days.map(entry => entry.value), metric.total!) })) };
		}
		const bucket = dailyBucket(widget.bucket ?? "auto", days);
		return {
			bucket,
			series: values.map(item => {
				const buckets = new Map<string, (number | null)[]>();
				for (const entry of item.days) {
					const key = dayKey[bucket](entry.day);
					buckets.set(key, [...buckets.get(key) ?? [], entry.value]);
				}
				return { deviceId: item.id, points: [...buckets].map(([key, list]) => [key, total(list, metric.total!)]) };
			})
		};
	};

	const sampled = async (widget: Widget, metric: Metric, ids: DeviceInfo[], from: string, to: string) => {
		if (daysBetween(from, to) > MAX_SAMPLED_DAYS) throw new WidgetError("period_too_long");
		const { start, end } = await bounds(from, to);
		const group = GROUP[widget.view]!;
		const bucket = group === "time" ? sampledBucket(widget.bucket ?? "auto", start, end) : null;
		const list = ids.map(device => device.id);
		const empty = { total: { value: null }, vehicle: { values: [] }, time: { bucket, series: [] } }[group];
		if (list.length === 0) return empty;

		const table = sql.unsafe(metric.source === "extra" ? "device_extra" : "positions");
		const value = metric.source === "extra"
			? sql`CASE WHEN jsonb_typeof(data -> ${widget.key!}) = 'number' THEN (data ->> ${widget.key!})::float END`
			: sql.unsafe(metric.column!);
		const agg = widget.agg ?? "avg";
		const aggregate = agg === "last" ? sql`last(${value}, time)` : sql`${sql.unsafe(agg)}(${value})`;
		const result = sql`round((${aggregate} FILTER (WHERE ${value} IS NOT NULL))::numeric, 2)::float`;
		const where = sql`device_id = ANY (${list}) AND time >= ${start} AND time < ${end}`;

		if (group === "total") {
			const [row] = await sql<{ value: number | null }[]>`SELECT ${result} AS value FROM ${table} WHERE ${where}`;
			return { value: row!.value };
		}
		if (group === "vehicle") {
			const rows = await sql<{ device_id: number; value: number | null }[]>`
				SELECT device_id, ${result} AS value FROM ${table} WHERE ${where} GROUP BY 1`;
			const byDevice = new Map(rows.map(row => [row.device_id, row.value]));
			return { values: list.map(id => ({ deviceId: id, value: byDevice.get(id) ?? null })) };
		}
		const rows = await sql<{ device_id: number; time: Date; value: number | null }[]>`
			SELECT device_id, time_bucket(${bucket}::interval, time, ${timeZone}) AS time, ${result} AS value
			FROM ${table} WHERE ${where} GROUP BY 1, 2 ORDER BY 1, 2`;
		return {
			bucket,
			series: list.map(id => ({ deviceId: id, points: rows.filter(row => row.device_id === id).map(row => [row.time, row.value]) }))
		};
	};

	const current = async (widget: Widget, metric: Metric, ids: DeviceInfo[]) => {
		if (metric.source === "status") return {};
		if (metric.source === "odometer") {
			const values = await Promise.all(ids.map(async device => ({ deviceId: device.id, value: await odometerOf(device) })));
			return GROUP[widget.view] === "total" ? { value: total(values.map(item => item.value), "sum") } : { values };
		}
		// Deadlines of the vehicles, the closest first
		const items = [];
		const deadlines = ids.length === 0 ? [] : await sql<{ device_id: number; kind: string; title: string; due_date: string | null;
			due_km: number | null; remind_days: number; remind_km: number }[]>`
			SELECT device_id, kind, title, to_char(due_date, 'YYYY-MM-DD') AS due_date, due_km, remind_days, remind_km
			FROM maintenance WHERE device_id = ANY (${ids.map(device => device.id)})`;
		for (const row of deadlines) {
			const km = await odometerOf(devices.get(row.device_id)!);
			items.push({ deviceId: row.device_id, kind: row.kind, title: row.title, dueDate: row.due_date, dueKm: row.due_km,
				...deadlineState(row, km, todayIso) });
		}
		const order = ["due", "soon", "ok"];
		items.sort((a, b) => order.indexOf(a.state) - order.indexOf(b.state) ||
			(a.remainingDays ?? Infinity) - (b.remainingDays ?? Infinity) || (a.remainingKm ?? Infinity) - (b.remainingKm ?? Infinity));
		return { items: items.slice(0, 20) };
	};

	const compute = async (widget: Widget): Promise<WidgetResult> => {
		const metric = METRICS[widget.metric] as Metric;
		// Viewers of a share see only the status; "all" = the active devices of the user
		const usable = (id: number) => {
			const item = access.get(id);
			return item !== undefined && (metric.source === "status" || item.role === "owner") && metric.kinds.includes(item.kind);
		};
		const wanted = widget.devices === "all"
			? [...access.keys()].filter(id => usable(id) && !devices.get(id)!.archived).sort((a, b) => a - b)
			: widget.devices;
		const ids = wanted.filter(usable).map(id => devices.get(id)!);
		const { from, to } = resolvePeriod(widget.period ?? dashboardPeriod, todayIso);
		try {
			const data = DAILY.includes(metric.source)
				? await daily(widget, metric, ids, from, to)
				: SAMPLED.includes(metric.source) ? await sampled(widget, metric, ids, from, to) : await current(widget, metric, ids);
			return {
				status: "ok",
				from,
				to,
				devices: ids.map(device => ({ id: device.id, name: device.name, color: device.color, kind: device.kind })),
				unavailable: wanted.filter(id => !usable(id)),
				...data
			};
		} catch (error) {
			if (error instanceof WidgetError) return { status: "error", error: error.code };
			throw error;
		}
	};

	const results = await Promise.all(widgets.map(async widget => [widget.id, await compute(widget)] as const));
	return Object.fromEntries(results);
}
