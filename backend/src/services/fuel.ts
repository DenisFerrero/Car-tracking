import type { FastifyBaseLogger } from "fastify";
import type { Sql } from "../db.ts";
import type { FuelType } from "./costs.ts";

// National average prices of the fuels: weekly survey of the Ministry of the Environment
// (MASE, open data, every Monday since 2005). CSV in ISO-8859-1, Italian numbers in euro
// per 1000 litres:
//   DATA_RILEVAZIONE,BENZINA,GASOLIO_AUTO,GPL,METANO,...
//   2026-11-16,"1.969,6","2.210,01","835,66",...
// Stored per week; the vehicles with fuelPriceAuto get each new week in the history of
// their fuel price (a price entered by the owner on the same day wins).

const COLUMNS: Record<FuelType, string> = { petrol: "BENZINA", diesel: "GASOLIO_AUTO", lpg: "GPL" };
// Weeks kept: enough for the charts and the trips of the last years
const KEEP_WEEKS = 3 * 53;
// A new survey every Monday, published within a couple of days
const STALE_DAYS = 8;
const RETRY_MS = 6 * 3600e3;

export interface FuelAverage {
	week: string;
	prices: Partial<Record<FuelType, number>>;
}

/** "1.969,6" → 1969.6; empty or invalid → null */
function italianNumber (text: string): number | null {
	const value = Number(text.replace(/\./g, "").replace(",", "."));
	return text.trim() !== "" && Number.isFinite(value) ? value : null;
}

/** Fields of a CSV line, with quotes */
function fields (line: string): string[] {
	const result: string[] = [];
	let current = "", quoted = false;
	for (const char of line) {
		if (char === '"') quoted = !quoted;
		else if (char === "," && !quoted) {
			result.push(current);
			current = "";
		} else current += char;
	}
	result.push(current);
	return result;
}

/** Weeks of the CSV, newest first, prices per litre; rows without a date are skipped */
export function parseWeeklyPrices (csv: string): FuelAverage[] {
	const lines = csv.split(/\r?\n/).filter(line => line.trim() !== "");
	const header = fields(lines[0] ?? "").map(name => name.trim().toUpperCase());
	const dateColumn = header.indexOf("DATA_RILEVAZIONE");
	if (dateColumn < 0) throw new Error("Unknown format of the fuel prices");
	const weeks: FuelAverage[] = [];
	for (const line of lines.slice(1)) {
		const values = fields(line);
		const week = values[dateColumn]?.trim() ?? "";
		if (!/^\d{4}-\d{2}-\d{2}$/.test(week)) continue;
		const prices: Partial<Record<FuelType, number>> = {};
		for (const [fuel, column] of Object.entries(COLUMNS) as [FuelType, string][]) {
			const index = header.indexOf(column);
			const value = index < 0 ? null : italianNumber(values[index] ?? "");
			// Per 1000 litres; outside 0.1-10 €/l it's not a price
			if (value !== null && value >= 100 && value <= 10_000) prices[fuel] = Math.round(value) / 1000;
		}
		weeks.push({ week, prices });
	}
	return weeks.sort((a, b) => b.week.localeCompare(a.week));
}

export class FuelPrices {
	readonly #sql: Sql;
	readonly #log: FastifyBaseLogger;
	readonly #url: string;
	#lastAttempt = 0;

	constructor (sql: Sql, log: FastifyBaseLogger, url: string) {
		this.#sql = sql;
		this.#log = log;
		this.#url = url;
	}

	/** Latest average of a fuel, null when unknown */
	async latest (fuel: FuelType): Promise<{ week: string; price: number } | null> {
		const [row] = await this.#sql<{ week: string; price: number }[]>`
			SELECT to_char(week, 'YYYY-MM-DD') AS week, price FROM fuel_averages WHERE fuel = ${fuel} ORDER BY week DESC LIMIT 1`;
		return row ?? null;
	}

	/** Downloads the survey when the newest week is old (at most every 6 hours); returns the weeks stored */
	async refreshIfStale (now = Date.now()): Promise<number> {
		if (!this.#url || now - this.#lastAttempt < RETRY_MS) return 0;
		const [newest] = await this.#sql<{ week: Date }[]>`SELECT max(week) AS week FROM fuel_averages`;
		if (newest?.week && now - newest.week.getTime() < STALE_DAYS * 86400e3) return 0;
		this.#lastAttempt = now;
		try {
			return await this.refresh();
		} catch (error) {
			this.#log.warn({ err: error }, "Fuel prices not updated");
			return 0;
		}
	}

	async refresh (): Promise<number> {
		const response = await fetch(this.#url, { signal: AbortSignal.timeout(30e3) });
		if (!response.ok) throw new Error(`Fuel prices: HTTP ${response.status}`);
		const weeks = parseWeeklyPrices(new TextDecoder("latin1").decode(await response.arrayBuffer())).slice(0, KEEP_WEEKS);
		const rows = weeks.flatMap(item => Object.entries(item.prices).map(([fuel, price]) => ({ fuel, week: item.week, price })));
		if (rows.length === 0) return 0;
		await this.#sql`
			INSERT INTO fuel_averages ${this.#sql(rows)}
			ON CONFLICT (fuel, week) DO UPDATE SET price = excluded.price`;
		await this.#sql`DELETE FROM fuel_averages WHERE week < ${weeks.at(-1)!.week}`;
		const applied = await this.applyAuto();
		this.#log.info({ weeks: weeks.length, latest: weeks[0]?.week, applied }, "Fuel prices updated");
		return weeks.length;
	}

	/**
	 * The latest average in the history of the vehicles that follow it (or one vehicle),
	 * not when a price of the owner is already there that day, nor for a vehicle with the
	 * prices of its refuels of the last 14 days (the real price wins). Returns the prices added.
	 */
	async applyAuto (deviceId: number | null = null): Promise<number> {
		const added = await this.#sql`
			INSERT INTO vehicle_rates (device_id, kind, valid_from, value, source)
			SELECT d.id, 'price', a.week, a.price, 'auto' FROM devices d
			JOIN LATERAL (SELECT week, price FROM fuel_averages WHERE fuel = d.fuel_type ORDER BY week DESC LIMIT 1) a ON true
			WHERE d.fuel_price_auto AND (${deviceId}::int IS NULL OR d.id = ${deviceId})
				AND NOT (d.rates_from_refuels AND EXISTS (SELECT 1 FROM refuels r WHERE r.device_id = d.id AND r.cost > 0
					AND r.day > now()::date - 14))
			ON CONFLICT DO NOTHING`;
		return added.count;
	}
}
