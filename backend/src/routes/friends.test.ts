import assert from "node:assert/strict";
import { after, before, describe, test } from "node:test";
import { runJobs } from "../server.ts";
import { Harness, sleep, waitFor } from "../test/harness.ts";
import type { User } from "../test/harness.ts";
import { MAX_FRIENDS, MAX_PENDING, newFriendCode, normalizeFriendCode } from "./friends.ts";
import { MAX_PHONES, MAX_VEHICLES } from "./phones.ts";

const IMEI = "860000000000037";
// Center of Milan and a point ~2 km away
const HOME = { lat: 45.4642, lon: 9.19 };
const AWAY = { lat: 45.4822, lon: 9.19 };

const fix = (secondsAgo: number, where: { lat: number; lon: number }, extra: Record<string, unknown> = {}) =>
	({ time: new Date(Date.now() - secondsAgo * 1000).toISOString(), lat: where.lat, lon: where.lon, accuracy: 12.4, ...extra });

describe("friend codes", () => {
	test("format and normalization", () => {
		const code = newFriendCode();
		assert.match(code, /^[0-9A-HJKMNP-TV-Z]{10}$/);
		assert.equal(normalizeFriendCode(" ctf1:abcde-fghjk "), "ABCDEFGHJK");
		assert.equal(normalizeFriendCode("o0il1 23456"), "00111" + "23456");
	});
});

describe("friends and phones", { skip: !process.env.TEST_DATABASE_URL && "TEST_DATABASE_URL not set" }, () => {
	let h: Harness;
	let anna: User;
	let bruno: User;
	let carla: User;

	before(async () => {
		h = await Harness.start();
		anna = await h.onboard("anna@example.com", "Anna");
		bruno = await h.onboard("bruno@example.com", "Bruno");
		carla = await h.onboard("carla@example.com", "Carla");
	});
	after(async () => {
		await h?.close();
	});

	test("personal code: created once, renewed on request", async () => {
		const first = await h.api("GET", "/api/friends", { token: anna.token });
		assert.equal(first.status, 200);
		assert.match(first.body.code, /^[0-9A-Z]{10}$/);
		assert.deepEqual(first.body.friends, []);
		assert.equal((await h.api("GET", "/api/friends", { token: anna.token })).body.code, first.body.code);

		const renewed = await h.api("POST", "/api/friends/code", { token: anna.token });
		assert.notEqual(renewed.body.code, first.body.code);
		assert.equal((await h.api("GET", "/api/friends", { token: anna.token })).body.code, renewed.body.code);
		// The old code no longer works
		assert.equal((await h.api("POST", "/api/friends", { token: bruno.token, body: { code: first.body.code } })).status, 404);
	});

	test("friend requests: validation, accept, decline, crossed requests, realtime", async () => {
		const annaCode = (await h.api("GET", "/api/friends", { token: anna.token })).body.code as string;
		assert.equal((await h.api("POST", "/api/friends", { token: bruno.token, body: { code: "short" } })).status, 400);
		assert.equal((await h.api("POST", "/api/friends", { token: bruno.token, body: { code: "UUUUUUUUUU" } })).status, 400);
		assert.equal((await h.api("POST", "/api/friends", { token: bruno.token, body: { code: annaCode, extra: 1 } })).status, 400);
		assert.equal((await h.api("POST", "/api/friends", { token: anna.token, body: { code: annaCode } })).body.error, "friend_self");

		const live = await h.live(anna.token);
		// As read from the QR code, lower case with a dash: a request, not a friendship yet
		const typed = `CTF1:${annaCode.slice(0, 5).toLowerCase()}-${annaCode.slice(5)}`;
		const asked = await h.api("POST", "/api/friends", { token: bruno.token, body: { code: typed } });
		assert.deepEqual(asked.body, { id: anna.id, name: "Anna", status: "requested" });
		await waitFor(() => live.of("friends").some(message => message.userId === bruno.id && message.request === true));
		// Again: still one request, no second notice
		assert.equal((await h.api("POST", "/api/friends", { token: bruno.token, body: { code: annaCode } })).body.status, "requested");
		await sleep(50);
		assert.equal(live.of("friends").length, 1);
		const pending = (await h.api("GET", "/api/friends", { token: anna.token })).body;
		assert.deepEqual(pending.friends, []);
		assert.deepEqual(pending.incoming.map((item: { id: number; name: string }) => [item.id, item.name]), [[bruno.id, "Bruno"]]);
		assert.deepEqual((await h.api("GET", "/api/friends", { token: bruno.token })).body.outgoing.map((item: { id: number }) => item.id), [anna.id]);

		// Declined, then asked again and accepted
		assert.equal((await h.api("DELETE", `/api/friends/requests/${carla.id}`, { token: anna.token })).status, 404);
		assert.equal((await h.api("DELETE", `/api/friends/requests/${bruno.id}`, { token: anna.token })).status, 200);
		assert.deepEqual((await h.api("GET", "/api/friends", { token: bruno.token })).body.outgoing, []);
		await h.api("POST", "/api/friends", { token: bruno.token, body: { code: annaCode } });
		assert.equal((await h.api("POST", `/api/friends/requests/${carla.id}/accept`, { token: anna.token })).status, 404);
		const accepted = await h.api("POST", `/api/friends/requests/${bruno.id}/accept`, { token: anna.token });
		assert.deepEqual(accepted.body, { id: bruno.id, name: "Bruno" });
		const brunoLive = await h.live(bruno.token);
		await waitFor(() => live.of("friends").some(message => message.userId === bruno.id && message.added === true));
		live.close();
		brunoLive.close();
		// Already friends
		assert.equal((await h.api("POST", "/api/friends", { token: bruno.token, body: { code: annaCode } })).body.status, "friends");
		assert.deepEqual((await h.api("GET", "/api/friends", { token: anna.token })).body.incoming, []);

		const annaFriends = (await h.api("GET", "/api/friends", { token: anna.token })).body.friends;
		assert.deepEqual(annaFriends.map((friend: { name: string }) => friend.name), ["Bruno"]);
		assert.equal(annaFriends[0].email, undefined);
		assert.deepEqual((await h.api("GET", "/api/friends", { token: bruno.token })).body.friends.map((friend: { id: number }) => friend.id), [anna.id]);
		assert.deepEqual((await h.api("GET", "/api/friends", { token: carla.token })).body.friends, []);
	});

	test("crossed requests are a friendship at once; limits", async () => {
		const carlaCode = (await h.api("GET", "/api/friends", { token: carla.token })).body.code;
		const brunoCode = (await h.api("GET", "/api/friends", { token: bruno.token })).body.code;
		assert.equal((await h.api("POST", "/api/friends", { token: bruno.token, body: { code: carlaCode } })).body.status, "requested");
		assert.equal((await h.api("POST", "/api/friends", { token: carla.token, body: { code: brunoCode } })).body.status, "friends");
		assert.equal((await h.api("DELETE", `/api/friends/${bruno.id}`, { token: carla.token })).status, 200);

		await h.sql`
			INSERT INTO users (email, name) SELECT 'filler' || n || '@example.com', 'Filler ' || n FROM generate_series(1, ${MAX_FRIENDS}) n`;
		// Too many requests sent
		await h.sql`
			INSERT INTO friend_requests (from_id, to_id) SELECT ${bruno.id}, id FROM users WHERE email LIKE 'filler%' ORDER BY id LIMIT ${MAX_PENDING}`;
		assert.equal((await h.api("POST", "/api/friends", { token: bruno.token, body: { code: carlaCode } })).body.error, "too_many_requests");
		await h.sql`DELETE FROM friend_requests WHERE from_id = ${bruno.id}`;
		// Too many friends: no request, no acceptance
		await h.sql`
			INSERT INTO friendships (user_id, friend_id) SELECT ${carla.id}, id FROM users WHERE email LIKE 'filler%'`;
		const annaCode = (await h.api("GET", "/api/friends", { token: anna.token })).body.code;
		assert.equal((await h.api("POST", "/api/friends", { token: carla.token, body: { code: annaCode } })).body.error, "too_many_friends");
		assert.equal((await h.api("POST", "/api/friends", { token: anna.token, body: { code: carlaCode } })).body.status, "requested");
		assert.equal((await h.api("POST", `/api/friends/requests/${anna.id}/accept`, { token: carla.token })).body.error, "too_many_friends");
		await h.sql`DELETE FROM users WHERE email LIKE 'filler%'`;
		await h.api("DELETE", `/api/friends/requests/${anna.id}`, { token: carla.token });
	});

	let phoneId: number;

	test("phones: creation, limit, positions, realtime and areas of friends", async () => {
		assert.equal((await h.api("POST", "/api/phones", { token: anna.token, body: { name: "" } })).status, 400);
		const created = await h.api("POST", "/api/phones", { token: anna.token, body: { name: "Pixel di Anna" } });
		assert.equal(created.status, 200);
		phoneId = created.body.id;
		let upload: string = created.body.uploadToken;
		assert.match(upload, /^[A-Za-z0-9_-]{43}$/);

		const listed = (await h.api("GET", "/api/devices", { token: anna.token })).body;
		assert.equal(listed.length, 1);
		assert.equal(listed[0].kind, "phone");
		assert.equal(listed[0].imei, "");
		assert.equal(listed[0].color, "#43A047");
		assert.equal(listed[0].connected, false);
		assert.equal(listed[0].lastPosition, null);

		// Shared with Bruno, who creates an arrival area around home
		assert.equal((await h.api("POST", `/api/devices/${phoneId}/shares`, { token: anna.token, body: { userId: carla.id, expiresAt: null } })).body.error, "not_found");
		assert.equal((await h.api("POST", `/api/devices/${phoneId}/shares`, { token: anna.token, body: { userId: bruno.id, expiresAt: null } })).status, 200);
		const area = await h.api("POST", `/api/devices/${phoneId}/geofences`, { token: bruno.token, body: { name: "Casa", lat: HOME.lat, lon: HOME.lon, radius: 300 } });
		assert.equal(area.status, 200);

		// The positions come with the upload token of the phone, not with a session
		const path = "/api/phones/positions";
		for (const body of [{}, { positions: [] }, { positions: [fix(0, HOME, { accuracy: -1 })] }, { positions: [fix(0, { lat: 91, lon: 0 })] }, { positions: [{ ...fix(0, HOME), heading: 3 }] }]) {
			assert.equal((await h.api("POST", path, { token: upload, body })).status, 400, JSON.stringify(body));
		}
		for (const token of [undefined, anna.token, "x".repeat(10), "x".repeat(43)]) {
			assert.equal((await h.api("POST", path, { token, body: { positions: [fix(0, HOME)] } })).body.error, "invalid_token");
		}
		// A new token replaces the old one, only the owner gets it
		assert.equal((await h.api("POST", `/api/phones/${phoneId}/token`, { token: bruno.token })).body.error, "owner_only");
		assert.equal((await h.api("POST", `/api/phones/${phoneId}/token`, { token: carla.token })).status, 404);
		const renewed = (await h.api("POST", `/api/phones/${phoneId}/token`, { token: anna.token })).body.uploadToken;
		assert.equal((await h.api("POST", path, { token: upload, body: { positions: [fix(0, HOME)] } })).status, 401);
		upload = renewed;
		// Too old or in the future: skipped
		assert.deepEqual((await h.api("POST", path, { token: upload, body: { positions: [fix(400 * 86400, HOME), fix(-3600, HOME)] } })).body, { accepted: 0 });

		const brunoLive = await h.live(bruno.token);
		const annaLive = await h.live(anna.token);

		// State of the phone without positions: battery and pause, seen by the friends
		const pausedUntil = new Date(Date.now() + 3600e3).toISOString();
		assert.deepEqual((await h.api("POST", path, { token: upload, body: { battery: 76, pausedUntil } })).body, { accepted: 0 });
		await waitFor(() => brunoLive.of("device").some(message => message.battery === 76 && message.pausedUntil !== null));
		for (const body of [{ battery: 101 }, { battery: 50.5 }, { pausedUntil: new Date(Date.now() + 5 * 3600e3).toISOString() }]) {
			assert.equal((await h.api("POST", path, { token: upload, body })).status, 400, JSON.stringify(body));
		}
		assert.equal((await h.api("GET", `/api/devices/${phoneId}`, { token: bruno.token })).body.pausedUntil, new Date(pausedUntil).toISOString());
		await h.api("POST", path, { token: upload, body: { pausedUntil: null } });
		const resumed = (await h.api("GET", `/api/devices/${phoneId}`, { token: bruno.token })).body;
		assert.equal(resumed.pausedUntil, null);
		assert.equal(resumed.battery, 76);

		const parked = fix(30, AWAY, { speed: 0 });
		const sent = await h.api("POST", path, { token: upload, body: { positions: [fix(60, AWAY, { speed: 30.4, altitude: 120.6 }), parked] } });
		assert.deepEqual(sent.body, { accepted: 2 });
		await waitFor(() => brunoLive.of("position").length === 2 && annaLive.of("position").length === 2);
		assert.deepEqual(Object.keys(brunoLive.of("position")[0]!.position).sort(), ["lat", "lon", "speed", "stale", "status", "time"]);
		assert.equal(annaLive.of("position")[0]!.position.accuracy, 12);
		assert.equal(annaLive.of("position")[0]!.position.status, 0);
		assert.equal(annaLive.of("position")[1]!.position.status, 1);
		// Replayed batch
		assert.deepEqual((await h.api("POST", path, { token: upload, body: { positions: [parked] } })).body, { accepted: 0 });

		// An imprecise fix at home doesn't trigger the area, a precise one does
		await h.api("POST", path, { token: upload, body: { positions: [fix(20, HOME, { accuracy: 900 })] } });
		await sleep(100);
		assert.equal(brunoLive.of("notification").length, 0);
		await h.api("POST", path, { token: upload, body: { positions: [fix(10, HOME, { accuracy: 20 })] } });
		await waitFor(() => brunoLive.of("notification").some(message => message.notification.kind === "geofence_enter"));
		assert.equal(brunoLive.of("notification")[0]!.notification.data.device, "Pixel di Anna");
		brunoLive.close();
		annaLive.close();

		const phone = (await h.api("GET", `/api/devices/${phoneId}`, { token: anna.token })).body;
		assert.equal(phone.connected, true);
		assert.equal(phone.lastPosition.accuracy, 20);
		assert.equal(phone.live, undefined);
		const shared = (await h.api("GET", "/api/devices", { token: bruno.token })).body;
		assert.equal(shared[0].kind, "phone");
		assert.equal(shared[0].ownerName, "Anna");
		const history = await h.api("GET", `/api/devices/${phoneId}/positions?from=${encodeURIComponent(new Date(Date.now() - 3600e3).toISOString())}&to=${encodeURIComponent(new Date().toISOString())}`, { token: anna.token });
		assert.equal(history.body.positions.length, 4);

		for (let i = 1; i < MAX_PHONES; i++) assert.equal((await h.api("POST", "/api/phones", { token: anna.token, body: { name: `Phone ${i}` } })).status, 200);
		assert.equal((await h.api("POST", "/api/phones", { token: anna.token, body: { name: "Too many" } })).body.error, "too_many_phones");
	});

	test("phones have no commands, alarms or offline notifications", async () => {
		const live = await h.live(anna.token);
		live.send({ type: "watch", deviceId: phoneId });
		await sleep(100);
		const [commands] = await h.sql<{ count: number }[]>`SELECT count(*)::int AS count FROM commands WHERE device_id = ${phoneId}`;
		assert.equal(commands!.count, 0);
		await h.server.ctx.hub.renewLive();
		live.close();

		for (const [method, path, body] of [
			["GET", `/api/devices/${phoneId}/commands`],
			["POST", `/api/devices/${phoneId}/commands`, { type: "locate" }],
			["GET", `/api/devices/${phoneId}/notification-settings`],
			["PUT", `/api/devices/${phoneId}/notification-settings`, { kinds: [] }]
		] as [string, string, unknown?][]) {
			assert.equal((await h.api(method, path, { token: anna.token, body })).body.error, "not_a_tracker", `${method} ${path}`);
		}

		const tracker = await h.claim(anna, IMEI);
		assert.equal((await h.api("POST", `/api/phones/${tracker}/token`, { token: anna.token })).body.error, "not_a_phone");

		await h.sql`UPDATE devices SET last_seen_at = now() - interval '2 days', paused_until = now() - interval '1 minute' WHERE id = ${phoneId}`;
		// Shorter retention for the phones (30 days), not for the trackers
		await h.sql`
			INSERT INTO positions (time, device_id, lat, lon, status, stale, events)
			VALUES (now() - interval '40 days', ${phoneId}, 45, 9, 1, false, 0), (now() - interval '40 days', ${tracker}, 45, 9, 1, false, 0)`;
		await runJobs(h.server.ctx);
		const old = await h.sql<{ device_id: number }[]>`SELECT device_id FROM positions WHERE time < now() - interval '35 days'`;
		assert.deepEqual(old.map(row => row.device_id), [tracker]);
		assert.equal((await h.sql`SELECT paused_until FROM devices WHERE id = ${phoneId}`)[0]!.paused_until, null);
		const [state] = await h.sql<{ offline_notified: boolean }[]>`SELECT offline_notified FROM devices WHERE id = ${phoneId}`;
		assert.equal(state!.offline_notified, false);
	});

	test("removing a friend ends the shares in both directions", async () => {
		const brunoPhone = (await h.api("POST", "/api/phones", { token: bruno.token, body: { name: "Bruno" } })).body.id;
		assert.equal((await h.api("POST", `/api/devices/${brunoPhone}/shares`, { token: bruno.token, body: { userId: anna.id, expiresAt: null } })).status, 200);
		assert.equal((await h.api("POST", `/api/devices/${brunoPhone}/geofences`, { token: anna.token, body: { name: "Ufficio", lat: HOME.lat, lon: HOME.lon, radius: 300 } })).status, 200);

		const live = await h.live(bruno.token);
		assert.equal((await h.api("DELETE", `/api/friends/${carla.id}`, { token: anna.token })).status, 404);
		assert.equal((await h.api("DELETE", "/api/friends/abc", { token: anna.token })).status, 400);
		const removed = await h.api("DELETE", `/api/friends/${bruno.id}`, { token: anna.token });
		assert.deepEqual(removed.body, { ok: true, sharesEnded: 2 });
		await waitFor(() => live.of("access").some(message => message.deviceId === phoneId && message.revoked === true));
		await waitFor(() => live.of("friends").some(message => message.userId === anna.id && message.added === false));
		live.close();

		assert.equal((await h.api("GET", `/api/devices/${phoneId}`, { token: bruno.token })).status, 404);
		assert.equal((await h.api("GET", `/api/devices/${brunoPhone}`, { token: anna.token })).status, 404);
		const [areas] = await h.sql<{ count: number }[]>`SELECT count(*)::int AS count FROM geofences WHERE user_id IN (${anna.id}, ${bruno.id})`;
		assert.equal(areas!.count, 0);
		assert.deepEqual((await h.api("GET", "/api/friends", { token: bruno.token })).body.friends, []);
		// No longer friends: no new share
		assert.equal((await h.api("POST", `/api/devices/${phoneId}/shares`, { token: anna.token, body: { userId: bruno.id, expiresAt: null } })).status, 404);
	});

	test("deleting a phone removes it with its history and its upload token", async () => {
		const upload = (await h.api("POST", `/api/phones/${phoneId}/token`, { token: anna.token })).body.uploadToken;
		assert.equal((await h.api("DELETE", `/api/devices/${phoneId}`, { token: anna.token })).status, 200);
		assert.equal((await h.api("POST", "/api/phones/positions", { token: upload, body: { positions: [fix(0, HOME)] } })).status, 401);
		assert.equal((await h.sql`SELECT 1 FROM devices WHERE id = ${phoneId}`).length, 0);
		assert.equal((await h.sql`SELECT 1 FROM positions WHERE device_id = ${phoneId}`).length, 0);
		assert.equal((await h.api("GET", `/api/devices/${phoneId}`, { token: anna.token })).status, 404);
	});

	test("trips of a phone, export of the period", async () => {
		const phone = (await h.api("POST", "/api/phones", { token: carla.token, body: { name: "Carla" } })).body.id;
		// 10 minutes walking north, a stop of 2 minutes (same trip), 10 minutes more, then still
		const start = Date.now() - 3600e3;
		const rows = Array.from({ length: 40 }, (_, minute) => {
			const moving = minute <= 10 || (minute >= 13 && minute <= 23);
			const step = Math.min(minute, 11) + Math.max(0, Math.min(minute, 23) - 12);
			return { time: new Date(start + minute * 60e3), device_id: phone, lat: 45 + step * 0.002, lon: 9, speed: moving ? 12 : 0, status: moving ? 0 : 1, stale: false, events: 0 };
		});
		await h.sql`INSERT INTO positions ${h.sql(rows)}`;
		const range = `from=${new Date(start - 60e3).toISOString()}&to=${new Date().toISOString()}`;
		const trips = (await h.api("GET", `/api/devices/${phone}/trips?${range}`, { token: carla.token })).body;
		assert.equal(trips.trips.length, 1);
		assert.ok(trips.trips[0].distanceKm > 4, String(trips.trips[0].distanceKm));

		const gpx = await h.api("GET", `/api/devices/${phone}/export?${range}&format=gpx`, { token: carla.token });
		assert.equal(gpx.status, 200);
		assert.match(gpx.headers.get("content-type")!, /gpx/);
		assert.match(gpx.headers.get("content-disposition")!, /Carla-\d{4}-\d{2}-\d{2}\.gpx/);
		assert.equal((gpx.body as string).match(/<trkseg>/g)!.length, 1);
		const csv = await h.api("GET", `/api/devices/${phone}/export?${range}&format=csv`, { token: carla.token });
		const lines = (csv.body as string).trim().split("\r\n");
		assert.equal(lines.length, 41);
		assert.match(lines[1]!, /,1$/);
		assert.match(lines[40]!, /,$/);
		assert.equal((await h.api("GET", `/api/devices/${phone}/export?${range}&format=kml`, { token: carla.token })).status, 400);
		assert.equal((await h.api("GET", `/api/devices/${phone}/export?format=csv`, { token: carla.token })).status, 400);
		assert.equal((await h.api("GET", `/api/devices/${phone}/export?${range}&format=csv`, { token: anna.token })).status, 404);
	});

	test("account: export of the data, deletion", async () => {
		await h.befriend(bruno, carla);
		const exported = await h.api("GET", "/api/account/export", { token: carla.token });
		assert.equal(exported.status, 200);
		assert.match(exported.headers.get("content-disposition")!, /attachment; filename="car-tracking-/);
		assert.equal(exported.body.profile.email, "carla@example.com");
		assert.equal(exported.body.devices[0].kind, "phone");
		assert.equal(exported.body.positions.length, 40);
		assert.deepEqual(exported.body.friends.map((friend: { name: string }) => friend.name), ["Bruno"]);
		assert.ok(exported.body.authEvents.length > 0);
		assert.equal(JSON.stringify(exported.body).includes("password"), false);

		const phone = exported.body.devices[0].id;
		assert.equal((await h.api("POST", `/api/devices/${phone}/shares`, { token: carla.token, body: { userId: bruno.id, expiresAt: null } })).status, 200);
		assert.equal((await h.api("DELETE", "/api/account", { token: carla.token, body: { email: "other@example.com" } })).body.error, "email_mismatch");
		// Not a recent login: the TOTP code is needed
		const old = await h.session(carla.id, "app", 3600e3);
		assert.equal((await h.api("DELETE", "/api/account", { token: old, body: { email: "carla@example.com" } })).body.error, "step_up_required");

		const live = await h.live(bruno.token);
		assert.equal((await h.api("DELETE", "/api/account", { token: carla.token, body: { email: " Carla@Example.com " } })).status, 200);
		await waitFor(() => live.of("access").some(message => message.deviceId === phone && message.revoked === true));
		live.close();
		assert.equal((await h.api("GET", "/api/account", { token: carla.token })).status, 401);
		assert.equal((await h.sql`SELECT 1 FROM users WHERE id = ${carla.id}`).length, 0);
		assert.equal((await h.sql`SELECT 1 FROM positions WHERE device_id = ${phone}`).length, 0);
		assert.deepEqual((await h.api("GET", "/api/friends", { token: bruno.token })).body.friends, []);
	});

	test("vehicles without a tracker: fed by the phone of the owner, deadlines, limits", async () => {
		assert.equal((await h.api("POST", "/api/vehicles", { token: bruno.token, body: { name: "" } })).status, 400);
		assert.equal((await h.api("POST", "/api/vehicles", { token: bruno.token, body: { name: "Panda", fuelType: "hydrogen" } })).status, 400);
		const created = await h.api("POST", "/api/vehicles", { token: bruno.token, body: { name: "Panda", model: "Fiat Panda 1.2", fuelType: "diesel" } });
		assert.equal(created.status, 200);
		const vehicle: number = created.body.id;
		const listed = (await h.api("GET", "/api/devices", { token: bruno.token })).body.find((device: { id: number }) => device.id === vehicle);
		assert.equal(listed.kind, "vehicle");
		assert.equal(listed.color, "#FFB300");
		assert.equal(listed.connected, false);
		const profile = (await h.api("GET", `/api/devices/${vehicle}/vehicle`, { token: bruno.token })).body;
		assert.equal(profile.model, "Fiat Panda 1.2");
		assert.equal(profile.fuelType, "diesel");

		// Only the owner of the phone and of the vehicle shares from it
		const [annaPhone] = await h.sql<{ id: number }[]>`
			SELECT d.id FROM devices d JOIN device_users du ON du.device_id = d.id WHERE du.user_id = ${anna.id} AND d.kind = 'phone' LIMIT 1`;
		const annaUpload = (await h.api("POST", `/api/phones/${annaPhone!.id}/token`, { token: anna.token })).body.uploadToken;
		assert.deepEqual((await h.api("POST", "/api/phones/positions", { token: annaUpload, body: { positions: [fix(60, HOME, { vehicleId: vehicle })] } })).body, { accepted: 0 });
		assert.equal((await h.api("POST", "/api/phones/positions", { token: annaUpload, body: { positions: [fix(60, HOME, { vehicleId: 0 })] } })).status, 400);

		const live = await h.live(bruno.token);
		const phone = (await h.api("POST", "/api/phones", { token: bruno.token, body: { name: "Bruno 2" } })).body;
		const upload: string = phone.uploadToken;
		const driven = [fix(600, HOME, { speed: 40, vehicleId: vehicle }), fix(300, AWAY, { speed: 45, vehicleId: vehicle }), fix(30, HOME)];
		const sent = await h.api("POST", "/api/phones/positions", { token: upload, body: { positions: driven } });
		assert.deepEqual(sent.body, { accepted: 3 });
		assert.equal((await h.sql`SELECT 1 FROM positions WHERE device_id = ${vehicle}`).length, 2);
		await waitFor(() => live.of("position").some(message => message.deviceId === vehicle));
		live.close();
		const after = (await h.api("GET", `/api/devices/${vehicle}`, { token: bruno.token })).body;
		assert.equal(after.connected, true);
		assert.equal(after.lastPosition.status, 0);
		// Replayed: skipped
		assert.deepEqual((await h.api("POST", "/api/phones/positions", { token: upload, body: { positions: [driven[1]] } })).body, { accepted: 0 });

		// Car features: odometer and deadlines; no commands; not for the phone
		assert.equal((await h.api("PUT", `/api/devices/${vehicle}/odometer`, { token: bruno.token, body: { km: 84000 } })).body.odometerKm, 84000);
		assert.equal((await h.api("GET", `/api/devices/${vehicle}/maintenance`, { token: bruno.token })).status, 200);
		assert.equal((await h.api("GET", `/api/devices/${phone.id}/maintenance`, { token: bruno.token })).body.error, "not_a_vehicle");
		assert.equal((await h.api("GET", `/api/devices/${vehicle}/commands`, { token: bruno.token })).body.error, "not_a_tracker");

		for (let i = 1; i < MAX_VEHICLES; i++) assert.equal((await h.api("POST", "/api/vehicles", { token: bruno.token, body: { name: `Car ${i}` } })).status, 200);
		assert.equal((await h.api("POST", "/api/vehicles", { token: bruno.token, body: { name: "Too many" } })).body.error, "too_many_vehicles");

		// Removed: gone with its history
		assert.equal((await h.api("DELETE", `/api/devices/${vehicle}`, { token: bruno.token })).status, 200);
		assert.equal((await h.sql`SELECT 1 FROM devices WHERE id = ${vehicle}`).length, 0);
		assert.equal((await h.sql`SELECT 1 FROM positions WHERE device_id = ${vehicle}`).length, 0);
	});

	test("the last administrator can't delete the account; the administrator deletes users with their devices", async () => {
		const admin = await h.onboard("root@example.com", "Root", true);
		assert.equal((await h.api("DELETE", "/api/account", { token: admin.token, body: { email: "root@example.com" } })).body.error, "last_admin");
		const tracker = (await h.sql<{ id: number }[]>`SELECT id FROM devices WHERE imei = ${IMEI}`)[0]!.id;
		assert.equal((await h.api("DELETE", `/api/admin/users/${anna.id}`, { token: admin.token })).status, 200);
		assert.equal((await h.api("DELETE", `/api/admin/users/${anna.id}`, { token: admin.token })).status, 404);
		// The tracker is free again, without the history of Anna
		const [device] = await h.sql<{ name: string }[]>`SELECT name FROM devices WHERE id = ${tracker}`;
		assert.equal(device!.name, "");
		assert.equal((await h.sql`SELECT 1 FROM positions WHERE device_id = ${tracker}`).length, 0);
		assert.equal((await h.sql`SELECT 1 FROM device_users WHERE device_id = ${tracker}`).length, 0);
	});
});
