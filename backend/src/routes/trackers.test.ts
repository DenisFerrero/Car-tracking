import assert from "node:assert/strict";
import { after, before, describe, test } from "node:test";
import { Harness, Tracker, point, waitFor } from "../test/harness.ts";
import type { User } from "../test/harness.ts";

// Vehicles and trackers: a tracker paired in a vehicle of the user, moved to another
// vehicle (the previous one keeps its history), removed, archived vehicles

const IMEI = "860000000000052";
const OTHER = "860000000000060";

describe("trackers installed in vehicles", { skip: !process.env.TEST_DATABASE_URL && "TEST_DATABASE_URL not set" }, () => {
	let h: Harness;
	let anna: User;
	let bruno: User;

	before(async () => {
		h = await Harness.start();
		anna = await h.onboard("anna@example.com", "Anna");
		bruno = await h.onboard("bruno@example.com", "Bruno");
		await h.befriend(anna, bruno);
	});

	after(async () => {
		await h.close();
	});

	const device = async (user: User, id: number) => (await h.api("GET", `/api/devices/${id}`, { token: user.token })).body;
	const kind = async (id: number) => (await h.sql<{ kind: string }[]>`SELECT kind FROM devices WHERE id = ${id}`)[0]?.kind;

	test("paired in a vehicle of the user: the vehicle keeps its history and gets the tracker", async () => {
		const vehicle = (await h.api("POST", "/api/vehicles", { token: anna.token, body: { name: "Panda", fuelType: "lpg" } })).body.id as number;
		await h.api("PUT", `/api/devices/${vehicle}/odometer`, { token: anna.token, body: { km: 52000 } });
		// The tracker is powered on before the pairing: it has a row and a connection
		const tracker = await Tracker.connect(h, IMEI);
		const free = await tracker.hello();
		const code = h.server.ctx.secrets.pairingCode(IMEI);

		// Name of a new vehicle or an existing vehicle, not both or none
		assert.equal((await h.api("POST", "/api/devices/claim", { token: anna.token, body: { imei: IMEI, code } })).status, 400);
		assert.equal((await h.api("POST", "/api/devices/claim", { token: anna.token, body: { imei: IMEI, code, name: "X", vehicleId: vehicle } })).status, 400);
		// Only vehicles of the user, without a tracker
		assert.equal((await h.api("POST", "/api/devices/claim", { token: bruno.token, body: { imei: IMEI, code, vehicleId: vehicle } })).status, 404);

		const live = await h.live(anna.token);
		const claim = await h.api("POST", "/api/devices/claim", { token: anna.token, body: { imei: IMEI, code, vehicleId: vehicle } });
		assert.deepEqual(claim.body, { id: vehicle, registered: true });
		assert.equal(await kind(vehicle), "tracker");
		assert.equal(await kind(free), undefined);
		await waitFor(() => live.of("access").some(message => message.deviceId === vehicle));
		live.close();

		// Disconnected: at the next connection the ACK carries the id of the vehicle
		await waitFor(() => tracker.closed !== null);
		const again = await Tracker.connect(h, IMEI);
		assert.equal(await again.hello(), vehicle);
		again.send([point(new Date(), 45.1, 9.1)]);
		await waitFor(async () => (await h.sql`SELECT 1 FROM positions WHERE device_id = ${vehicle}`).length === 1);
		await again.close();

		const detail = await device(anna, vehicle);
		assert.equal(detail.kind, "tracker");
		assert.equal(detail.imei, IMEI);
		assert.equal(detail.archived, false);
		assert.equal(detail.installations.length, 1);
		assert.equal(detail.installations[0].imei, IMEI);
		assert.equal((await h.api("GET", `/api/devices/${vehicle}/maintenance`, { token: anna.token })).body.odometerKm, 52000);
		// A vehicle with a tracker isn't fed by the phone and can't be archived
		assert.equal((await h.api("PATCH", `/api/devices/${vehicle}`, { token: anna.token, body: { archived: true } })).body.error, "not_archivable");
		// Paired already: another tracker can't go in the same vehicle
		const otherCode = h.server.ctx.secrets.pairingCode(OTHER);
		assert.equal((await h.api("POST", "/api/devices/claim", { token: anna.token, body: { imei: OTHER, code: otherCode, vehicleId: vehicle } })).body.error, "vehicle_has_tracker");
	});

	test("moved to another vehicle: the history stays, the previous vehicle can be archived", async () => {
		const from = (await h.sql<{ id: number }[]>`SELECT id FROM devices WHERE imei = ${IMEI}`)[0]!.id;
		await h.api("POST", `/api/devices/${from}/shares`, { token: anna.token, body: { userId: bruno.id, expiresAt: null } });
		await h.api("POST", `/api/devices/${from}/commands`, { token: anna.token, body: { type: "locate" } });

		// Only the owner, only vehicles with a tracker, a target of the owner without a tracker
		assert.equal((await h.api("POST", `/api/devices/${from}/tracker/move`, { token: bruno.token, body: { vehicle: { name: "Y" } } })).status, 403);
		assert.equal((await h.api("POST", `/api/devices/${from}/tracker/move`, { token: anna.token, body: {} })).status, 400);
		assert.equal((await h.api("POST", `/api/devices/${from}/tracker/move`, { token: anna.token, body: { vehicleId: from } })).body.error, "vehicle_has_tracker");
		const brunoCar = (await h.api("POST", "/api/vehicles", { token: bruno.token, body: { name: "Golf" } })).body.id as number;
		assert.equal((await h.api("POST", `/api/devices/${from}/tracker/move`, { token: anna.token, body: { vehicleId: brunoCar } })).status, 404);

		const tracker = await Tracker.connect(h, IMEI);
		await tracker.hello();
		const moved = await h.api("POST", `/api/devices/${from}/tracker/move`, {
			token: anna.token, body: { vehicle: { name: "Ypsilon", color: "#00897B", fuelType: "petrol" }, archive: true }
		});
		assert.equal(moved.status, 200);
		const to: number = moved.body.id;
		await waitFor(() => tracker.closed !== null);
		assert.equal(await kind(from), "vehicle");
		assert.equal(await kind(to), "tracker");

		// The previous vehicle: history, odometer, shares; archived, without the pending commands
		const previous = await device(anna, from);
		assert.equal(previous.kind, "vehicle");
		assert.equal(previous.archived, true);
		assert.equal(previous.imei, "");
		assert.equal(previous.installations[0].removedAt !== null, true);
		assert.equal((await h.sql`SELECT 1 FROM positions WHERE device_id = ${from}`).length, 1);
		assert.equal((await h.api("GET", `/api/devices/${from}/maintenance`, { token: anna.token })).body.odometerKm, 52000);
		assert.equal((await h.sql`SELECT 1 FROM commands WHERE device_id = ${from} AND result IS NULL AND NOT superseded`).length, 0);
		assert.equal((await device(bruno, from)).name, "Panda");
		assert.equal((await h.api("GET", `/api/devices/${from}/commands`, { token: anna.token })).body.error, "not_a_tracker");

		// The new vehicle: same hardware, the tracker sends there
		const current = await device(anna, to);
		assert.equal(current.imei, IMEI);
		assert.equal(current.name, "Ypsilon");
		const again = await Tracker.connect(h, IMEI);
		assert.equal(await again.hello(), to);
		await again.close();

		// Archived vehicles come back from the archive; back again to the first vehicle
		assert.equal((await h.api("PATCH", `/api/devices/${from}`, { token: anna.token, body: { archived: false } })).status, 200);
		assert.equal((await device(anna, from)).archived, false);
		assert.equal((await h.api("POST", `/api/devices/${to}/tracker/move`, { token: anna.token, body: { vehicleId: from } })).body.id, from);
		assert.equal((await device(anna, from)).installations.length, 2);
	});

	test("removed: the vehicle stays without tracker, the tracker can be paired again", async () => {
		const id = (await h.sql<{ id: number }[]>`SELECT id FROM devices WHERE imei = ${IMEI}`)[0]!.id;
		assert.equal((await h.api("DELETE", `/api/devices/${id}/tracker`, { token: bruno.token })).status, 403);
		assert.equal((await h.api("DELETE", `/api/devices/${id}/tracker`, { token: anna.token })).status, 200);
		assert.equal((await h.api("DELETE", `/api/devices/${id}/tracker`, { token: anna.token })).body.error, "not_a_tracker");
		assert.equal(await kind(id), "vehicle");
		assert.equal((await h.sql`SELECT 1 FROM positions WHERE device_id = ${id}`).length, 1);
		const check = await h.api("POST", "/api/devices/claim/check", { token: bruno.token, body: { imei: IMEI, code: h.server.ctx.secrets.pairingCode(IMEI) } });
		assert.equal(check.body.available, true);
		const paired = await h.claim(bruno, IMEI, "Golf GTI");
		assert.notEqual(paired, id);
		// The new owner doesn't see the installations of the previous one
		assert.equal((await device(bruno, paired)).installations.length, 1);
		// Deleting the vehicle of a tracker frees the tracker, without history
		assert.equal((await h.api("DELETE", `/api/devices/${paired}`, { token: bruno.token })).status, 200);
		assert.equal((await h.sql`SELECT 1 FROM tracker_installations WHERE vehicle_id = ${paired}`).length, 0);
	});
});
