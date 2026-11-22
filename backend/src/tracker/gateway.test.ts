import assert from "node:assert/strict";
import crypto from "node:crypto";
import fs from "node:fs";
import http from "node:http";
import os from "node:os";
import path from "node:path";
import zlib from "node:zlib";
import { after, before, describe, test } from "node:test";
import { compressTree } from "../../scripts/compress-web.ts";
import { COMMAND, EVENT, RESULT, STATUS, encodeCommandResult, encodeHello } from "../protocol/protocol.ts";
import { Harness, SKIP, Tracker, point, sleep, waitFor } from "../test/harness.ts";
import type { User } from "../test/harness.ts";

const IMEI = "860000000000037";

interface Recorded {
	url: string;
	body: string;
	headers: http.IncomingHttpHeaders;
}

/** Local HTTP server answering with `handler`, recording the requests */
async function mockServer (handler: (request: Recorded) => { status: number; body?: unknown }) {
	const requests: Recorded[] = [];
	const server = http.createServer((request, response) => {
		let body = "";
		request.on("data", chunk => { body += chunk; });
		request.on("end", () => {
			const recorded = { url: request.url ?? "", body, headers: request.headers };
			requests.push(recorded);
			const answer = handler(recorded);
			response.writeHead(answer.status, { "content-type": "application/json" });
			response.end(answer.body === undefined ? "" : JSON.stringify(answer.body));
		});
	});
	await new Promise<void>(resolve => server.listen(0, "127.0.0.1", resolve));
	const { port } = server.address() as { port: number };
	return { url: `http://127.0.0.1:${port}`, requests, close: () => new Promise(resolve => server.close(resolve)) };
}

describe("trackers, analysis, push, web app", { skip: SKIP }, () => {
	let h: Harness;
	let user: User;
	let deviceId: number;
	let fcm: Awaited<ReturnType<typeof mockServer>>;
	let cells: Awaited<ReturnType<typeof mockServer>>;
	let web: string;
	let pushStatus = 200;

	before(async () => {
		fcm = await mockServer(request => {
			if (request.url === "/token") return { status: 200, body: { access_token: "access" } };
			return { status: pushStatus, body: {} };
		});
		cells = await mockServer(request => {
			const cell = JSON.parse(request.body).cellTowers[0];
			if (cell.cellId === 123456789) return { status: 200, body: { location: { lat: 45.46, lng: 9.19 }, accuracy: 812.4 } };
			if (cell.cellId === 500) return { status: 404 };
			return { status: 500 };
		});
		const account = path.join(os.tmpdir(), `ct-fcm-${process.pid}.json`);
		const { privateKey } = crypto.generateKeyPairSync("rsa", { modulusLength: 2048 });
		fs.writeFileSync(account, JSON.stringify({
			project_id: "car-tracking", client_email: "push@car-tracking.iam.gserviceaccount.com",
			private_key: privateKey.export({ type: "pkcs8", format: "pem" })
		}));
		web = fs.mkdtempSync(path.join(os.tmpdir(), "ct-web-"));
		fs.writeFileSync(path.join(web, "index.html"), "<!doctype html><title>Car Tracking</title>");
		fs.writeFileSync(path.join(web, "main.dart.js"), "console.log('car tracking');\n".repeat(200));
		fs.writeFileSync(path.join(web, "tiny.js"), "1");
		assert.equal(compressTree(web), 1);

		h = await Harness.start({
			FCM_SERVICE_ACCOUNT_FILE: account,
			FCM_TOKEN_URL: `${fcm.url}/token`,
			FCM_API_URL: fcm.url,
			CELL_GEOLOCATION_URL: `${cells.url}/geolocate`,
			WEB_ROOT: web,
			ANDROID_CERT_SHA256: "AA:BB"
		});
		user = await h.onboard("driver@example.com", "Driver");
		deviceId = await h.claim(user, IMEI);
	});
	after(async () => {
		await h?.close();
		await fcm?.close();
		await cells?.close();
		if (web) fs.rmSync(web, { recursive: true, force: true });
	});

	test("authentication: the first frame must be a valid HELLO", async () => {
		const key = h.server.ctx.secrets.deviceKey(IMEI);
		const info = { manufacturer: "SIMCOM", model: "A7670E", revision: "1", firmware: "3.0.0" };
		const firstFrames: (Buffer | string)[] = [
			encodeHello(Buffer.alloc(32), IMEI, 1, 0, info),  // wrong key
			encodeHello(key, "860000000000045", 1, 0, info),  // key of another IMEI
			encodeCommandResult(key, deviceId, 1, 0, 1, RESULT.OK),  // not a HELLO
			Buffer.from("garbage"),
			Buffer.alloc(2000, 0x21),  // too big
			"text"
		];
		for (const data of firstFrames) {
			const tracker = await Tracker.connect(h, IMEI);
			tracker.raw(data);
			await waitFor(() => tracker.closed !== null);
			assert.equal(tracker.closed, typeof data === "string" ? 1003 : 4001);
		}

		// No HELLO in time, silent after the HELLO: closed
		const quick = await Harness.start({}, false, { helloMs: 100, idleMs: 300 });
		try {
			const mute = await Tracker.connect(quick, IMEI);
			await waitFor(() => mute.closed === 4001);
			// Another IMEI: the next test expects the first registration of IMEI
			const idle = await Tracker.connect(quick, "860000000000052");
			await idle.hello();
			// Pings keep it open
			for (let i = 0; i < 4; i++) {
				idle.socket.ping();
				await sleep(150);
			}
			assert.equal(idle.closed, null);
			await waitFor(() => idle.closed !== null);
		} finally {
			await quick.close();
		}
	});

	test("HELLO, telemetry, replay, realtime, push and commands", async () => {
		await h.api("POST", "/api/account/push-tokens", { token: user.token, body: { token: "valid-device-token-0123456789" } });
		await h.api("POST", "/api/account/push-tokens", { token: user.token, body: { token: "stale-device-token-0123456789" } });
		await h.api("PATCH", "/api/account", { token: user.token, body: { locale: "it" } });

		const live = await h.live(user.token);
		live.send({ type: "watch", deviceId });
		const tracker = await Tracker.connect(h, IMEI);
		assert.equal(await tracker.hello(), deviceId);
		await waitFor(() => live.of("registered").length === 1);

		// Drive: 30 points, 10 s apart, a tilt alarm, a cell, a stale point with only the cell
		pushStatus = 404;
		const start = Date.now() - 400e3;
		const points = Array.from({ length: 30 }, (_, i) => point(new Date(start + i * 10e3), 45.4642 + i * 0.0008, 9.19 + i * 0.0006, {
			speed: 40 + i,
			satellites: 5 + (i % 8),
			signal: -70 - i,
			events: i === 5 ? EVENT.TILT : 0,
			cell: i === 0 ? { mcc: 222, mnc: 1, area: 16001, id: 123456789 } : i === 1 ? { mcc: 222, mnc: 1, area: 16001, id: 500 } : i === 2 ? { mcc: 222, mnc: 1, area: 1, id: 7 } : null,
			status: i === 29 ? STATUS.ENGINE_OFF : STATUS.MOVING
		}));
		points.push(point(new Date(start + 305e3), 0, 0, { stale: true, cell: { mcc: 222, mnc: 1, area: 16001, id: 123456789 } }));
		// Invalid: in the future, outside the coordinates, 0,0 without cell
		points.push(point(new Date(Date.now() + 86400e3), 45, 9), point(new Date(start + 306e3), 95, 9), point(new Date(start + 307e3), 0, 0));
		for (let i = 0; i < points.length; i += 6) tracker.send(points.slice(i, i + 6));
		await waitFor(async () => (await h.sql<{ n: number }[]>`SELECT count(*)::int AS n FROM positions`)[0]!.n === 31);
		await waitFor(() => live.of("position").length === 31);
		await waitFor(() => live.of("notification").length === 1);
		assert.equal(live.of("notification")[0]!.notification.kind, "tilt");
		// Push in the language of the user, the invalid token deleted
		await waitFor(() => fcm.requests.filter(request => request.url.endsWith("messages:send")).length === 2);
		const sent = JSON.parse(fcm.requests.find(request => request.url.endsWith("messages:send"))!.body);
		assert.equal(sent.message.notification.title, "Auto sollevata o inclinata");
		assert.match(sent.message.notification.body, /Panda/);
		assert.equal(sent.message.android.priority, "high");
		assert.equal(fcm.requests.find(request => request.url.endsWith("messages:send"))!.headers.authorization, "Bearer access");
		await waitFor(async () => (await h.sql`SELECT 1 FROM push_tokens`).length === 0);
		// Cells: known, unknown (cached as such), service error (not cached)
		await waitFor(async () => (await h.sql`SELECT 1 FROM cells`).length === 2);
		const [cell] = await h.sql<{ lat: number; accuracy: number }[]>`SELECT lat, accuracy FROM cells WHERE cell_id = 123456789`;
		assert.equal(cell!.accuracy, 812);
		const cellRequests = cells.requests.length;
		tracker.send([point(new Date(start + 308e3), 45.47, 9.2, { cell: { mcc: 222, mnc: 1, area: 16001, id: 123456789 } })]);
		await waitFor(async () => (await h.sql<{ n: number }[]>`SELECT count(*)::int AS n FROM positions`)[0]!.n === 32);
		await sleep(100);
		assert.equal(cells.requests.length, cellRequests);

		// Replayed frame and frame with the id of another device: nothing stored
		tracker.send(points.slice(0, 6));
		await sleep(300);
		assert.equal((await h.sql<{ n: number }[]>`SELECT count(*)::int AS n FROM positions`)[0]!.n, 32);

		// The open map asked for live tracking: delivered right after the ACK
		await waitFor(() => tracker.commands().length === 1);
		const frame = tracker.commands()[0]!;
		assert.equal(frame.commands[0]!.id, COMMAND.LIVE);
		assert.ok(frame.commands[0]!.seconds! > 590 && frame.commands[0]!.seconds! <= 600);
		tracker.result(frame.counter);
		await waitFor(async () => (await h.sql`SELECT result FROM commands WHERE counter = ${frame.counter}`)[0]?.result === 0);
		await waitFor(() => live.of("command").length > 0);
		const detail = await h.api("GET", `/api/devices/${deviceId}`, { token: user.token });
		assert.ok(detail.body.liveUntil > Date.now() / 1000);
		assert.equal(detail.body.connected, true);

		// Commands while connected: sent immediately, the anti-theft pause too
		pushStatus = 200;
		await h.api("POST", `/api/devices/${deviceId}/commands`, { token: user.token, body: { type: "antitheft", seconds: 3600 } });
		await waitFor(() => tracker.commands().length === 2);
		const pause = tracker.commands()[1]!;
		assert.deepEqual(pause.commands.map(command => command.id), [COMMAND.ANTITHEFT]);
		tracker.result(pause.counter, RESULT.EXPIRED);
		await waitFor(async () => (await h.sql`SELECT result FROM commands WHERE counter = ${pause.counter}`)[0]?.result === RESULT.EXPIRED);
		// Result for an unknown counter: ignored
		tracker.result(12345);
		await sleep(100);

		// A new connection replaces the old one
		const second = await Tracker.connect(h, IMEI);
		await second.hello();
		await waitFor(() => tracker.closed === 4000);
		assert.equal(h.server.gateway.connectedTrackers, 1);
		await second.close();
		await waitFor(async () => !(await h.api("GET", `/api/devices/${deviceId}`, { token: user.token })).body.connected);
		live.close();

		// Malformed or forged frames are dropped, other frame types end the connection
		const rogue = await Tracker.connect(h, IMEI);
		await rogue.hello();
		rogue.raw(Buffer.from("garbage"));
		rogue.raw(Buffer.alloc(40, 0x25));
		rogue.raw(Buffer.alloc(1500, 0x22));
		rogue.raw(encodeCommandResult(Buffer.alloc(32), rogue.deviceId, 1, 0, 1, RESULT.OK));
		await sleep(200);
		assert.equal(rogue.closed, null);
		rogue.sendHello();
		await waitFor(() => rogue.closed === 1008);
		assert.equal((await h.sql<{ n: number }[]>`SELECT count(*)::int AS n FROM positions`)[0]!.n, 32);
	});

	test("history and analysis of the owner", async () => {
		const range = `from=${new Date(Date.now() - 3600e3).toISOString()}&to=${new Date(Date.now() + 60e3).toISOString()}`;
		const positions = await h.api("GET", `/api/devices/${deviceId}/positions?${range}`, { token: user.token });
		assert.equal(positions.body.positions.length, 32);
		assert.equal(positions.body.truncated, false);
		assert.equal(positions.body.positions[0].cell_id, 123456789);
		const stale = positions.body.positions.find((item: { stale: boolean }) => item.stale);
		assert.equal(stale.lat, null);
		assert.equal(stale.cell_lat, 45.46);

		const stats = await h.api("GET", `/api/devices/${deviceId}/stats?${range}`, { token: user.token });
		assert.equal(stats.body.bucket, "2 minutes");
		assert.equal(stats.body.series.reduce((sum: number, row: { points: number }) => sum + row.points, 0), 32);
		assert.ok(stats.body.series.reduce((sum: number, row: { meters: number }) => sum + row.meters, 0) > 2500);

		const trips = await h.api("GET", `/api/devices/${deviceId}/trips?${range}`, { token: user.token });
		assert.ok(trips.body.trips.length >= 1);
		assert.ok(trips.body.totals.distanceKm > 2.5, String(trips.body.totals.distanceKm));

		const distribution = await h.api("GET", `/api/devices/${deviceId}/distribution?${range}`, { token: user.token });
		assert.equal(distribution.body.quality.total, 32);
		assert.ok(distribution.body.signal.length > 1);

		const coverage = await h.api("GET", `/api/devices/${deviceId}/coverage?${range}`, { token: user.token });
		assert.ok(coverage.body.cells.length > 10);

		const traffic = await h.api("GET", `/api/devices/${deviceId}/traffic?${range}`, { token: user.token });
		assert.equal(traffic.body.budgetBytes, 200 * 1024 * 1024);
		assert.ok(traffic.body.daily[0].uplink > 0 && traffic.body.daily[0].downlink > 0);

		// Long periods use larger buckets
		const week = `from=${new Date(Date.now() - 30 * 86400e3).toISOString()}&to=${new Date().toISOString()}`;
		assert.equal((await h.api("GET", `/api/devices/${deviceId}/stats?${week}`, { token: user.token })).status, 200);

		const notifications = await h.api("GET", "/api/notifications", { token: user.token });
		assert.equal(notifications.body.notifications[0].kind, "tilt");
		assert.equal(notifications.body.notifications[0].data.device, "Panda");
	});

	test("public endpoints, headers, web app files", async () => {
		const config = await h.api("GET", "/api/config");
		assert.equal(config.body.simBudgetMb, 200);
		assert.equal(config.body.pushEnabled, true);
		assert.equal(config.body.cellGeolocation, true);
		const links = await h.api("GET", "/.well-known/assetlinks.json");
		assert.equal(links.body[0].target.package_name, "com.cartracking.app");
		const health = await h.api("GET", "/healthz");
		assert.equal(health.status, 200);
		assert.ok(health.headers.get("content-security-policy"));
		assert.equal(health.headers.get("referrer-policy"), "strict-origin-when-cross-origin");
		assert.equal(health.headers.get("x-content-type-options"), "nosniff");

		// Unauthenticated API calls never reach the handlers
		for (const route of ["/api/devices", "/api/account", "/api/admin/users", "/api/notifications"]) {
			const response = await h.api("GET", route);
			assert.equal(response.status, 401, route);
		}
		assert.equal((await h.api("GET", "/api/nothing", { token: user.token })).status, 404);
		// Malformed and oversized bodies
		const malformed = await fetch(`${h.base}/api/auth/login`, { method: "POST", headers: { "content-type": "application/json" }, body: "{" });
		assert.equal(malformed.status, 400);
		const huge = await fetch(`${h.base}/api/auth/login`, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ email: "x".repeat(70000) }) });
		assert.equal(huge.status, 413);
		const poisoned = await fetch(`${h.base}/api/auth/login`, { method: "POST", headers: { "content-type": "application/json" }, body: '{"__proto__":{"admin":true}}' });
		assert.equal(poisoned.status, 400);

		// Web app: precompressed copy when accepted, plain otherwise, SPA fallback
		const brotli = await fetch(`${h.base}/main.dart.js`, { headers: { "accept-encoding": "br" } });
		assert.equal(brotli.headers.get("content-encoding"), "br");
		assert.equal(brotli.headers.get("cache-control"), "no-cache");
		assert.match(await brotli.text(), /car tracking/);
		const plain = await new Promise<{ encoding: string | undefined; body: Buffer }>((resolve, reject) => {
			http.get(`${h.base}/main.dart.js`, { headers: { "accept-encoding": "identity" } }, response => {
				const chunks: Buffer[] = [];
				response.on("data", chunk => chunks.push(chunk));
				response.on("end", () => resolve({ encoding: response.headers["content-encoding"], body: Buffer.concat(chunks) }));
			}).on("error", reject);
		});
		assert.equal(plain.encoding, undefined);
		assert.equal(plain.body.toString(), zlib.gunzipSync(fs.readFileSync(path.join(web, "main.dart.js.gz"))).toString());
		const index = await h.api("GET", "/");
		assert.match(index.body, /Car Tracking/);
		const deepLink = await h.api("GET", "/device/1");
		assert.match(deepLink.body, /Car Tracking/);
	});

	test("rate limits per client address", async () => {
		const strict = await Harness.start({ RATE_LIMIT: "5", AUTH_RATE_LIMIT: "2" }, false);
		try {
			for (let i = 0; i < 2; i++) await strict.api("POST", "/api/auth/login", { body: { email: "a@example.com", password: "x" } });
			const limited = await strict.api("POST", "/api/auth/login", { body: { email: "a@example.com", password: "x" } });
			assert.equal(limited.status, 429);
			assert.equal(limited.body.error, "rate_limited");
			let last = 0;
			for (let i = 0; i < 6; i++) last = (await strict.api("GET", "/api/devices", { token: "random-token-random-token" })).status;
			assert.equal(last, 429);
		} finally {
			await strict.close();
		}
	});

	test("trackers banned after repeated failures", async () => {
		for (let i = 0; i < 6; i++) {
			const forged = await Tracker.connect(h, IMEI, Buffer.alloc(32));
			forged.sendHello();
			await waitFor(() => forged.closed !== null);
		}
		// Banned (5 failures in the first test): even the right key is refused at once
		const tracker = await Tracker.connect(h, IMEI);
		await waitFor(() => tracker.closed === 1008);
	});
});
