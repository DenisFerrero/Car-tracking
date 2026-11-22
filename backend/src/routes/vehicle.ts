import type { FastifyInstance } from "fastify";
import { z } from "zod";
import type { Context } from "../context.ts";
import { badRequest, notFound, parse } from "../http/errors.ts";
import { requireDevice, requireTracker } from "../services/access.ts";
import { FUEL_TYPES, FUEL_UNITS, RATE_KINDS, convertConsumption, rateOn, vehicleProfile } from "../services/costs.ts";
import type { RateKind, VehicleProfile } from "../services/costs.ts";
import { daysOf, today } from "../services/daily.ts";
import type { DayStats } from "../services/daily.ts";
import { BATTERY_GOOD, BATTERY_LOW, batteryHealth, deadlineState, odometer, setOdometer } from "../services/vehicle.ts";
import type { DeadlineRow } from "../services/vehicle.ts";
import { idParams } from "./devices.ts";

// Statistics over months (owner, trackers and phones), costs of the trips (consumption,
// fuel, wear), and the car behind a tracker: odometer, health of the battery, deadlines.

export const MAX_DEADLINES = 30;
const KINDS = ["service", "inspection", "insurance", "tax", "tyres", "other"] as const;
const day = z.string().regex(/^\d{4}-\d{2}-\d{2}$/).refine(value => !Number.isNaN(Date.parse(value)), "invalid date");

const fields = {
	kind: z.enum(KINDS),
	title: z.string().trim().max(60).default(""),
	dueDate: day.nullable().default(null),
	dueKm: z.number().int().min(0).max(5_000_000).nullable().default(null),
	everyMonths: z.number().int().min(1).max(120).nullable().default(null),
	everyKm: z.number().int().min(100).max(200_000).nullable().default(null),
	remindDays: z.number().int().min(1).max(120).default(30),
	remindKm: z.number().int().min(100).max(20_000).default(1000),
	note: z.string().trim().max(500).default("")
};
// A custom deadline ("other") is known only by its description
const newDeadline = z.strictObject(fields)
	.refine(value => value.dueDate !== null || value.dueKm !== null, "dueDate or dueKm")
	.refine(value => value.kind !== "other" || value.title !== "", "title of a custom deadline");
const deadlineChanges = z.strictObject({
	kind: fields.kind,
	title: z.string().trim().max(60),
	dueDate: day.nullable(),
	dueKm: z.number().int().min(0).max(5_000_000).nullable(),
	everyMonths: z.number().int().min(1).max(120).nullable(),
	everyKm: z.number().int().min(100).max(200_000).nullable(),
	remindDays: z.number().int().min(1).max(120),
	remindKm: z.number().int().min(100).max(20_000),
	note: z.string().trim().max(500)
}).partial();

const profileBody = z.strictObject({
	model: z.string().trim().max(60).default(""),
	fuelUnit: z.enum(FUEL_UNITS),
	fuelType: z.enum(FUEL_TYPES).nullable().default(null),
	fuelPriceAuto: z.boolean().default(false)
}).refine(value => !value.fuelPriceAuto || value.fuelType !== null, "fuel type of the average price");

// Values over time: price per litre 0-10 €, consumption 1-50 l/100 km (2-100 km/l, the unit
// of the request), wear 0-10 €/km
export const MAX_RATES = 500;
const RANGES: Record<RateKind, { min: number; max: number; strict?: boolean }> = {
	price: { min: 0, max: 10, strict: true },
	consumption: { min: 1, max: 50 },
	wear: { min: 0, max: 10 }
};
const rateBody = z.strictObject({
	kind: z.enum(RATE_KINDS),
	validFrom: day.refine(value => value >= "2000-01-01", "too old").optional(),
	value: z.number().finite(),
	unit: z.enum(FUEL_UNITS).default("l_per_100km")
}).transform(body => ({ ...body, value: body.kind === "consumption" && body.unit === "km_per_l" ? convertConsumption(body.value) : body.value }))
	.refine(({ kind, value }) => value <= RANGES[kind].max && (RANGES[kind].strict ? value > RANGES[kind].min : value >= RANGES[kind].min),
		"value out of range");

const round = (value: number, digits: number) => Math.round(value * 10 ** digits) / 10 ** digits;

/** Profile, values newest first, values of today, cost per km, national average of the fuel */
const presentProfile = async (ctx: Context, profile: VehicleProfile, todayIso: string) => {
	const now = (kind: RateKind) => rateOn(profile.rates[kind].filter(item => item.validFrom <= todayIso), todayIso);
	const consumption = now("consumption");
	const price = now("price");
	const wear = now("wear");
	const fuelPerKm = consumption === null || price === null ? null : consumption / 100 * price;
	return {
		model: profile.model,
		fuelUnit: profile.fuelUnit,
		fuelType: profile.fuelType,
		fuelPriceAuto: profile.fuelPriceAuto,
		rates: Object.fromEntries(RATE_KINDS.map(kind => [kind, [...profile.rates[kind]].reverse()])),
		current: { price, consumption: consumption === null ? null : round(consumption, 2), wear },
		costPerKm: fuelPerKm === null && wear === null ? null : round((fuelPerKm ?? 0) + (wear ?? 0), 3),
		average: profile.fuelType ? await ctx.fuel.latest(profile.fuelType) : null
	};
};

const COLUMNS = `id, kind, title, to_char(due_date, 'YYYY-MM-DD') AS due_date, due_km, every_months, every_km,
	remind_days, remind_km, notified_stage, note, device_id`;

type Row = DeadlineRow & { every_months: number | null; every_km: number | null; note: string };

const present = (row: Row, odometerKm: number | null, todayIso: string) => ({
	id: row.id,
	kind: row.kind,
	title: row.title,
	dueDate: row.due_date,
	dueKm: row.due_km,
	everyMonths: row.every_months,
	everyKm: row.every_km,
	remindDays: row.remind_days,
	remindKm: row.remind_km,
	note: row.note,
	...deadlineState(row, odometerKm, todayIso)
});

/** Monday of the ISO week of a day */
function weekOf (iso: string): string {
	const date = new Date(`${iso}T00:00:00Z`);
	date.setUTCDate(date.getUTCDate() - (date.getUTCDay() + 6) % 7);
	return date.toISOString().slice(0, 10);
}

/** Totals of groups of days: km, business / personal km, driving, trips, top speed, SIM, alarms, voltage */
export function summarize (days: DayStats[], key: (day: string) => string) {
	const groups = new Map<string, DayStats[]>();
	for (const item of days) groups.set(key(item.day), [...groups.get(key(item.day)) ?? [], item]);
	const round = (value: number) => Math.round(value * 10) / 10;
	return [...groups].map(([period, items]) => {
		const voltages = items.map(item => item.restVoltage).filter((value): value is number => value !== null);
		return {
			period,
			distanceKm: round(items.reduce((sum, item) => sum + item.distanceKm, 0)),
			businessKm: round(items.reduce((sum, item) => sum + item.businessKm, 0)),
			personalKm: round(items.reduce((sum, item) => sum + item.personalKm, 0)),
			drivingMin: items.reduce((sum, item) => sum + item.drivingMin, 0),
			trips: items.reduce((sum, item) => sum + item.trips, 0),
			maxSpeed: items.reduce((max, item) => Math.max(max, item.maxSpeed), 0),
			trafficBytes: items.reduce((sum, item) => sum + item.trafficBytes, 0),
			alarms: items.reduce((sum, item) => sum + item.alarms, 0),
			restVoltage: voltages.length ? Math.round(voltages.reduce((a, b) => a + b, 0) / voltages.length * 100) / 100 : null,
			days: items.length
		};
	});
}

export function registerVehicleRoutes (app: FastifyInstance, ctx: Context): void {
	const { sql } = ctx;
	const tz = ctx.config.TIMEZONE;

	/** Trend over months and weeks; trackers: SIM, alarms, health of the car battery */
	app.get("/api/devices/:id/trends", async (request) => {
		const { id } = parse(idParams, request.params);
		const { months } = parse(z.strictObject({ months: z.coerce.number().int().min(1).max(36).default(12) }), request.query);
		const access = await requireDevice(sql, request.auth!.user, id, "owner");
		const device = { id, kind: access.kind };
		const [start] = await sql<{ day: string }[]>`
			SELECT to_char(date_trunc('month', now() AT TIME ZONE ${tz}) - make_interval(months => ${months - 1}), 'YYYY-MM-DD') AS day`;
		const days = await daysOf(sql, tz, device, start!.day);
		const current = await today(sql, tz);
		const recent = days.filter(item => Date.parse(current) - Date.parse(item.day) < 90 * 86400e3);
		const weeksFrom = weekOf(new Date(Date.parse(current) - 25 * 7 * 86400e3).toISOString().slice(0, 10));
		return {
			months: summarize(days, item => item.slice(0, 7)),
			weeks: summarize(days.filter(item => item.day >= weeksFrom), weekOf),
			simBudgetBytes: access.kind === "tracker" ? ctx.config.SIM_BUDGET_MB * 1024 * 1024 : null,
			odometerKm: access.kind === "tracker" ? await odometer(sql, tz, device) : null,
			battery: access.kind === "tracker"
				? {
					...batteryHealth(recent.slice(0, -1)),
					good: BATTERY_GOOD,
					low: BATTERY_LOW,
					days: recent.map(item => ({ day: item.day, restVoltage: item.restVoltage, minVoltage: item.minVoltage }))
				}
				: null
		};
	});

	// --- Costs of the trips (owner, trackers and phones)
	const profileOf = async (id: number) => presentProfile(ctx, await vehicleProfile(sql, id), await today(sql, tz));

	app.get("/api/devices/:id/vehicle", async (request) => {
		const { id } = parse(idParams, request.params);
		await requireDevice(sql, request.auth!.user, id, "owner");
		return profileOf(id);
	});

	app.put("/api/devices/:id/vehicle", async (request) => {
		const { id } = parse(idParams, request.params);
		const body = parse(profileBody, request.body);
		await requireDevice(sql, request.auth!.user, id, "owner");
		await sql`
			UPDATE devices SET vehicle_model = ${body.model}, fuel_unit = ${body.fuelUnit}, fuel_type = ${body.fuelType},
				fuel_price_auto = ${body.fuelPriceAuto}
			WHERE id = ${id}`;
		// Following the average: the latest one right away
		if (body.fuelPriceAuto) await ctx.fuel.applyAuto(id);
		return profileOf(id);
	});

	/** Price, consumption or wear from a day (default today): the same day replaces it */
	app.post("/api/devices/:id/rates", async (request) => {
		const { id } = parse(idParams, request.params);
		const body = parse(rateBody, request.body);
		await requireDevice(sql, request.auth!.user, id, "owner");
		const [count] = await sql<{ count: number }[]>`
			SELECT count(*)::int AS count FROM vehicle_rates WHERE device_id = ${id} AND kind = ${body.kind}`;
		if (count!.count >= MAX_RATES) throw badRequest(`At most ${MAX_RATES} values`, "too_many_rates");
		await sql`
			INSERT INTO vehicle_rates (device_id, kind, valid_from, value) VALUES (${id}, ${body.kind}, ${body.validFrom ?? await today(sql, tz)}, ${body.value})
			ON CONFLICT (device_id, kind, valid_from) DO UPDATE SET value = excluded.value`;
		return profileOf(id);
	});

	app.delete("/api/devices/:id/rates/:kind/:day", async (request) => {
		const { id, kind, day: validFrom } = parse(idParams.extend({ kind: z.enum(RATE_KINDS), day }), request.params);
		await requireDevice(sql, request.auth!.user, id, "owner");
		const deleted = await sql`DELETE FROM vehicle_rates WHERE device_id = ${id} AND kind = ${kind} AND valid_from = ${validFrom}`;
		if (deleted.count === 0) throw notFound("Value not found");
		return profileOf(id);
	});

	// --- Odometer and deadlines of a car (trackers, owner)
	const loadDeadline = async (request: { params: unknown; auth: { user: Parameters<typeof requireTracker>[1] } | null }) => {
		const { id } = parse(idParams, request.params);
		const [row] = await sql<Row[]>`SELECT ${sql.unsafe(COLUMNS)} FROM maintenance WHERE id = ${id}`;
		if (!row) throw notFound("Deadline not found");
		const access = await requireTracker(sql, request.auth!.user, row.device_id).catch(() => {
			throw notFound("Deadline not found");
		});
		return { row, device: { id: row.device_id, kind: access.kind } };
	};

	app.get("/api/devices/:id/maintenance", async (request) => {
		const { id } = parse(idParams, request.params);
		const access = await requireTracker(sql, request.auth!.user, id);
		const odometerKm = await odometer(sql, tz, { id, kind: access.kind });
		const current = await today(sql, tz);
		const rows = await sql<Row[]>`SELECT ${sql.unsafe(COLUMNS)} FROM maintenance WHERE device_id = ${id}`;
		const items = rows.map(row => present(row, odometerKm, current))
			.sort((a, b) => ["due", "soon", "ok"].indexOf(a.state) - ["due", "soon", "ok"].indexOf(b.state) ||
				(a.remainingDays ?? Infinity) - (b.remainingDays ?? Infinity) || (a.remainingKm ?? Infinity) - (b.remainingKm ?? Infinity));
		const log = await sql`
			SELECT id, kind, title, to_char(done_on, 'YYYY-MM-DD') AS "doneOn", km, note FROM maintenance_log
			WHERE device_id = ${id} ORDER BY done_on DESC, id DESC LIMIT 50`;
		return { odometerKm, items, log };
	});

	app.put("/api/devices/:id/odometer", async (request) => {
		const { id } = parse(idParams, request.params);
		const { km } = parse(z.strictObject({ km: z.number().int().min(0).max(5_000_000) }), request.body);
		const access = await requireTracker(sql, request.auth!.user, id);
		await setOdometer(sql, tz, { id, kind: access.kind }, km);
		return { odometerKm: await odometer(sql, tz, { id, kind: access.kind }) };
	});

	app.post("/api/devices/:id/maintenance", async (request) => {
		const { id } = parse(idParams, request.params);
		const body = parse(newDeadline, request.body);
		await requireTracker(sql, request.auth!.user, id);
		const [count] = await sql<{ count: number }[]>`SELECT count(*)::int AS count FROM maintenance WHERE device_id = ${id}`;
		if (count!.count >= MAX_DEADLINES) throw badRequest(`At most ${MAX_DEADLINES} deadlines`, "too_many_deadlines");
		const [row] = await sql<Row[]>`
			INSERT INTO maintenance (device_id, kind, title, due_date, due_km, every_months, every_km, remind_days, remind_km, note)
			VALUES (${id}, ${body.kind}, ${body.title}, ${body.dueDate}, ${body.dueKm}, ${body.everyMonths}, ${body.everyKm},
				${body.remindDays}, ${body.remindKm}, ${body.note})
			RETURNING ${sql.unsafe(COLUMNS)}`;
		return present(row!, await odometer(sql, tz, { id, kind: "tracker" }), await today(sql, tz));
	});

	app.patch("/api/maintenance/:id", async (request) => {
		const body = parse(deadlineChanges, request.body);
		const { row, device } = await loadDeadline(request);
		const next = { dueDate: body.dueDate === undefined ? row.due_date : body.dueDate, dueKm: body.dueKm === undefined ? row.due_km : body.dueKm };
		if (next.dueDate === null && next.dueKm === null) throw badRequest("A date or a km is needed", "deadline_empty");
		if ((body.kind ?? row.kind) === "other" && (body.title ?? row.title) === "") {
			throw badRequest("A custom deadline needs a description", "deadline_untitled");
		}
		const [updated] = await sql<Row[]>`
			UPDATE maintenance SET
				kind = COALESCE(${body.kind ?? null}, kind), title = COALESCE(${body.title ?? null}, title),
				due_date = ${next.dueDate}, due_km = ${next.dueKm},
				every_months = ${body.everyMonths === undefined ? sql`every_months` : body.everyMonths},
				every_km = ${body.everyKm === undefined ? sql`every_km` : body.everyKm},
				remind_days = COALESCE(${body.remindDays ?? null}, remind_days), remind_km = COALESCE(${body.remindKm ?? null}, remind_km),
				note = COALESCE(${body.note ?? null}, note)
			WHERE id = ${row.id} RETURNING ${sql.unsafe(COLUMNS)}`;
		return present(updated!, await odometer(sql, tz, device), await today(sql, tz));
	});

	app.delete("/api/maintenance/:id", async (request) => {
		const { row } = await loadDeadline(request);
		await sql`DELETE FROM maintenance WHERE id = ${row.id}`;
		return { ok: true };
	});

	/** Done: written in the log; a recurring deadline moves forward, a one-off one is removed */
	app.post("/api/maintenance/:id/done", async (request) => {
		const { row, device } = await loadDeadline(request);
		const current = await today(sql, tz);
		const odometerKm = await odometer(sql, tz, device);
		const body = parse(z.strictObject({
			doneOn: day.default(current),
			km: z.number().int().min(0).max(5_000_000).nullable().default(odometerKm),
			note: z.string().trim().max(500).default("")
		}), request.body ?? {});
		await sql`
			INSERT INTO maintenance_log (device_id, kind, title, done_on, km, note)
			VALUES (${row.device_id}, ${row.kind}, ${row.title}, ${body.doneOn}, ${body.km}, ${body.note})`;
		const recurring = row.every_months !== null || row.every_km !== null;
		if (!recurring) {
			await sql`DELETE FROM maintenance WHERE id = ${row.id}`;
			return { next: null };
		}
		// Recurring by km without odometer: the next km is unknown, the deadline stays as it was
		const [updated] = await sql<Row[]>`
			UPDATE maintenance SET notified_stage = 0,
				due_date = CASE WHEN every_months IS NOT NULL THEN ${body.doneOn}::date + make_interval(months => every_months)
					WHEN every_km IS NULL OR ${body.km}::int IS NULL THEN due_date END,
				due_km = CASE WHEN every_km IS NOT NULL AND ${body.km}::int IS NOT NULL THEN ${body.km}::int + every_km
					WHEN every_months IS NULL THEN due_km END
			WHERE id = ${row.id} RETURNING ${sql.unsafe(COLUMNS)}`;
		return { next: present(updated!, odometerKm, current) };
	});
}
