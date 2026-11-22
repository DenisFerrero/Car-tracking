import { z } from "zod";
import type { Sql, Tx } from "../db.ts";
import { badRequest, notFound } from "../http/errors.ts";
import { FUEL_TYPES } from "./costs.ts";

// Vehicles and the trackers installed in them. A vehicle is what the user sees (map,
// history, km, deadlines, costs, areas, shares); a tracker is hardware installed in a
// vehicle. The row of a vehicle with a tracker is kind 'tracker' and holds the columns of
// the hardware; moving the tracker moves them to another vehicle (which becomes kind
// 'tracker'), the previous vehicle becomes kind 'vehicle' and keeps its history. The
// tracker receives the id of the new vehicle in the ACK of its next connection.

export const MAX_VEHICLES = 10;

export const vehicleBody = z.strictObject({
	name: z.string().trim().min(1).max(60),
	color: z.string().regex(/^#[0-9A-Fa-f]{6}$/).default("#FFB300"),
	model: z.string().trim().max(80).default(""),
	fuelType: z.enum(FUEL_TYPES).nullable().default(null)
});
export type VehicleBody = z.output<typeof vehicleBody>;

/** New vehicle without a tracker, owned by the user */
export async function createVehicle (tx: Tx, userId: number, body: VehicleBody): Promise<number> {
	await tx`SELECT 1 FROM users WHERE id = ${userId} FOR UPDATE`;
	const [count] = await tx<{ count: number }[]>`
		SELECT count(*)::int AS count FROM device_users du JOIN devices d ON d.id = du.device_id
		WHERE du.user_id = ${userId} AND du.role = 'owner' AND d.kind = 'vehicle'`;
	if (count!.count >= MAX_VEHICLES) throw badRequest(`At most ${MAX_VEHICLES} vehicles`, "too_many_vehicles");
	const [device] = await tx<{ id: number }[]>`
		INSERT INTO devices (kind, name, color, model, vehicle_model, fuel_type)
		VALUES ('vehicle', ${body.name}, ${body.color}, 'vehicle', ${body.model}, ${body.fuelType}) RETURNING id`;
	await tx`INSERT INTO device_users (device_id, user_id, role) VALUES (${device!.id}, ${userId}, 'owner')`;
	return device!.id;
}

/** A vehicle of the user without a tracker, locked for the installation */
export async function ownVehicle (tx: Tx, userId: number, id: number): Promise<void> {
	const [row] = await tx<{ kind: string }[]>`
		SELECT d.kind FROM devices d JOIN device_users du ON du.device_id = d.id AND du.role = 'owner'
		WHERE d.id = ${id} AND du.user_id = ${userId} FOR UPDATE OF d`;
	if (!row) throw notFound("Vehicle not found");
	if (row.kind !== "vehicle") throw badRequest("The vehicle has a tracker already", "vehicle_has_tracker");
}

interface Hardware {
	imei: string;
	manufacturer: string;
	model: string;
	revision: string;
	firmware: string;
	registered_at: Date | null;
	last_seen_at: Date | null;
	offline_notified: boolean;
	downlink_counter: number;
	auto_update: boolean;
	update_checked_at: Date | null;
}

/** Takes the hardware out of a row: the row becomes a vehicle without a tracker */
async function takeHardware (tx: Tx, id: number): Promise<Hardware> {
	const [hardware] = await tx<Hardware[]>`
		SELECT imei, manufacturer, model, revision, firmware, registered_at, last_seen_at, offline_notified,
			downlink_counter, auto_update, update_checked_at
		FROM devices WHERE id = ${id} AND kind = 'tracker' FOR UPDATE`;
	if (!hardware) throw badRequest("Only for vehicles with a tracker", "not_a_tracker");
	await tx`
		UPDATE devices SET kind = 'vehicle', imei = NULL, manufacturer = '', model = 'vehicle', revision = '', firmware = '',
			registered_at = NULL, offline_notified = false, downlink_counter = 0, auto_update = true, update_checked_at = NULL
		WHERE id = ${id}`;
	// Commands and updates were for that tracker
	await tx`UPDATE commands SET superseded = true WHERE device_id = ${id} AND result IS NULL`;
	await tx`DELETE FROM firmware_updates WHERE device_id = ${id}`;
	await tx`UPDATE tracker_installations SET removed_at = now() WHERE vehicle_id = ${id} AND removed_at IS NULL`;
	return hardware;
}

/** Installs the hardware in a vehicle without a tracker */
export async function installHardware (tx: Tx, id: number, hardware: Hardware): Promise<void> {
	await tx`
		UPDATE devices SET kind = 'tracker', imei = ${hardware.imei}, manufacturer = ${hardware.manufacturer},
			model = ${hardware.model}, revision = ${hardware.revision}, firmware = ${hardware.firmware},
			registered_at = ${hardware.registered_at}, offline_notified = ${hardware.offline_notified},
			downlink_counter = ${hardware.downlink_counter}, auto_update = ${hardware.auto_update},
			update_checked_at = ${hardware.update_checked_at},
			last_seen_at = GREATEST(last_seen_at, ${hardware.last_seen_at}), archived_at = NULL
		WHERE id = ${id}`;
	await tx`INSERT INTO tracker_installations (imei, vehicle_id) VALUES (${hardware.imei}, ${id})`;
}

/** Moves the tracker of a vehicle to another vehicle (without tracker) of the same owner */
export async function moveTracker (tx: Tx, from: number, to: number): Promise<string> {
	const hardware = await takeHardware(tx, from);
	await installHardware(tx, to, hardware);
	return hardware.imei;
}

/**
 * Removes the tracker from a vehicle, which stays with its history: the tracker gets a row
 * without owner, ready to be paired again with its code
 */
export async function detachTracker (tx: Tx, from: number): Promise<string> {
	const hardware = await takeHardware(tx, from);
	await tx`
		INSERT INTO devices (imei, manufacturer, model, revision, firmware, registered_at, last_seen_at, downlink_counter, auto_update)
		VALUES (${hardware.imei}, ${hardware.manufacturer}, ${hardware.model}, ${hardware.revision}, ${hardware.firmware},
			${hardware.registered_at}, ${hardware.last_seen_at}, ${hardware.downlink_counter}, ${hardware.auto_update})`;
	return hardware.imei;
}

/**
 * Pairing in a vehicle the user already has: the hardware of the free tracker goes to the
 * vehicle, the row of the free tracker (and what it sent before the pairing) is deleted
 */
export async function pairInVehicle (tx: Tx, trackerRow: number, vehicle: number): Promise<void> {
	const hardware = await takeHardware(tx, trackerRow);
	await tx`DELETE FROM positions WHERE device_id = ${trackerRow}`;
	await tx`DELETE FROM traffic WHERE device_id = ${trackerRow}`;
	await tx`DELETE FROM device_extra WHERE device_id = ${trackerRow}`;
	await tx`DELETE FROM devices WHERE id = ${trackerRow}`;
	await installHardware(tx, vehicle, hardware);
}

export async function installations (sql: Sql, vehicle: number) {
	return sql<{ imei: string; installedAt: Date; removedAt: Date | null }[]>`
		SELECT imei, installed_at AS "installedAt", removed_at AS "removedAt" FROM tracker_installations
		WHERE vehicle_id = ${vehicle} ORDER BY installed_at DESC LIMIT 20`;
}
