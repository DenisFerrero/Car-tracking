import type { Sql } from "../db.ts";
import { distanceMeters } from "./analytics.ts";
import type { Notifier } from "./notifier.ts";
import { inSchedule } from "./schedule.ts";
import type { Schedule } from "./schedule.ts";

// Arrival areas: circles or polygons chosen by a user on the map of a device ("almost
// home", "at the office", a car park, a town). Every new position with a GNSS fix is
// checked against the areas of the device; crossing the border notifies the user who
// created the area.
//
// An area with a schedule notifies only the crossings in its hours; the side of the border
// is followed all the time.
//
// The border has a margin when leaving (circles: 10% of the radius, at least 30 m;
// polygons: 30 m from the nearest side): a car parked on the edge doesn't produce a
// notification at every point.

export const MAX_AREAS_PER_DEVICE = 20;
export const MAX_VERTICES = 50;
const POLYGON_MARGIN = 30;
/** Smallest polygon, m² (a circle of 50 m is about 7850 m²) */
const MIN_POLYGON_AREA = 500;
const EARTH_RADIUS = 6371000;

/** Vertex of a polygon: [lat, lon] */
export type Vertex = [number, number];

export interface AreaPoint {
	time: Date;
	lat: number | null;
	lon: number | null;
	stale: boolean;
}

interface AreaRow {
	id: number;
	user_id: number;
	name: string;
	lat: number;
	lon: number;
	radius: number;
	polygon: Vertex[] | null;
	notify_enter: boolean;
	notify_exit: boolean;
	inside: boolean | null;
	checked_at: Date | null;
	schedule: Schedule | null;
}

export function exitMargin (radius: number): number {
	return Math.max(30, radius * 0.1);
}

/** Meters east and north of an origin: flat projection, precise enough within 50 km */
function toMeters (origin: { lat: number; lon: number }, lat: number, lon: number): [number, number] {
	const rad = Math.PI / 180;
	return [(lon - origin.lon) * rad * Math.cos(origin.lat * rad) * EARTH_RADIUS, (lat - origin.lat) * rad * EARTH_RADIUS];
}

/** Point inside the polygon (ray casting) */
export function inPolygon (polygon: Vertex[], point: { lat: number; lon: number }): boolean {
	let inside = false;
	for (let i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
		const [latI, lonI] = polygon[i]!;
		const [latJ, lonJ] = polygon[j]!;
		if ((latI > point.lat) !== (latJ > point.lat) && point.lon < (lonJ - lonI) * (point.lat - latI) / (latJ - latI) + lonI) inside = !inside;
	}
	return inside;
}

/** Distance in meters from the nearest side of the polygon */
export function distanceToPolygon (polygon: Vertex[], point: { lat: number; lon: number }): number {
	let best = Infinity;
	for (let i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
		const [ax, ay] = toMeters(point, ...polygon[j]!);
		const [bx, by] = toMeters(point, ...polygon[i]!);
		const length = (bx - ax) ** 2 + (by - ay) ** 2;
		const t = length === 0 ? 0 : Math.max(0, Math.min(1, -(ax * (bx - ax) + ay * (by - ay)) / length));
		best = Math.min(best, Math.hypot(ax + t * (bx - ax), ay + t * (by - ay)));
	}
	return best;
}

/** Two segments that cross (shared ends of adjacent sides excluded by the caller) */
function crosses (a: [number, number], b: [number, number], c: [number, number], d: [number, number]): boolean {
	const side = (p: [number, number], q: [number, number], r: [number, number]) => Math.sign((q[0] - p[0]) * (r[1] - p[1]) - (q[1] - p[1]) * (r[0] - p[0]));
	return side(a, b, c) !== side(a, b, d) && side(c, d, a) !== side(c, d, b);
}

/**
 * Center, radius of the circle around it and area of a polygon, or null when the sides
 * cross each other or it's too small
 */
export function polygonShape (polygon: Vertex[]): { lat: number; lon: number; radius: number; area: number } | null {
	const lat = polygon.reduce((sum, vertex) => sum + vertex[0], 0) / polygon.length;
	const lon = polygon.reduce((sum, vertex) => sum + vertex[1], 0) / polygon.length;
	const points = polygon.map(vertex => toMeters({ lat, lon }, ...vertex));
	const n = points.length;
	for (let i = 0; i < n; i++) {
		for (let j = i + 1; j < n; j++) {
			// Adjacent sides share a vertex
			if (j === i + 1 || (i === 0 && j === n - 1)) continue;
			if (crosses(points[i]!, points[(i + 1) % n]!, points[j]!, points[(j + 1) % n]!)) return null;
		}
	}
	const area = Math.abs(points.reduce((sum, [x, y], i) => sum + x * points[(i + 1) % n]![1] - points[(i + 1) % n]![0] * y, 0)) / 2;
	if (area < MIN_POLYGON_AREA) return null;
	const radius = Math.ceil(Math.max(...polygon.map(vertex => distanceMeters(lat, lon, vertex[0], vertex[1]))));
	return { lat, lon, radius: Math.max(50, radius), area };
}

/** Side of the border of a point, given the previous side */
export function isInside (area: { lat: number; lon: number; radius: number; polygon?: Vertex[] | null }, point: { lat: number; lon: number },
	wasInside: boolean | null): boolean {
	if (area.polygon) {
		return inPolygon(area.polygon, point) || (wasInside === true && distanceToPolygon(area.polygon, point) <= POLYGON_MARGIN);
	}
	const distance = distanceMeters(area.lat, area.lon, point.lat, point.lon);
	return distance <= area.radius + (wasInside === true ? exitMargin(area.radius) : 0);
}

export class Geofences {
	readonly #sql: Sql;
	readonly #notifier: Notifier;
	readonly #timeZone: string;

	constructor (sql: Sql, notifier: Notifier, timeZone: string) {
		this.#sql = sql;
		this.#notifier = notifier;
		this.#timeZone = timeZone;
	}

	/** Side of the border of a new area from the last fix: no notification at creation */
	async initialState (deviceId: number, area: { lat: number; lon: number; radius: number; polygon: Vertex[] | null }): Promise<{ inside: boolean | null; checkedAt: Date | null }> {
		const [last] = await this.#sql<{ time: Date; lat: number; lon: number }[]>`
			SELECT time, lat, lon FROM positions
			WHERE device_id = ${deviceId} AND NOT stale AND lat IS NOT NULL AND time > now() - interval '7 days'
			ORDER BY time DESC LIMIT 1`;
		if (!last) return { inside: null, checkedAt: null };
		return { inside: isInside(area, last, null), checkedAt: last.time };
	}

	/** Checks the new points of a device (any order) against the areas of its users */
	async evaluate (deviceId: number, points: AreaPoint[]): Promise<void> {
		const fixes = points
			.filter((point): point is AreaPoint & { lat: number; lon: number } => !point.stale && point.lat !== null && point.lon !== null)
			.sort((a, b) => a.time.getTime() - b.time.getTime());
		if (fixes.length === 0) return;

		// Only the areas of users who still see the device (shares can expire)
		const areas = await this.#sql<AreaRow[]>`
			SELECT g.id, g.user_id, g.name, g.lat, g.lon, g.radius, g.polygon, g.notify_enter, g.notify_exit, g.inside, g.checked_at, g.schedule
			FROM geofences g
			JOIN device_users du ON du.device_id = g.device_id AND du.user_id = g.user_id
				AND (du.expires_at IS NULL OR du.expires_at > now())
			WHERE g.device_id = ${deviceId}`;

		for (const area of areas) {
			let inside = area.inside;
			let checkedAt = area.checked_at;
			const crossings: { kind: "geofence_enter" | "geofence_exit"; point: AreaPoint }[] = [];
			for (const point of fixes) {
				if (checkedAt && point.time.getTime() <= checkedAt.getTime()) continue;
				const next = isInside(area, point, inside);
				if (inside !== null && next !== inside) crossings.push({ kind: next ? "geofence_enter" : "geofence_exit", point });
				inside = next;
				checkedAt = point.time;
			}
			if (checkedAt === area.checked_at) continue;

			// Conditional update: concurrent batches of the same device don't notify twice
			const updated = await this.#sql`
				UPDATE geofences SET inside = ${inside}, checked_at = ${checkedAt}
				WHERE id = ${area.id} AND checked_at IS NOT DISTINCT FROM ${area.checked_at}`;
			if (updated.count !== 1) continue;
			for (const { kind, point } of crossings) {
				if (kind === "geofence_enter" ? !area.notify_enter : !area.notify_exit) continue;
				if (!inSchedule(area.schedule, point.time, this.#timeZone)) continue;
				await this.#notifier.notifyArea(area.user_id, deviceId, kind, area.name, point.time, { lat: point.lat, lon: point.lon });
			}
		}
	}
}
