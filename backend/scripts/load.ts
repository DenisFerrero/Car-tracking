import { randomInt } from "node:crypto";
import { parseArgs } from "node:util";
import { WebSocket } from "ws";
import { connect } from "../src/db.ts";
import { hashToken, randomToken } from "../src/auth/secrets.ts";
import { DeviceSecrets } from "../src/crypto/device.ts";
import { DIRECTION_DOWNLINK, STATUS, TYPE, decodeAck, decryptFrame, encodeHello, encodeTelemetry, parseFrame } from "../src/protocol/protocol.ts";
import type { Point } from "../src/protocol/protocol.ts";

// Load test of a backend on a TEST installation: users and trackers of the test with days of
// history, then for some minutes trackers connected that send their points and users of the
// app that open the usual screens. Prints the times of every API (median, 95th and 99th
// percentile), the errors, and the slowest queries of pg_stat_statements.
//   npm run load -- --trackers 50 --users 10 --days 60 --minutes 5
//   npm run load -- --cleanup          removes users, trackers and points of the test
// It writes into DATABASE_URL (users load-N@load.invalid, IMEIs 990000000000NNN) and resets
// the statistics of the queries: never on the server in use. The backend needs a high
// RATE_LIMIT (all the users of the test come from one address); the trackers connect at
// 25 a minute (the limit of the gateway per address).

const { values: args } = parseArgs({
	options: {
		url: { type: "string", default: "http://localhost:4000" },
		trackers: { type: "string", default: "50" },
		users: { type: "string", default: "10" },
		days: { type: "string", default: "60" },
		minutes: { type: "string", default: "5" },
		// Seconds between two batches of a tracker (the firmware: 60 while driving)
		batch: { type: "string", default: "60" },
		// Seconds between two screens of a user
		think: { type: "string", default: "2" },
		"skip-seed": { type: "boolean", default: false },
		cleanup: { type: "boolean", default: false },
		"allow-remote": { type: "boolean", default: false }
	}
});

const EMAIL = "@load.invalid";
const IMEI_PREFIX = "990000000";
const DAY_MS = 86400e3;
const url = new URL(args.url);
const trackers = Number(args.trackers);
const users = Math.min(Number(args.users), trackers);
const days = Number(args.days);
const minutes = Number(args.minutes);
const batchSeconds = Number(args.batch);
const thinkSeconds = Number(args.think);

if (!["localhost", "127.0.0.1", "[::1]"].includes(url.hostname) && !args["allow-remote"]) {
	console.error(`${url.host} is not local: a load test writes users, trackers and points. Add --allow-remote for a test server.`);
	process.exit(1);
}
const masterKey = process.env.CRYPTO_MASTER_KEY ?? "";
if (!process.env.DATABASE_URL || masterKey.length < 32) {
	console.error("DATABASE_URL and CRYPTO_MASTER_KEY (the same of the backend) are needed");
	process.exit(1);
}
const sql = connect(process.env.DATABASE_URL);
const secrets = new DeviceSecrets(masterKey);
const imeiOf = (index: number) => `${IMEI_PREFIX}${String(index).padStart(6, "0")}`;

async function cleanup (): Promise<void> {
	const devices = await sql<{ id: number }[]>`SELECT id FROM devices WHERE imei LIKE ${`${IMEI_PREFIX}%`}`;
	const ids = devices.map(device => device.id);
	if (ids.length) {
		for (const table of ["positions", "traffic", "device_extra", "daily_stats"]) {
			await sql`DELETE FROM ${sql(table)} WHERE device_id IN ${sql(ids)}`;
		}
		await sql`DELETE FROM devices WHERE id IN ${sql(ids)}`;
	}
	const removed = await sql`DELETE FROM users WHERE email LIKE ${`%${EMAIL}`}`;
	console.log(`Removed ${ids.length} trackers and ${removed.count} users of the load test`);
}

if (args.cleanup) {
	await cleanup();
	await sql.end();
	process.exit(0);
}

// --- Users, trackers and history

interface Tracker {
	id: number;
	imei: string;
	/** Start of the drive of the live phase */
	lat: number;
	lon: number;
}

interface User {
	id: number;
	token: string;
	devices: number[];
}

async function seed (): Promise<{ users: User[]; trackers: Tracker[] }> {
	const result: User[] = [];
	for (let n = 0; n < users; n++) {
		const [user] = await sql<{ id: number }[]>`
			INSERT INTO users (email, name, password_hash, locale) VALUES (${`load-${n}${EMAIL}`}, ${`Load ${n}`}, '-', 'it')
			ON CONFLICT (email) DO UPDATE SET name = excluded.name RETURNING id`;
		const token = randomToken();
		await sql`
			INSERT INTO sessions (token_hash, user_id, client, stage, user_agent, expires_at)
			VALUES (${hashToken(token)}, ${user!.id}, 'app', 'full', 'load test', now() + interval '1 day')`;
		result.push({ id: user!.id, token, devices: [] });
	}
	const list: Tracker[] = [];
	for (let n = 0; n < trackers; n++) {
		const imei = imeiOf(n);
		const [device] = await sql<{ id: number }[]>`
			INSERT INTO devices (imei, name, kind, registered_at, last_seen_at, fuel_type)
			VALUES (${imei}, ${`Load ${n}`}, 'tracker', now(), now(), 'petrol')
			ON CONFLICT (imei) DO UPDATE SET name = excluded.name RETURNING id`;
		const owner = result[n % result.length]!;
		// One owner, the one of this run: a run with other numbers of users moves the trackers
		await sql`DELETE FROM device_users WHERE device_id = ${device!.id} AND user_id <> ${owner.id}`;
		await sql`
			INSERT INTO device_users (device_id, user_id, role) VALUES (${device!.id}, ${owner.id}, 'owner')
			ON CONFLICT DO NOTHING`;
		await sql`
			INSERT INTO vehicle_rates (device_id, kind, valid_from, value) VALUES
				(${device!.id}, 'consumption', '2020-01-01', 6.5), (${device!.id}, 'price', '2020-01-01', 1.85), (${device!.id}, 'wear', '2020-01-01', 0.12)
			ON CONFLICT DO NOTHING`;
		owner.devices.push(device!.id);
		list.push({ id: device!.id, imei, lat: 45 + randomInt(1000) / 1000, lon: 9 + randomInt(1000) / 1000 });
	}
	return { users: result, trackers: list };
}

/**
 * History of every tracker: two drives a day (8:00 and 18:00, 45 minutes, a point every
 * 10 s) and a heartbeat every hour, like the firmware; old chunks compressed like the
 * policy does. About 600 points a day per tracker.
 */
async function history (list: Tracker[]): Promise<void> {
	const started = Date.now();
	for (const [index, tracker] of list.entries()) {
		await sql`
			INSERT INTO positions (time, device_id, lat, lon, altitude, speed, voltage, satellites, signal, temperature, pressure, status)
			SELECT t, ${tracker.id}, ${tracker.lat} + 0.0004 * s, ${tracker.lon} + 0.0003 * s + 0.002 * sin(s / 20.0),
				120 + (s % 40), 30 + (s % 70), 13.9, 6 + (s % 8), -70 - (s % 35), 18 + (s % 10), 1010 + (s % 8), ${STATUS.MOVING}
			FROM generate_series(1, ${days}) d, generate_series(0, 1) trip, generate_series(0, 269) s,
				LATERAL (SELECT date_trunc('day', now()) - make_interval(days => d) + make_interval(hours => 8 + 10 * trip, secs => s * 10) AS t) x
			ON CONFLICT DO NOTHING`;
		await sql`
			INSERT INTO positions (time, device_id, lat, lon, voltage, satellites, signal, status)
			SELECT date_trunc('day', now()) - make_interval(days => d) + make_interval(hours => h), ${tracker.id},
				${tracker.lat}, ${tracker.lon}, 12.5, 7, -80, ${STATUS.HEARTBEAT}
			FROM generate_series(1, ${days}) d, generate_series(0, 23) h
			ON CONFLICT DO NOTHING`;
		if ((index + 1) % 10 === 0 || index === list.length - 1) {
			process.stdout.write(`\r  history: ${index + 1}/${list.length} trackers`);
		}
	}
	const [compressed] = await sql<{ count: number }[]>`
		SELECT count(*)::int AS count FROM (SELECT compress_chunk(c, true) FROM show_chunks('positions', older_than => interval '14 days') c) x`;
	console.log(`, ${compressed!.count} chunks compressed (${Math.round((Date.now() - started) / 1000)} s)`);
}

/** Daily summaries like the hourly job (statistics, dashboards, odometer) */
async function summaries (list: Tracker[]): Promise<void> {
	const { computeDay, storeDay } = await import("../src/services/daily.ts");
	const timeZone = process.env.TIMEZONE ?? "Europe/Rome";
	const started = Date.now();
	for (const [index, tracker] of list.entries()) {
		for (let d = days; d >= 1; d--) {
			const day = new Date(Date.now() - d * DAY_MS).toISOString().slice(0, 10);
			await storeDay(sql, tracker.id, await computeDay(sql, timeZone, { id: tracker.id, kind: "tracker" }, day));
		}
		process.stdout.write(`\r  daily summaries: ${index + 1}/${list.length} trackers`);
	}
	console.log(` (${Math.round((Date.now() - started) / 1000)} s)`);
}

// --- Measures

const times = new Map<string, number[]>();
const errors = new Map<string, number>();
// Answers that are not ok, by route and status: what the errors are
const failures = new Map<string, number>();
let trackerFrames = 0;
let trackerPoints = 0;
let trackerErrors = 0;

function measure (name: string, ms: number, ok: boolean): void {
	times.set(name, [...times.get(name) ?? [], ms]);
	if (!ok) errors.set(name, (errors.get(name) ?? 0) + 1);
}

const percentile = (sorted: number[], p: number) => sorted[Math.min(sorted.length - 1, Math.floor(sorted.length * p))] ?? 0;

// --- Trackers connected

// The gateway accepts 30 connections a minute per address: the trackers of the test (one
// address) connect a bit below that
const CONNECTIONS_PER_MINUTE = 25;

async function runTracker (tracker: Tracker, index: number, until: number): Promise<void> {
	// The ones whose turn comes after the end of the run don't connect
	const delay = index * 60e3 / CONNECTIONS_PER_MINUTE;
	if (Date.now() + delay >= until) return;
	await new Promise(resolve => setTimeout(resolve, delay));
	const key = secrets.deviceKey(tracker.imei);
	let counter = Math.floor(Date.now() / 1000);
	const socket = new WebSocket(new URL("/tracker", url.href.replace(/^http/, "ws")));
	socket.binaryType = "nodebuffer";
	await new Promise((resolve, reject) => {
		socket.once("open", resolve);
		socket.once("error", reject);
	});
	const ack = new Promise<number>((resolve, reject) => {
		socket.on("message", (payload: Buffer) => {
			const frame = parseFrame(payload);
			const plaintext = decryptFrame(frame, key, DIRECTION_DOWNLINK);
			if (plaintext && frame.type === TYPE.ACK) resolve(decodeAck(plaintext));
		});
		socket.once("close", () => reject(new Error("closed before the ACK")));
	});
	const helloAt = performance.now();
	socket.send(encodeHello(key, tracker.imei, counter++, Math.floor(Date.now() / 1000), { manufacturer: "Load", model: "Node", revision: "1", firmware: "load" }));
	const deviceId = await ack;
	measure("tracker HELLO → ACK", performance.now() - helloAt, true);
	let step = 0;
	// Spread over the batch interval: not all the trackers at the same moment
	await new Promise(resolve => setTimeout(resolve, randomInt(batchSeconds * 1000)));
	while (Date.now() < until && socket.readyState === WebSocket.OPEN) {
		const base = step;
		step += 6;
		const points: Point[] = Array.from({ length: 6 }, (_, i) => ({
			time: new Date(Date.now() - (5 - i) * 10e3),
			lat: tracker.lat + (base + i) * 0.0004,
			lon: tracker.lon + (base + i) * 0.0003,
			altitude: 120,
			pressure: 1012,
			temperature: 20,
			speed: 50,
			satellites: 9,
			signal: -75,
			voltage: 13.9,
			events: 0,
			cell: null,
			stale: false,
			status: STATUS.MOVING
		}));
		socket.send(encodeTelemetry(key, deviceId, counter++, points));
		trackerFrames++;
		trackerPoints += points.length;
		await new Promise(resolve => setTimeout(resolve, Math.max(0, Math.min(batchSeconds * 1000, until - Date.now()))));
	}
	socket.close(1000);
}

// --- Users of the app

type Screen = { name: string; weight: number; run: (user: User, device: number) => Promise<Response> };

/** Query of a period until now */
const last = (days: number) => `from=${new Date(Date.now() - days * DAY_MS).toISOString()}&to=${new Date().toISOString()}`;

const SCREENS: Screen[] = [
	{ name: "GET /api/devices", weight: 6, run: user => api(user, "GET", "/api/devices") },
	{ name: "GET /api/devices/:id", weight: 3, run: (user, id) => api(user, "GET", `/api/devices/${id}`) },
	{ name: "GET /api/notifications", weight: 2, run: user => api(user, "GET", "/api/notifications") },
	{ name: "GET /api/devices/:id/positions (2 h)", weight: 3, run: (user, id) => api(user, "GET", `/api/devices/${id}/positions?${last(1 / 12)}`) },
	{ name: "GET /api/devices/:id/positions (1 day)", weight: 2, run: (user, id) => api(user, "GET", `/api/devices/${id}/positions?${last(1)}`) },
	{ name: "GET /api/devices/:id/trips (7 days)", weight: 2, run: (user, id) => api(user, "GET", `/api/devices/${id}/trips?${last(7)}`) },
	{ name: "GET /api/devices/:id/stats (7 days)", weight: 2, run: (user, id) => api(user, "GET", `/api/devices/${id}/stats?${last(7)}`) },
	{ name: "GET /api/devices/:id/stats (30 days)", weight: 1, run: (user, id) => api(user, "GET", `/api/devices/${id}/stats?${last(30)}`) },
	{ name: "GET /api/devices/:id/coverage (30 days)", weight: 1, run: (user, id) => api(user, "GET", `/api/devices/${id}/coverage?${last(30)}`) },
	{ name: "GET /api/devices/:id/trends", weight: 1, run: (user, id) => api(user, "GET", `/api/devices/${id}/trends`) },
	{ name: "GET /api/devices/:id/maintenance", weight: 1, run: (user, id) => api(user, "GET", `/api/devices/${id}/maintenance`) },
	{ name: "GET /api/devices/:id/refuels", weight: 1, run: (user, id) => api(user, "GET", `/api/devices/${id}/refuels`) },
	{ name: "GET /api/devices/:id/parking", weight: 1, run: (user, id) => api(user, "GET", `/api/devices/${id}/parking`) },
	{ name: "GET /api/devices/:id/vehicle", weight: 1, run: (user, id) => api(user, "GET", `/api/devices/${id}/vehicle`) },
	{
		name: "GET /api/summary/:month (last month)", weight: 1, run: user => {
			const month = new Date();
			month.setUTCDate(1);
			month.setUTCMonth(month.getUTCMonth() - 1);
			return api(user, "GET", `/api/summary/${month.toISOString().slice(0, 7)}`);
		}
	},
	{
		name: "POST /api/dashboards/data (30 days)", weight: 2, run: user => api(user, "POST", "/api/dashboards/data", {
			period: "30d",
			widgets: [
				{ id: "km", metric: "distance", view: "number", devices: "all" },
				{ id: "kmDays", metric: "distance", view: "bars", devices: "all" },
				{ id: "cost", metric: "cost", view: "vehicles", devices: "all" },
				{ id: "voltage", metric: "voltage", view: "line", devices: "all" },
				{ id: "status", metric: "status", view: "map", devices: "all" }
			]
		})
	}
];
const totalWeight = SCREENS.reduce((sum, screen) => sum + screen.weight, 0);

function api (user: User, method: string, path: string, body?: unknown): Promise<Response> {
	return fetch(new URL(path, url), {
		method,
		headers: { authorization: `Bearer ${user.token}`, ...(body ? { "content-type": "application/json" } : {}) },
		body: body ? JSON.stringify(body) : undefined
	});
}

async function runUser (user: User, until: number): Promise<void> {
	// The realtime channel stays open, like the app
	const live = new WebSocket(new URL("/api/live", url.href.replace(/^http/, "ws")), { headers: { authorization: `Bearer ${user.token}` } });
	live.on("error", () => measure("WS /api/live", 0, false));
	while (Date.now() < until) {
		let pick = randomInt(totalWeight);
		const screen = SCREENS.find(item => (pick -= item.weight) < 0)!;
		const device = user.devices[randomInt(user.devices.length)]!;
		const started = performance.now();
		try {
			const response = await screen.run(user, device);
			await response.arrayBuffer();
			measure(screen.name, performance.now() - started, response.ok);
			if (!response.ok) failures.set(`${screen.name} → ${response.status}`, (failures.get(`${screen.name} → ${response.status}`) ?? 0) + 1);
		} catch {
			measure(screen.name, performance.now() - started, false);
		}
		await new Promise(resolve => setTimeout(resolve, thinkSeconds * 1000 * (0.5 + Math.random())));
	}
	live.close();
}

// --- Run

console.log(`Load test on ${url.origin}: ${trackers} trackers, ${users} users, ${days} days of history, ${minutes} minutes`);
const { users: people, trackers: list } = await seed();
if (!args["skip-seed"]) {
	await history(list);
	await summaries(list);
}
await sql`SELECT pg_stat_statements_reset(0, (SELECT oid FROM pg_database WHERE datname = current_database()), 0)`.catch(() => {
	console.log("  pg_stat_statements not loaded: no statistics of the queries");
});

const started = Date.now();
const until = started + minutes * 60e3;
const ticker = setInterval(() => {
	const requests = [...times.values()].reduce((sum, list) => sum + list.length, 0);
	process.stdout.write(`\r  ${Math.round((Date.now() - started) / 1000)} s: ${requests} requests, ${trackerFrames} tracker frames`);
}, 5000);
await Promise.all([
	...list.map((tracker, index) => runTracker(tracker, index, until).catch(() => void trackerErrors++)),
	...people.map(user => runUser(user, until))
]);
clearInterval(ticker);
// Rates over the duration of the run (the last trackers close a moment later)
const seconds = Math.max(1, (until - started) / 1000);

console.log(`\n\nRequests of the app (${seconds.toFixed(0)} s)`);
console.log("route".padEnd(44) + "count".padStart(7) + "err".padStart(5) + "p50".padStart(8) + "p95".padStart(8) + "p99".padStart(8) + "max".padStart(8));
for (const [name, list] of [...times].sort((a, b) => percentile([...b[1]].sort((x, y) => x - y), 0.95) - percentile([...a[1]].sort((x, y) => x - y), 0.95))) {
	const sorted = [...list].sort((a, b) => a - b);
	const ms = (value: number) => `${Math.round(value)}`.padStart(8);
	console.log(name.slice(0, 43).padEnd(44) + `${sorted.length}`.padStart(7) + `${errors.get(name) ?? 0}`.padStart(5) +
		ms(percentile(sorted, 0.5)) + ms(percentile(sorted, 0.95)) + ms(percentile(sorted, 0.99)) + ms(sorted.at(-1)!));
}
const requests = [...times.values()].reduce((sum, list) => sum + list.length, 0);
console.log(`\n${(requests / seconds).toFixed(1)} requests/s, trackers: ${trackerFrames} frames (${trackerPoints} points, ` +
	`${(trackerPoints / seconds).toFixed(1)} points/s), ${trackerErrors} trackers failed`);
for (const [failure, count] of [...failures].sort((a, b) => b[1] - a[1])) console.log(`  ${count}× ${failure}`);

const queries = await sql<{ query: string; calls: number; mean: number; max: number; total: number }[]>`
	SELECT left(regexp_replace(query, '[[:space:]]+', ' ', 'g'), 110) AS query, calls::int, round(mean_exec_time::numeric, 1)::float AS mean,
		round(max_exec_time::numeric, 1)::float AS max, round(total_exec_time::numeric)::float AS total
	FROM pg_stat_statements WHERE dbid = (SELECT oid FROM pg_database WHERE datname = current_database())
		AND query NOT ILIKE '%pg_stat_statements%'
	ORDER BY total_exec_time DESC LIMIT 12`.catch(() => []);
if (queries.length) {
	console.log("\nQueries by total time (ms)");
	for (const item of queries) {
		console.log(`${`${item.total}`.padStart(8)} total ${`${item.calls}`.padStart(6)}× mean ${`${item.mean}`.padStart(7)} max ${`${item.max}`.padStart(7)}  ${item.query}`);
	}
}
await sql.end();
console.log("\nUsers and trackers of the test stay for other runs (--skip-seed); remove them with --cleanup");
