import type { WebSocket } from "ws";
import type { Context } from "../context.ts";
import { IMEI_PATTERN } from "../crypto/device.ts";
import { FW_CHUNK_SIZE, FW_MAX_WINDOW, MAX_FRAME_SIZE, ProtocolError, TYPE, decodeCommandResult, decodeExtra, decodeFirmwareRequest,
	decodeFirmwareResult, decodeHello, decodeTelemetry, decryptFrame, encodeFirmwareChunk, parseFrame, plainType } from "../protocol/protocol.ts";
import type { Point } from "../protocol/protocol.ts";
import { viewerPosition } from "../services/access.ts";
import type { Cells } from "../services/cells.ts";
import type { Downlink } from "../services/commands.ts";
import { storeExtra } from "../services/extra.ts";
import { kindsOfEvents } from "../services/notifier.ts";
import { Throttle } from "../services/throttle.ts";

// Gateway of the trackers: one WebSocket per tracker on /tracker (TLS terminated by the
// proxy), every binary message is one frame of the protocol. No broker in between: the
// frame type says what a message is and the connection says which tracker sent it.
//
// - the first frame must be a HELLO authenticated with the key of its IMEI, within
//   helloMs: the server answers with the ACK, then sends the pending commands
// - then TELEMETRY, COMMAND_RESULT, EXTRA (data of another board, src/services/extra.ts)
//   and UPDATE_CHECK (daily, automatic updates) with the device id of the ACK; a frame that fails
//   the authentication is dropped, any other frame type or a text message ends the
//   connection
// - firmware updates (src/services/firmware.ts): the offer after the commands, then the
//   plain FW_REQUEST / FW_RESULT of the tracker, answered with FW_CHUNK
// - the tracker keeps the connection alive with WebSocket pings (answered by ws), a
//   connection silent for idleMs is closed
// - per client address: at most 30 connections a minute and 10 failed HELLO in 10
//   minutes, then a ban (checked before any work, no cost for floods)

// Points outside this window are rejected (clock errors, replays of old frames)
const MAX_FUTURE_MS = 10 * 60e3;
const MAX_CLIENTS = 1000;
// Frames received and not yet processed: a tracker sends a few at a time
const MAX_QUEUED = 32;
// Authenticated frames of the tracker after the ACK
const SEALED_UPLINK = new Set<number>([TYPE.TELEMETRY, TYPE.COMMAND_RESULT, TYPE.EXTRA, TYPE.UPDATE_CHECK]);

export interface GatewayTimeouts {
	/** Time for the first frame (HELLO) after the WebSocket handshake */
	helloMs: number;
	/** Connection closed without frames or pings for this long (> keepalive of the firmware) */
	idleMs: number;
}

const DEFAULT_TIMEOUTS: GatewayTimeouts = { helloMs: 10e3, idleMs: 3 * 60e3 };

interface Session {
	socket: WebSocket;
	ip: string;
	imei: string | null;
	deviceId: number | null;
	/** ACK sent: commands can be delivered */
	ready: boolean;
	queue: Promise<void>;
	queued: number;
	timer: NodeJS.Timeout;
}

export function validPoint (point: Point, now: number, retentionDays: number): boolean {
	const time = point.time.getTime();
	if (!Number.isFinite(time) || time < now - retentionDays * 86400e3 || time > now + MAX_FUTURE_MS) return false;
	if (point.lat < -90 || point.lat > 90 || point.lon < -180 || point.lon > 180) return false;
	// 0,0 is "no position": accepted only for the stale points with a cell
	return !(point.lat === 0 && point.lon === 0) || (point.stale && point.cell !== null);
}

export class Gateway implements Downlink {
	readonly #ctx: Context;
	readonly #cells: Cells;
	readonly #timeouts: GatewayTimeouts;
	readonly #sockets = new Set<Session>();
	readonly #trackers = new Map<string, Session>();
	readonly #connections = new Throttle(30, 60e3, 10 * 60e3);
	readonly #failures = new Throttle(10, 10 * 60e3, 30 * 60e3);
	readonly #sweeper: NodeJS.Timeout;

	constructor (ctx: Context, cells: Cells, timeouts: Partial<GatewayTimeouts> = {}) {
		this.#ctx = ctx;
		this.#cells = cells;
		this.#timeouts = { ...DEFAULT_TIMEOUTS, ...timeouts };
		this.#sweeper = setInterval(() => {
			this.#connections.sweep();
			this.#failures.sweep();
		}, 60e3);
	}

	handleWebSocket (socket: WebSocket, ip: string): void {
		if (this.#failures.isBanned(ip) || !this.#connections.hit(ip) || this.#sockets.size >= MAX_CLIENTS) {
			socket.close(1008, "rejected");
			return;
		}
		const session: Session = {
			socket, ip, imei: null, deviceId: null, ready: false, queue: Promise.resolve(), queued: 0,
			timer: setTimeout(() => this.#fail(session, "No HELLO"), this.#timeouts.helloMs)
		};
		this.#sockets.add(session);

		socket.on("ping", () => this.#alive(session));
		socket.on("message", (data, isBinary) => {
			if (!isBinary || session.queued >= MAX_QUEUED) {
				socket.close(1003, "unsupported");
				return;
			}
			const payload = Array.isArray(data) ? Buffer.concat(data) : Buffer.from(data as Buffer);
			session.queued += 1;
			session.queue = session.queue
				.then(() => this.#handle(session, payload))
				.catch(error => {
					if (error instanceof ProtocolError) this.#ctx.log.info({ err: error, imei: session.imei }, "Frame rejected");
					else this.#ctx.log.error({ err: error, imei: session.imei }, "Frame failed");
				})
				.finally(() => { session.queued -= 1; });
		});
		socket.on("close", () => {
			clearTimeout(session.timer);
			this.#sockets.delete(session);
			if (session.imei && this.#trackers.get(session.imei) === session) this.#trackers.delete(session.imei);
		});
	}

	/** Bad credentials: counted against the address, the connection is closed */
	#fail (session: Session, reason: string): void {
		this.#failures.hit(session.ip);
		this.#ctx.log.warn({ ip: session.ip, reason }, "Tracker authentication failed");
		session.socket.close(4001, "unauthorized");
	}

	#alive (session: Session): void {
		if (!session.imei) return;
		clearTimeout(session.timer);
		session.timer = setTimeout(() => session.socket.terminate(), this.#timeouts.idleMs);
	}

	send (imei: string, payload: Buffer): boolean {
		const session = this.#trackers.get(imei);
		if (!session?.ready) return false;
		session.socket.send(payload, { binary: true });
		return true;
	}

	isReady (imei: string): boolean {
		return this.#trackers.get(imei)?.ready ?? false;
	}

	isConnected (imei: string): boolean {
		return this.#trackers.has(imei);
	}

	get connectedTrackers (): number {
		return this.#trackers.size;
	}

	async #handle (session: Session, payload: Buffer): Promise<void> {
		if (session.socket.readyState !== session.socket.OPEN) return;
		if (!session.imei) {
			await this.#authenticate(session, payload);
			return;
		}
		this.#alive(session);
		if (payload.length > MAX_FRAME_SIZE) throw new ProtocolError("Frame too big");
		const plain = plainType(payload);
		if (plain !== null && session.deviceId) {
			await (plain === TYPE.FW_REQUEST ? this.#onFirmwareRequest(session, session.deviceId, payload)
				: this.#ctx.firmware.result(session.deviceId, decodeFirmwareResult(payload)));
			return;
		}

		const frame = parseFrame(payload);
		if (!SEALED_UPLINK.has(frame.type)) {
			session.socket.close(1008, "unexpected frame");
			throw new ProtocolError(`Unexpected frame type ${frame.type}`);
		}
		if (!session.deviceId || frame.deviceId !== session.deviceId) throw new ProtocolError(`Unknown device id ${frame.deviceId}`);
		const plaintext = decryptFrame(frame, this.#ctx.secrets.deviceKey(session.imei));
		if (!plaintext) throw new ProtocolError("Authentication failed");
		await this.#traffic(session.deviceId, frame.type, true, payload.length);

		if (frame.type === TYPE.TELEMETRY) {
			await this.#onTelemetry(session.deviceId, decodeTelemetry(plaintext, frame.timestamp));
		} else if (frame.type === TYPE.EXTRA) {
			if (!(await storeExtra(this.#ctx, session.deviceId, frame.timestamp, decodeExtra(plaintext)))) throw new ProtocolError("Invalid extra data");
		} else if (frame.type === TYPE.UPDATE_CHECK) {
			await this.#ctx.firmware.autoUpdate(session.deviceId);
		} else {
			const result = decodeCommandResult(plaintext);
			await this.#ctx.commands.handleResult(session.deviceId, result.counter, result.result);
		}
	}

	/** First frame: an authenticated HELLO, anything else closes the connection */
	async #authenticate (session: Session, payload: Buffer): Promise<void> {
		let info: ReturnType<typeof decodeHello> | null = null;
		let imei = "";
		try {
			const frame = payload.length <= MAX_FRAME_SIZE ? parseFrame(payload) : null;
			if (frame?.type === TYPE.HELLO && frame.imei && IMEI_PATTERN.test(frame.imei)) {
				const plaintext = decryptFrame(frame, this.#ctx.secrets.deviceKey(frame.imei));
				if (plaintext) {
					info = decodeHello(plaintext);
					imei = frame.imei;
				}
			}
		} catch {
			// Malformed: same answer as a wrong key
		}
		if (!info) {
			clearTimeout(session.timer);
			this.#fail(session, "Invalid HELLO");
			return;
		}

		session.imei = imei;
		this.#alive(session);
		// A new connection of the same tracker replaces the old one
		const previous = this.#trackers.get(imei);
		this.#trackers.set(imei, session);
		previous?.socket.close(4000, "replaced");
		await this.#onHello(session, imei, info, payload.length);
	}

	async #traffic (deviceId: number, type: number, uplink: boolean, bytes: number): Promise<void> {
		await this.#ctx.sql`INSERT INTO traffic (time, device_id, frame_type, uplink, bytes) VALUES (now(), ${deviceId}, ${type}, ${uplink}, ${bytes})`;
	}

	async #onHello (session: Session, imei: string, info: ReturnType<typeof decodeHello>, bytes: number): Promise<void> {
		const { sql, hub, log } = this.#ctx;
		const [device] = await sql<{ id: number; first: boolean; offline_notified: boolean }[]>`
			WITH previous AS (SELECT registered_at, offline_notified FROM devices WHERE imei = ${imei})
			INSERT INTO devices (imei, manufacturer, model, revision, firmware, registered_at, last_seen_at)
			VALUES (${imei}, ${info.manufacturer.slice(0, 100)}, ${info.model.slice(0, 100)}, ${info.revision.slice(0, 100)},
				${info.firmware.slice(0, 50)}, now(), now())
			ON CONFLICT (imei) DO UPDATE SET manufacturer = excluded.manufacturer, model = excluded.model,
				revision = excluded.revision, firmware = excluded.firmware,
				registered_at = COALESCE(devices.registered_at, now()), last_seen_at = now(), offline_notified = false
			RETURNING id, (SELECT registered_at FROM previous) IS NULL AS first,
				COALESCE((SELECT offline_notified FROM previous), false) AS offline_notified`;
		if (!device) return;

		session.deviceId = device.id;
		// Frame type 0 = a connection (its cost is estimated by the analysis)
		await this.#traffic(device.id, 0, true, 0);
		await this.#traffic(device.id, TYPE.HELLO, true, bytes);

		const ack = await this.#ctx.commands.buildAck(device.id, imei);
		if (session.socket.readyState !== session.socket.OPEN) return;
		session.socket.send(ack, { binary: true });
		await this.#traffic(device.id, TYPE.ACK, false, ack.length);
		log.info({ deviceId: device.id, imei, firmware: info.firmware }, "Tracker connected");

		const lastSeenAt = new Date();
		hub.toDevice(device.id, { type: "device", deviceId: device.id, online: true, lastSeenAt, firmware: info.firmware },
			{ type: "device", deviceId: device.id, online: true, lastSeenAt });
		if (device.first) hub.toDevice(device.id, { type: "registered", deviceId: device.id });
		if (device.offline_notified) await this.#ctx.notifier.notifyDevice(device.id, "online", new Date());
		// Ready only now: a command created meanwhile is sent once, by this flush
		session.ready = true;
		await this.#ctx.commands.flush(device.id);
		await this.#ctx.firmware.onHello(device.id, info.firmware);
	}

	/** A window of the image of the pending update, in chunks */
	async #onFirmwareRequest (session: Session, deviceId: number, payload: Buffer): Promise<void> {
		const { offset, length } = decodeFirmwareRequest(payload);
		const image = await this.#ctx.firmware.pendingImage(deviceId);
		if (!image) throw new ProtocolError("No firmware update pending");
		if (length < 1 || length > FW_MAX_WINDOW || offset + length > image.length) throw new ProtocolError("Invalid firmware window");
		const traffic: { time: Date; device_id: number; frame_type: number; uplink: boolean; bytes: number }[] =
			[{ time: new Date(), device_id: deviceId, frame_type: TYPE.FW_REQUEST, uplink: true, bytes: payload.length }];
		for (let start = offset; start < offset + length; start += FW_CHUNK_SIZE) {
			if (session.socket.readyState !== session.socket.OPEN) return;
			const chunk = encodeFirmwareChunk(start, image.subarray(start, Math.min(start + FW_CHUNK_SIZE, offset + length)));
			session.socket.send(chunk, { binary: true });
			traffic.push({ time: new Date(), device_id: deviceId, frame_type: TYPE.FW_CHUNK, uplink: false, bytes: chunk.length });
		}
		await this.#ctx.sql`INSERT INTO traffic ${this.#ctx.sql(traffic)}`;
		await this.#ctx.firmware.progress(deviceId, offset + length);
	}

	async #onTelemetry (deviceId: number, decoded: Point[]): Promise<void> {
		const { sql, hub, notifier, config } = this.#ctx;
		const now = Date.now();
		const points = decoded.filter(point => validPoint(point, now, config.RETENTION_DAYS));
		if (points.length === 0) return;

		const rows = points.map(point => {
			const unknown = point.lat === 0 && point.lon === 0;
			return {
				time: point.time,
				device_id: deviceId,
				lat: unknown ? null : point.lat,
				lon: unknown ? null : point.lon,
				altitude: point.altitude,
				speed: point.speed,
				pressure: point.pressure,
				temperature: point.temperature,
				voltage: point.voltage,
				satellites: point.satellites,
				signal: point.signal,
				events: point.events,
				status: point.status,
				stale: point.stale,
				mcc: point.cell?.mcc ?? null,
				mnc: point.cell?.mnc ?? null,
				cell_area: point.cell?.area ?? null,
				cell_id: point.cell?.id ?? null
			};
		});
		// Replayed frames hit the primary key (device_id, time) and are skipped
		const inserted = await sql<{ time: Date }[]>`
			INSERT INTO positions ${sql(rows)} ON CONFLICT (device_id, time) DO NOTHING RETURNING time`;
		const fresh = new Set(inserted.map(row => row.time.getTime()));

		const [state] = await sql<{ offline_notified: boolean }[]>`
			UPDATE devices SET last_seen_at = now(), offline_notified = false
			WHERE id = ${deviceId} RETURNING (SELECT offline_notified FROM devices WHERE id = ${deviceId}) AS offline_notified`;
		if (state?.offline_notified) await notifier.notifyDevice(deviceId, "online", new Date());

		for (const row of rows) {
			if (!fresh.has(row.time.getTime())) continue;
			hub.toDevice(deviceId, { type: "position", deviceId, position: row }, { type: "position", deviceId, position: viewerPosition(row) });
			if (row.cell_id !== null) this.#cells.resolve({ mcc: row.mcc!, mnc: row.mnc!, area: row.cell_area!, id: row.cell_id });
			for (const kind of kindsOfEvents(row.events)) {
				await notifier.notifyDevice(deviceId, kind, row.time, { lat: row.lat, lon: row.lon });
			}
		}
		await this.#ctx.geofences.evaluate(deviceId, rows.filter(row => fresh.has(row.time.getTime())));
	}

	async close (): Promise<void> {
		clearInterval(this.#sweeper);
		for (const session of this.#sockets) {
			clearTimeout(session.timer);
			session.socket.terminate();
		}
		await Promise.allSettled([...this.#sockets].map(session => session.queue));
	}
}
