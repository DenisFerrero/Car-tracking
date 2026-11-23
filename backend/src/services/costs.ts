import type { Sql } from "../db.ts";

// Cost of the trips: fuel from the consumption and the price per litre, wear of the
// vehicle per km (tyres, maintenance, depreciation: e.g. from the ACI tables of the
// model). The three values change over time (vehicle_rates): each trip uses the ones
// valid on its day. The consumption is stored in l/100 km and shown in the unit the owner
// prefers. The fuel price can follow the national average (src/services/fuel.ts).
// An electric vehicle uses the same values in kWh: consumption in kWh/100 km, price per
// kWh, refuels as charges; a hybrid without plug runs on petrol. The mileage allowance
// (€/km, over time too) applies to the business km of the trip log.

export const FUEL_UNITS = ["l_per_100km", "km_per_l"] as const;
export type FuelUnit = typeof FUEL_UNITS[number];
export const FUEL_TYPES = ["petrol", "diesel", "lpg", "electric", "hybrid"] as const;
export type FuelType = typeof FUEL_TYPES[number];
/** Fuel of the national average price of a type (none for the electric ones) */
export type AverageFuel = "petrol" | "diesel" | "lpg";
export const AVERAGE_FUEL: Record<FuelType, AverageFuel | null> = {
	petrol: "petrol", diesel: "diesel", lpg: "lpg", hybrid: "petrol", electric: null
};
/** Unit of the quantities (refuels, consumption, price) */
export const energyUnit = (fuelType: FuelType | null): "l" | "kWh" => fuelType === "electric" ? "kWh" : "l";
export const RATE_KINDS = ["price", "consumption", "wear", "reimbursement"] as const;
export type RateKind = typeof RATE_KINDS[number];

export const RATE_SOURCES = ["manual", "auto", "refuel"] as const;
export type RateSource = typeof RATE_SOURCES[number];

export interface Rate {
	validFrom: string;
	value: number;
	/** Entered by the owner, national average, from the refuels */
	source?: RateSource;
}

export interface VehicleProfile {
	model: string;
	fuelUnit: FuelUnit;
	fuelType: FuelType | null;
	fuelPriceAuto: boolean;
	ratesFromRefuels: boolean;
	/** Oldest first; consumption in l/100 km */
	rates: Record<RateKind, Rate[]>;
}

export interface TripCost {
	fuelL: number | null;
	fuelCost: number | null;
	wearCost: number | null;
	cost: number | null;
}

const round2 = (value: number) => Math.round(value * 100) / 100;

/** The same consumption in the other unit: 5 l/100 km = 20 km/l (and back) */
export const convertConsumption = (value: number): number => 100 / value;

/** Something to compute: consumption or wear */
export const hasCosts = (profile: VehicleProfile): boolean => profile.rates.consumption.length > 0 || profile.rates.wear.length > 0;

/** Value valid on a day (YYYY-MM-DD): the last one since then, before the first value the first one */
export function rateOn (rates: Rate[], day: string): number | null {
	let found = rates[0]?.value ?? null;
	for (const item of rates) if (item.validFrom <= day) found = item.value;
	return found;
}

/** Litres, fuel, wear and total of a distance on a day; null what is not known */
export function tripCost (km: number, profile: VehicleProfile, day: string): TripCost {
	const per100 = rateOn(profile.rates.consumption, day);
	const price = rateOn(profile.rates.price, day);
	const wear = rateOn(profile.rates.wear, day);
	const litres = per100 === null ? null : km * per100 / 100;
	const fuelCost = litres === null || price === null ? null : round2(litres * price);
	const wearCost = wear === null ? null : round2(km * wear);
	return {
		fuelL: litres === null ? null : round2(litres),
		fuelCost,
		wearCost,
		cost: fuelCost === null && wearCost === null ? null : round2((fuelCost ?? 0) + (wearCost ?? 0))
	};
}

/** Mileage allowance of some business km on a day, null without an allowance */
export function reimbursement (businessKm: number, profile: VehicleProfile, day: string): number | null {
	const rate = rateOn(profile.rates.reimbursement, day);
	return rate === null ? null : round2(businessKm * rate);
}

/** Sum of the costs of some trips (each with the values of its day) */
export function sumCosts (costs: TripCost[]): TripCost {
	const sum = (key: keyof TripCost) => {
		const values = costs.map(item => item[key]).filter((value): value is number => value !== null);
		return values.length ? round2(values.reduce((a, b) => a + b, 0)) : null;
	};
	return { fuelL: sum("fuelL"), fuelCost: sum("fuelCost"), wearCost: sum("wearCost"), cost: sum("cost") };
}

export async function vehicleProfile (sql: Sql, deviceId: number): Promise<VehicleProfile> {
	const [row] = await sql<Omit<VehicleProfile, "rates">[]>`
		SELECT vehicle_model AS model, fuel_unit AS "fuelUnit", fuel_type AS "fuelType", fuel_price_auto AS "fuelPriceAuto",
			rates_from_refuels AS "ratesFromRefuels"
		FROM devices WHERE id = ${deviceId}`;
	const rows = await sql<(Rate & { kind: RateKind })[]>`
		SELECT kind, to_char(valid_from, 'YYYY-MM-DD') AS "validFrom", value, source FROM vehicle_rates
		WHERE device_id = ${deviceId} ORDER BY valid_from`;
	const rates = Object.fromEntries(RATE_KINDS.map(kind => [kind, rows.filter(item => item.kind === kind)
		.map(({ validFrom, value, source }) => ({ validFrom, value, source }))])) as Record<RateKind, Rate[]>;
	return { ...row!, rates };
}
