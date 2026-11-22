import assert from "node:assert/strict";
import { after, before, describe, test } from "node:test";
import { WebSocket } from "ws";
import { COMMAND, EVENT, STATUS } from "../protocol/protocol.ts";
import { expireShares, runJobs } from "../server.ts";
import { Harness, Tracker, point, sleep, waitFor } from "../test/harness.ts";
import type { Live, User } from "../test/harness.ts";

const IMEI = "860000000000011";
const OTHER_IMEI = "860000000000029";
// Center of Milan and a point ~2 km away
const HOME = { lat: 45.4642, lon: 9.19 };
const AWAY = { lat: 45.4822, lon: 9.19 };

const inHours = (hours: number) => new Date(Date.now() + hours * 3600e3).toISOString();
const period = (from: Date, to = new Date(Date.now() + 60e3)) => `from=${encodeURIComponent(from.toISOString())}&to=${encodeURIComponent(to.toISOString())}`;

describe("devices, sharing, arrival areas", { skip: !process.env.TEST_DATABASE_URL && "TEST_DATABASE_URL not set" }, () => {
	let h: Harness;
	let owner: User;
	let viewer: User;
	let stranger: User;
	let admin: User;
	let deviceId: number;
	let tracker: Tracker;

	before(async () => {
		h = await Harness.start();
		owner = await h.onboard("owner@example.com", "Owner");
		viewer = await h.onboard("viewer@example.com", "Viewer");
		stranger = await h.onboard("stranger@example.com", "Stranger");
		admin = await h.onboard("admin@example.com", "Admin", true);
		await h.befriend(owner, viewer);
	});
	after(async () => {
		tracker?.close();
		await h?.close();
	});

	test("guided procedure: check, claim, first contact", async () => {
		const code = h.server.ctx.secrets.pairingCode(IMEI);
		assert.equal((await h.api("POST", "/api/devices/claim/check", { token: owner.token, body: { imei: IMEI, code: "AAAA-BBBB" } })).body.error, "invalid_pairing");
		assert.equal((await h.api("POST", "/api/devices/claim/check", { token: owner.token, body: { imei: "123", code } })).status, 400);
		const check = await h.api("POST", "/api/devices/claim/check", { token: owner.token, body: { imei: IMEI, code } });
		assert.deepEqual(check.body, { valid: true, registered: false, available: true, mine: false });
		assert.equal((await h.api("POST", "/api/devices/claim", { token: owner.token, body: { imei: IMEI, code: "x", name: "Panda" } })).body.error, "invalid_pairing");

		const live = await h.live(owner.token);
		deviceId = await h.claim(owner, IMEI);
		await waitFor(() => live.of("access").some(message => message.deviceId === deviceId && message.revoked === false));
		assert.deepEqual((await h.api("POST", "/api/devices/claim/check", { token: owner.token, body: { imei: IMEI, code } })).body,
			{ valid: true, registered: false, available: false, mine: true });
		const taken = await h.api("POST", "/api/devices/claim", { token: stranger.token, body: { imei: IMEI, code, name: "Mia" } });
		assert.equal(taken.status, 409);
		assert.equal(taken.body.error, "already_claimed");

		tracker = await Tracker.connect(h, IMEI);
		assert.equal(await tracker.hello(), deviceId);
		await waitFor(() => live.of("registered").length === 1);
		live.close();

		const list = await h.api("GET", "/api/devices", { token: owner.token });
		assert.equal(list.body.length, 1);
		assert.equal(list.body[0].imei, IMEI);
		assert.equal(list.body[0].role, "owner");
		assert.equal(list.body[0].connected, true);
		assert.equal(list.body[0].firmware, "3.0.0");
	});

	test("the administrator manages users, not their devices", async () => {
		assert.deepEqual((await h.api("GET", "/api/devices", { token: admin.token })).body, []);
		assert.equal((await h.api("GET", `/api/devices/${deviceId}`, { token: admin.token })).status, 404);
		assert.equal((await h.api("GET", `/api/devices/${deviceId}`, { token: stranger.token })).body.error, "not_found");
		assert.equal((await h.api("GET", "/api/devices/abc", { token: owner.token })).status, 400);
		assert.equal((await h.api("GET", "/api/devices/99999999999", { token: owner.token })).status, 400);
	});

	test("sharing: validation, temporary and permanent, owner only operations", async () => {
		const path = `/api/devices/${deviceId}/shares`;
		assert.equal((await h.api("POST", path, { token: owner.token, body: { userId: stranger.id, expiresAt: null } })).status, 404);
		assert.equal((await h.api("POST", path, { token: owner.token, body: { userId: owner.id, expiresAt: null } })).body.error, "share_self");
		assert.equal((await h.api("POST", path, { token: owner.token, body: { userId: viewer.id, expiresAt: inHours(-1) } })).status, 400);
		assert.equal((await h.api("POST", path, { token: owner.token, body: { userId: viewer.id, expiresAt: inHours(24 * 400) } })).status, 400);
		assert.equal((await h.api("POST", path, { token: owner.token, body: { userId: viewer.id, expiresAt: "tomorrow" } })).status, 400);
		assert.equal((await h.api("POST", path, { token: owner.token, body: { userId: viewer.id } })).status, 400);
		assert.equal((await h.api("POST", path, { token: stranger.token, body: { userId: viewer.id, expiresAt: null } })).status, 404);

		const live = await h.live(viewer.token);
		const shared = await h.api("POST", path, { token: owner.token, body: { userId: viewer.id, expiresAt: inHours(2) } });
		assert.equal(shared.body.userId, viewer.id);
		await waitFor(() => live.of("access").some(message => message.deviceId === deviceId && message.revoked === false));
		live.close();

		const shares = await h.api("GET", path, { token: owner.token });
		assert.equal(shares.body.length, 1);
		assert.equal(shares.body[0].name, "Viewer");
		assert.equal(shares.body[0].email, undefined);
		assert.ok(new Date(shares.body[0].expiresAt).getTime() > Date.now() + 3600e3);
		assert.equal((await h.api("GET", path, { token: viewer.token })).body.error, "owner_only");

		// Permanent, then back to a date
		assert.equal((await h.api("PATCH", `${path}/${viewer.id}`, { token: owner.token, body: { expiresAt: null } })).status, 200);
		assert.equal((await h.api("GET", path, { token: owner.token })).body[0].expiresAt, null);
		assert.equal((await h.api("PATCH", `${path}/${stranger.id}`, { token: owner.token, body: { expiresAt: null } })).status, 404);
		assert.equal((await h.api("PATCH", `${path}/${viewer.id}`, { token: viewer.token, body: { expiresAt: null } })).status, 403);
	});

	test("viewers: reduced data, no settings, commands or analysis", async () => {
		// Viewers see only what happened after the start of the share (the protocol has
		// one second resolution: the points after the share are in the next seconds)
		const now = Date.now();
		tracker.send([
			point(new Date(now - 3600e3), HOME.lat - 0.01, HOME.lon, { speed: 70 }),
			point(new Date(now + 1000), HOME.lat, HOME.lon, { speed: 50 }),
			point(new Date(now + 2000), HOME.lat + 0.001, HOME.lon, { status: STATUS.ENGINE_OFF, speed: 0 })
		]);
		await waitFor(async () => (await h.sql`SELECT 1 FROM positions WHERE device_id = ${deviceId}`).length === 3);

		const list = await h.api("GET", "/api/devices", { token: viewer.token });
		assert.equal(list.body.length, 1);
		const device = list.body[0];
		assert.equal(device.role, "viewer");
		assert.equal(device.ownerName, "Owner");
		assert.equal(device.shareExpiresAt, null);
		for (const key of ["imei", "model", "firmware", "manufacturer", "revision", "registeredAt"]) assert.equal(key in device, false, key);
		assert.deepEqual(Object.keys(device.lastPosition).sort(), ["lat", "lon", "speed", "stale", "status", "time"]);
		assert.equal(device.lastPosition.status, 1);

		const detail = await h.api("GET", `/api/devices/${deviceId}`, { token: viewer.token });
		assert.equal(detail.body.imei, undefined);
		assert.equal(detail.body.live, undefined);
		const ownerDetail = await h.api("GET", `/api/devices/${deviceId}`, { token: owner.token });
		assert.equal(ownerDetail.body.imei, IMEI);
		assert.equal(ownerDetail.body.lastPosition.voltage, 12.6);

		const history = await h.api("GET", `/api/devices/${deviceId}/positions?${period(new Date(now - 7 * 86400e3))}`, { token: viewer.token });
		assert.equal(history.body.positions.length, 2);
		assert.equal(history.body.positions[0].voltage, undefined);
		assert.equal(history.body.positions[0].status, 0);

		const forbidden: [string, string, unknown?][] = [
			["PATCH", `/api/devices/${deviceId}`, { name: "Mia" }],
			["DELETE", `/api/devices/${deviceId}`],
			["GET", `/api/devices/${deviceId}/commands`],
			["POST", `/api/devices/${deviceId}/commands`, { type: "locate" }],
			["GET", `/api/devices/${deviceId}/notification-settings`],
			["PUT", `/api/devices/${deviceId}/notification-settings`, { kinds: [] }],
			["POST", `/api/devices/${deviceId}/shares`, { userId: stranger.id, expiresAt: null }],
			["DELETE", `/api/devices/${deviceId}/shares/${viewer.id}`],
			...["stats", "trips", "distribution", "coverage", "traffic"].map(name =>
				["GET", `/api/devices/${deviceId}/${name}?${period(new Date(now - 86400e3))}`] as [string, string])
		];
		for (const [method, path, body] of forbidden) {
			const response = await h.api(method, path, { token: viewer.token, body });
			assert.equal(response.status, 403, `${method} ${path}`);
			assert.equal(response.body.error, "owner_only", `${method} ${path}`);
		}
		assert.equal((await h.api("DELETE", `/api/devices/${deviceId}/access`, { token: owner.token })).body.error, "owner_cannot_leave");
	});

	test("realtime: viewers get reduced positions, never start live tracking", async () => {
		const viewerLive = await h.live(viewer.token);
		viewerLive.send({ type: "watch", deviceId });
		viewerLive.send({ type: "ping" });
		await waitFor(() => viewerLive.of("pong").length === 1);
		await sleep(100);
		assert.equal(tracker.commands().length, 0);
		const [pending] = await h.sql`SELECT 1 FROM commands WHERE device_id = ${deviceId} AND payload @> ${h.sql.json([{ id: COMMAND.LIVE }])}`;
		assert.equal(pending, undefined);

		const ownerLive = await h.live(owner.token);
		ownerLive.send({ type: "watch", deviceId });
		await waitFor(() => tracker.commands().some(item => item.commands.some(command => command.id === COMMAND.LIVE)));

		tracker.send([point(new Date(Date.now() + 4000), HOME.lat, HOME.lon + 0.001, { events: EVENT.MOTION })]);
		await waitFor(() => viewerLive.of("position").length === 1 && ownerLive.of("position").length === 1);
		assert.equal(viewerLive.of("position")[0]!.position.voltage, undefined);
		assert.equal(ownerLive.of("position")[0]!.position.voltage, 12.6);
		// Alarms only to the owner
		await waitFor(() => ownerLive.of("notification").length === 1);
		assert.equal(viewerLive.of("notification").length, 0);
		const notification = ownerLive.of("notification")[0]!.notification;
		assert.equal(notification.kind, "motion");
		assert.equal(notification.data.device, "Panda");

		// Invalid and unauthorized messages are ignored
		viewerLive.send("not json");
		viewerLive.send({ type: "watch", deviceId: "x" });
		viewerLive.send({ type: "watch", deviceId: 999999 });
		viewerLive.send("x".repeat(5000));
		viewerLive.socket.send(Buffer.from([1, 2, 3]));
		viewerLive.send({ type: "unwatch", deviceId });
		viewerLive.send({ type: "ping" });
		await waitFor(() => viewerLive.of("pong").length === 2);

		await h.server.ctx.hub.renewLive();
		viewerLive.close();
		ownerLive.close();
	});

	test("realtime limits: message flood and connections per user", async () => {
		const flood = await h.live(stranger.token);
		for (let i = 0; i < 40; i++) flood.send({ type: "ping" });
		await waitFor(() => flood.closed !== null);
		assert.equal(flood.closed!.code, 4008);

		const sockets: Live[] = [];
		for (let i = 0; i < 10; i++) sockets.push(await h.live(stranger.token));
		const extra = new WebSocket(h.base.replace("http", "ws") + "/api/live", { headers: { authorization: `Bearer ${stranger.token}` } });
		assert.equal(await new Promise<number>(resolve => extra.on("close", code => resolve(code))), 4009);
		for (const socket of sockets) socket.close();
		await sleep(100);

		const anonymous = await h.api("GET", "/api/live");
		assert.equal(anonymous.status, 401);
	});

	test("arrival areas: validation, enter and exit notifications, other users", async () => {
		const path = `/api/devices/${deviceId}/geofences`;
		assert.equal((await h.api("POST", path, { token: viewer.token, body: { name: "Casa", lat: 95, lon: 9, radius: 300 } })).status, 400);
		assert.equal((await h.api("POST", path, { token: viewer.token, body: { name: "Casa", lat: 45, lon: 9, radius: 10 } })).status, 400);
		assert.equal((await h.api("POST", path, { token: viewer.token, body: { name: "", lat: 45, lon: 9, radius: 300 } })).status, 400);
		assert.equal((await h.api("POST", path, { token: stranger.token, body: { name: "Casa", lat: 45, lon: 9, radius: 300 } })).status, 404);

		// The device is at HOME: the area starts "inside", no notification at creation
		const home = await h.api("POST", path, { token: viewer.token, body: { name: "Casa", ...HOME, radius: 300, notifyExit: true } });
		assert.equal(home.status, 200, JSON.stringify(home.body));
		assert.equal(home.body.inside, true);
		assert.equal(home.body.notifyEnter, true);
		const office = await h.api("POST", path, { token: viewer.token, body: { name: "Ufficio", ...AWAY, radius: 200 } });
		assert.equal(office.body.inside, false);
		const ownerArea = await h.api("POST", path, { token: owner.token, body: { name: "Box", ...AWAY, radius: 200, notifyEnter: false } });

		const list = await h.api("GET", path, { token: viewer.token });
		assert.deepEqual(list.body.map((area: { name: string }) => area.name), ["Casa", "Ufficio"]);
		assert.equal((await h.api("GET", path, { token: owner.token })).body.length, 1);

		const live = await h.live(viewer.token);
		const start = Date.now() + 6000;
		tracker.send([
			point(new Date(start + 1000), (HOME.lat + AWAY.lat) / 2, HOME.lon),
			point(new Date(start + 2000), AWAY.lat, AWAY.lon),
			// Jitter on the border of the office: no second notification
			point(new Date(start + 3000), AWAY.lat + 0.0019, AWAY.lon),
			point(new Date(start + 4000), AWAY.lat, AWAY.lon)
		]);
		await waitFor(() => live.of("notification").length === 2);
		await sleep(150);
		const kinds = live.of("notification").map(item => `${item.notification.kind}:${item.notification.data.area}`);
		assert.deepEqual(kinds.sort(), ["geofence_enter:Ufficio", "geofence_exit:Casa"]);
		// notifyEnter false: nothing for the owner
		const [ownerRows] = await h.sql<{ count: number }[]>`SELECT count(*)::int AS count FROM notifications WHERE user_id = ${owner.id} AND kind LIKE 'geofence%'`;
		assert.equal(ownerRows!.count, 0);

		// Replayed points don't notify again
		tracker.send([point(new Date(start + 2000), AWAY.lat, AWAY.lon)]);
		await sleep(200);
		assert.equal(live.of("notification").length, 2);

		// Edit: name only keeps the state, a moved center recomputes it silently
		const renamed = await h.api("PATCH", `/api/geofences/${home.body.id}`, { token: viewer.token, body: { name: "Casa mia" } });
		assert.equal(renamed.body.name, "Casa mia");
		assert.equal(renamed.body.inside, false);
		const moved = await h.api("PATCH", `/api/geofences/${home.body.id}`, { token: viewer.token, body: { ...AWAY, radius: 500 } });
		assert.equal(moved.body.inside, true);
		assert.equal((await h.api("PATCH", `/api/geofences/${home.body.id}`, { token: viewer.token, body: { radius: 1 } })).status, 400);
		assert.equal((await h.api("PATCH", `/api/geofences/${home.body.id}`, { token: viewer.token, body: { color: "red" } })).status, 400);
		assert.equal((await h.api("PATCH", `/api/geofences/${home.body.id}`, { token: owner.token, body: { name: "X" } })).status, 404);
		assert.equal((await h.api("DELETE", `/api/geofences/${ownerArea.body.id}`, { token: viewer.token })).status, 404);
		assert.equal((await h.api("DELETE", `/api/geofences/${ownerArea.body.id}`, { token: owner.token })).status, 200);

		// Notifications page with the data to localize
		const notifications = await h.api("GET", "/api/notifications?limit=10", { token: viewer.token });
		assert.equal(notifications.body.unread, 2);
		assert.equal(notifications.body.notifications[0].data.device, "Panda");
		assert.ok(notifications.body.notifications[0].data.time);
		const older = await h.api("GET", `/api/notifications?before=${notifications.body.notifications[0].id}`, { token: viewer.token });
		assert.equal(older.body.notifications.length, 1);
		assert.equal((await h.api("GET", "/api/notifications?limit=1000", { token: viewer.token })).status, 400);
		await h.api("POST", "/api/notifications/read", { token: viewer.token, body: { ids: [notifications.body.notifications[0].id] } });
		assert.equal((await h.api("GET", "/api/notifications", { token: viewer.token })).body.unread, 1);
		await h.api("POST", "/api/notifications/read", { token: viewer.token, body: {} });
		assert.equal((await h.api("GET", "/api/notifications", { token: viewer.token })).body.unread, 0);
		live.close();

		// At most 20 areas per device and user
		await h.sql`
			INSERT INTO geofences (user_id, device_id, name, lat, lon, radius)
			SELECT ${viewer.id}, ${deviceId}, 'Area ' || n, 45, 9, 100 FROM generate_series(1, 18) n`;
		const tooMany = await h.api("POST", path, { token: viewer.token, body: { name: "Troppe", ...HOME, radius: 300 } });
		assert.equal(tooMany.body.error, "too_many_areas");
		assert.equal((await h.api("DELETE", `/api/geofences/${office.body.id}`, { token: viewer.token })).status, 200);
		assert.equal((await h.api("DELETE", `/api/geofences/${office.body.id}`, { token: viewer.token })).status, 404);
	});

	test("revocation and expiry remove access and areas", async () => {
		const live = await h.live(viewer.token);
		assert.equal((await h.api("DELETE", `/api/devices/${deviceId}/shares/${viewer.id}`, { token: owner.token })).status, 200);
		await waitFor(() => live.of("access").some(message => message.deviceId === deviceId && message.revoked === true));
		assert.equal((await h.api("DELETE", `/api/devices/${deviceId}/shares/${viewer.id}`, { token: owner.token })).status, 404);
		assert.deepEqual((await h.api("GET", "/api/devices", { token: viewer.token })).body, []);
		assert.equal((await h.api("GET", `/api/devices/${deviceId}/geofences`, { token: viewer.token })).status, 404);
		const [areas] = await h.sql<{ count: number }[]>`SELECT count(*)::int AS count FROM geofences WHERE user_id = ${viewer.id}`;
		assert.equal(areas!.count, 0);

		// The viewer leaves by themselves
		await h.api("POST", `/api/devices/${deviceId}/shares`, { token: owner.token, body: { userId: viewer.id, expiresAt: null } });
		assert.equal((await h.api("DELETE", `/api/devices/${deviceId}/access`, { token: viewer.token })).status, 200);
		assert.equal((await h.api("DELETE", `/api/devices/${deviceId}/access`, { token: viewer.token })).status, 404);

		// A temporary share ends: the next event drops it, the job deletes it
		await h.api("POST", `/api/devices/${deviceId}/shares`, { token: owner.token, body: { userId: viewer.id, expiresAt: inHours(1) } });
		await waitFor(() => live.of("access").filter(message => message.revoked === false).length >= 2);
		// Ends in a moment: the open connection knows the end date
		await h.sql`UPDATE device_users SET expires_at = now() + interval '300 milliseconds' WHERE user_id = ${viewer.id}`;
		await h.server.ctx.hub.refreshUser(viewer.id);
		await sleep(400);
		const before = live.of("access").filter(message => message.revoked).length;
		tracker.send([point(new Date(Date.now() + 12e3), HOME.lat, HOME.lon)]);
		await waitFor(() => live.of("access").filter(message => message.revoked).length > before);
		assert.equal(live.of("position").length, 0);
		assert.deepEqual((await h.api("GET", "/api/devices", { token: viewer.token })).body, []);
		await expireShares(h.server.ctx);
		const [rows] = await h.sql<{ count: number }[]>`SELECT count(*)::int AS count FROM device_users WHERE user_id = ${viewer.id}`;
		assert.equal(rows!.count, 0);
		live.close();
	});

	test("owner: settings, commands, analysis, offline job, release", async () => {
		const ownerLive = await h.live(owner.token);
		assert.equal((await h.api("PATCH", `/api/devices/${deviceId}`, { token: owner.token, body: { name: "Golf", color: "#000000" } })).status, 200);
		await waitFor(() => ownerLive.of("device").some(message => message.name === "Golf"));
		assert.equal((await h.api("PATCH", `/api/devices/${deviceId}`, { token: owner.token, body: { color: "black" } })).status, 400);

		const settings = await h.api("GET", `/api/devices/${deviceId}/notification-settings`, { token: owner.token });
		assert.equal(settings.body.kinds.length, 9);
		assert.equal((await h.api("PUT", `/api/devices/${deviceId}/notification-settings`, { token: owner.token, body: { kinds: ["offline", "offline"] } })).status, 200);
		assert.deepEqual((await h.api("GET", `/api/devices/${deviceId}/notification-settings`, { token: owner.token })).body.kinds, ["offline"]);
		assert.equal((await h.api("PUT", `/api/devices/${deviceId}/notification-settings`, { token: owner.token, body: { kinds: ["fire"] } })).status, 400);

		assert.equal((await h.api("POST", `/api/devices/${deviceId}/commands`, { token: owner.token, body: { type: "live", seconds: 9000 } })).body.error, "live_too_long");
		assert.equal((await h.api("POST", `/api/devices/${deviceId}/commands`, { token: owner.token, body: { type: "reboot" } })).status, 400);
		const created = await h.api("POST", `/api/devices/${deviceId}/commands`, { token: owner.token, body: { type: "locate" } });
		assert.ok(created.body.command.id);
		await waitFor(() => tracker.commands().some(item => item.commands.some(command => command.id === COMMAND.LOCATE)));
		const frame = tracker.commands().at(-1)!;
		tracker.result(frame.counter);
		await waitFor(async () => (await h.api("GET", `/api/devices/${deviceId}/commands`, { token: owner.token })).body.commands.some((command: { result: number | null }) => command.result === 0));

		const from = new Date(Date.now() - 86400e3);
		for (const name of ["stats", "trips", "distribution", "coverage", "traffic"]) {
			const response = await h.api("GET", `/api/devices/${deviceId}/${name}?${period(from)}`, { token: owner.token });
			assert.equal(response.status, 200, `${name} ${JSON.stringify(response.body)}`);
		}
		const stats = await h.api("GET", `/api/devices/${deviceId}/stats?${period(from)}`, { token: owner.token });
		assert.ok(stats.body.series.length > 0);
		const positions = await h.api("GET", `/api/devices/${deviceId}/positions?${period(from)}`, { token: owner.token });
		assert.ok(positions.body.positions.length >= 7);
		assert.equal((await h.api("GET", `/api/devices/${deviceId}/stats?${period(new Date(Date.now() - 100 * 86400e3))}`, { token: owner.token })).body.error, "period_too_long");
		assert.equal((await h.api("GET", `/api/devices/${deviceId}/stats?from=2026-01-02T00:00:00Z&to=2026-01-01T00:00:00Z`, { token: owner.token })).status, 400);
		assert.equal((await h.api("GET", `/api/devices/${deviceId}/stats?from=yesterday&to=today`, { token: owner.token })).status, 400);

		// Offline after the configured hours: one notification, "online" when it comes back
		await tracker.close();
		await h.sql`UPDATE devices SET last_seen_at = now() - interval '2 days' WHERE id = ${deviceId}`;
		await runJobs(h.server.ctx);
		await waitFor(() => ownerLive.of("notification").some(message => message.notification.kind === "offline"));
		await runJobs(h.server.ctx);
		assert.equal(ownerLive.of("notification").filter(message => message.notification.kind === "offline").length, 1);
		tracker = await Tracker.connect(h, IMEI);
		await tracker.hello();
		// "online" is not in the chosen kinds
		await sleep(150);
		assert.equal(ownerLive.of("notification").some(message => message.notification.kind === "online"), false);
		const [state] = await h.sql<{ offline_notified: boolean }[]>`SELECT offline_notified FROM devices WHERE id = ${deviceId}`;
		assert.equal(state!.offline_notified, false);

		// Release: history deleted, the tracker can be claimed again
		await h.api("POST", `/api/devices/${deviceId}/shares`, { token: owner.token, body: { userId: viewer.id, expiresAt: null } });
		assert.equal((await h.api("DELETE", `/api/devices/${deviceId}`, { token: owner.token })).status, 200);
		await waitFor(() => ownerLive.of("access").some(message => message.deviceId === deviceId && message.revoked));
		const [positionsLeft] = await h.sql<{ count: number }[]>`SELECT count(*)::int AS count FROM positions WHERE device_id = ${deviceId}`;
		assert.equal(positionsLeft!.count, 0);
		assert.deepEqual((await h.api("GET", "/api/devices", { token: viewer.token })).body, []);
		const again = await h.claim(stranger, IMEI, "Nuova");
		assert.equal(again, deviceId);
		assert.equal((await h.api("GET", `/api/devices/${deviceId}`, { token: stranger.token })).body.registered, undefined);
		ownerLive.close();
	});

	test("trackers: wrong key, unknown device id", async () => {
		const forged = await Tracker.connect(h, OTHER_IMEI, Buffer.alloc(32));
		forged.sendHello();
		await waitFor(() => forged.closed === 4001);
		const other = await Tracker.connect(h, OTHER_IMEI);
		await other.hello();
		// Telemetry for a device id that isn't its own: ignored
		other.send([point(new Date(), HOME.lat, HOME.lon)], deviceId);
		await sleep(150);
		const [rows] = await h.sql<{ count: number }[]>`SELECT count(*)::int AS count FROM positions WHERE time > now() - interval '1 minute' AND device_id = ${deviceId}`;
		assert.equal(rows!.count, 0);
		await other.close();
	});
});
