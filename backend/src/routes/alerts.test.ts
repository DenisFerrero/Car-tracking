import assert from "node:assert/strict";
import { after, before, describe, test } from "node:test";
import { runJobs } from "../server.ts";
import { localTime } from "../services/schedule.ts";
import { Harness, sleep, waitFor } from "../test/harness.ts";
import type { User } from "../test/harness.ts";

// Areas with a schedule, low battery of a phone, long stop

const HOME = { lat: 45.4642, lon: 9.19 };
const AWAY = { lat: 45.4822, lon: 9.19 };
const FAR = { lat: 45.55, lon: 9.3 };

const fix = (secondsAgo: number, where: { lat: number; lon: number }, extra: Record<string, unknown> = {}) =>
	({ time: new Date(Date.now() - secondsAgo * 1000).toISOString(), lat: where.lat, lon: where.lon, accuracy: 10, ...extra });

describe("alerts", { skip: !process.env.TEST_DATABASE_URL && "TEST_DATABASE_URL not set" }, () => {
	let h: Harness;
	let anna: User;
	let bruno: User;
	let phoneId: number;
	let upload: string;
	const path = "/api/phones/positions";

	before(async () => {
		h = await Harness.start();
		anna = await h.onboard("anna@example.com", "Anna");
		bruno = await h.onboard("bruno@example.com", "Bruno");
		await h.befriend(anna, bruno);
		const phone = await h.api("POST", "/api/phones", { token: anna.token, body: { name: "Pixel" } });
		phoneId = phone.body.id;
		upload = phone.body.uploadToken;
		await h.api("POST", `/api/devices/${phoneId}/shares`, { token: anna.token, body: { userId: bruno.id, expiresAt: null } });
	});
	after(async () => {
		await h?.close();
	});

	test("areas with a schedule notify only in their hours", async () => {
		const areas = `/api/devices/${phoneId}/geofences`;
		for (const schedule of [{ days: [], from: "07:00", to: "08:00" }, { days: [8], from: "07:00", to: "08:00" }, { days: [1], from: "25:00", to: "08:00" }]) {
			assert.equal((await h.api("POST", areas, { token: bruno.token, body: { name: "X", ...HOME, radius: 300, schedule } })).status, 400);
		}
		// Today all day / every day except today, in the time zone of the platform
		const today = localTime(new Date(), "Europe/Rome").day;
		const always = { days: [today], from: "00:00", to: "00:00" };
		const never = { days: [1, 2, 3, 4, 5, 6, 7].filter(day => day !== today), from: "00:00", to: "00:00" };
		const home = await h.api("POST", areas, { token: bruno.token, body: { name: "Casa", ...HOME, radius: 300, notifyExit: true, schedule: always } });
		assert.equal(home.status, 200, JSON.stringify(home.body));
		assert.deepEqual(home.body.schedule, always);
		const school = await h.api("POST", areas, { token: bruno.token, body: { name: "Scuola", ...AWAY, radius: 300, schedule: never } });
		assert.deepEqual(school.body.schedule.days, never.days);
		const plain = await h.api("POST", areas, { token: bruno.token, body: { name: "Parco", ...FAR, radius: 300 } });
		assert.equal(plain.body.schedule, null);

		const live = await h.live(bruno.token);
		await h.api("POST", path, { token: upload, body: { positions: [fix(50, HOME)] } });
		await h.api("POST", path, { token: upload, body: { positions: [fix(40, AWAY, { speed: 30 })] } });
		await waitFor(() => live.of("notification").length === 1);
		await sleep(150);
		// Left home (in its hours); arrived at school outside its hours: followed, not notified
		assert.deepEqual(live.of("notification").map(item => `${item.notification.kind}:${item.notification.data.area}`), ["geofence_exit:Casa"]);
		const list = (await h.api("GET", areas, { token: bruno.token })).body as { name: string; inside: boolean }[];
		assert.equal(list.find(area => area.name === "Scuola")!.inside, true);

		// Schedule changed, removed; the other fields stay
		const changed = await h.api("PATCH", `/api/geofences/${school.body.id}`, { token: bruno.token, body: { schedule: { days: [3, 3, 1], from: "22:00", to: "06:00" } } });
		assert.deepEqual(changed.body.schedule, { days: [1, 3], from: "22:00", to: "06:00" });
		const renamed = await h.api("PATCH", `/api/geofences/${school.body.id}`, { token: bruno.token, body: { name: "Scuola media" } });
		assert.deepEqual(renamed.body.schedule.days, [1, 3]);
		const removed = await h.api("PATCH", `/api/geofences/${school.body.id}`, { token: bruno.token, body: { schedule: null } });
		assert.equal(removed.body.schedule, null);
		assert.equal((await h.api("PATCH", `/api/geofences/${school.body.id}`, { token: bruno.token, body: { schedule: { days: [1] } } })).status, 400);
		for (const area of [home, school, plain]) await h.api("DELETE", `/api/geofences/${area.body.id}`, { token: bruno.token });

		const exported = await h.api("GET", "/api/account/export", { token: bruno.token });
		assert.equal(exported.status, 200);
		live.close();
	});

	test("polygon areas: entered and left by their sides, invalid shapes", async () => {
		const areas = `/api/devices/${phoneId}/geofences`;
		// About 500 x 500 m around HOME; AWAY is 2 km north
		const square: [number, number][] = [[45.462, 9.187], [45.462, 9.193], [45.4665, 9.193], [45.4665, 9.187]];
		const crossed: [number, number][] = [[45.462, 9.187], [45.4665, 9.193], [45.462, 9.193], [45.4665, 9.187]];
		const tiny: [number, number][] = [[45.462, 9.187], [45.462, 9.1871], [45.4621, 9.187]];
		const huge: [number, number][] = [[45, 9], [45, 10], [46, 10], [46, 9]];
		for (const [body, code] of [[{ polygon: crossed }, "polygon_invalid"], [{ polygon: tiny }, "polygon_invalid"], [{ polygon: huge }, "polygon_too_large"],
			[{ polygon: square.slice(0, 2) }, "validation"], [{ lat: 45 }, "validation"], [{ polygon: [[91, 9], [45, 9], [45, 10]] }, "validation"]] as const) {
			const response = await h.api("POST", areas, { token: bruno.token, body: { name: "X", ...body } });
			assert.equal(response.body.error, code, JSON.stringify(body));
		}

		// Newer than the last point of the test before: older points are history, not areas
		await h.api("POST", path, { token: upload, body: { positions: [fix(38, AWAY)] } });
		const created = await h.api("POST", areas, { token: bruno.token, body: { name: "Quartiere", polygon: square, notifyExit: true } });
		assert.equal(created.status, 200, JSON.stringify(created.body));
		assert.deepEqual(created.body.polygon, square);
		assert.equal(created.body.inside, false);
		assert.ok(Math.abs(created.body.lat - 45.46425) < 1e-9 && created.body.radius > 300 && created.body.radius < 400, JSON.stringify(created.body));

		const live = await h.live(bruno.token);
		// Inside; then 20 m out of the east side (within the margin); then far
		await h.api("POST", path, { token: upload, body: { positions: [fix(37, HOME)] } });
		await waitFor(() => live.of("notification").length === 1);
		await h.api("POST", path, { token: upload, body: { positions: [fix(36, { lat: 45.4642, lon: 9.19325 })] } });
		await sleep(150);
		assert.equal(live.of("notification").length, 1);
		await h.api("POST", path, { token: upload, body: { positions: [fix(35, AWAY, { speed: 30 })] } });
		await waitFor(() => live.of("notification").length === 2);
		assert.deepEqual(live.of("notification").map(item => item.notification.kind), ["geofence_enter", "geofence_exit"]);

		// Moved by its vertices; the center alone doesn't move a polygon; back to a circle
		const moved = await h.api("PATCH", `/api/geofences/${created.body.id}`, { token: bruno.token, body: { polygon: square.map(([lat, lon]) => [lat + 0.02, lon]) } });
		assert.equal(moved.body.inside, true);
		const kept = await h.api("PATCH", `/api/geofences/${created.body.id}`, { token: bruno.token, body: { lat: 40 } });
		assert.equal(kept.body.lat, moved.body.lat);
		assert.equal((await h.api("PATCH", `/api/geofences/${created.body.id}`, { token: bruno.token, body: { polygon: crossed } })).body.error, "polygon_invalid");
		const circle = await h.api("PATCH", `/api/geofences/${created.body.id}`, { token: bruno.token, body: { polygon: null, ...HOME, radius: 200 } });
		assert.deepEqual([circle.body.polygon, circle.body.radius, circle.body.inside], [null, 200, false]);
		assert.equal((await h.api("GET", "/api/account/export", { token: bruno.token })).body.areas[0].polygon, null);
		await h.api("DELETE", `/api/geofences/${created.body.id}`, { token: bruno.token });
		live.close();
	});

	test("low battery of a phone: threshold of each friend, once per discharge", async () => {
		const alerts = `/api/devices/${phoneId}/alerts`;
		assert.equal((await h.api("GET", `/api/devices/${phoneId}`, { token: bruno.token })).body.batteryAlert, 20);
		assert.equal((await h.api("GET", `/api/devices/${phoneId}`, { token: anna.token })).body.batteryAlert, undefined);
		// The owner doesn't get it; trackers have no phone battery
		assert.equal((await h.api("PATCH", alerts, { token: anna.token, body: { batteryAlert: 30 } })).body.error, "not_a_shared_phone");
		for (const batteryAlert of [4, 51, 20.5]) {
			assert.equal((await h.api("PATCH", alerts, { token: bruno.token, body: { batteryAlert } })).status, 400);
		}

		const brunoLive = await h.live(bruno.token);
		const annaLive = await h.live(anna.token);
		const battery = async (value: number) => {
			await h.api("POST", path, { token: upload, body: { battery: value } });
			await waitFor(() => brunoLive.of("device").some(message => message.battery === value));
		};
		const received = () => brunoLive.of("notification").filter(item => item.notification.kind === "phone_battery");

		await battery(25);
		await battery(20);
		await waitFor(() => received().length === 1);
		assert.equal(received()[0]!.notification.data.battery, 20);
		assert.equal(received()[0]!.notification.data.device, "Pixel");
		// Lower, a small charge, positions only: nothing new
		await battery(15);
		await battery(28);
		await h.api("POST", path, { token: upload, body: { positions: [fix(30, AWAY)] } });
		await h.api("POST", path, { token: upload, body: { pausedUntil: null } });
		await sleep(150);
		assert.equal(received().length, 1);
		// Charged 10 points above the threshold: the next discharge is notified again
		await battery(35);
		await battery(19);
		await waitFor(() => received().length === 2);

		// A higher threshold starts again; off
		assert.deepEqual((await h.api("PATCH", alerts, { token: bruno.token, body: { batteryAlert: 40 } })).body, { stopAlertHours: null, batteryAlert: 40 });
		await battery(18);
		await waitFor(() => received().length === 3);
		assert.equal((await h.api("PATCH", alerts, { token: bruno.token, body: { batteryAlert: null } })).body.batteryAlert, null);
		await battery(60);
		await battery(10);
		await sleep(150);
		assert.equal(received().length, 3);
		assert.equal(annaLive.of("notification").length, 0);
		brunoLive.close();
		annaLive.close();
	});

	test("long stop: hours and areas of each user, one per stop", async () => {
		const device = `/api/devices/${phoneId}`;
		const alerts = `${device}/alerts`;
		const annaLive = await h.live(anna.token);
		const brunoLive = await h.live(bruno.token);
		for (const stopAlertHours of [0, 73, 1.5, "2"]) {
			assert.equal((await h.api("PATCH", alerts, { token: anna.token, body: { stopAlertHours } })).status, 400);
		}
		assert.deepEqual((await h.api("PATCH", alerts, { token: anna.token, body: { stopAlertHours: 2 } })).body, { stopAlertHours: 2 });
		assert.equal((await h.api("GET", device, { token: anna.token })).body.stopAlertHours, 2);
		assert.equal((await h.api("GET", device, { token: bruno.token })).body.stopAlertHours, null);
		assert.equal((await h.api("PATCH", alerts, { token: bruno.token, body: { stopAlertHours: 4 } })).body.stopAlertHours, 4);

		const stops = (live: typeof annaLive) => live.of("notification").filter(item => item.notification.kind === "long_stop");
		const shift = () => h.sql`UPDATE positions SET time = time - interval '2 hours' WHERE device_id = ${phoneId} AND status = 0`;
		// Moving 1 hour ago: not yet
		await h.api("POST", path, { token: upload, body: { positions: [fix(3600, FAR, { speed: 30 }), fix(1, FAR, { speed: 0 })] } });
		await runJobs(h.server.ctx);
		await sleep(100);
		assert.equal(stops(annaLive).length, 0);

		// Moving 3 hours ago, still there: Anna (2 hours), not Bruno (4 hours)
		await shift();
		await runJobs(h.server.ctx);
		await waitFor(() => stops(annaLive).length === 1);
		assert.equal(stops(annaLive)[0]!.notification.data.hours, 2);
		assert.equal(stops(annaLive)[0]!.notification.lat, FAR.lat);
		await runJobs(h.server.ctx);
		await sleep(100);
		assert.equal(stops(annaLive).length, 1);
		assert.equal(stops(brunoLive).length, 0);

		// A new stop inside an area of Anna: a known place for her, not for Bruno
		await h.api("POST", path, { token: upload, body: { positions: [fix(1800, FAR, { speed: 20 }), fix(0, FAR, { speed: 0 })] } });
		await shift();
		await shift();
		const area = await h.api("POST", `${device}/geofences`, { token: anna.token, body: { name: "Lavoro", ...FAR, radius: 300 } });
		assert.equal(area.body.inside, true);
		await runJobs(h.server.ctx);
		await waitFor(() => stops(brunoLive).length === 1);
		assert.equal(stops(brunoLive)[0]!.notification.data.hours, 4);
		assert.equal(stops(annaLive).length, 1);
		// Paused or silent phone: not stopped
		await h.api("DELETE", `/api/geofences/${area.body.id}`, { token: anna.token });
		await h.api("POST", path, { token: upload, body: { pausedUntil: new Date(Date.now() + 3600e3).toISOString() } });
		await runJobs(h.server.ctx);
		await sleep(100);
		assert.equal(stops(annaLive).length, 1);
		await h.api("POST", path, { token: upload, body: { pausedUntil: null } });
		await runJobs(h.server.ctx);
		await waitFor(() => stops(annaLive).length === 2);
		assert.equal(stops(brunoLive).length, 1);

		// Off
		assert.equal((await h.api("PATCH", alerts, { token: anna.token, body: { stopAlertHours: null } })).status, 200);
		assert.equal((await h.api("GET", device, { token: anna.token })).body.stopAlertHours, null);
		annaLive.close();
		brunoLive.close();
	});
});
