import type { Context } from "../context.ts";

// Long stop: each user (owner or viewer) chooses for each device after how many hours a
// device standing still outside their own arrival areas is notified (car left somewhere
// unusual, phone forgotten). One notification per stop and user; a device that doesn't
// report (tracker offline, phone paused or no longer sharing) isn't "stopped", it's
// silent: the offline notification covers the trackers.

/** A phone standing still sends a position every 5 minutes */
const PHONE_SILENT = "30 minutes";

export async function notifyLongStops (ctx: Context): Promise<void> {
	const stops = await ctx.sql<{ id: number; user_id: number; since: Date; lat: number; lon: number; hours: number }[]>`
		SELECT d.id, du.user_id, moved.since, last.lat, last.lon, du.stop_alert_hours AS hours
		FROM device_users du
		JOIN devices d ON d.id = du.device_id
		CROSS JOIN LATERAL (
			SELECT max(time) AS since FROM positions
			WHERE device_id = d.id AND status = 0 AND time > now() - interval '7 days') moved
		CROSS JOIN LATERAL (
			SELECT time, lat, lon FROM positions
			WHERE device_id = d.id AND NOT stale AND lat IS NOT NULL AND time > now() - interval '7 days'
			ORDER BY time DESC LIMIT 1) last
		WHERE du.stop_alert_hours IS NOT NULL AND (du.expires_at IS NULL OR du.expires_at > now())
			AND moved.since < now() - make_interval(hours => du.stop_alert_hours)
			AND last.time > moved.since
			AND du.stop_alerted_at IS DISTINCT FROM moved.since
			AND CASE WHEN d.kind = 'phone'
				THEN d.paused_until IS NULL AND last.time > now() - ${PHONE_SILENT}::interval
				ELSE NOT d.offline_notified END
			-- Inside an area of the user (home, office): a known place
			AND NOT EXISTS (SELECT 1 FROM geofences g WHERE g.device_id = d.id AND g.user_id = du.user_id AND g.inside)`;
	for (const stop of stops) {
		// Conditional update: concurrent jobs don't notify twice
		const updated = await ctx.sql`
			UPDATE device_users SET stop_alerted_at = ${stop.since}
			WHERE device_id = ${stop.id} AND user_id = ${stop.user_id} AND stop_alerted_at IS DISTINCT FROM ${stop.since}`;
		if (updated.count !== 1) continue;
		await ctx.notifier.notifyUser(stop.user_id, stop.id, "long_stop", stop.since, { hours: stop.hours }, { lat: stop.lat, lon: stop.lon });
	}
}
