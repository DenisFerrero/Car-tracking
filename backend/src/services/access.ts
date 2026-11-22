import type { Sql } from "../db.ts";
import { badRequest, forbidden, notFound } from "../http/errors.ts";
import type { AuthUser } from "../http/session.ts";

// Access to the devices. Every tracker has one owner (the user who added it): commands,
// settings, history, analysis, sharing. Viewers are shares, permanent or with an end:
// they see only the current position, the speed and the state of the car. The
// administrators manage the users, not their data: no access to the devices of others.

export type Role = "owner" | "viewer";
/** Tracker with the firmware, phone of a person, vehicle fed by the phone of its owner */
export type DeviceKind = "tracker" | "phone" | "vehicle";

export interface Access {
	role: Role;
	kind: DeviceKind;
	/** End of a temporary share */
	expiresAt: Date | null;
	/** Start of the share: viewers don't see what happened before */
	since: Date;
}

const ACTIVE = "(du.expires_at IS NULL OR du.expires_at > now())";

interface AccessRow {
	device_id: number;
	role: Role;
	kind: DeviceKind;
	expires_at: Date | null;
	created_at: Date;
}

const toAccess = (row: AccessRow): Access => ({ role: row.role, kind: row.kind, expiresAt: row.expires_at, since: row.created_at });

export async function deviceAccess (sql: Sql, userId: number, deviceId: number): Promise<Access | null> {
	const [row] = await sql<AccessRow[]>`
		SELECT du.device_id, du.role, d.kind, du.expires_at, du.created_at FROM device_users du JOIN devices d ON d.id = du.device_id
		WHERE du.device_id = ${deviceId} AND du.user_id = ${userId} AND ${sql.unsafe(ACTIVE)}`;
	return row ? toAccess(row) : null;
}

/** 404 for the devices of other users: it doesn't disclose which ids exist */
export async function requireDevice (sql: Sql, user: AuthUser, deviceId: number, need: "view" | "owner" = "view"): Promise<Access> {
	const access = await deviceAccess(sql, user.id, deviceId);
	if (!access) throw notFound("Device not found");
	if (need === "owner" && access.role !== "owner") throw forbidden("Only the owner can do this", "owner_only");
	return access;
}

/** Commands, alarms and their settings: trackers of the user, not phones */
export async function requireTracker (sql: Sql, user: AuthUser, deviceId: number): Promise<Access> {
	const access = await requireDevice(sql, user, deviceId, "owner");
	if (access.kind !== "tracker") throw badRequest("Only for trackers", "not_a_tracker");
	return access;
}

/** Deadlines and odometer: cars, with a tracker or fed by a phone */
export async function requireVehicle (sql: Sql, user: AuthUser, deviceId: number): Promise<Access> {
	const access = await requireDevice(sql, user, deviceId, "owner");
	if (access.kind === "phone") throw badRequest("Only for vehicles", "not_a_vehicle");
	return access;
}

/** Devices visible by a user, with the role and the end of the share */
export async function visibleDevices (sql: Sql, userId: number): Promise<Map<number, Access>> {
	const rows = await sql<AccessRow[]>`
		SELECT du.device_id, du.role, d.kind, du.expires_at, du.created_at FROM device_users du JOIN devices d ON d.id = du.device_id
		WHERE du.user_id = ${userId} AND ${sql.unsafe(ACTIVE)}`;
	return new Map(rows.map(row => [row.device_id, toAccess(row)]));
}

/** Whether a cached access is still valid now */
export function isActive (access: Access | undefined, now = Date.now()): access is Access {
	return access !== undefined && (access.expiresAt === null || access.expiresAt.getTime() > now);
}

// --- What a viewer can see: no IMEI, modem, battery, signal, alarms or cells

export interface PositionRow {
	time: Date;
	lat: number | null;
	lon: number | null;
	speed: number | null;
	status: number;
	stale: boolean;
	[key: string]: unknown;
}

/** Moving (0) or parked (1): heartbeat and alarm states stay with the owner */
export function viewerPosition (position: PositionRow) {
	return {
		time: position.time,
		lat: position.lat,
		lon: position.lon,
		speed: position.speed,
		status: position.status === 0 ? 0 : 1,
		stale: position.stale
	};
}
