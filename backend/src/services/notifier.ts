import type { FastifyBaseLogger } from "fastify";
import type { Sql } from "../db.ts";
import { notificationText } from "../i18n.ts";
import type { NotificationData, NotificationKind } from "../i18n.ts";
import { EVENT } from "../protocol/protocol.ts";
import type { Fcm } from "./fcm.ts";
import type { Hub } from "./hub.ts";
import type { NewError } from "./platform-log.ts";
import type { MonthTotals } from "./summary.ts";

// Notifications: stored for the inbox of the app (kind + values, the app writes the text
// in its language), sent on the realtime channel and, when Firebase is configured, as
// push notifications in the language of the user.
//
// - alarms and state of the tracker (KINDS): only the owner, per kind settings
// - arrival areas: the user who created the area (owner or viewer)
// - long stop, low battery of a phone: each user, by their own settings on the device
// - summary of the month: each user who wants it, no device
// - errors never seen before in the platform log: the administrators who want them
// - parking: proposal at the ignition off (owners who want it), reminder and end (who set it)

export const KINDS = ["motion", "tilt", "power_lost", "low_battery", "offline", "online", "battery_health", "maintenance", "firmware"] as const;
export type Kind = typeof KINDS[number];

export function kindsOfEvents (events: number): Kind[] {
	const kinds: Kind[] = [];
	// Tilt and power loss are more specific than the motion that usually comes with them
	if (events & EVENT.TILT) kinds.push("tilt");
	if (events & EVENT.POWER_LOST) kinds.push("power_lost");
	if ((events & EVENT.MOTION) && kinds.length === 0) kinds.push("motion");
	if (events & EVENT.LOW_BATTERY) kinds.push("low_battery");
	return kinds;
}

export function deviceName (device: { name: string; imei: string | null }): string {
	return device.name || (device.imei ? `Tracker ${device.imei.slice(-4)}` : "Phone");
}

interface Position {
	lat: number | null;
	lon: number | null;
}

export class Notifier {
	readonly #sql: Sql;
	readonly #log: FastifyBaseLogger;
	readonly #hub: Hub;
	readonly #fcm: Fcm | null;
	readonly #timeZone: string;

	constructor (sql: Sql, log: FastifyBaseLogger, hub: Hub, fcm: Fcm | null, timeZone: string) {
		this.#sql = sql;
		this.#log = log;
		this.#hub = hub;
		this.#fcm = fcm;
		this.#timeZone = timeZone;
	}

	get pushEnabled (): boolean {
		return this.#fcm !== null;
	}

	/** Alarm or state change of a tracker, health of the car and deadlines, for its owner */
	async notifyDevice (deviceId: number, kind: Kind, at: Date, position: Position = { lat: null, lon: null },
		extra: Omit<NotificationData, "device" | "time"> = {}): Promise<void> {
		const recipients = await this.#sql<{ user_id: number; locale: string | null; name: string; imei: string | null }[]>`
			SELECT du.user_id, u.locale, d.name, d.imei FROM device_users du
			JOIN users u ON u.id = du.user_id AND NOT u.disabled
			JOIN devices d ON d.id = du.device_id
			LEFT JOIN notification_settings ns ON ns.user_id = du.user_id AND ns.device_id = du.device_id
			WHERE du.device_id = ${deviceId} AND du.role = 'owner' AND (ns.kinds IS NULL OR ${kind} = ANY (ns.kinds))`;
		for (const recipient of recipients) {
			await this.#deliver(recipient.user_id, recipient.locale, deviceId, kind, { device: deviceName(recipient), time: at.toISOString(), ...extra }, position);
		}
	}

	/** Alert chosen by a user on a device they see: long stop, low battery of a phone */
	async notifyUser (userId: number, deviceId: number, kind: "long_stop" | "phone_battery", at: Date,
		extra: Pick<NotificationData, "battery" | "hours">, position: Position = { lat: null, lon: null }): Promise<void> {
		const [recipient] = await this.#sql<{ locale: string | null; name: string; imei: string | null }[]>`
			SELECT u.locale, d.name, d.imei FROM users u, devices d WHERE u.id = ${userId} AND NOT u.disabled AND d.id = ${deviceId}`;
		if (!recipient) return;
		await this.#deliver(userId, recipient.locale, deviceId, kind, { device: deviceName(recipient), time: at.toISOString(), ...extra }, position);
	}

	/** A device entered or left an arrival area of a user */
	async notifyArea (userId: number, deviceId: number, kind: "geofence_enter" | "geofence_exit", area: string, at: Date, position: Position): Promise<void> {
		const [recipient] = await this.#sql<{ locale: string | null; name: string; imei: string | null }[]>`
			SELECT u.locale, d.name, d.imei FROM users u, devices d WHERE u.id = ${userId} AND NOT u.disabled AND d.id = ${deviceId}`;
		if (!recipient) return;
		await this.#deliver(userId, recipient.locale, deviceId, kind, { device: deviceName(recipient), area, time: at.toISOString() }, position);
	}

	/** Totals of the month just ended (src/services/summary.ts) */
	async notifySummary (userId: number, month: string, totals: MonthTotals): Promise<void> {
		const [recipient] = await this.#sql<{ locale: string | null }[]>`SELECT locale FROM users WHERE id = ${userId} AND NOT disabled`;
		if (!recipient) return;
		await this.#deliver(userId, recipient.locale, null, "monthly_summary", {
			device: "", month, distanceKm: totals.distanceKm, trips: totals.trips, cost: totals.cost, time: new Date().toISOString()
		}, { lat: null, lon: null });
	}

	/** Parking of a vehicle: proposal, reminder before the end, end (time: the ignition off or the end) */
	async notifyParking (userId: number, deviceId: number, kind: "parking_prompt" | "parking_reminder" | "parking_expired", at: Date,
		extra: Pick<NotificationData, "minutes">, position: Position): Promise<void> {
		const [recipient] = await this.#sql<{ locale: string | null; name: string; imei: string | null }[]>`
			SELECT u.locale, d.name, d.imei FROM users u, devices d WHERE u.id = ${userId} AND NOT u.disabled AND d.id = ${deviceId}`;
		if (!recipient) return;
		await this.#deliver(userId, recipient.locale, deviceId, kind, { device: deviceName(recipient), time: at.toISOString(), ...extra },
			{ lat: position.lat, lon: position.lon });
	}

	/** New errors of the platform log: the first one in the text, the count of the others */
	async notifyAdmins (errors: NewError[]): Promise<void> {
		const admins = await this.#sql<{ id: number; locale: string | null }[]>`
			SELECT id, locale FROM users WHERE is_admin AND admin_alerts AND NOT disabled`;
		const [first] = errors;
		for (const admin of admins) {
			await this.#deliver(admin.id, admin.locale, null, "platform_error", {
				device: "", source: first!.source, message: first!.message.slice(0, 200), others: errors.length - 1, time: new Date().toISOString()
			}, { lat: null, lon: null });
		}
	}

	async #deliver (userId: number, locale: string | null, deviceId: number | null, kind: NotificationKind, data: NotificationData, position: Position): Promise<void> {
		const [notification] = await this.#sql<{ id: number; created_at: Date }[]>`
			INSERT INTO notifications (user_id, device_id, kind, data, lat, lon)
			VALUES (${userId}, ${deviceId}, ${kind}, ${this.#sql.json(data as never)}, ${position.lat}, ${position.lon})
			RETURNING id, created_at`;
		this.#hub.toUser(userId, {
			type: "notification",
			notification: {
				id: notification!.id, deviceId, kind, data, lat: position.lat, lon: position.lon,
				createdAt: notification!.created_at, readAt: null
			}
		});
		if (!this.#fcm) return;
		const { title, body } = notificationText(locale, kind, data, this.#timeZone);
		await this.#push(userId, title, body, {
			...(deviceId === null ? {} : { deviceId: String(deviceId) }), ...(data.month ? { month: data.month } : {}),
			kind, notificationId: String(notification!.id)
		});
	}

	async #push (userId: number, title: string, body: string, data: Record<string, string>): Promise<void> {
		const tokens = await this.#sql<{ token: string }[]>`SELECT token FROM push_tokens WHERE user_id = ${userId}`;
		for (const { token } of tokens) {
			try {
				const result = await this.#fcm!.send(token, title, body, data);
				if (result === "invalid_token") await this.#sql`DELETE FROM push_tokens WHERE token = ${token}`;
			} catch (error) {
				this.#log.warn({ err: error }, "Push notification failed");
			}
		}
	}
}
