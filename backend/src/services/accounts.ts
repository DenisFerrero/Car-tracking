import type { Context } from "../context.ts";
import type { DeviceKind } from "./access.ts";
import { allowDecompression } from "../db.ts";
import type { Sql } from "../db.ts";

// Removal of devices and users with all their data: used by the owner (device removed),
// by the user (account deleted) and by the administrator (user deleted).

/**
 * Data of a device removed by its owner: positions, traffic, alarms, shares. A phone is
 * deleted, a tracker stays without owner, ready to be paired again.
 * Returns the users who could see it.
 */
export async function releaseDevice (sql: Sql, id: number, kind: DeviceKind): Promise<number[]> {
	return sql.begin(async tx => {
		await allowDecompression(tx);
		const removed = await tx<{ user_id: number }[]>`DELETE FROM device_users WHERE device_id = ${id} RETURNING user_id`;
		await tx`DELETE FROM positions WHERE device_id = ${id}`;
		await tx`DELETE FROM traffic WHERE device_id = ${id}`;
		await tx`DELETE FROM notifications WHERE device_id = ${id}`;
		await tx`DELETE FROM notification_settings WHERE device_id = ${id}`;
		await tx`DELETE FROM geofences WHERE device_id = ${id}`;
		await tx`DELETE FROM firmware_updates WHERE device_id = ${id}`;
		// Car of the previous owner: statistics, trip log, deadlines, odometer, costs
		await tx`DELETE FROM daily_stats WHERE device_id = ${id}`;
		await tx`DELETE FROM trip_tags WHERE device_id = ${id}`;
		await tx`DELETE FROM maintenance WHERE device_id = ${id}`;
		await tx`DELETE FROM maintenance_log WHERE device_id = ${id}`;
		await tx`DELETE FROM vehicle_rates WHERE device_id = ${id}`;
		await tx`DELETE FROM refuels WHERE device_id = ${id}`;
		await tx`DELETE FROM parkings WHERE device_id = ${id}`;
		// Links sent by the previous owner stop showing the tracker
		await tx`DELETE FROM live_links WHERE device_id = ${id}`;
		await tx`DELETE FROM device_extra WHERE device_id = ${id}`;
		await tx`DELETE FROM tracker_installations WHERE vehicle_id = ${id}`;
		await tx`UPDATE commands SET superseded = true WHERE device_id = ${id} AND result IS NULL`;
		// Only a tracker exists without its owner (it can be paired again)
		if (kind !== "tracker") await tx`DELETE FROM devices WHERE id = ${id}`;
		else {
			await tx`
				UPDATE devices SET name = '', color = '#1E88E5', battery = NULL, paused_until = NULL, odometer_base = NULL,
					odometer_day = NULL, battery_health_alerted_at = NULL, vehicle_model = '', fuel_unit = 'l_per_100km',
					fuel_type = NULL, fuel_price_auto = false, rates_from_refuels = true, parking_prompt = false, auto_update = true,
					archived_at = NULL WHERE id = ${id}`;
		}
		return removed.map(row => row.user_id);
	});
}

/** A user and everything of theirs: the devices they own are released first */
export async function deleteUser (ctx: Context, userId: number): Promise<void> {
	const owned = await ctx.sql<{ id: number; kind: DeviceKind }[]>`
		SELECT d.id, d.kind FROM device_users du JOIN devices d ON d.id = du.device_id
		WHERE du.user_id = ${userId} AND du.role = 'owner'`;
	const viewers = new Set<number>();
	for (const device of owned) {
		for (const viewer of await releaseDevice(ctx.sql, device.id, device.kind)) viewers.add(viewer);
	}
	ctx.hub.disconnectUser(userId);
	// Sessions, passkeys, friendships, requests, areas...: ON DELETE CASCADE
	await ctx.sql`DELETE FROM users WHERE id = ${userId}`;
	viewers.delete(userId);
	for (const viewer of viewers) await ctx.hub.refreshUser(viewer);
}
