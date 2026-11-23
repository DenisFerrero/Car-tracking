import assert from "node:assert/strict";
import { after, before, describe, test } from "node:test";
import { Harness } from "../test/harness.ts";
import type { User } from "../test/harness.ts";
import { measure, summary } from "../services/refuels.ts";
import type { Refuel } from "../services/refuels.ts";
import { MAX_REFUELS } from "./refuels.ts";

// Refuels: real consumption between two full tanks, price per litre, the costs of the trips
// and the dashboards fed by them

test("consumption between full tanks, partial refuels, wrong readings", () => {
	let id = 0;
	const refuel = (day: string, litres: number, odometerKm: number | null, full = true, cost: number | null = null): Refuel =>
		({ id: ++id, day, litres, cost, odometerKm, full, note: "" });
	const measured = measure([
		refuel("2026-10-20", 40, 10_600, true, 76),
		// First full tank: nothing to measure; then a partial one, counted in the next interval
		refuel("2026-10-01", 35, 10_000),
		refuel("2026-10-10", 10, 10_300, false, 20),
		// No odometer: the interval can't be measured, the next one starts here
		refuel("2026-11-01", 30, null),
		refuel("2026-11-10", 30, 11_000),
		// Odometer going back, then 1 litre in 900 km: wrong readings
		refuel("2026-11-12", 20, 10_900),
		refuel("2026-11-20", 1, 11_800)
	]);
	assert.deepEqual(measured.map(item => item.day), ["2026-10-01", "2026-10-10", "2026-10-20", "2026-11-01", "2026-11-10", "2026-11-12", "2026-11-20"]);
	assert.deepEqual(measured.map(item => item.consumption), [null, null, 8.33, null, null, null, null]);
	assert.deepEqual([measured[2]!.km, measured[2]!.since, measured[2]!.pricePerLitre], [600, "2026-10-01", 1.9]);
	assert.equal(measured[1]!.pricePerLitre, 2);
	assert.equal(measured[6]!.since, null);
	assert.deepEqual(summary(measured), { count: 7, litres: 166, cost: 96, averageConsumption: 8.33, lastConsumption: 8.33, measuredKm: 600 });
	assert.deepEqual(summary([]), { count: 0, litres: 0, cost: null, averageConsumption: null, lastConsumption: null, measuredKm: 0 });
});

describe("refuels", { skip: !process.env.TEST_DATABASE_URL && "TEST_DATABASE_URL not set" }, () => {
	let h: Harness;
	let anna: User;
	let bruno: User;
	let vehicle: number;
	let today: string;
	const day = (offset: number) => new Date(Date.parse(today) + offset * 86400e3).toISOString().slice(0, 10);

	before(async () => {
		h = await Harness.start();
		anna = await h.onboard("anna@example.com", "Anna");
		bruno = await h.onboard("bruno@example.com", "Bruno");
		vehicle = (await h.api("POST", "/api/vehicles", { token: anna.token, body: { name: "Punto" } })).body.id;
		const tz = h.server.ctx.config.TIMEZONE;
		today = (await h.sql<{ day: string }[]>`SELECT to_char(now() AT TIME ZONE ${tz}, 'YYYY-MM-DD') AS day`)[0]!.day;
	});
	after(async () => {
		await h?.close();
	});

	test("added, measured, changed, removed; prices and consumptions in the costs", async () => {
		const path = `/api/devices/${vehicle}/refuels`;
		const empty = (await h.api("GET", path, { token: anna.token })).body;
		assert.deepEqual(empty, {
			refuels: [], summary: { count: 0, litres: 0, cost: null, averageConsumption: null, lastConsumption: null, measuredKm: 0 },
			ratesFromRefuels: true, fuelUnit: "l_per_100km", odometerKm: null
		});
		assert.equal((await h.api("GET", path, { token: bruno.token })).status, 404);
		const phone = (await h.api("POST", "/api/phones", { token: anna.token, body: { name: "Pixel" } })).body.id;
		assert.equal((await h.api("GET", `/api/devices/${phone}/refuels`, { token: anna.token })).body.error, "not_a_vehicle");
		for (const body of [{ litres: 0 }, { litres: 501 }, { litres: 30, cost: -1 }, { litres: 30, odometerKm: 1.5 }, { litres: 30, day: "1999-12-31" },
			{ litres: 30, note: "x".repeat(201) }, { litres: 30, extra: true }, {}]) {
			assert.equal((await h.api("POST", path, { token: anna.token, body })).status, 400, JSON.stringify(body));
		}
		assert.equal((await h.api("POST", path, { token: anna.token, body: { litres: 30, day: day(2) } })).body.error, "refuel_future");

		await h.api("POST", path, { token: anna.token, body: { day: day(-30), litres: 35, cost: 64.75, odometerKm: 20_000 } });
		await h.api("POST", path, { token: anna.token, body: { day: day(-20), litres: 15, cost: 28.5, odometerKm: 20_400, full: false } });
		const third = (await h.api("POST", path, { token: anna.token, body: { day: day(-10), litres: 25, cost: 47.5, odometerKm: 21_000, note: " Autostrada " } })).body;
		assert.equal(third.refuels.length, 3);
		const [last] = third.refuels;
		// 15 + 25 litres in 1000 km
		assert.deepEqual([last.day, last.km, last.consumption, last.since, last.pricePerLitre, last.note], [day(-10), 1000, 4, day(-30), 1.9, "Autostrada"]);
		assert.deepEqual(third.summary, { count: 3, litres: 75, cost: 140.75, averageConsumption: 4, lastConsumption: 4, measuredKm: 1000 });

		// The costs of the trips: price from the day of each refuel, consumption from the start of the interval
		const profile = (await h.api("GET", `/api/devices/${vehicle}/vehicle`, { token: anna.token })).body;
		assert.deepEqual(profile.rates.price.map((item: { validFrom: string; value: number; source: string }) => [item.validFrom, item.value, item.source]),
			[[day(-10), 1.9, "refuel"], [day(-20), 1.9, "refuel"], [day(-30), 1.85, "refuel"]]);
		assert.deepEqual(profile.rates.consumption, [{ validFrom: day(-30), value: 4, source: "refuel" }]);
		assert.equal(profile.ratesFromRefuels, true);

		// A value of the owner on the same day wins and stays when the refuels change
		await h.api("POST", `/api/devices/${vehicle}/rates`, { token: anna.token, body: { kind: "price", validFrom: day(-20), value: 2.05 } });
		const changed = (await h.api("PATCH", `/api/refuels/${last.id}`, { token: anna.token, body: { litres: 35, cost: null } })).body;
		assert.equal(changed.refuels[0].consumption, 5);
		assert.equal(changed.refuels[0].pricePerLitre, null);
		const after = (await h.api("GET", `/api/devices/${vehicle}/vehicle`, { token: anna.token })).body;
		assert.deepEqual(after.rates.price.map((item: { value: number; source: string }) => [item.value, item.source]), [[2.05, "manual"], [1.85, "refuel"]]);
		assert.deepEqual(after.rates.consumption.map((item: { value: number }) => item.value), [5]);
		for (const body of [{ litres: -1 }, { day: "tomorrow" }, { full: "yes" }]) {
			assert.equal((await h.api("PATCH", `/api/refuels/${last.id}`, { token: anna.token, body })).status, 400);
		}
		assert.equal((await h.api("PATCH", `/api/refuels/${last.id}`, { token: anna.token, body: { day: day(3) } })).body.error, "refuel_future");
		assert.equal((await h.api("PATCH", `/api/refuels/${last.id}`, { token: bruno.token, body: { note: "x" } })).status, 404);
		const kept = (await h.api("PATCH", `/api/refuels/${last.id}`, { token: anna.token, body: { odometerKm: null, full: true, note: "" } })).body;
		assert.equal(kept.refuels[0].consumption, null);
		await h.api("PATCH", `/api/refuels/${last.id}`, { token: anna.token, body: { odometerKm: 21_000, day: day(-10), cost: 47.5 } });

		// The owner turns them off: only the values entered remain
		const off = (await h.api("PUT", `/api/devices/${vehicle}/vehicle`, { token: anna.token, body: { fuelUnit: "km_per_l", ratesFromRefuels: false } })).body;
		assert.deepEqual([off.ratesFromRefuels, off.rates.price.length, off.rates.consumption.length], [false, 1, 0]);
		const unchanged = (await h.api("PUT", `/api/devices/${vehicle}/vehicle`, { token: anna.token, body: { fuelUnit: "km_per_l" } })).body;
		assert.equal(unchanged.ratesFromRefuels, false);
		await h.api("PUT", `/api/devices/${vehicle}/vehicle`, { token: anna.token, body: { fuelUnit: "l_per_100km", ratesFromRefuels: true } });

		// The national average doesn't replace the real prices of the last 14 days
		await h.sql`INSERT INTO fuel_averages (fuel, week, price) VALUES ('petrol', ${day(-1)}, 1.7)`;
		await h.api("PUT", `/api/devices/${vehicle}/vehicle`, { token: anna.token, body: { fuelUnit: "l_per_100km", fuelType: "petrol", fuelPriceAuto: true } });
		assert.equal(await h.server.ctx.fuel.applyAuto(vehicle), 0);
		await h.sql`UPDATE refuels SET day = day - 30 WHERE device_id = ${vehicle}`;
		assert.equal(await h.server.ctx.fuel.applyAuto(vehicle), 1);
		await h.sql`UPDATE refuels SET day = day + 30 WHERE device_id = ${vehicle}`;

		// The odometer of today, to fill in the next refuel
		await h.api("PUT", `/api/devices/${vehicle}/odometer`, { token: anna.token, body: { km: 21_500 } });
		assert.equal((await h.api("GET", path, { token: anna.token })).body.odometerKm, 21_500);

		// In the export of the personal data
		const exported = (await h.api("GET", "/api/account/export", { token: anna.token })).body;
		assert.equal(exported.refuels.length, 3);
		assert.equal(exported.vehicles.find((item: { deviceId: number }) => item.deviceId === vehicle).ratesFromRefuels, true);

		assert.equal((await h.api("DELETE", `/api/refuels/${last.id}`, { token: bruno.token })).status, 404);
		const removed = (await h.api("DELETE", `/api/refuels/${last.id}`, { token: anna.token })).body;
		assert.deepEqual([removed.refuels.length, removed.summary.averageConsumption], [2, null]);
		assert.equal((await h.api("DELETE", `/api/refuels/${last.id}`, { token: anna.token })).status, 404);
		const none = (await h.api("GET", `/api/devices/${vehicle}/vehicle`, { token: anna.token })).body;
		assert.equal(none.rates.consumption.length, 0);
	});

	test("dashboards: amount, litres, price and consumption of the refuels", async () => {
		await h.sql`DELETE FROM refuels`;
		const path = `/api/devices/${vehicle}/refuels`;
		await h.api("POST", path, { token: anna.token, body: { day: day(-40), litres: 30, cost: 54, odometerKm: 30_000 } });
		await h.api("POST", path, { token: anna.token, body: { day: day(-5), litres: 30, cost: 60, odometerKm: 30_500 } });
		await h.api("POST", path, { token: anna.token, body: { day: day(-5), litres: 10, cost: 21, odometerKm: 30_510, full: false } });
		const data = async (metric: string, view = "number", period = "30d") => (await h.api("POST", "/api/dashboards/data", {
			token: anna.token, body: { period, widgets: [{ id: "w", metric, view, devices: "all" }] }
		})).body.results.w;
		assert.equal((await data("refuelCost")).value, 81);
		assert.equal((await data("refuelLitres")).value, 40);
		assert.equal((await data("refuelPrice")).value, 2.1);
		// The interval started before the period: measured anyway
		assert.equal((await data("realConsumption")).value, 6);
		assert.equal((await data("refuelCost", "number", "90d")).value, 135);
		const bars = await data("refuelCost", "bars");
		assert.deepEqual(bars.series[0].points, [[day(-5), 81]]);
		assert.deepEqual((await data("refuelLitres", "vehicles")).values, [{ deviceId: vehicle, value: 40 }]);
		// Not for phones
		const phone = (await h.api("GET", "/api/devices", { token: anna.token })).body.find((item: { kind: string }) => item.kind === "phone").id;
		const widget = await h.api("POST", "/api/dashboards/data", { token: anna.token, body: { widgets: [{ id: "w", metric: "refuelCost", view: "number", devices: [phone] }] } });
		assert.deepEqual(widget.body.results.w.unavailable, [phone]);
	});

	test("at most MAX_REFUELS per vehicle", async () => {
		await h.sql`
			INSERT INTO refuels (device_id, day, litres)
			SELECT ${vehicle}, '2010-01-01'::date + n, 30 FROM generate_series(1, ${MAX_REFUELS - (await h.sql<{ count: number }[]>`SELECT count(*)::int AS count FROM refuels`)[0]!.count}) n`;
		assert.equal((await h.api("POST", `/api/devices/${vehicle}/refuels`, { token: anna.token, body: { litres: 30 } })).body.error, "too_many_refuels");
	});
});
