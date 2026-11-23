import assert from "node:assert/strict";
import { after, before, describe, test } from "node:test";
import { STATUS } from "../protocol/protocol.ts";
import { promptParking, runParkings } from "../services/parking.ts";
import { Harness, Tracker, point, sleep, waitFor } from "../test/harness.ts";
import type { Live, User } from "../test/harness.ts";

// Parking of a vehicle: the place from the latest position, the optional end of the ticket
// with its reminder and its notification, the end when the vehicle leaves or by hand, the
// proposal at the ignition off

describe("parking", { skip: !process.env.TEST_DATABASE_URL && "TEST_DATABASE_URL not set" }, () => {
	let h: Harness;
	let anna: User;
	let bruno: User;
	let tracker: Tracker;
	let car: number;
	let vehicle: number;
	let live: Live;
	const IMEI = "860000000000301";
	const notices = (kind: string) => live.of("notification").filter(item => item.notification.kind === kind);
	const inMinutes = (minutes: number) => new Date(Date.now() + minutes * 60e3).toISOString();

	before(async () => {
		h = await Harness.start();
		anna = await h.onboard("anna@example.com", "Anna");
		bruno = await h.onboard("bruno@example.com", "Bruno");
		car = await h.claim(anna, IMEI, "Golf");
		tracker = await Tracker.connect(h, IMEI);
		await tracker.hello();
		vehicle = (await h.api("POST", "/api/vehicles", { token: anna.token, body: { name: "Panda" } })).body.id;
		live = await h.live(anna.token);
	});
	after(async () => {
		live?.close();
		await tracker?.close();
		await h?.close();
	});

	test("set where the vehicle is, with or without the end of the ticket, changed, ended by hand", async () => {
		const path = `/api/devices/${car}/parking`;
		assert.deepEqual((await h.api("GET", path, { token: anna.token })).body, { parking: null, position: null, prompt: false });
		assert.equal((await h.api("GET", path, { token: bruno.token })).status, 404);
		const phone = (await h.api("POST", "/api/phones", { token: anna.token, body: { name: "Pixel" } })).body.id;
		assert.equal((await h.api("GET", `/api/devices/${phone}/parking`, { token: anna.token })).body.error, "not_a_vehicle");

		tracker.send([point(new Date(Date.now() - 60e3), 45.07, 7.68, { status: STATUS.ENGINE_OFF, speed: 0 })]);
		await waitFor(async () => (await h.api("GET", path, { token: anna.token })).body.position !== null);
		for (const body of [{ expiresAt: inMinutes(-1) }, { expiresAt: inMinutes(32 * 24 * 60) }, { lat: 45 }, { remindMinutes: 121 }, { note: "x".repeat(201) }, { extra: 1 }]) {
			assert.equal((await h.api("PUT", path, { token: anna.token, body })).status, 400, JSON.stringify(body));
		}
		assert.equal((await h.api("PUT", path, { token: anna.token, body: { expiresAt: inMinutes(-1) } })).body.error, "parking_past");
		assert.equal((await h.api("PUT", path, { token: anna.token, body: { expiresAt: inMinutes(32 * 24 * 60) } })).body.error, "parking_too_long");

		// Paid by the minute: no end
		const free = (await h.api("PUT", path, { token: anna.token, body: { note: " Piano -2 " } })).body.parking;
		assert.deepEqual([free.lat, free.lon, free.expiresAt, free.remindMinutes, free.note, free.userId], [45.07, 7.68, null, 10, "Piano -2", anna.id]);
		// Ticket until in 12 minutes, the place chosen on the map
		const ticket = (await h.api("PUT", path, { token: anna.token, body: { lat: 45.1, lon: 7.7, expiresAt: inMinutes(12), remindMinutes: 15 } })).body.parking;
		assert.deepEqual([ticket.id, ticket.lat, ticket.note], [free.id, 45.1, ""]);
		assert.ok(Math.abs(Date.parse(ticket.expiresAt) - Date.now() - 12 * 60e3) < 5000);

		assert.deepEqual((await h.api("DELETE", path, { token: anna.token })).body.parking, null);
		assert.equal((await h.api("DELETE", path, { token: anna.token })).status, 404);
		// The vehicle without a tracker and without positions: no place
		const other = (await h.api("PUT", `/api/devices/${vehicle}/parking`, { token: anna.token, body: {} })).body;
		assert.deepEqual([other.parking.lat, other.position], [null, null]);
		await h.api("DELETE", `/api/devices/${vehicle}/parking`, { token: anna.token });
	});

	test("reminder before the end, notification at the end, once; late ends not notified", async () => {
		const path = `/api/devices/${car}/parking`;
		await h.api("PUT", path, { token: anna.token, body: { expiresAt: inMinutes(30) } });
		await runParkings(h.server.ctx);
		assert.equal(notices("parking_reminder").length, 0);
		// A new end: the reminder again
		await h.api("PUT", path, { token: anna.token, body: { expiresAt: inMinutes(8), remindMinutes: 10 } });
		await runParkings(h.server.ctx);
		await runParkings(h.server.ctx);
		await waitFor(() => notices("parking_reminder").length === 1);
		const reminder = notices("parking_reminder")[0]!.notification;
		assert.deepEqual([reminder.deviceId, reminder.data.device, reminder.data.minutes, reminder.lat], [car, "Golf", 8, 45.07]);
		// The same end again: no new reminder
		const same = (await h.api("GET", path, { token: anna.token })).body.parking.expiresAt;
		await h.api("PUT", path, { token: anna.token, body: { expiresAt: same, remindMinutes: 10, note: "Strisce blu" } });
		await runParkings(h.server.ctx);
		await sleep(100);
		assert.equal(notices("parking_reminder").length, 1);

		await h.sql`UPDATE parkings SET expires_at = now() - interval '1 minute' WHERE device_id = ${car} AND ended_at IS NULL`;
		await runParkings(h.server.ctx);
		await runParkings(h.server.ctx);
		await waitFor(() => notices("parking_expired").length === 1);
		assert.equal(notices("parking_expired")[0]!.notification.data.device, "Golf");

		// Ended two hours ago while the backend was down: only marked
		await h.api("PUT", `/api/devices/${vehicle}/parking`, { token: anna.token, body: { expiresAt: inMinutes(60) } });
		await h.sql`UPDATE parkings SET expires_at = now() - interval '2 hours', reminded_at = now() WHERE device_id = ${vehicle} AND ended_at IS NULL`;
		await runParkings(h.server.ctx);
		await sleep(100);
		assert.equal(notices("parking_expired").length, 1);
		const [row] = await h.sql<{ notified: boolean }[]>`SELECT expired_notified_at IS NOT NULL AS notified FROM parkings WHERE device_id = ${vehicle} AND ended_at IS NULL`;
		assert.equal(row!.notified, true);
		await h.api("DELETE", `/api/devices/${vehicle}/parking`, { token: anna.token });
	});

	test("ended when the vehicle leaves; old parkings removed", async () => {
		await h.sql`UPDATE parkings SET started_at = now() - interval '10 minutes' WHERE device_id = ${car} AND ended_at IS NULL`;
		// Still: the parking stays
		tracker.send([point(new Date(Date.now() - 30e3), 45.07, 7.68, { status: STATUS.HEARTBEAT, speed: 0 })]);
		await sleep(200);
		await runParkings(h.server.ctx);
		assert.notEqual((await h.api("GET", `/api/devices/${car}/parking`, { token: anna.token })).body.parking, null);
		tracker.send([point(new Date(Date.now() - 20e3), 45.08, 7.69, { speed: 45 })]);
		await sleep(200);
		await runParkings(h.server.ctx);
		assert.equal((await h.api("GET", `/api/devices/${car}/parking`, { token: anna.token })).body.parking, null);

		await h.sql`UPDATE parkings SET ended_at = now() - interval '31 days' WHERE device_id = ${car}`;
		await runParkings(h.server.ctx);
		const [count] = await h.sql<{ count: number }[]>`SELECT count(*)::int AS count FROM parkings WHERE device_id = ${car}`;
		assert.equal(count!.count, 0);
	});

	test("proposal at the ignition off: owners who want it, fresh points, once in a while, not while parked", async () => {
		const prompt = `/api/devices/${car}/parking/prompt`;
		assert.equal((await h.api("PUT", `/api/devices/${vehicle}/parking/prompt`, { token: anna.token, body: { enabled: true } })).body.error, "not_a_tracker");
		assert.equal((await h.api("PUT", prompt, { token: anna.token, body: { enabled: "yes" } })).status, 400);
		// Off: nothing
		tracker.send([point(new Date(Date.now() - 10e3), 45.07, 7.68, { status: STATUS.ENGINE_OFF, speed: 0 })]);
		await sleep(300);
		assert.equal(notices("parking_prompt").length, 0);
		assert.equal((await h.api("PUT", prompt, { token: anna.token, body: { enabled: true } })).body.prompt, true);
		// A point of the offline queue, 20 minutes old: nothing
		tracker.send([point(new Date(Date.now() - 20 * 60e3), 45.07, 7.68, { status: STATUS.ENGINE_OFF, speed: 0 })]);
		await sleep(300);
		assert.equal(notices("parking_prompt").length, 0);
		tracker.send([point(new Date(Date.now() - 5e3), 45.07, 7.68, { status: STATUS.ENGINE_OFF, speed: 0 })]);
		await waitFor(() => notices("parking_prompt").length === 1);
		const proposal = notices("parking_prompt")[0]!.notification;
		assert.deepEqual([proposal.deviceId, proposal.lat, proposal.lon], [car, 45.07, 7.68]);
		// Again a few minutes later: nothing
		tracker.send([point(new Date(Date.now() - 2e3), 45.07, 7.68, { status: STATUS.ENGINE_OFF, speed: 0 })]);
		await sleep(300);
		assert.equal(notices("parking_prompt").length, 1);
		// Already parked: nothing (later than the pause between proposals)
		await h.api("PUT", `/api/devices/${car}/parking`, { token: anna.token, body: {} });
		const off = [{ time: new Date(), status: STATUS.ENGINE_OFF, lat: 45.07, lon: 7.68 }];
		assert.equal(await promptParking(h.server.ctx, car, off, Date.now() + 11 * 60e3), false);
		await h.api("DELETE", `/api/devices/${car}/parking`, { token: anna.token });
		assert.equal(await promptParking(h.server.ctx, car, [{ ...off[0]!, time: new Date(Date.now() + 11 * 60e3) }], Date.now() + 11 * 60e3), true);
		await waitFor(() => notices("parking_prompt").length === 2);

		// Removed device: its parkings with it; the tracker paired again starts without the proposal
		await h.api("PUT", `/api/devices/${car}/parking`, { token: anna.token, body: {} });
		await h.api("DELETE", `/api/devices/${car}`, { token: anna.token });
		const [row] = await h.sql<{ count: number; prompt: boolean }[]>`
			SELECT (SELECT count(*)::int FROM parkings WHERE device_id = ${car}) AS count, parking_prompt AS prompt FROM devices WHERE id = ${car}`;
		assert.deepEqual([row!.count, row!.prompt], [0, false]);
	});
});
