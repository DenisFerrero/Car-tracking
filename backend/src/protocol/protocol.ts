/**
 * Binary protocol (v2) between the trackers and the server.
 * The firmware counterpart is firmware/protocol.cpp, the two must stay aligned
 * (firmware/test/cross-check.ts verifies it).
 *
 * Frame:
 *   u8      header       (VERSION << 4) | type
 *   ...     device ref   HELLO: IMEI as u64 LE, TELEMETRY / COMMAND_RESULT / UPDATE_CHECK / EXTRA: device id varint,
 *                        ACK / COMMAND: nothing (the connection identifies the device)
 *   u32 LE  counter      never repeated with the same key (persisted by the device)
 *   u32 LE  timestamp    unix seconds (TELEMETRY: timestamp of the first point)
 *   ...     ciphertext   ChaCha20, AAD = all the bytes above
 *   8 B     tag          truncated Poly1305
 *
 * Nonce = counter (u32 LE) | timestamp (u32 LE) | direction (u32 LE, 0 uplink / 1 downlink)
 *
 * TELEMETRY plaintext, a list of points, every value is a delta from the previous point
 * (the first point starts from timestamp = header timestamp and all the other values = 0):
 *   u8      flags        bits 0-1 status, then FLAG_* for the optional fields
 *   varint  dt           seconds
 *   zigzag  dlat, dlon   1e-5 degrees
 *   zigzag  daltitude    meters                  (FLAG_ALTITUDE)
 *   zigzag  dpressure    hPa * 10                (FLAG_PRESSURE)
 *   zigzag  dtemperature °C * 10                 (FLAG_TEMPERATURE)
 *   varint  speed        km/h, absolute value    (FLAG_SPEED)
 *   u8      satellites   used in the fix         (FLAG_SATELLITES)
 *   u8      ext          more flags, EXT_*       (FLAG_EXTENDED)
 *   u8      signal       -dBm, cellular or WiFi  (EXT_SIGNAL)
 *   zigzag  dvoltage     vehicle battery, V * 100 (EXT_VOLTAGE)
 *   u8      events       EVENT_* bit mask        (EXT_EVENTS)
 *   varint  mcc, mnc     serving cell, absolute  (EXT_CELL)
 *   varint  area, cell   TAC/LAC and cell id
 *   -       stale        position of the last fix, the GNSS has no fix now (EXT_STALE)
 *
 * HELLO plaintext: manufacturer, model, revision, firmware as u8 length + bytes
 * ACK plaintext:   device id varint
 *
 * COMMAND (server -> tracker): a list of u8 command id + parameters,
 * durations relative to the frame timestamp. The tracker applies a counter only once and
 * only if greater than the last one: the server uses max(unix seconds, previous + 1).
 *   LIVE       varint seconds   every sample sent right away (0 stops)
 *   ANTITHEFT  varint seconds   alarms paused, e.g. at the mechanic (0 resumes)
 *   LOCATE     -                a position sent as soon as possible
 * COMMAND_RESULT plaintext (tracker -> server): u32 counter of the command
 * frame + u8 RESULT
 *
 * Firmware update over the air, on the same connection:
 *   FW_OFFER (server -> tracker, sealed like a COMMAND, downlink counter): u32 size,
 *            32 B SHA-256 of the image, u8 length + version
 *   FW_REQUEST (tracker -> server, plain): u8 header, u32 offset, u16 length (a window)
 *   FW_CHUNK (server -> tracker, plain): u8 header, u32 offset, data (FW_CHUNK_SIZE at most)
 *   FW_RESULT (tracker -> server, plain): u8 header, u8 FW_STATUS
 * Requests and chunks aren't sealed: the image has no secrets (the device key stays in the
 * NVS of the tracker) and the tracker installs it only if the SHA-256 of the authenticated
 * offer matches.
 *   UPDATE_CHECK (tracker -> server): no plaintext. Sent once a day by the builds with
 *            AUTO_UPDATE: the server answers with a FW_OFFER of the newest image of the
 *            variant, if the owner allows the automatic updates
 *
 * EXTRA plaintext (tracker -> server): a JSON object in UTF-8, data of the vehicle read by
 * the tracker from another board; timestamp = time of the reading. The server stores it
 * as it is (no processing), new fields need no change of the protocol.
 */
import { DIRECTION_DOWNLINK, DIRECTION_UPLINK, TAG_LENGTH, buildNonce, open, seal } from "../crypto/device.ts";

export const VERSION = 2;

export const TYPE = { HELLO: 1, TELEMETRY: 2, ACK: 3, COMMAND: 4, COMMAND_RESULT: 5, FW_OFFER: 6, FW_REQUEST: 7, FW_CHUNK: 8, FW_RESULT: 9, UPDATE_CHECK: 10, EXTRA: 11 } as const;

/** Data of a FW_CHUNK, and largest window of a FW_REQUEST */
export const FW_CHUNK_SIZE = 1024;
export const FW_MAX_WINDOW = 32 * 1024;

/** FW_RESULT of the tracker */
export const FW_STATUS = { INSTALLED: 0, BAD_HASH: 1, WRITE_FAILED: 2, TOO_BIG: 3, TIMEOUT: 4 } as const;

export const COMMAND = { LIVE: 1, ANTITHEFT: 2, LOCATE: 3 } as const;

export const RESULT = { OK: 0, UNKNOWN_COMMAND: 1, EXPIRED: 2 } as const;

export const STATUS = { MOVING: 0, ENGINE_OFF: 1, HEARTBEAT: 2, ALARM: 3 } as const;

// Why a point was recorded besides the regular tracking
export const EVENT = { MOTION: 0x01, TILT: 0x02, POWER_LOST: 0x04, LOW_BATTERY: 0x08 } as const;

const FLAG_STATUS_MASK = 0x03;
const FLAG_ALTITUDE = 0x04;
const FLAG_PRESSURE = 0x08;
const FLAG_TEMPERATURE = 0x10;
const FLAG_SPEED = 0x20;
const FLAG_SATELLITES = 0x40;
const FLAG_EXTENDED = 0x80;

const EXT_SIGNAL = 0x01;
const EXT_VOLTAGE = 0x02;
const EXT_EVENTS = 0x04;
const EXT_CELL = 0x08;
const EXT_STALE = 0x10;
const EXT_KNOWN = EXT_SIGNAL | EXT_VOLTAGE | EXT_EVENTS | EXT_CELL | EXT_STALE;

const COORDINATE_SCALE = 1e5;
const PRESSURE_SCALE = 10;
const TEMPERATURE_SCALE = 10;
const VOLTAGE_SCALE = 100;

export const MAX_FRAME_SIZE = 1024;

export class ProtocolError extends Error {}

export interface Cell {
	mcc: number;
	mnc: number;
	area: number;
	id: number;
}

export interface Point {
	time: Date;
	lat: number;
	lon: number;
	altitude: number | null;
	pressure: number | null;
	temperature: number | null;
	speed: number | null;
	satellites: number | null;
	signal: number | null;
	voltage: number | null;
	events: number;
	cell: Cell | null;
	stale: boolean;
	status: number;
}

export interface DeviceInfo {
	manufacturer: string;
	model: string;
	revision: string;
	firmware: string;
}

export interface Command {
	id: number;
	seconds?: number;
}

export interface Frame {
	type: number;
	imei?: string;
	deviceId?: number;
	counter: number;
	timestamp: number;
	aad: Buffer;
	ciphertext: Buffer;
	tag: Buffer;
}

class Reader {
	readonly #buffer: Buffer;
	offset: number;
	readonly #end: number;

	constructor (buffer: Buffer, offset = 0, end = buffer.length) {
		this.#buffer = buffer;
		this.offset = offset;
		this.#end = end;
	}

	get remaining (): number {
		return this.#end - this.offset;
	}

	#ensure (size: number): void {
		if (this.remaining < size) throw new ProtocolError("Truncated frame");
	}

	u8 (): number {
		this.#ensure(1);
		return this.#buffer[this.offset++]!;
	}

	u32 (): number {
		this.#ensure(4);
		const value = this.#buffer.readUInt32LE(this.offset);
		this.offset += 4;
		return value;
	}

	u64 (): bigint {
		this.#ensure(8);
		const value = this.#buffer.readBigUInt64LE(this.offset);
		this.offset += 8;
		return value;
	}

	varint (): number {
		let result = 0;
		for (let shift = 0; shift < 35; shift += 7) {
			const byte = this.u8();
			result += (byte & 0x7f) * 2 ** shift;
			if ((byte & 0x80) === 0) return result;
		}
		throw new ProtocolError("Invalid varint");
	}

	zigzag (): number {
		const value = this.varint();
		return value % 2 === 0 ? value / 2 : -(value + 1) / 2;
	}

	bytes (size: number): Buffer {
		this.#ensure(size);
		const value = Buffer.from(this.#buffer.subarray(this.offset, this.offset + size));
		this.offset += size;
		return value;
	}

	string (): string {
		const size = this.u8();
		this.#ensure(size);
		const value = this.#buffer.subarray(this.offset, this.offset + size).toString("utf8");
		this.offset += size;
		return value;
	}
}

class Writer {
	readonly #bytes: number[] = [];

	u8 (value: number): void {
		this.#bytes.push(value & 0xff);
	}

	u32 (value: number): void {
		for (let i = 0; i < 4; i++) this.u8(Math.floor(value / 2 ** (8 * i)));
	}

	u64 (value: bigint | string): void {
		let big = BigInt(value);
		for (let i = 0; i < 8; i++) {
			this.u8(Number(big & 0xffn));
			big >>= 8n;
		}
	}

	varint (value: number): void {
		let v = value;
		while (v >= 0x80) {
			this.u8((v % 0x80) | 0x80);
			v = Math.floor(v / 0x80);
		}
		this.u8(v);
	}

	zigzag (value: number): void {
		this.varint(value >= 0 ? value * 2 : -value * 2 - 1);
	}

	bytes (value: Buffer): void {
		for (const byte of value) this.u8(byte);
	}

	string (value: string): void {
		const encoded = Buffer.from(value, "utf8").subarray(0, 255);
		this.u8(encoded.length);
		for (const byte of encoded) this.u8(byte);
	}

	toBuffer (): Buffer {
		return Buffer.from(this.#bytes);
	}
}

/** Parses the clear part of a frame, the payload stays encrypted */
export function parseFrame (buffer: Buffer): Frame {
	if (buffer.length > MAX_FRAME_SIZE) throw new ProtocolError("Invalid frame size");
	if (buffer.length < 1 + 8 + TAG_LENGTH) throw new ProtocolError("Truncated frame");

	const reader = new Reader(buffer, 0, buffer.length - TAG_LENGTH);
	const header = reader.u8();
	const version = header >> 4;
	const type = header & 0x0f;
	if (version !== VERSION) throw new ProtocolError(`Unsupported protocol version ${version}`);

	let imei: string | undefined;
	let deviceId: number | undefined;
	if (type === TYPE.HELLO) {
		imei = reader.u64().toString().padStart(15, "0");
	} else if (type === TYPE.TELEMETRY || type === TYPE.COMMAND_RESULT || type === TYPE.UPDATE_CHECK || type === TYPE.EXTRA) {
		deviceId = reader.varint();
	} else if (type !== TYPE.ACK && type !== TYPE.COMMAND && type !== TYPE.FW_OFFER) {
		throw new ProtocolError(`Unknown frame type ${type}`);
	}

	const counter = reader.u32();
	const timestamp = reader.u32();
	return {
		type,
		imei,
		deviceId,
		counter,
		timestamp,
		aad: buffer.subarray(0, reader.offset),
		ciphertext: buffer.subarray(reader.offset, buffer.length - TAG_LENGTH),
		tag: buffer.subarray(buffer.length - TAG_LENGTH)
	};
}

export function decryptFrame (frame: Frame, key: Buffer, direction = DIRECTION_UPLINK): Buffer | null {
	return open(key, buildNonce(frame.counter, frame.timestamp, direction), frame.aad, frame.ciphertext, frame.tag);
}

function sealFrame (key: Buffer, header: Writer, counter: number, timestamp: number, plaintext: Buffer, direction: number): Buffer {
	header.u32(counter);
	header.u32(timestamp);
	const aad = header.toBuffer();
	const { ciphertext, tag } = seal(key, buildNonce(counter, timestamp, direction), aad, plaintext);
	return Buffer.concat([aad, ciphertext, tag]);
}

function headerOf (type: number): Writer {
	const header = new Writer();
	header.u8((VERSION << 4) | type);
	return header;
}

export function decodeHello (plaintext: Buffer): DeviceInfo {
	const reader = new Reader(plaintext);
	return { manufacturer: reader.string(), model: reader.string(), revision: reader.string(), firmware: reader.string() };
}

/** Used by tests and simulator, the firmware has its own implementation */
export function encodeHello (key: Buffer, imei: string, counter: number, timestamp: number, info: DeviceInfo): Buffer {
	const header = headerOf(TYPE.HELLO);
	header.u64(imei);

	const body = new Writer();
	body.string(info.manufacturer);
	body.string(info.model);
	body.string(info.revision);
	body.string(info.firmware);
	return sealFrame(key, header, counter, timestamp, body.toBuffer(), DIRECTION_UPLINK);
}

export function decodeTelemetry (plaintext: Buffer, baseTimestamp: number): Point[] {
	const reader = new Reader(plaintext);
	const points: Point[] = [];
	let timestamp = baseTimestamp, lat = 0, lon = 0, altitude = 0, pressure = 0, temperature = 0, voltage = 0;

	while (reader.remaining > 0) {
		const flags = reader.u8();
		timestamp += reader.varint();
		lat += reader.zigzag();
		lon += reader.zigzag();

		const point: Point = {
			time: new Date(timestamp * 1000),
			lat: lat / COORDINATE_SCALE,
			lon: lon / COORDINATE_SCALE,
			altitude: null,
			pressure: null,
			temperature: null,
			speed: null,
			satellites: null,
			signal: null,
			voltage: null,
			events: 0,
			cell: null,
			stale: false,
			status: flags & FLAG_STATUS_MASK
		};

		if (flags & FLAG_ALTITUDE) {
			altitude += reader.zigzag();
			point.altitude = altitude;
		}
		if (flags & FLAG_PRESSURE) {
			pressure += reader.zigzag();
			point.pressure = pressure / PRESSURE_SCALE;
		}
		if (flags & FLAG_TEMPERATURE) {
			temperature += reader.zigzag();
			point.temperature = temperature / TEMPERATURE_SCALE;
		}
		if (flags & FLAG_SPEED) point.speed = reader.varint();
		if (flags & FLAG_SATELLITES) point.satellites = reader.u8();
		if (flags & FLAG_EXTENDED) {
			const ext = reader.u8();
			// Unknown fields have an unknown size: the rest of the frame can't be decoded
			if (ext & ~EXT_KNOWN) throw new ProtocolError(`Unknown extended flags ${ext}`);
			if (ext & EXT_SIGNAL) point.signal = -reader.u8();
			if (ext & EXT_VOLTAGE) {
				voltage += reader.zigzag();
				point.voltage = voltage / VOLTAGE_SCALE;
			}
			if (ext & EXT_EVENTS) point.events = reader.u8();
			if (ext & EXT_CELL) point.cell = { mcc: reader.varint(), mnc: reader.varint(), area: reader.varint(), id: reader.varint() };
			point.stale = (ext & EXT_STALE) !== 0;
		}
		points.push(point);
	}
	return points;
}

/** Used by tests and simulator, the firmware has its own implementation */
export function encodeTelemetry (key: Buffer, deviceId: number, counter: number, points: Point[]): Buffer {
	if (points.length === 0) throw new ProtocolError("No points");
	const baseTimestamp = Math.floor(points[0]!.time.getTime() / 1000);

	const header = headerOf(TYPE.TELEMETRY);
	header.varint(deviceId);

	const body = new Writer();
	let timestamp = baseTimestamp, lat = 0, lon = 0, altitude = 0, pressure = 0, temperature = 0, voltage = 0;

	for (const point of points) {
		let ext = 0;
		if (point.signal != null) ext |= EXT_SIGNAL;
		if (point.voltage != null) ext |= EXT_VOLTAGE;
		if (point.events) ext |= EXT_EVENTS;
		if (point.cell) ext |= EXT_CELL;
		if (point.stale) ext |= EXT_STALE;

		let flags = point.status & FLAG_STATUS_MASK;
		if (point.altitude != null) flags |= FLAG_ALTITUDE;
		if (point.pressure != null) flags |= FLAG_PRESSURE;
		if (point.temperature != null) flags |= FLAG_TEMPERATURE;
		if (point.speed != null) flags |= FLAG_SPEED;
		if (point.satellites != null) flags |= FLAG_SATELLITES;
		if (ext) flags |= FLAG_EXTENDED;
		body.u8(flags);

		const pointTimestamp = Math.floor(point.time.getTime() / 1000);
		body.varint(pointTimestamp - timestamp);
		timestamp = pointTimestamp;

		const pointLat = Math.round(point.lat * COORDINATE_SCALE);
		const pointLon = Math.round(point.lon * COORDINATE_SCALE);
		body.zigzag(pointLat - lat);
		body.zigzag(pointLon - lon);
		lat = pointLat;
		lon = pointLon;

		if (point.altitude != null) {
			const value = Math.round(point.altitude);
			body.zigzag(value - altitude);
			altitude = value;
		}
		if (point.pressure != null) {
			const value = Math.round(point.pressure * PRESSURE_SCALE);
			body.zigzag(value - pressure);
			pressure = value;
		}
		if (point.temperature != null) {
			const value = Math.round(point.temperature * TEMPERATURE_SCALE);
			body.zigzag(value - temperature);
			temperature = value;
		}
		if (point.speed != null) body.varint(Math.round(point.speed));
		if (point.satellites != null) body.u8(point.satellites);
		if (ext) {
			body.u8(ext);
			if (point.signal != null) body.u8(-point.signal);
			if (point.voltage != null) {
				const value = Math.round(point.voltage * VOLTAGE_SCALE);
				body.zigzag(value - voltage);
				voltage = value;
			}
			if (point.events) body.u8(point.events);
			if (point.cell) {
				body.varint(point.cell.mcc);
				body.varint(point.cell.mnc);
				body.varint(point.cell.area);
				body.varint(point.cell.id);
			}
		}
	}
	return sealFrame(key, header, counter, baseTimestamp, body.toBuffer(), DIRECTION_UPLINK);
}

export function encodeAck (key: Buffer, deviceId: number, counter: number, timestamp: number): Buffer {
	const body = new Writer();
	body.varint(deviceId);
	return sealFrame(key, headerOf(TYPE.ACK), counter, timestamp, body.toBuffer(), DIRECTION_DOWNLINK);
}

export function decodeAck (plaintext: Buffer): number {
	return new Reader(plaintext).varint();
}

export function encodeCommand (key: Buffer, counter: number, timestamp: number, commands: Command[]): Buffer {
	const body = new Writer();
	for (const command of commands) {
		body.u8(command.id);
		if (command.id === COMMAND.LIVE || command.id === COMMAND.ANTITHEFT) {
			body.varint(Math.max(0, Math.round(command.seconds ?? 0)));
		} else if (command.id !== COMMAND.LOCATE) {
			throw new ProtocolError(`Unknown command ${command.id}`);
		}
	}
	return sealFrame(key, headerOf(TYPE.COMMAND), counter, timestamp, body.toBuffer(), DIRECTION_DOWNLINK);
}

/** Used by tests and simulator, the firmware has its own implementation */
export function decodeCommand (plaintext: Buffer): Command[] {
	const reader = new Reader(plaintext);
	const commands: Command[] = [];
	while (reader.remaining > 0) {
		const id = reader.u8();
		if (id === COMMAND.LIVE || id === COMMAND.ANTITHEFT) {
			commands.push({ id, seconds: reader.varint() });
		} else if (id === COMMAND.LOCATE) {
			commands.push({ id });
		} else {
			throw new ProtocolError(`Unknown command ${id}`);
		}
	}
	return commands;
}

/** Used by tests and simulator, the firmware has its own implementation */
export function encodeCommandResult (key: Buffer, deviceId: number, counter: number, timestamp: number,
	commandCounter: number, result: number): Buffer {
	const header = headerOf(TYPE.COMMAND_RESULT);
	header.varint(deviceId);
	const body = new Writer();
	body.u32(commandCounter);
	body.u8(result);
	return sealFrame(key, header, counter, timestamp, body.toBuffer(), DIRECTION_UPLINK);
}

export function decodeCommandResult (plaintext: Buffer): { counter: number; result: number } {
	const reader = new Reader(plaintext);
	return { counter: reader.u32(), result: reader.u8() };
}

/** Used by tests and simulator, the firmware has its own implementation */
export function encodeUpdateCheck (key: Buffer, deviceId: number, counter: number, timestamp: number): Buffer {
	const header = headerOf(TYPE.UPDATE_CHECK);
	header.varint(deviceId);
	return sealFrame(key, header, counter, timestamp, Buffer.alloc(0), DIRECTION_UPLINK);
}

/** Used by tests and simulator, the firmware has its own implementation */
export function encodeExtra (key: Buffer, deviceId: number, counter: number, timestamp: number, json: string): Buffer {
	const header = headerOf(TYPE.EXTRA);
	header.varint(deviceId);
	return sealFrame(key, header, counter, timestamp, Buffer.from(json, "utf8"), DIRECTION_UPLINK);
}

/** The JSON text of an EXTRA frame, parsed: anything but valid UTF-8 JSON is an error */
export function decodeExtra (plaintext: Buffer): unknown {
	try {
		return JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(plaintext));
	} catch {
		throw new ProtocolError("Invalid extra data");
	}
}

export interface FirmwareOffer {
	size: number;
	sha256: Buffer;
	version: string;
}

export function encodeFirmwareOffer (key: Buffer, counter: number, timestamp: number, offer: FirmwareOffer): Buffer {
	const body = new Writer();
	body.u32(offer.size);
	body.bytes(offer.sha256);
	body.string(offer.version);
	return sealFrame(key, headerOf(TYPE.FW_OFFER), counter, timestamp, body.toBuffer(), DIRECTION_DOWNLINK);
}

/** Used by tests and simulator, the firmware has its own implementation */
export function decodeFirmwareOffer (plaintext: Buffer): FirmwareOffer {
	const reader = new Reader(plaintext);
	return { size: reader.u32(), sha256: reader.bytes(32), version: reader.string() };
}

/** Type of a plain frame (FW_REQUEST, FW_RESULT), null for the sealed ones */
export function plainType (buffer: Buffer): number | null {
	if (buffer.length < 1 || buffer[0]! >> 4 !== VERSION) return null;
	const type = buffer[0]! & 0x0f;
	return type === TYPE.FW_REQUEST || type === TYPE.FW_RESULT ? type : null;
}

export function decodeFirmwareRequest (buffer: Buffer): { offset: number; length: number } {
	if (buffer.length !== 7) throw new ProtocolError("Invalid FW_REQUEST");
	return { offset: buffer.readUInt32LE(1), length: buffer.readUInt16LE(5) };
}

/** Used by tests and simulator */
export function encodeFirmwareRequest (offset: number, length: number): Buffer {
	const buffer = Buffer.alloc(7);
	buffer[0] = (VERSION << 4) | TYPE.FW_REQUEST;
	buffer.writeUInt32LE(offset, 1);
	buffer.writeUInt16LE(length, 5);
	return buffer;
}

export function encodeFirmwareChunk (offset: number, data: Buffer): Buffer {
	const header = Buffer.alloc(5);
	header[0] = (VERSION << 4) | TYPE.FW_CHUNK;
	header.writeUInt32LE(offset, 1);
	return Buffer.concat([header, data]);
}

export function decodeFirmwareResult (buffer: Buffer): number {
	if (buffer.length !== 2) throw new ProtocolError("Invalid FW_RESULT");
	return buffer[1]!;
}

export { DIRECTION_DOWNLINK, DIRECTION_UPLINK };
