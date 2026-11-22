import type { FastifyBaseLogger } from "fastify";
import type { Sql } from "../db.ts";
import type { DeviceSecrets } from "../crypto/device.ts";
import { COMMAND, RESULT, encodeAck, encodeCommand } from "../protocol/protocol.ts";
import type { Command } from "../protocol/protocol.ts";

// Commands for the trackers. A tracker is reachable only while it's connected (driving,
// heartbeat, alarm): commands are stored and sent when it subscribes to c/<imei>. The
// pending commands of a device are merged in a single frame, the newest value of each
// command wins. Durations are stored as absolute deadlines and converted to seconds
// relative to the frame timestamp when the frame is sent: a late delivery lasts only the
// remaining time, an expired command is not sent at all.

export type CommandType = "live" | "antitheft" | "locate";

/** until: unix seconds; 0 = stop (LIVE) / resume (ANTITHEFT) */
interface StoredCommand {
	id: number;
	until: number;
}

// A LOCATE not delivered within an hour is useless
const LOCATE_TTL = 3600;
// Live tracking requested by an open map: renewed while somebody is watching
export const LIVE_SECONDS = 600;
const LIVE_RENEW_BEFORE = 300;

const TYPES: Record<CommandType, number> = { live: COMMAND.LIVE, antitheft: COMMAND.ANTITHEFT, locate: COMMAND.LOCATE };

export interface Downlink {
	/** Sends a frame to a connected tracker, false when it's not connected */
	send (imei: string, payload: Buffer): boolean;
	/** Connected and acknowledged: it can receive commands */
	isReady (imei: string): boolean;
}

export interface CommandRow {
	id: number;
	device_id: number;
	counter: number;
	payload: StoredCommand[];
	created_at: Date;
	sent_at: Date | null;
	result: number | null;
	result_at: Date | null;
}

export interface CommandListener {
	(deviceId: number, command: CommandRow): void;
}

export class Commands {
	readonly #sql: Sql;
	readonly #secrets: DeviceSecrets;
	readonly #log: FastifyBaseLogger;
	#downlink: Downlink | null = null;
	readonly #listeners: CommandListener[] = [];

	constructor (sql: Sql, secrets: DeviceSecrets, log: FastifyBaseLogger) {
		this.#sql = sql;
		this.#secrets = secrets;
		this.#log = log;
	}

	setDownlink (downlink: Downlink): void {
		this.#downlink = downlink;
	}

	onChange (listener: CommandListener): void {
		this.#listeners.push(listener);
	}

	#emit (row: CommandRow): void {
		for (const listener of this.#listeners) listener(row.device_id, row);
	}

	/**
	 * Next counter of the frames sent to a tracker. ACK and COMMAND frames share key and
	 * direction, so they share the counter: a nonce is never reused.
	 */
	async nextCounter (deviceId: number): Promise<number> {
		const [row] = await this.#sql<{ downlink_counter: number }[]>`
			UPDATE devices SET downlink_counter = GREATEST(extract(epoch FROM now())::bigint, downlink_counter + 1)
			WHERE id = ${deviceId} RETURNING downlink_counter`;
		if (!row) throw new Error(`Unknown device ${deviceId}`);
		return Number(row.downlink_counter);
	}

	async buildAck (deviceId: number, imei: string): Promise<Buffer> {
		const counter = await this.nextCounter(deviceId);
		return encodeAck(this.#secrets.deviceKey(imei), deviceId, counter, Math.floor(Date.now() / 1000));
	}

	async create (deviceId: number, type: CommandType, seconds: number, userId: number | null): Promise<CommandRow> {
		const now = Math.floor(Date.now() / 1000);
		const command: StoredCommand = {
			id: TYPES[type],
			until: type === "locate" ? now + LOCATE_TTL : (seconds > 0 ? now + seconds : 0)
		};

		const row = await this.#sql.begin(async tx => {
			// Serializes the commands of the device
			await tx`SELECT 1 FROM devices WHERE id = ${deviceId} FOR UPDATE`;
			const pending = await tx<CommandRow[]>`
				UPDATE commands SET superseded = true
				WHERE device_id = ${deviceId} AND result IS NULL AND NOT superseded
				RETURNING id, payload`;

			const merged = new Map<number, StoredCommand>();
			for (const old of pending.sort((a, b) => a.id - b.id)) {
				for (const item of old.payload) merged.set(item.id, item);
			}
			merged.set(command.id, command);

			const [counterRow] = await tx<{ downlink_counter: number }[]>`
				UPDATE devices SET downlink_counter = GREATEST(extract(epoch FROM now())::bigint, downlink_counter + 1)
				WHERE id = ${deviceId} RETURNING downlink_counter`;
			const [inserted] = await tx<CommandRow[]>`
				INSERT INTO commands (device_id, counter, payload, created_by)
				VALUES (${deviceId}, ${counterRow!.downlink_counter}, ${tx.json([...merged.values()] as never)}, ${userId})
				RETURNING id, device_id, counter, payload, created_at, sent_at, result, result_at`;
			return inserted!;
		});

		this.#emit(row);
		await this.flush(deviceId);
		return row;
	}

	/** Keeps the live tracking active while somebody watches the device */
	async ensureLive (deviceId: number): Promise<void> {
		const now = Math.floor(Date.now() / 1000);
		const [active] = await this.#sql`
			SELECT 1 FROM commands, jsonb_array_elements(payload) AS item
			WHERE device_id = ${deviceId} AND NOT superseded AND (result IS NULL OR result = ${RESULT.OK})
				AND (item ->> 'id')::int = ${COMMAND.LIVE} AND (item ->> 'until')::bigint > ${now + LIVE_RENEW_BEFORE}
			LIMIT 1`;
		if (!active) await this.create(deviceId, "live", LIVE_SECONDS, null);
	}

	/** Sends the pending frame of a device, if it's listening */
	async flush (deviceId: number): Promise<void> {
		if (!this.#downlink) return;
		const [device] = await this.#sql<{ imei: string }[]>`SELECT imei FROM devices WHERE id = ${deviceId}`;
		if (!device || !this.#downlink.isReady(device.imei)) return;

		const [row] = await this.#sql<CommandRow[]>`
			SELECT id, device_id, counter, payload, created_at, sent_at, result, result_at FROM commands
			WHERE device_id = ${deviceId} AND result IS NULL AND NOT superseded ORDER BY id DESC LIMIT 1`;
		if (!row) return;

		const now = Math.floor(Date.now() / 1000);
		const items: Command[] = [];
		for (const item of row.payload) {
			if (item.until === 0) items.push({ id: item.id, seconds: 0 });
			else if (item.until > now) items.push(item.id === COMMAND.LOCATE ? { id: item.id } : { id: item.id, seconds: item.until - now });
		}
		if (items.length === 0) {
			const [expired] = await this.#sql<CommandRow[]>`
				UPDATE commands SET result = ${RESULT.EXPIRED}, result_at = now() WHERE id = ${row.id}
				RETURNING id, device_id, counter, payload, created_at, sent_at, result, result_at`;
			if (expired) this.#emit(expired);
			return;
		}

		// Same counter and same second give the same plaintext: a resend never reuses a
		// nonce with different data
		const frame = encodeCommand(this.#secrets.deviceKey(device.imei), Number(row.counter), now, items);
		if (this.#downlink.send(device.imei, frame)) {
			await this.#sql`UPDATE commands SET sent_at = now() WHERE id = ${row.id}`;
			await this.#sql`INSERT INTO traffic (time, device_id, frame_type, uplink, bytes) VALUES (now(), ${deviceId}, 4, false, ${frame.length})`;
			this.#log.info({ deviceId, counter: row.counter }, "Command sent");
		}
	}

	async handleResult (deviceId: number, counter: number, result: number): Promise<void> {
		const [row] = await this.#sql<CommandRow[]>`
			UPDATE commands SET result = ${result}, result_at = now()
			WHERE device_id = ${deviceId} AND counter = ${counter} AND result IS NULL
			RETURNING id, device_id, counter, payload, created_at, sent_at, result, result_at`;
		if (row) this.#emit(row);
	}

	async recent (deviceId: number, limit = 20): Promise<CommandRow[]> {
		return this.#sql<CommandRow[]>`
			SELECT id, device_id, counter, payload, created_at, sent_at, result, result_at FROM commands
			WHERE device_id = ${deviceId} AND NOT superseded ORDER BY id DESC LIMIT ${limit}`;
	}

	/** State derived from the commands accepted by the tracker */
	async state (deviceId: number): Promise<{ liveUntil: number | null; antitheftPausedUntil: number | null }> {
		const rows = await this.#sql<{ id: number; until: number }[]>`
			SELECT DISTINCT ON ((item ->> 'id')::int) (item ->> 'id')::int AS id, (item ->> 'until')::bigint AS until
			FROM commands, jsonb_array_elements(payload) AS item
			WHERE device_id = ${deviceId} AND result = ${RESULT.OK}
			ORDER BY (item ->> 'id')::int, commands.id DESC`;
		const now = Math.floor(Date.now() / 1000);
		const active = (id: number) => {
			const until = Number(rows.find(row => row.id === id)?.until ?? 0);
			return until > now ? until : null;
		};
		return { liveUntil: active(COMMAND.LIVE), antitheftPausedUntil: active(COMMAND.ANTITHEFT) };
	}
}
