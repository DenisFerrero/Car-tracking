import type { Sql } from "../db.ts";

// Refuels of a vehicle. A full tank closes an interval: the litres put in after the
// previous full tank (partial refuels included, the full one too) over the km between the
// two odometer readings are the real consumption of that interval. The amount paid gives
// the price per litre of the day. With rates_from_refuels the costs of the trips use them:
// the price from the day of the refuel, the consumption from the start of its interval
// (vehicle_rates with source "refuel", recomputed at every change; a value entered by the
// owner on the same day wins).

/** Real consumption outside this range is a wrong reading (l/100 km), not a value */
const CONSUMPTION_RANGE = { min: 1, max: 50 };

export interface Refuel {
	id: number;
	day: string;
	litres: number;
	cost: number | null;
	odometerKm: number | null;
	full: boolean;
	note: string;
}

export interface MeasuredRefuel extends Refuel {
	/** Price per litre, when the amount is known */
	pricePerLitre: number | null;
	/** Km and consumption (l/100 km) of the interval this full tank closes */
	km: number | null;
	consumption: number | null;
	/** Day of the previous full tank, start of the interval */
	since: string | null;
}

const round = (value: number, digits: number) => Math.round(value * 10 ** digits) / 10 ** digits;

/** Oldest first: by day, then odometer, then entry */
const chronological = (a: Refuel, b: Refuel) =>
	a.day.localeCompare(b.day) || (a.odometerKm ?? Infinity) - (b.odometerKm ?? Infinity) || a.id - b.id;

/** Refuels oldest first with the price per litre and the consumption of each closed interval */
export function measure (refuels: Refuel[]): MeasuredRefuel[] {
	let previous: Refuel | null = null;
	let litres = 0;
	return [...refuels].sort(chronological).map(item => {
		litres += item.litres;
		let km: number | null = null;
		let consumption: number | null = null;
		const since = item.full && previous ? previous.day : null;
		if (item.full && previous?.odometerKm != null && item.odometerKm !== null && item.odometerKm > previous.odometerKm) {
			km = item.odometerKm - previous.odometerKm;
			const value = litres / km * 100;
			if (value >= CONSUMPTION_RANGE.min && value <= CONSUMPTION_RANGE.max) consumption = round(value, 2);
		}
		if (item.full) {
			previous = item;
			litres = 0;
		}
		return {
			...item,
			pricePerLitre: item.cost === null || item.cost === 0 ? null : round(item.cost / item.litres, 3),
			km,
			consumption,
			since: consumption === null ? null : since
		};
	});
}

/** Totals: litres, amount, average consumption of the closed intervals (litres over km) */
export function summary (measured: MeasuredRefuel[]) {
	const closed = measured.filter(item => item.consumption !== null);
	const km = closed.reduce((sum, item) => sum + item.km!, 0);
	const litres = closed.reduce((sum, item) => sum + item.consumption! * item.km! / 100, 0);
	const costs = measured.filter(item => item.cost !== null);
	return {
		count: measured.length,
		litres: round(measured.reduce((sum, item) => sum + item.litres, 0), 2),
		cost: costs.length ? round(costs.reduce((sum, item) => sum + item.cost!, 0), 2) : null,
		averageConsumption: km > 0 ? round(litres / km * 100, 2) : null,
		lastConsumption: closed.at(-1)?.consumption ?? null,
		measuredKm: km
	};
}

export async function loadRefuels (sql: Sql, deviceId: number, from: string | null = null, to: string | null = null): Promise<Refuel[]> {
	return sql<Refuel[]>`
		SELECT id, to_char(day, 'YYYY-MM-DD') AS day, litres, cost, odometer_km AS "odometerKm", full_tank AS full, note
		FROM refuels WHERE device_id = ${deviceId}
			${from === null ? sql`` : sql`AND day >= ${from}::date`} ${to === null ? sql`` : sql`AND day <= ${to}::date`}
		ORDER BY day, id`;
}

/** Prices and consumptions of the refuels in the history of the costs, when the owner wants them */
export async function syncRefuelRates (sql: Sql, deviceId: number): Promise<void> {
	await sql.begin(async tx => {
		await tx`DELETE FROM vehicle_rates WHERE device_id = ${deviceId} AND source = 'refuel'`;
		const [device] = await tx<{ enabled: boolean }[]>`SELECT rates_from_refuels AS enabled FROM devices WHERE id = ${deviceId}`;
		if (!device?.enabled) return;
		const measured = measure(await loadRefuels(tx as unknown as Sql, deviceId));
		const rates = new Map<string, { kind: string; day: string; value: number }>();
		// Same day: the last refuel of the day (or of the interval) wins
		for (const item of measured) {
			if (item.pricePerLitre !== null && item.pricePerLitre <= 10) {
				rates.set(`price:${item.day}`, { kind: "price", day: item.day, value: item.pricePerLitre });
			}
			if (item.consumption !== null) rates.set(`consumption:${item.since}`, { kind: "consumption", day: item.since!, value: item.consumption });
		}
		const rows = [...rates.values()].map(rate => ({ device_id: deviceId, kind: rate.kind, valid_from: rate.day, value: rate.value, source: "refuel" }));
		if (rows.length) await tx`INSERT INTO vehicle_rates ${tx(rows)} ON CONFLICT DO NOTHING`;
	});
}
