import assert from "node:assert/strict";
import { after, before, describe, test } from "node:test";
import { notificationText } from "../i18n.ts";
import { monthDays, previousMonth, sendMonthlySummaries } from "../services/summary.ts";
import { Harness, waitFor } from "../test/harness.ts";
import type { Live, User } from "../test/harness.ts";

// Summary of the month: totals per device with the month before, deadlines coming up, and
// the notification of the start of the month

test("months, texts of the notification", () => {
	assert.deepEqual(monthDays("2024-02"), { from: "2024-02-01", to: "2024-02-29" });
	assert.deepEqual(monthDays("2026-12"), { from: "2026-12-01", to: "2026-12-31" });
	assert.equal(previousMonth("2026-01"), "2025-12");
	assert.equal(previousMonth("2026-11"), "2026-10");
	const data = { device: "", month: "2026-10", distanceKm: 1234.5, trips: 42, cost: 156.4, time: "2026-11-01T08:00:00Z" };
	assert.deepEqual(notificationText("it", "monthly_summary", data, "Europe/Rome"),
		{ title: "Il tuo mese di ottobre", body: "1.235 km · 42 viaggi · 156,40 € di costi" });
	assert.deepEqual(notificationText("en", "monthly_summary", { ...data, trips: 1, cost: null }, "Europe/Rome"),
		{ title: "Your October", body: "1,235 km · 1 trip" });
});

describe("summary of the month", { skip: !process.env.TEST_DATABASE_URL && "TEST_DATABASE_URL not set" }, () => {
	let h: Harness;
	let anna: User;
	let bruno: User;
	let vehicle: number;
	let month: string;
	let earlier: string;
	let live: Live;

	before(async () => {
		h = await Harness.start();
		anna = await h.onboard("anna@example.com", "Anna");
		bruno = await h.onboard("bruno@example.com", "Bruno");
		vehicle = (await h.api("POST", "/api/vehicles", { token: anna.token, body: { name: "Punto" } })).body.id;
		const tz = h.server.ctx.config.TIMEZONE;
		const today = (await h.sql<{ day: string }[]>`SELECT to_char(now() AT TIME ZONE ${tz}, 'YYYY-MM-DD') AS day`)[0]!.day;
		month = previousMonth(today.slice(0, 7));
		earlier = previousMonth(month);
		const stat = (day: string, km: number, trips: number) => ({
			device_id: vehicle, day, distance_km: km, business_km: km / 2, personal_km: 0, driving_min: trips * 30, trips, max_speed: 110,
			rest_voltage: null, min_voltage: null, traffic_bytes: 0, alarms: 0
		});
		await h.sql`INSERT INTO daily_stats ${h.sql([stat(`${month}-03`, 100, 2), stat(`${month}-15`, 50, 1), stat(`${earlier}-10`, 80, 3)])}`;
		await h.api("POST", `/api/devices/${vehicle}/rates`, { token: anna.token, body: { kind: "wear", validFrom: "2020-01-01", value: 0.1 } });
		await h.api("POST", `/api/devices/${vehicle}/refuels`, { token: anna.token, body: { day: `${month}-02`, litres: 30, cost: 57, odometerKm: 1000 } });
		await h.api("POST", `/api/devices/${vehicle}/refuels`, { token: anna.token, body: { day: `${month}-20`, litres: 40, cost: 78, odometerKm: 1500 } });
		await h.api("POST", `/api/devices/${vehicle}/maintenance`, { token: anna.token, body: { kind: "tax", dueDate: today, remindDays: 30 } });
		await h.api("POST", `/api/devices/${vehicle}/maintenance`, { token: anna.token, body: { kind: "inspection", dueDate: "2099-01-01" } });
		live = await h.live(anna.token);
	});
	after(async () => {
		live?.close();
		await h?.close();
	});

	test("totals per device, month before, deadlines", async () => {
		// Mileage allowance of the business km from the month: 0.40 €/km
		await h.api("POST", `/api/devices/${vehicle}/rates`, { token: anna.token, body: { kind: "reimbursement", validFrom: `${month}-01`, value: 0.4 } });
		const summary = (await h.api("GET", `/api/summary/${month}`, { token: anna.token })).body;
		assert.deepEqual([summary.month, summary.from, summary.complete], [month, `${month}-01`, true]);
		const [car] = summary.devices;
		assert.deepEqual([car.name, car.distanceKm, car.businessKm, car.trips, car.drivingMin, car.maxSpeed], ["Punto", 150, 75, 3, 90, 110]);
		// Price and consumption from the refuels: 150 km at 8 l/100 km and 1.90 €/l
		assert.deepEqual(car.cost, { fuelL: 12, fuelCost: 22.8, wearCost: 15, cost: 37.8 });
		assert.deepEqual(car.refuels, { count: 2, litres: 70, cost: 135, consumption: 8 });
		assert.deepEqual([car.trafficBytes, car.reimbursement, car.energyUnit], [null, 30, "l"]);
		assert.deepEqual(summary.totals, { distanceKm: 150, drivingMin: 90, trips: 3, cost: 37.8, refuelCost: 135, reimbursement: 30 });
		// Before the first refuel its values hold: 80 km at 8 l/100 km and 1.90 €/l, plus the wear; the
		// first allowance holds before its day too
		assert.deepEqual(summary.previous, { distanceKm: 80, drivingMin: 90, trips: 3, cost: 20.16, refuelCost: null, reimbursement: 16 });
		await h.api("DELETE", `/api/devices/${vehicle}/rates/reimbursement/${month}-01`, { token: anna.token });
		assert.deepEqual(summary.deadlines.map((item: { kind: string; state: string }) => [item.kind, item.state]), [["tax", "due"]]);

		// Bruno has no devices; months out of range
		assert.deepEqual((await h.api("GET", `/api/summary/${month}`, { token: bruno.token })).body.devices, []);
		for (const value of ["2026-13", "2026-1", "1990-01", "2999-01"]) {
			assert.equal((await h.api("GET", `/api/summary/${value}`, { token: anna.token })).status, 400, value);
		}
	});

	test("notification at the start of the month, once, for who wants it", async () => {
		const [year, number] = month.split("-").map(Number) as [number, number];
		// The first of the next month at 6 local time: too early; at 9 the summary
		const first = (hour: number) => new Date(`${new Date(Date.UTC(year, number, 1)).toISOString().slice(0, 10)}T${String(hour - 1).padStart(2, "0")}:00:00Z`);
		assert.equal(await sendMonthlySummaries(h.server.ctx, first(6)), 0);
		assert.equal(await sendMonthlySummaries(h.server.ctx, first(10)), 1);
		await waitFor(() => live.of("notification").some(item => item.notification.kind === "monthly_summary"));
		const { notification } = live.of("notification").find(item => item.notification.kind === "monthly_summary")!;
		assert.equal(notification.deviceId, null);
		assert.deepEqual([notification.data.month, notification.data.distanceKm, notification.data.trips, notification.data.cost], [month, 150, 3, 37.8]);
		assert.equal(await sendMonthlySummaries(h.server.ctx, first(11)), 0);

		// The preference in the account
		assert.equal((await h.api("GET", "/api/account", { token: anna.token })).body.monthlySummary, true);
		assert.equal((await h.api("PATCH", "/api/account", { token: anna.token, body: { monthlySummary: "no" } })).status, 400);
		await h.api("PATCH", "/api/account", { token: anna.token, body: { monthlySummary: false } });
		assert.equal((await h.api("GET", "/api/account", { token: anna.token })).body.monthlySummary, false);
		await h.sql`DELETE FROM monthly_summaries`;
		assert.equal(await sendMonthlySummaries(h.server.ctx, first(10)), 0);
		assert.equal((await h.api("GET", "/api/account/export", { token: anna.token })).body.profile.monthlySummary, false);
	});
});
