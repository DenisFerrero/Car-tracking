import { createHash } from "node:crypto";
import type { FastifyBaseLogger } from "fastify";
import type { DeviceSecrets } from "../crypto/device.ts";
import type { Sql } from "../db.ts";
import { FW_STATUS, encodeFirmwareOffer } from "../protocol/protocol.ts";
import type { Commands, Downlink } from "./commands.ts";
import type { Hub } from "./hub.ts";

// Firmware updates over the air. The images come from the releases of the repository
// (src/services/releases.ts) or from the administrator (npm run firmware); the owner of a
// tracker installs a newer one of the same variant, or the tracker asks for it once a day
// (UPDATE_CHECK, builds with AUTO_UPDATE) when the owner allows the automatic updates. The
// offer is sent after the ACK of every connection until the HELLO reports the new version:
// a download interrupted by a lost connection resumes from the bytes already sent.

export const DEFAULT_VARIANT = "default";
// Largest application partition of a 4 MB flash with OTA (min_spiffs: 1.9 MB)
export const MAX_IMAGE_SIZE = 2 * 1024 * 1024;
const ESP_IMAGE_MAGIC = 0xe9;
export const VERSION_PATTERN = /^\d{1,4}(\.\d{1,4}){0,3}$/;
export const VARIANT_PATTERN = /^[a-z0-9_-]{1,30}$/;

const STATUS_NAMES: Record<number, string> = {
	[FW_STATUS.INSTALLED]: "installed",
	[FW_STATUS.BAD_HASH]: "bad_hash",
	[FW_STATUS.WRITE_FAILED]: "write_failed",
	[FW_STATUS.TOO_BIG]: "too_big",
	[FW_STATUS.TIMEOUT]: "timeout"
};

export class FirmwareError extends Error {
	readonly code: string;

	constructor (code: string, message: string) {
		super(message);
		this.code = code;
	}
}

/** "2.3.0+lilygo" → version 2.3.0, variant lilygo; without "+": the default variant */
export function splitFirmware (firmware: string): { version: string; variant: string } {
	const plus = firmware.indexOf("+");
	if (plus < 0) return { version: firmware, variant: DEFAULT_VARIANT };
	return { version: firmware.slice(0, plus), variant: firmware.slice(plus + 1) || DEFAULT_VARIANT };
}

/** Numeric comparison of dotted versions: 2.10 > 2.9; text that isn't a number counts 0 */
export function compareVersions (a: string, b: string): number {
	const pa = a.split(".").map(part => Number.parseInt(part, 10) || 0);
	const pb = b.split(".").map(part => Number.parseInt(part, 10) || 0);
	for (let i = 0; i < Math.max(pa.length, pb.length); i++) {
		const delta = (pa[i] ?? 0) - (pb[i] ?? 0);
		if (delta !== 0) return Math.sign(delta);
	}
	return 0;
}

export interface FirmwareUpdate {
	/** Started by the tracker (UPDATE_CHECK), not by the owner */
	automatic: boolean;
	firmwareId: number;
	version: string;
	size: number;
	sent: number;
	status: string | null;
	requestedAt: Date;
	finishedAt: Date | null;
}

interface PendingRow {
	firmware_id: number;
	version: string;
	size: number;
	sha256: Buffer;
	sent: number;
	status: string | null;
	requested_at: Date;
	finished_at: Date | null;
	automatic?: boolean;
}

export class Firmware {
	readonly #sql: Sql;
	readonly #secrets: DeviceSecrets;
	readonly #commands: Commands;
	readonly #hub: Hub;
	readonly #log: FastifyBaseLogger;
	#downlink: Downlink | null = null;
	// Images being downloaded: one in memory is enough (a few trackers at a time)
	#cached: { id: number; data: Buffer } | null = null;

	constructor (sql: Sql, secrets: DeviceSecrets, commands: Commands, hub: Hub, log: FastifyBaseLogger) {
		this.#sql = sql;
		this.#secrets = secrets;
		this.#commands = commands;
		this.#hub = hub;
		this.#log = log;
	}

	setDownlink (downlink: Downlink): void {
		this.#downlink = downlink;
	}

	/** New image: an ESP32 application binary, version and variant as reported by the HELLO */
	async upload (data: Buffer, version: string, variant: string, notes = "", releaseUrl = ""): Promise<{ id: number; sha256: string }> {
		if (!VERSION_PATTERN.test(version)) throw new FirmwareError("invalid_version", "Version like 2.3.0");
		if (!VARIANT_PATTERN.test(variant)) throw new FirmwareError("invalid_variant", "Variant of lower case letters, digits, - and _");
		if (data.length < 256 || data[0] !== ESP_IMAGE_MAGIC) throw new FirmwareError("invalid_image", "Not an ESP32 application image");
		if (data.length > MAX_IMAGE_SIZE) throw new FirmwareError("image_too_big", `At most ${MAX_IMAGE_SIZE} bytes`);
		const sha256 = createHash("sha256").update(data).digest();
		const [row] = await this.#sql<{ id: number }[]>`
			INSERT INTO firmware_images (version, variant, size, sha256, data, notes, release_url)
			VALUES (${version}, ${variant}, ${data.length}, ${sha256}, ${data}, ${notes.slice(0, 500)}, ${releaseUrl.slice(0, 300)})
			ON CONFLICT (version, variant) DO NOTHING RETURNING id`;
		if (!row) throw new FirmwareError("version_exists", `Version ${version} of ${variant} already uploaded`);
		return { id: row.id, sha256: sha256.toString("hex") };
	}

	async list (): Promise<readonly unknown[]> {
		return this.#sql`
			SELECT i.id, i.version, i.variant, i.size, encode(i.sha256, 'hex') AS sha256, i.notes, i.release_url AS "releaseUrl",
				i.created_at AS "createdAt",
				(SELECT count(*)::int FROM firmware_updates u WHERE u.firmware_id = i.id AND u.finished_at IS NULL) AS pending
			FROM firmware_images i ORDER BY i.created_at DESC`;
	}

	async remove (id: number): Promise<boolean> {
		const deleted = await this.#sql`DELETE FROM firmware_images WHERE id = ${id}`;
		if (this.#cached?.id === id) this.#cached = null;
		return deleted.count === 1;
	}

	/** Images of a variant newer than a version, newest first */
	async newer (version: string, variant: string): Promise<{ id: number; version: string; size: number; notes: string; releaseUrl: string; createdAt: Date }[]> {
		const images = await this.#sql<{ id: number; version: string; size: number; notes: string; releaseUrl: string; createdAt: Date }[]>`
			SELECT id, version, size, notes, release_url AS "releaseUrl", created_at AS "createdAt" FROM firmware_images WHERE variant = ${variant}`;
		return images.filter(image => compareVersions(image.version, version) > 0).sort((a, b) => compareVersions(b.version, a.version));
	}

	/** Versions newer than the one of the tracker, same variant, the last update, automatic updates */
	async state (deviceId: number, firmware: string) {
		const { version, variant } = splitFirmware(firmware);
		const [device] = await this.#sql<{ auto_update: boolean; update_checked_at: Date | null }[]>`
			SELECT auto_update, update_checked_at FROM devices WHERE id = ${deviceId}`;
		return {
			version,
			variant,
			available: await this.newer(version, variant),
			update: await this.#update(deviceId),
			autoUpdate: device!.auto_update,
			// Builds with AUTO_UPDATE ask every day: when they last did
			updateCheckedAt: device!.update_checked_at
		};
	}

	/** The owner allows or stops the automatic updates of a tracker */
	async setAutoUpdate (deviceId: number, enabled: boolean): Promise<void> {
		await this.#sql`UPDATE devices SET auto_update = ${enabled} WHERE id = ${deviceId}`;
	}

	/** The owner installs an image: offered now if the tracker is connected, else at the next connection */
	async request (deviceId: number, firmware: string, firmwareId: number, userId: number): Promise<FirmwareUpdate> {
		const { version, variant } = splitFirmware(firmware);
		const [image] = await this.#sql<{ version: string; variant: string }[]>`SELECT version, variant FROM firmware_images WHERE id = ${firmwareId}`;
		if (!image) throw new FirmwareError("not_found", "Firmware not found");
		if (image.variant !== variant) throw new FirmwareError("wrong_variant", `The tracker runs the ${variant} variant`);
		if (compareVersions(image.version, version) <= 0) throw new FirmwareError("not_newer", `The tracker already runs ${version}`);
		return this.#start(deviceId, firmwareId, userId);
	}

	/**
	 * Daily UPDATE_CHECK of a tracker: the newest image of its variant, if the owner allows
	 * the automatic updates. An image that already failed on this tracker isn't tried again
	 * (a rollback every day would cost more than a MB of SIM each time).
	 */
	async autoUpdate (deviceId: number): Promise<number | null> {
		const [device] = await this.#sql<{ firmware: string; auto_update: boolean }[]>`
			UPDATE devices SET update_checked_at = now() WHERE id = ${deviceId} RETURNING firmware, auto_update`;
		if (!device?.auto_update) return null;
		if (await this.#pending(deviceId)) return this.offer(deviceId);
		const { version, variant } = splitFirmware(device.firmware);
		const [newest] = await this.newer(version, variant);
		if (!newest) return null;
		const [failed] = await this.#sql`
			SELECT 1 FROM firmware_updates WHERE device_id = ${deviceId} AND firmware_id = ${newest.id} AND status IS DISTINCT FROM 'done'`;
		if (failed) return null;
		this.#log.info({ deviceId, version: newest.version }, "Automatic firmware update");
		await this.#start(deviceId, newest.id, null);
		return newest.id;
	}

	async #start (deviceId: number, firmwareId: number, userId: number | null): Promise<FirmwareUpdate> {
		await this.#sql`
			INSERT INTO firmware_updates (device_id, firmware_id, requested_by, automatic) VALUES (${deviceId}, ${firmwareId}, ${userId}, ${userId === null})
			ON CONFLICT (device_id) DO UPDATE SET firmware_id = excluded.firmware_id, requested_by = excluded.requested_by, automatic = excluded.automatic,
				requested_at = now(), sent = 0, status = NULL, finished_at = NULL`;
		await this.offer(deviceId);
		const update = (await this.#update(deviceId))!;
		this.#event(deviceId, update);
		return update;
	}

	/** Stops a pending update (an image already installed is not undone) */
	async cancel (deviceId: number): Promise<boolean> {
		const deleted = await this.#sql`DELETE FROM firmware_updates WHERE device_id = ${deviceId} AND finished_at IS NULL`;
		if (deleted.count === 1) this.#event(deviceId, null);
		return deleted.count === 1;
	}

	/**
	 * After the ACK of a connection: the update is finished when the tracker reports the new
	 * version, failed when it rebooted after the installation with the old one (the
	 * bootloader rolled back), otherwise it's offered again. Returns the image offered.
	 */
	async onHello (deviceId: number, firmware: string): Promise<number | null> {
		const pending = await this.#pending(deviceId);
		if (!pending) return null;
		const { version } = splitFirmware(firmware);
		if (version === pending.version || pending.status === "installed") {
			const status = version === pending.version ? "done" : "not_applied";
			await this.#sql`UPDATE firmware_updates SET status = ${status}, finished_at = now() WHERE device_id = ${deviceId}`;
			this.#log.info({ deviceId, version, status }, "Firmware update finished");
			this.#event(deviceId, await this.#update(deviceId));
			return null;
		}
		return this.offer(deviceId);
	}

	/** Sends the offer if an update is pending and the tracker is connected */
	async offer (deviceId: number): Promise<number | null> {
		const pending = await this.#pending(deviceId);
		const [device] = await this.#sql<{ imei: string | null }[]>`SELECT imei FROM devices WHERE id = ${deviceId}`;
		const imei = device?.imei;
		if (!pending || !imei || !this.#downlink?.isReady(imei)) return null;
		const counter = await this.#commands.nextCounter(deviceId);
		const frame = encodeFirmwareOffer(this.#secrets.deviceKey(imei), counter, Math.floor(Date.now() / 1000),
			{ size: pending.size, sha256: pending.sha256, version: pending.version });
		if (!this.#downlink.send(imei, frame)) return null;
		await this.#sql`INSERT INTO traffic (time, device_id, frame_type, uplink, bytes) VALUES (now(), ${deviceId}, 6, false, ${frame.length})`;
		return pending.firmware_id;
	}

	/** Image of the update pending for a tracker, null when there is none */
	async pendingImage (deviceId: number): Promise<Buffer | null> {
		const pending = await this.#pending(deviceId);
		if (!pending) return null;
		if (this.#cached?.id !== pending.firmware_id) {
			const [row] = await this.#sql<{ data: Buffer }[]>`SELECT data FROM firmware_images WHERE id = ${pending.firmware_id}`;
			this.#cached = { id: pending.firmware_id, data: row!.data };
		}
		return this.#cached.data;
	}

	async progress (deviceId: number, sent: number): Promise<void> {
		await this.#sql`UPDATE firmware_updates SET sent = GREATEST(sent, ${sent}) WHERE device_id = ${deviceId} AND finished_at IS NULL`;
		const update = await this.#update(deviceId);
		if (update) this.#event(deviceId, update);
	}

	/** FW_RESULT: installed (the tracker reboots) or failed */
	async result (deviceId: number, code: number): Promise<void> {
		const status = STATUS_NAMES[code] ?? "failed";
		const finished = code !== FW_STATUS.INSTALLED;
		await this.#sql`
			UPDATE firmware_updates SET status = ${status}, finished_at = ${finished ? new Date() : null}
			WHERE device_id = ${deviceId} AND finished_at IS NULL`;
		this.#log.info({ deviceId, status }, "Firmware result");
		this.#event(deviceId, await this.#update(deviceId));
	}

	async #pending (deviceId: number): Promise<PendingRow | null> {
		const [row] = await this.#sql<PendingRow[]>`
			SELECT u.firmware_id, i.version, i.size, i.sha256, u.sent, u.status, u.requested_at, u.finished_at
			FROM firmware_updates u JOIN firmware_images i ON i.id = u.firmware_id
			WHERE u.device_id = ${deviceId} AND u.finished_at IS NULL`;
		return row ?? null;
	}

	async #update (deviceId: number): Promise<FirmwareUpdate | null> {
		const [row] = await this.#sql<PendingRow[]>`
			SELECT u.firmware_id, i.version, i.size, u.sent, u.status, u.requested_at, u.finished_at, u.automatic
			FROM firmware_updates u JOIN firmware_images i ON i.id = u.firmware_id WHERE u.device_id = ${deviceId}`;
		if (!row) return null;
		return {
			automatic: row.automatic!,
			firmwareId: row.firmware_id,
			version: row.version,
			size: row.size,
			sent: row.sent,
			status: row.status,
			requestedAt: row.requested_at,
			finishedAt: row.finished_at
		};
	}

	/** Owner only: viewers don't see the firmware */
	#event (deviceId: number, update: FirmwareUpdate | null): void {
		this.#hub.toDevice(deviceId, { type: "firmware", deviceId, update });
	}
}
