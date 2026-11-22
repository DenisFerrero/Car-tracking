import type { Sql } from "../db.ts";
import { distanceMeters } from "./analytics.ts";
import type { Notifier } from "./notifier.ts";
import { inSchedule } from "./schedule.ts";
import type { Schedule } from "./schedule.ts";

// Arrival areas: circles chosen by a user on the map of a device ("almost home", "at the
// office"). Every new position with a GNSS fix is checked against the areas of the
// device; crossing the border notifies the user who created the area.
//
// An area with a schedule notifies only the crossings in its hours; the side of the border
// is followed all the time.
//
// The border has a margin when leaving (10% of the radius, at least 30 m): a car parked on
// the edge doesn't produce a notification at every point.

export const MAX_AREAS_PER_DEVICE = 20;

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
	notify_enter: boolean;
	notify_exit: boolean;
	inside: boolean | null;
	checked_at: Date | null;
	schedule: Schedule | null;
}

export function exitMargin (radius: number): number {
	return Math.max(30, radius * 0.1);
}

/** Side of the border of a point, given the previous side */
export function isInside (area: { lat: number; lon: number; radius: number }, point: { lat: number; lon: number }, wasInside: boolean | null): boolean {
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
	async initialState (deviceId: number, area: { lat: number; lon: number; radius: number }): Promise<{ inside: boolean | null; checkedAt: Date | null }> {
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
			SELECT g.id, g.user_id, g.name, g.lat, g.lon, g.radius, g.notify_enter, g.notify_exit, g.inside, g.checked_at, g.schedule
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
