import type { FastifyBaseLogger } from "fastify";
import type { WebSocket } from "ws";
import { z } from "zod";
import type { Sql } from "../db.ts";
import type { AuthUser } from "../http/session.ts";
import { deviceAccess, isActive, visibleDevices } from "./access.ts";
import type { Access } from "./access.ts";
import type { Commands } from "./commands.ts";

// Realtime channel of the app (WebSocket /api/live, JSON messages). Every connection
// receives the events of the devices its user can see: everything for the owner, the
// position only for the viewers. The map of a device opened by its owner ("watch") asks
// the tracker for the live tracking while the map stays open; viewers get the normal
// updates and don't spend the data plan of the owner.
//
// Client -> server: { type: "watch" | "unwatch", deviceId } | { type: "ping" }
// Server -> client: { type: "hello" | "pong" | "position" | "device" | "command" | "notification" | "registered" | "access" | "friends", ... }

const PING_INTERVAL = 30e3;
const LIVE_RENEW_INTERVAL = 4 * 60e3;
// Per connection: burst of 20 messages, then 2 per second
const MESSAGE_BURST = 20;
const MESSAGE_RATE = 2;
export const MAX_CONNECTIONS_PER_USER = 10;
const MAX_MESSAGE_LENGTH = 200;

const clientMessage = z.discriminatedUnion("type", [
	z.strictObject({ type: z.enum(["watch", "unwatch"]), deviceId: z.number().int().positive().max(2 ** 31 - 1) }),
	z.strictObject({ type: z.literal("ping") })
]);

interface Connection {
	socket: WebSocket;
	user: AuthUser;
	devices: Map<number, Access>;
	watching: Set<number>;
	alive: boolean;
	tokens: number;
	refilledAt: number;
}

export class Hub {
	readonly #sql: Sql;
	readonly #log: FastifyBaseLogger;
	readonly #commands: Commands;
	readonly #connections = new Set<Connection>();
	readonly #timers: NodeJS.Timeout[] = [];

	constructor (sql: Sql, log: FastifyBaseLogger, commands: Commands) {
		this.#sql = sql;
		this.#log = log;
		this.#commands = commands;

		this.#timers.push(setInterval(() => this.#ping(), PING_INTERVAL));
		this.#timers.push(setInterval(() => void this.renewLive(), LIVE_RENEW_INTERVAL));
		// Commands and their results are for the owner only
		commands.onChange((deviceId, command) => this.toDevice(deviceId, { type: "command", deviceId, command }));
	}

	get connections (): number {
		return this.#connections.size;
	}

	async attach (socket: WebSocket, user: AuthUser): Promise<void> {
		const own = [...this.#connections].filter(connection => connection.user.id === user.id);
		if (own.length >= MAX_CONNECTIONS_PER_USER) {
			socket.close(4009, "too many connections");
			return;
		}
		const connection: Connection = {
			socket, user, devices: await visibleDevices(this.#sql, user.id), watching: new Set(), alive: true,
			tokens: MESSAGE_BURST, refilledAt: Date.now()
		};
		this.#connections.add(connection);

		socket.on("pong", () => { connection.alive = true; });
		socket.on("close", () => this.#connections.delete(connection));
		socket.on("message", (data, binary) => {
			if (!this.#allow(connection)) {
				socket.close(4008, "rate limit");
				return;
			}
			if (binary) return;
			void this.#onMessage(connection, data.toString()).catch(error => this.#log.warn({ err: error }, "Realtime message failed"));
		});
		this.#send(connection, { type: "hello", user: user.id });
	}

	/** Token bucket of the messages of a connection */
	#allow (connection: Connection): boolean {
		const now = Date.now();
		connection.tokens = Math.min(MESSAGE_BURST, connection.tokens + (now - connection.refilledAt) / 1000 * MESSAGE_RATE);
		connection.refilledAt = now;
		if (connection.tokens < 1) return false;
		connection.tokens -= 1;
		return true;
	}

	async #onMessage (connection: Connection, text: string): Promise<void> {
		if (text.length > MAX_MESSAGE_LENGTH) return;
		let json: unknown;
		try {
			json = JSON.parse(text);
		} catch {
			return;
		}
		const parsed = clientMessage.safeParse(json);
		if (!parsed.success) return;
		const message = parsed.data;

		if (message.type === "ping") {
			this.#send(connection, { type: "pong" });
		} else if (message.type === "watch") {
			const access = await deviceAccess(this.#sql, connection.user.id, message.deviceId);
			if (!access) return;
			connection.devices.set(message.deviceId, access);
			connection.watching.add(message.deviceId);
			if (access.role === "owner" && access.kind === "tracker") await this.#commands.ensureLive(message.deviceId);
		} else {
			connection.watching.delete(message.deviceId);
		}
	}

	#send (connection: Connection, message: unknown): void {
		if (connection.socket.readyState === connection.socket.OPEN) connection.socket.send(JSON.stringify(message));
	}

	#ping (): void {
		for (const connection of this.#connections) {
			if (!connection.alive) {
				connection.socket.terminate();
				this.#connections.delete(connection);
				continue;
			}
			connection.alive = false;
			connection.socket.ping();
		}
	}

	/** Renews the live tracking of the devices watched by their owners */
	async renewLive (): Promise<void> {
		const watched = new Set<number>();
		for (const connection of this.#connections) {
			for (const id of connection.watching) {
				const access = connection.devices.get(id);
				if (access?.role === "owner" && access.kind === "tracker") watched.add(id);
			}
		}
		for (const id of watched) {
			await this.#commands.ensureLive(id).catch(error => this.#log.warn({ err: error, deviceId: id }, "Live renewal failed"));
		}
	}

	/**
	 * Event of a device: `message` for the owner, `viewerMessage` for the viewers (nothing
	 * when undefined). An expired share is dropped here, at the first event after the end.
	 */
	toDevice (deviceId: number, message: unknown, viewerMessage?: unknown): void {
		const now = Date.now();
		for (const connection of this.#connections) {
			const access = connection.devices.get(deviceId);
			if (!access) continue;
			if (!isActive(access, now)) {
				connection.devices.delete(deviceId);
				connection.watching.delete(deviceId);
				this.#send(connection, { type: "access", deviceId, revoked: true });
				continue;
			}
			if (access.role === "owner") this.#send(connection, message);
			else if (viewerMessage !== undefined) this.#send(connection, viewerMessage);
		}
	}

	toUser (userId: number, message: unknown): void {
		for (const connection of this.#connections) if (connection.user.id === userId) this.#send(connection, message);
	}

	/** After a change of the devices of a user (claim, share, revocation, expiry) */
	/** Vehicles whose tracker was installed, moved or removed: their users reload them */
	async devicesChanged (ids: number[]): Promise<void> {
		const users = await this.#sql<{ user_id: number }[]>`SELECT DISTINCT user_id FROM device_users WHERE device_id = ANY (${ids})`;
		for (const { user_id: userId } of users) {
			await this.refreshUser(userId);
			for (const connection of this.#connections) {
				if (connection.user.id !== userId) continue;
				for (const id of ids) if (connection.devices.has(id)) this.#send(connection, { type: "access", deviceId: id, revoked: false });
			}
		}
	}

	async refreshUser (userId: number): Promise<void> {
		const own = [...this.#connections].filter(connection => connection.user.id === userId);
		if (own.length === 0) return;
		const devices = await visibleDevices(this.#sql, userId);
		for (const connection of own) {
			for (const id of connection.devices.keys()) {
				if (!devices.has(id)) {
					connection.watching.delete(id);
					this.#send(connection, { type: "access", deviceId: id, revoked: true });
				}
			}
			for (const id of devices.keys()) {
				if (!connection.devices.has(id)) this.#send(connection, { type: "access", deviceId: id, revoked: false });
			}
			connection.devices = new Map(devices);
		}
	}

	/** Closes the connections of a user (logout everywhere, disabled account) */
	disconnectUser (userId: number): void {
		for (const connection of this.#connections) if (connection.user.id === userId) connection.socket.close(4001, "session ended");
	}

	close (): void {
		for (const timer of this.#timers) clearInterval(timer);
		for (const connection of this.#connections) connection.socket.close(1001, "server shutdown");
	}
}
