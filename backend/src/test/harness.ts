import assert from "node:assert/strict";
import { Secret, TOTP } from "otpauth";
import pino from "pino";
import { WebSocket } from "ws";
import type { FastifyBaseLogger } from "fastify";
import { loadConfig } from "../config.ts";
import { connect } from "../db.ts";
import { hashToken, randomToken } from "../auth/secrets.ts";
import { DIRECTION_DOWNLINK, RESULT, STATUS, TYPE, decodeAck, decodeCommand, decodeFirmwareOffer, decryptFrame, encodeCommandResult,
	encodeHello, encodeTelemetry, parseFrame } from "../protocol/protocol.ts";
import type { Command, FirmwareOffer, Point } from "../protocol/protocol.ts";
import { startServer } from "../server.ts";
import type { Server } from "../server.ts";
import type { GatewayTimeouts } from "../tracker/gateway.ts";

// Shared helpers of the end to end tests: a backend on a clean TimescaleDB, e.g.
//   docker run -d --rm --name ct-test-db -p 55432:5432 -e POSTGRES_PASSWORD=test -e POSTGRES_DB=ct_test timescale/timescaledb:2.24.0-pg17
//   TEST_DATABASE_URL=postgres://postgres:test@localhost:55432/ct_test npm test
// Every test file empties the database at the start (the files run one at a time).

export const DATABASE_URL = process.env.TEST_DATABASE_URL;
export const SKIP = !DATABASE_URL && "TEST_DATABASE_URL not set";
export const MASTER_KEY = "integration-test-master-key-0123456789";
export const PUBLIC_URL = "http://localhost:4999";
export const PASSWORD = "una password lunga e sicura";

export const totp = (secret: string, offset = 0) =>
	new TOTP({ algorithm: "SHA1", digits: 6, period: 30, secret: Secret.fromBase32(secret) }).generate({ timestamp: Date.now() + offset });

export interface Response {
	status: number;
	body: any;
	headers: Headers;
}

export interface ApiOptions {
	token?: string;
	body?: unknown;
	headers?: Record<string, string>;
}

export interface User {
	id: number;
	token: string;
	secret: string;
	recoveryCodes: string[];
}

export async function resetDatabase (): Promise<void> {
	const sql = connect(DATABASE_URL!);
	await sql.unsafe("DROP SCHEMA IF EXISTS public CASCADE; CREATE SCHEMA public;");
	await sql.end();
}

export class Harness {
	server!: Server;
	base!: string;

	static async start (env: Record<string, string> = {}, reset = true, trackerTimeouts: Partial<GatewayTimeouts> = {}): Promise<Harness> {
		const harness = new Harness();
		if (reset) await resetDatabase();
		const config = loadConfig({
			DATABASE_URL,
			CRYPTO_MASTER_KEY: MASTER_KEY,
			PUBLIC_URL,
			HOST: "127.0.0.1",
			PORT: "0",
			NODE_ENV: "test",
			LOG_LEVEL: "silent",
			RATE_LIMIT: "100000",
			AUTH_RATE_LIMIT: "100000",
			// No public data from the internet in the tests
			FUEL_PRICES_URL: "",
			...env
		});
		harness.server = await startServer(config, pino({ level: process.env.TEST_LOG_LEVEL ?? "silent" }) as FastifyBaseLogger, trackerTimeouts);
		harness.base = harness.server.address.replace("[::1]", "localhost");
		return harness;
	}

	get sql () {
		return this.server.ctx.sql;
	}

	async close (): Promise<void> {
		await this.server?.close();
	}

	async api (method: string, path: string, options: ApiOptions = {}): Promise<Response> {
		const response = await fetch(this.base + path, {
			method,
			headers: {
				...(options.body !== undefined ? { "content-type": "application/json" } : {}),
				...(options.token ? { authorization: `Bearer ${options.token}` } : {}),
				...options.headers
			},
			body: options.body !== undefined ? JSON.stringify(options.body) : undefined
		});
		const text = await response.text();
		let body: unknown = text;
		try {
			body = text ? JSON.parse(text) : null;
		} catch {
			// Not JSON (web app files)
		}
		return { status: response.status, body, headers: response.headers };
	}

	async invite (email: string, name: string, isAdmin = false): Promise<string> {
		const token = randomToken();
		await this.sql`
			INSERT INTO invites (token_hash, email, name, is_admin, expires_at)
			VALUES (${hashToken(token)}, ${email}, ${name}, ${isAdmin}, now() + interval '1 hour')`;
		return token;
	}

	/** Invite accepted and TOTP enrolled: full app session */
	async onboard (email: string, name: string, isAdmin = false): Promise<User> {
		const token = await this.invite(email, name, isAdmin);
		const accepted = await this.api("POST", `/api/auth/invites/${token}`, { body: { password: PASSWORD, client: "app" } });
		assert.equal(accepted.status, 200, JSON.stringify(accepted.body));
		const enroll = await this.api("POST", "/api/auth/enroll/start", { token: accepted.body.token });
		const confirmed = await this.api("POST", "/api/auth/enroll/confirm", { token: accepted.body.token, body: { code: totp(enroll.body.secret) } });
		assert.equal(confirmed.status, 200, JSON.stringify(confirmed.body));
		const [row] = await this.sql<{ id: number }[]>`SELECT id FROM users WHERE email = ${email}`;
		return { id: row!.id, token: confirmed.body.token, secret: enroll.body.secret, recoveryCodes: confirmed.body.recoveryCodes };
	}

	/** Extra full session of a user, without waiting for a new TOTP step */
	async session (userId: number, client: "app" | "web" = "app", authenticatedAgoMs = 0): Promise<string> {
		const token = randomToken();
		await this.sql`
			INSERT INTO sessions (token_hash, user_id, client, stage, expires_at, authenticated_at)
			VALUES (${hashToken(token)}, ${userId}, ${client}, 'full', now() + interval '1 hour', ${new Date(Date.now() - authenticatedAgoMs)})`;
		return token;
	}

	/** Device owned by a user, claimed with its pairing code */
	async claim (user: User, imei: string, name = "Panda"): Promise<number> {
		const code = this.server.ctx.secrets.pairingCode(imei);
		const claim = await this.api("POST", "/api/devices/claim", { token: user.token, body: { imei, code, name, color: "#FF5722" } });
		assert.equal(claim.status, 200, JSON.stringify(claim.body));
		return claim.body.id;
	}

	/** a asks b with the friend code of b, b accepts */
	async befriend (a: User, b: User): Promise<void> {
		const code = (await this.api("GET", "/api/friends", { token: b.token })).body.code;
		const asked = await this.api("POST", "/api/friends", { token: a.token, body: { code } });
		assert.equal(asked.status, 200, JSON.stringify(asked.body));
		const accepted = await this.api("POST", `/api/friends/requests/${a.id}/accept`, { token: b.token });
		assert.equal(accepted.status, 200, JSON.stringify(accepted.body));
	}

	/** Realtime channel of the app with the received messages */
	async live (token: string): Promise<Live> {
		const socket = new WebSocket(this.base.replace("http", "ws") + "/api/live", { headers: { authorization: `Bearer ${token}` } });
		const live = new Live(socket);
		await new Promise((resolve, reject) => {
			socket.once("open", resolve);
			socket.once("error", reject);
		});
		await waitFor(() => live.messages.some(message => message.type === "hello"));
		return live;
	}
}

export class Live {
	readonly socket: WebSocket;
	readonly messages: { type: string; [key: string]: any }[] = [];
	closed: { code: number; reason: string } | null = null;

	constructor (socket: WebSocket) {
		this.socket = socket;
		socket.on("message", data => this.messages.push(JSON.parse(data.toString())));
		socket.on("close", (code, reason) => { this.closed = { code, reason: reason.toString() }; });
	}

	send (message: unknown): void {
		this.socket.send(typeof message === "string" ? message : JSON.stringify(message));
	}

	of (type: string) {
		return this.messages.filter(message => message.type === type);
	}

	close (): void {
		this.socket.close();
	}
}

export async function waitFor (condition: () => boolean | Promise<boolean>, timeout = 5000): Promise<void> {
	const end = Date.now() + timeout;
	while (Date.now() < end) {
		if (await condition()) return;
		await sleep(20);
	}
	throw new Error("Timeout waiting for condition");
}

export const sleep = (ms: number) => new Promise(resolve => setTimeout(resolve, ms));

// --- Tracker simulated with the protocol of the firmware

export function point (time: Date, lat: number, lon: number, extra: Partial<Point> = {}): Point {
	return {
		time, lat, lon, altitude: 120, pressure: 1013, temperature: 21.5, speed: 40, satellites: 9, signal: -80,
		voltage: 12.6, events: 0, cell: null, stale: false, status: STATUS.MOVING, ...extra
	};
}

/** Tracker on the WebSocket of the gateway, frames encoded like the firmware */
export class Tracker {
	readonly socket: WebSocket;
	readonly key: Buffer;
	readonly imei: string;
	readonly received: Buffer[] = [];
	counter = Math.floor(Date.now() / 1000);
	deviceId = 0;
	closed: number | null = null;

	private constructor (socket: WebSocket, key: Buffer, imei: string) {
		this.socket = socket;
		this.key = key;
		this.imei = imei;
		socket.on("message", (data: Buffer) => this.received.push(data));
		socket.on("close", code => { this.closed = code; });
	}

	static url (h: Harness): string {
		return h.base.replace("http", "ws") + "/tracker";
	}

	/** WebSocket open, nothing sent yet: hello() authenticates it */
	static async connect (h: Harness, imei: string, key = h.server.ctx.secrets.deviceKey(imei)): Promise<Tracker> {
		const socket = new WebSocket(Tracker.url(h));
		socket.binaryType = "nodebuffer";
		const tracker = new Tracker(socket, key, imei);
		await new Promise<void>((resolve, reject) => {
			socket.once("open", () => resolve());
			socket.once("error", reject);
		});
		return tracker;
	}

	#frames (type: number): Buffer[] {
		return this.received.filter(data => (data[0]! & 0x0F) === type);
	}

	sendHello (firmware = "3.0.0"): void {
		this.raw(encodeHello(this.key, this.imei, this.counter++, Math.floor(Date.now() / 1000), {
			manufacturer: "SIMCOM", model: "A7670E", revision: "1", firmware
		}));
	}

	/** HELLO -> ACK with the device id */
	async hello (firmware = "3.0.0"): Promise<number> {
		const before = this.#frames(TYPE.ACK).length;
		this.sendHello(firmware);
		await waitFor(() => this.#frames(TYPE.ACK).length > before);
		this.deviceId = decodeAck(decryptFrame(parseFrame(this.#frames(TYPE.ACK).at(-1)!), this.key, DIRECTION_DOWNLINK)!);
		return this.deviceId;
	}

	raw (data: Buffer | string): void {
		this.socket.send(data);
	}

	send (points: Point[], deviceId = this.deviceId): void {
		this.raw(encodeTelemetry(this.key, deviceId, this.counter++, points));
	}

	commands (): { counter: number; commands: Command[] }[] {
		return this.#frames(TYPE.COMMAND).map(data => {
			const frame = parseFrame(data);
			return { counter: frame.counter, commands: decodeCommand(decryptFrame(frame, this.key, DIRECTION_DOWNLINK)!) };
		});
	}

	offers (): FirmwareOffer[] {
		return this.#frames(TYPE.FW_OFFER).map(data => decodeFirmwareOffer(decryptFrame(parseFrame(data), this.key, DIRECTION_DOWNLINK)!));
	}

	/** FW_CHUNK frames: offset and data */
	chunks (): { offset: number; data: Buffer }[] {
		return this.#frames(TYPE.FW_CHUNK).map(data => ({ offset: data.readUInt32LE(1), data: data.subarray(5) }));
	}

	result (commandCounter: number, result: number = RESULT.OK): void {
		this.raw(encodeCommandResult(this.key, this.deviceId, this.counter++, Math.floor(Date.now() / 1000), commandCounter, result));
	}

	async close (): Promise<void> {
		if (this.closed !== null) return;
		const done = new Promise(resolve => this.socket.once("close", resolve));
		this.socket.close();
		await done;
	}
}
