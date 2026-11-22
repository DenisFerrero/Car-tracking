import type { FastifyBaseLogger } from "fastify";
import type { Sql } from "../db.ts";
import type { Cell } from "../protocol/protocol.ts";

// Approximate position of the serving cells, for the points without a GNSS fix. Optional:
// the cell ids are sent to an external service with the MLS geolocate API (BeaconDB,
// OpenCelliD compatible proxies...). Results, unknown cells included, are cached.

const RETRY_UNKNOWN_DAYS = 30;

export class Cells {
	readonly #sql: Sql;
	readonly #log: FastifyBaseLogger;
	readonly #url: string;
	readonly #inflight = new Set<string>();

	constructor (sql: Sql, log: FastifyBaseLogger, url: string) {
		this.#sql = sql;
		this.#log = log;
		this.#url = url;
	}

	/** Resolves a cell in the background, if not cached yet */
	resolve (cell: Cell): void {
		if (!this.#url) return;
		const key = `${cell.mcc}-${cell.mnc}-${cell.area}-${cell.id}`;
		if (this.#inflight.has(key)) return;
		this.#inflight.add(key);
		void this.#lookup(cell)
			.catch(error => this.#log.warn({ err: error, cell: key }, "Cell geolocation failed"))
			.finally(() => this.#inflight.delete(key));
	}

	async #lookup (cell: Cell): Promise<void> {
		const [cached] = await this.#sql<{ lat: number | null; fetched_at: Date }[]>`
			SELECT lat, fetched_at FROM cells WHERE mcc = ${cell.mcc} AND mnc = ${cell.mnc} AND area = ${cell.area} AND cell_id = ${cell.id}`;
		if (cached && (cached.lat !== null || Date.now() - cached.fetched_at.getTime() < RETRY_UNKNOWN_DAYS * 86400e3)) return;

		const response = await fetch(this.#url, {
			method: "POST",
			headers: { "content-type": "application/json" },
			body: JSON.stringify({
				considerIp: false,
				cellTowers: [{
					// LTE cell ids have 28 bits, GSM ones 16
					radioType: cell.id > 0xffff ? "lte" : "gsm",
					mobileCountryCode: cell.mcc,
					mobileNetworkCode: cell.mnc,
					locationAreaCode: cell.area,
					cellId: cell.id
				}]
			}),
			signal: AbortSignal.timeout(10e3)
		});

		let lat: number | null = null, lon: number | null = null, accuracy: number | null = null;
		if (response.ok) {
			const body = await response.json() as { location?: { lat: number; lng: number }; accuracy?: number };
			if (body.location) {
				lat = body.location.lat;
				lon = body.location.lng;
				accuracy = Math.round(body.accuracy ?? 0);
			}
		} else if (response.status !== 404) {
			throw new Error(`HTTP ${response.status}`);
		}

		await this.#sql`
			INSERT INTO cells (mcc, mnc, area, cell_id, lat, lon, accuracy, fetched_at)
			VALUES (${cell.mcc}, ${cell.mnc}, ${cell.area}, ${cell.id}, ${lat}, ${lon}, ${accuracy}, now())
			ON CONFLICT (mcc, mnc, area, cell_id) DO UPDATE SET lat = excluded.lat, lon = excluded.lon,
				accuracy = excluded.accuracy, fetched_at = now()`;
	}
}
