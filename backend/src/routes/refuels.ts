import type { FastifyInstance } from "fastify";
import { z } from "zod";
import type { Context } from "../context.ts";
import { badRequest, notFound, parse } from "../http/errors.ts";
import { requireVehicle } from "../services/access.ts";
import type { DeviceKind } from "../services/access.ts";
import { today } from "../services/daily.ts";
import { loadRefuels, measure, summary, syncRefuelRates } from "../services/refuels.ts";
import { energyUnit } from "../services/costs.ts";
import type { FuelType } from "../services/costs.ts";
import { odometer } from "../services/vehicle.ts";
import { idParams } from "./devices.ts";

// Refuels of a vehicle (owner, trackers and vehicles): litres, amount, odometer, full tank;
// for an electric vehicle charges in kWh, at home or at a public station.
// Every change recomputes the prices and consumptions they give to the costs of the trips.

export const MAX_REFUELS = 2000;
const day = z.string().regex(/^\d{4}-\d{2}-\d{2}$/).refine(value => !Number.isNaN(Date.parse(value)) && value >= "2000-01-01", "invalid date");
const fields = {
	day,
	litres: z.number().finite().gt(0).max(500),
	cost: z.number().finite().min(0).max(10_000).nullable(),
	odometerKm: z.number().int().min(0).max(5_000_000).nullable(),
	full: z.boolean(),
	place: z.enum(["home", "public"]).nullable(),
	note: z.string().trim().max(200)
};
const newRefuel = z.strictObject({
	...fields,
	day: day.optional(),
	cost: fields.cost.default(null),
	odometerKm: fields.odometerKm.default(null),
	full: fields.full.default(true),
	place: fields.place.default(null),
	note: fields.note.default("")
});
const changes = z.strictObject(fields).partial();

export function registerRefuelRoutes (app: FastifyInstance, ctx: Context): void {
	const { sql } = ctx;
	const tz = ctx.config.TIMEZONE;

	/** Refuels newest first with what they measure, totals, odometer now (to fill in the next one) */
	const present = async (device: { id: number; kind: DeviceKind }) => {
		const measured = measure(await loadRefuels(sql, device.id));
		const [row] = await sql<{ enabled: boolean; fuelUnit: string; fuelType: FuelType | null }[]>`
			SELECT rates_from_refuels AS enabled, fuel_unit AS "fuelUnit", fuel_type AS "fuelType" FROM devices WHERE id = ${device.id}`;
		return {
			refuels: measured.reverse(),
			summary: summary(measured),
			ratesFromRefuels: row!.enabled,
			fuelUnit: row!.fuelUnit,
			/** Litres, or kWh for an electric vehicle */
			energyUnit: energyUnit(row!.fuelType),
			odometerKm: await odometer(sql, tz, device)
		};
	};

	/** A refuel of a vehicle of the user, else 404 */
	const load = async (request: { params: unknown; auth: { user: Parameters<typeof requireVehicle>[1] } | null }) => {
		const { id } = parse(idParams, request.params);
		const [row] = await sql<{ id: number; device_id: number }[]>`SELECT id, device_id FROM refuels WHERE id = ${id}`;
		if (!row) throw notFound("Refuel not found");
		const access = await requireVehicle(sql, request.auth!.user, row.device_id).catch(() => {
			throw notFound("Refuel not found");
		});
		return { id: row.id, device: { id: row.device_id, kind: access.kind } };
	};

	const notFuture = async (value: string | undefined) => {
		if (value !== undefined && value > await today(sql, tz)) throw badRequest("A refuel can't be in the future", "refuel_future");
	};

	app.get("/api/devices/:id/refuels", async (request) => {
		const { id } = parse(idParams, request.params);
		const access = await requireVehicle(sql, request.auth!.user, id);
		return present({ id, kind: access.kind });
	});

	app.post("/api/devices/:id/refuels", async (request) => {
		const { id } = parse(idParams, request.params);
		const body = parse(newRefuel, request.body);
		const access = await requireVehicle(sql, request.auth!.user, id);
		await notFuture(body.day);
		const [count] = await sql<{ count: number }[]>`SELECT count(*)::int AS count FROM refuels WHERE device_id = ${id}`;
		if (count!.count >= MAX_REFUELS) throw badRequest(`At most ${MAX_REFUELS} refuels`, "too_many_refuels");
		await sql`
			INSERT INTO refuels (device_id, day, litres, cost, odometer_km, full_tank, place, note)
			VALUES (${id}, ${body.day ?? await today(sql, tz)}, ${body.litres}, ${body.cost}, ${body.odometerKm}, ${body.full}, ${body.place}, ${body.note})`;
		await syncRefuelRates(sql, id);
		return present({ id, kind: access.kind });
	});

	app.patch("/api/refuels/:id", async (request) => {
		const body = parse(changes, request.body);
		const { id, device } = await load(request);
		await notFuture(body.day);
		await sql`
			UPDATE refuels SET day = COALESCE(${body.day ?? null}, day), litres = COALESCE(${body.litres ?? null}, litres),
				cost = ${body.cost === undefined ? sql`cost` : body.cost},
				odometer_km = ${body.odometerKm === undefined ? sql`odometer_km` : body.odometerKm},
				full_tank = COALESCE(${body.full ?? null}, full_tank), note = COALESCE(${body.note ?? null}, note),
				place = ${body.place === undefined ? sql`place` : body.place}
			WHERE id = ${id}`;
		await syncRefuelRates(sql, device.id);
		return present(device);
	});

	app.delete("/api/refuels/:id", async (request) => {
		const { id, device } = await load(request);
		await sql`DELETE FROM refuels WHERE id = ${id}`;
		await syncRefuelRates(sql, device.id);
		return present(device);
	});
}
