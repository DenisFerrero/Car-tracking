// Analysis of a track, plain functions (tested in analytics.test.ts)

import { hasCosts, sumCosts, tripCost } from "./costs.ts";
import type { TripCost, VehicleProfile } from "./costs.ts";

export interface TrackPoint {
	time: Date;
	lat: number | null;
	lon: number | null;
	speed: number | null;
	status: number;
	stale: boolean;
}

export interface Trip {
	start: Date;
	end: Date;
	startLat: number;
	startLon: number;
	endLat: number;
	endLon: number;
	distanceKm: number;
	durationMin: number;
	maxSpeed: number;
	avgSpeed: number;
	points: number;
}

const EARTH_RADIUS = 6371000;
const STATUS_MOVING = 0;
const STATUS_ENGINE_OFF = 1;
const STATUS_HEARTBEAT = 2;
// A gap longer than this splits two trips (the tracker was off or without network)
const MAX_GAP_MS = 10 * 60e3;
// Trips shorter than this are noise (engine started and stopped)
const MIN_TRIP_METERS = 200;
// Jumps faster than this are GNSS errors and don't count in the distance
const MAX_PLAUSIBLE_KMH = 300;

export function distanceMeters (lat1: number, lon1: number, lat2: number, lon2: number): number {
	const toRad = (deg: number) => deg * Math.PI / 180;
	const dLat = toRad(lat2 - lat1);
	const dLon = toRad(lon2 - lon1);
	const h = Math.sin(dLat / 2) ** 2 + Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLon / 2) ** 2;
	return 2 * EARTH_RADIUS * Math.asin(Math.min(1, Math.sqrt(h)));
}

/**
 * Splits a chronological track in trips: consecutive driving points, closed by the engine
 * off point or by a long gap. Stale points (no fix) don't contribute to the distance.
 */
export function splitTrips (points: TrackPoint[]): Trip[] {
	const trips: Trip[] = [];
	let current: { points: TrackPoint[]; distance: number; maxSpeed: number } | null = null;
	let last: TrackPoint | null = null;

	const close = () => {
		if (!current) return;
		const located = current.points.filter(point => point.lat !== null && !point.stale);
		const first = located[0];
		const final = located[located.length - 1];
		if (first && final && current.distance >= MIN_TRIP_METERS) {
			const start = current.points[0]!.time;
			const end = current.points[current.points.length - 1]!.time;
			const hours = (end.getTime() - start.getTime()) / 3600e3;
			trips.push({
				start,
				end,
				startLat: first.lat!,
				startLon: first.lon!,
				endLat: final.lat!,
				endLon: final.lon!,
				distanceKm: Math.round(current.distance) / 1000,
				durationMin: Math.round(hours * 60),
				maxSpeed: current.maxSpeed,
				avgSpeed: hours > 0 ? Math.round(current.distance / 1000 / hours) : 0,
				points: current.points.length
			});
		}
		current = null;
	};

	for (const point of points) {
		const driving = point.status === STATUS_MOVING || point.status === STATUS_ENGINE_OFF;
		if (current && last && point.time.getTime() - last.time.getTime() > MAX_GAP_MS) close();

		if (driving) {
			if (!current) current = { points: [], distance: 0, maxSpeed: 0 };
			const previous = [...current.points].reverse().find(item => item.lat !== null && !item.stale);
			if (previous && point.lat !== null && point.lon !== null && !point.stale) {
				const meters = distanceMeters(previous.lat!, previous.lon!, point.lat, point.lon);
				const seconds = (point.time.getTime() - previous.time.getTime()) / 1000;
				if (seconds > 0 && meters / seconds * 3.6 <= MAX_PLAUSIBLE_KMH) current.distance += meters;
			}
			current.points.push(point);
			current.maxSpeed = Math.max(current.maxSpeed, point.speed ?? 0);
			if (point.status === STATUS_ENGINE_OFF) close();
		}
		last = point;
	}
	close();
	return trips;
}

/** Trips of a tracker, or of a phone (no engine: stops longer than 5 minutes) */
export function tripsOfKind<T extends TrackPoint> (kind: "tracker" | "phone", points: T[]): Trip[] {
	return splitTrips(kind === "phone" ? phoneTrack(points) : points);
}

// A phone stopped for longer than this ends a trip (traffic lights and queues don't)
const PHONE_STOP_MS = 5 * 60e3;

/**
 * Phones have no engine: a point is "stopped" when slower than walking. Short stops stay
 * in the trip (moving), the first point of a long stop closes it (engine off), the rest
 * of the stop are heartbeats, outside of any trip.
 */
export function phoneTrack (points: TrackPoint[]): TrackPoint[] {
	const track = points.map(point => ({ ...point }));
	let i = 0;
	while (i < track.length) {
		if (track[i]!.status === STATUS_MOVING) {
			i++;
			continue;
		}
		let j = i;
		while (j < track.length && track[j]!.status !== STATUS_MOVING) j++;
		// Stop from i to j - 1: long when the next movement (or now) is far
		const until = j < track.length ? track[j]!.time.getTime() : Date.now();
		const long = until - track[i]!.time.getTime() > PHONE_STOP_MS;
		for (let k = i; k < j; k++) track[k]!.status = !long ? STATUS_MOVING : k === i ? STATUS_ENGINE_OFF : STATUS_HEARTBEAT;
		i = j;
	}
	return track;
}

const xml = (text: string) => text.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");

export interface ExportPoint extends TrackPoint {
	altitude: number | null;
	accuracy: number | null;
	satellites: number | null;
	signal: number | null;
	voltage: number | null;
}

/** GPX 1.1: a segment per trip, the points outside of the trips are not exported */
export function toGpx (name: string, points: ExportPoint[], trips: Trip[]): string {
	const segments = trips.map(trip => {
		const inside = points.filter(point => point.lat !== null && !point.stale && point.time >= trip.start && point.time <= trip.end);
		const rows = inside.map(point => `<trkpt lat="${point.lat}" lon="${point.lon}">` +
			(point.altitude === null ? "" : `<ele>${point.altitude}</ele>`) + `<time>${point.time.toISOString()}</time></trkpt>`);
		return `<trkseg>\n${rows.join("\n")}\n</trkseg>`;
	});
	return `<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1" creator="Car Tracking" xmlns="http://www.topografix.com/GPX/1/1">
<trk><name>${xml(name)}</name>
${segments.join("\n")}
</trk>
</gpx>
`;
}

/** CSV of all the points, a trip number for the ones inside a trip */
export function toCsv (points: ExportPoint[], trips: Trip[]): string {
	const header = "time,lat,lon,altitude,speed,accuracy,satellites,signal,voltage,status,stale,trip";
	const cell = (value: number | null) => value === null ? "" : String(value);
	let t = 0;
	const rows = points.map(point => {
		while (t < trips.length && trips[t]!.end < point.time) t++;
		const trip = t < trips.length && trips[t]!.start <= point.time ? String(t + 1) : "";
		return [point.time.toISOString(), cell(point.lat), cell(point.lon), cell(point.altitude), cell(point.speed), cell(point.accuracy),
			cell(point.satellites), cell(point.signal), cell(point.voltage), point.status, point.stale ? 1 : 0, trip].join(",");
	});
	return [header, ...rows].join("\r\n") + "\r\n";
}

/**
 * Trip log of a period for the spreadsheets: a row per trip, totals business / personal /
 * not marked. Italian: semicolons and decimal commas (what Excel expects in Italy).
 */
export function toLogbook (trips: Trip[], tags: { start: Date; purpose: "business" | "personal" | null; note: string }[],
	locale: string | null, timeZone: string, profile: VehicleProfile | null = null): string {
	const it = locale === "it";
	const separator = it ? ";" : ",";
	const number = (value: number, digits: number) => it ? value.toFixed(digits).replace(".", ",") : value.toFixed(digits);
	const text = (value: string) => /[;,"\n]/.test(value) ? `"${value.replace(/"/g, '""')}"` : value;
	const date = (value: Date) => value.toLocaleDateString("sv-SE", { timeZone });
	const time = (value: Date) => value.toLocaleTimeString("it-IT", { timeZone, hour: "2-digit", minute: "2-digit" });
	const label = { business: it ? "Lavoro" : "Business", personal: it ? "Personale" : "Personal", none: "" };
	const byStart = new Map(tags.map(tag => [tag.start.getTime(), tag]));
	// Costs (litres, fuel, wear, total) when the owner entered consumption or wear
	const costs = profile !== null && hasCosts(profile) ? profile : null;
	const header = [
		...it
			? ["Data", "Partenza", "Arrivo", "Da (lat, lon)", "A (lat, lon)", "Km", "Durata (min)", "Tipo", "Note"]
			: ["Date", "Start", "End", "From (lat, lon)", "To (lat, lon)", "Km", "Duration (min)", "Purpose", "Note"],
		...costs ? it ? ["Litri", "Carburante (€)", "Usura (€)", "Costo (€)"] : ["Litres", "Fuel (€)", "Wear (€)", "Cost (€)"] : []
	];
	const costCells = (cost: TripCost | null) => cost === null ? []
		: [cost.fuelL, cost.fuelCost, cost.wearCost, cost.cost].map(value => value === null ? "" : number(value, 2));
	// Each trip with consumption, fuel price and wear of its day; the totals are sums of the trips
	const totals = { business: 0, personal: 0, none: 0 };
	const tripCosts: Record<keyof typeof totals, TripCost[]> = { business: [], personal: [], none: [] };
	const rows = trips.map(trip => {
		const tag = byStart.get(trip.start.getTime());
		const purpose = tag?.purpose ?? "none";
		const cost = costs && tripCost(trip.distanceKm, costs, date(trip.start));
		totals[purpose] += trip.distanceKm;
		if (cost) tripCosts[purpose].push(cost);
		return [date(trip.start), time(trip.start), time(trip.end), text(`${trip.startLat.toFixed(5)} ${trip.startLon.toFixed(5)}`),
			text(`${trip.endLat.toFixed(5)} ${trip.endLon.toFixed(5)}`), number(trip.distanceKm, 1), trip.durationMin, label[purpose],
			text(tag?.note ?? ""), ...costCells(cost)].join(separator);
	});
	const total = (name: string, km: number, items: TripCost[]) =>
		[name, "", "", "", "", number(km, 1), "", "", "", ...costCells(costs && sumCosts(items))].join(separator);
	return [header.join(separator), ...rows, "",
		total(it ? "Totale lavoro" : "Total business", totals.business, tripCosts.business),
		total(it ? "Totale personale" : "Total personal", totals.personal, tripCosts.personal),
		total(it ? "Non indicato" : "Not marked", totals.none, tripCosts.none),
		total(it ? "Totale" : "Total", totals.business + totals.personal + totals.none,
			[...tripCosts.business, ...tripCosts.personal, ...tripCosts.none])].join("\r\n") + "\r\n";
}

/** Bucket of the time series for a period: about 100-300 values per chart */
export function bucketFor (from: Date, to: Date): string {
	const hours = (to.getTime() - from.getTime()) / 3600e3;
	if (hours <= 6) return "2 minutes";
	if (hours <= 26) return "10 minutes";
	if (hours <= 24 * 8) return "1 hour";
	if (hours <= 24 * 32) return "6 hours";
	return "1 day";
}

// Bytes on the SIM besides the frame: WebSocket (6) + TLS record (29) + TCP/IP (40) +
// TCP ACK of the other side (40)
export const FRAME_OVERHEAD = 115;
// TCP + TLS handshake + WebSocket upgrade, about
export const CONNECTION_COST = 6500;
