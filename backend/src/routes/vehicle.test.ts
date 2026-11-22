import assert from "node:assert/strict";
import { after, before, describe, test } from "node:test";
import { resetDailyJobs, runJobs } from "../server.ts";
import { Harness, sleep, waitFor } from "../test/harness.ts";
import type { Live, User } from "../test/harness.ts";
import { MAX_DEADLINES, MAX_RATES } from "./vehicle.ts";

// Statistics over months, battery health, trip log, odometer and deadlines

const IMEI = "860000000000045";
const DAY = 86400e3;

describe("statistics, trip log, car", { skip: !process.env.TEST_DATABASE_URL && "TEST_DATABASE_URL not set" }, () => {
	let h: Harness;
	let anna: User;
	let bruno: User;
	let carla: User;
	let deviceId: number;
	let live: Live;
	const iso = (time: number) => new Date(time).toISOString().slice(0, 10);

	/** A 30 minute trip at 8:00 UTC some days ago, then the car parked with a weak battery */
	async function drive (daysAgo: number, restVoltage: number): Promise<void> {
		const base = Date.parse(`${iso(Date.now() - daysAgo * DAY)}T08:00:00Z`);
		const rows = [];
		for (let minute = 0; minute <= 30; minute++) {
			rows.push({
				time: new Date(base + minute * 60e3), device_id: deviceId, lat: 45 + minute * 0.005, lon: 9, speed: 33,
				status: minute === 30 ? 1 : 0, stale: false, events: minute === 5 ? 1 : 0, voltage: 14.1
			});
		}
		for (const hour of [4, 10]) {
			rows.push({ time: new Date(base + hour * 3600e3), device_id: deviceId, lat: 45.15, lon: 9, speed: 0, status: 2, stale: false, events: 0, voltage: restVoltage });
		}
		await h.sql`INSERT INTO positions ${h.sql(rows)}`;
	}

	before(async () => {
		h = await Harness.start();
		anna = await h.onboard("anna@example.com", "Anna");
		bruno = await h.onboard("bruno@example.com", "Bruno");
		carla = await h.onboard("carla@example.com", "Carla");
		await h.befriend(anna, bruno);
		deviceId = await h.claim(anna, IMEI, "Panda");
		await h.sql`UPDATE devices SET registered_at = now() - interval '20 days' WHERE id = ${deviceId}`;
		await h.api("POST", `/api/devices/${deviceId}/shares`, { token: anna.token, body: { userId: bruno.id, expiresAt: null } });
		for (let daysAgo = 10; daysAgo >= 1; daysAgo--) await drive(daysAgo, 12.05);
		await h.sql`INSERT INTO traffic (time, device_id, frame_type, uplink, bytes) VALUES (now() - interval '2 days', ${deviceId}, 1, true, 1000)`;
		live = await h.live(anna.token);
	});
	after(async () => {
		live?.close();
		await h?.close();
	});

	test("daily summaries, trend, health of the car battery", async () => {
		const path = `/api/devices/${deviceId}/trends`;
		assert.equal((await h.api("GET", path, { token: bruno.token })).body.error, "owner_only");
		assert.equal((await h.api("GET", path, { token: carla.token })).status, 404);
		assert.equal((await h.api("GET", `${path}?months=40`, { token: anna.token })).status, 400);

		resetDailyJobs();
		await runJobs(h.server.ctx);
		const stored = await h.sql<{ day: string; distance_km: number; rest_voltage: number; alarms: number; traffic_bytes: string }[]>`
			SELECT to_char(day, 'YYYY-MM-DD') AS day, distance_km, rest_voltage, alarms, traffic_bytes FROM daily_stats WHERE device_id = ${deviceId} ORDER BY day`;
		const driven = stored.filter(row => row.distance_km > 0);
		assert.equal(driven.length, 10);
		assert.ok(driven.every(row => row.distance_km > 16 && row.distance_km < 17), JSON.stringify(driven[0]));
		assert.ok(driven.every(row => row.rest_voltage === 12.05 && row.alarms === 1));
		assert.ok(stored.some(row => Number(row.traffic_bytes) > 1000));

		// Low resting voltage: one notification, not again at the next run
		await waitFor(() => live.of("notification").some(item => item.notification.kind === "battery_health"));
		const alert = live.of("notification").find(item => item.notification.kind === "battery_health")!;
		assert.equal(alert.notification.data.voltage, 12.05);
		resetDailyJobs();
		await runJobs(h.server.ctx);
		await sleep(100);
		assert.equal(live.of("notification").filter(item => item.notification.kind === "battery_health").length, 1);

		const trends = (await h.api("GET", path, { token: anna.token })).body;
		assert.equal(trends.months.length >= 1, true);
		const total = trends.months.reduce((sum: number, month: { distanceKm: number }) => sum + month.distanceKm, 0);
		assert.ok(total > 160 && total < 170, String(total));
		assert.ok(trends.weeks.length >= 2);
		assert.equal(trends.months.reduce((sum: number, month: { trips: number }) => sum + month.trips, 0), 10);
		assert.equal(trends.battery.state, "low");
		assert.equal(trends.battery.average, 12.05);
		assert.equal(trends.battery.trendPerMonth, 0);
		assert.equal(trends.battery.low, 12.2);
		assert.ok(trends.battery.days.length >= 10);
		assert.equal(trends.odometerKm, null);
		assert.ok(trends.simBudgetBytes > 0);
	});

	test("trip log: purpose and note, statistics, monthly CSV", async () => {
		const day = Date.now() - 2 * DAY;
		const midnight = Date.parse(`${iso(day)}T00:00:00Z`);
		const query = `from=${new Date(midnight - DAY).toISOString()}&to=${new Date(midnight + DAY).toISOString()}`;
		const trips = (await h.api("GET", `/api/devices/${deviceId}/trips?${query}`, { token: anna.token })).body.trips;
		const trip = trips.find((item: { start: string }) => item.start.startsWith(iso(day)));
		assert.equal(trip.purpose, null);
		assert.equal(trip.note, "");

		const tag = `/api/devices/${deviceId}/trips/tag`;
		assert.equal((await h.api("PUT", tag, { token: anna.token, body: { start: trip.start, purpose: "work" } })).status, 400);
		assert.equal((await h.api("PUT", tag, { token: bruno.token, body: { start: trip.start, purpose: "business" } })).body.error, "owner_only");
		assert.equal((await h.api("PUT", tag, { token: anna.token, body: { start: trip.start, purpose: "business", note: "Cliente; Rossi" } })).status, 200);
		const tagged = (await h.api("GET", `/api/devices/${deviceId}/trips?${query}`, { token: anna.token })).body.trips
			.find((item: { start: string }) => item.start === trip.start);
		assert.deepEqual([tagged.purpose, tagged.note], ["business", "Cliente; Rossi"]);
		const [row] = await h.sql<{ business_km: number }[]>`SELECT business_km FROM daily_stats WHERE device_id = ${deviceId} AND day = ${iso(day)}`;
		assert.equal(row!.business_km, trip.distanceKm);
		const other = trips.find((item: { start: string }) => item.start !== trip.start);
		await h.api("PUT", tag, { token: anna.token, body: { start: other.start, purpose: "personal" } });

		const month = iso(day).slice(0, 7);
		const logbook = `/api/devices/${deviceId}/logbook`;
		assert.equal((await h.api("GET", `${logbook}?month=2026-13`, { token: anna.token })).status, 400);
		assert.equal((await h.api("GET", `${logbook}?month=${month}`, { token: bruno.token })).status, 403);
		const english = await h.api("GET", `${logbook}?month=${month}`, { token: anna.token });
		assert.match(String(english.headers.get("content-disposition")), new RegExp(`Panda-${month}\\.csv`));
		assert.match(english.body, /^Date,Start,End,/);
		assert.match(english.body, /Business,"Cliente; Rossi"/);
		await h.api("PATCH", "/api/account", { token: anna.token, body: { locale: "it" } });
		const italian = (await h.api("GET", `${logbook}?month=${month}`, { token: anna.token })).body as string;
		assert.match(italian, /^Data;Partenza;Arrivo;/);
		assert.match(italian, /Totale lavoro;;;;;16,\d;/);
		assert.match(italian, /Lavoro;"Cliente; Rossi"/);
		await h.api("PATCH", "/api/account", { token: anna.token, body: { locale: "en" } });

		// Costs: profile, then price, consumption and wear over time
		const vehicle = `/api/devices/${deviceId}/vehicle`;
		const empty = {
			model: "", fuelUnit: "l_per_100km", fuelType: null, fuelPriceAuto: false, rates: { price: [], consumption: [], wear: [] },
			current: { price: null, consumption: null, wear: null }, costPerKm: null, average: null
		};
		assert.deepEqual((await h.api("GET", vehicle, { token: anna.token })).body, empty);
		assert.equal((await h.api("GET", vehicle, { token: bruno.token })).body.error, "owner_only");
		for (const body of [{ fuelUnit: "mpg" }, { fuelUnit: "km_per_l", fuelType: "kerosene" }, { fuelUnit: "km_per_l", fuelPriceAuto: true },
			{ fuelUnit: "km_per_l", consumption: 5 }]) {
			assert.equal((await h.api("PUT", vehicle, { token: anna.token, body })).status, 400, JSON.stringify(body));
		}
		assert.equal((await h.api("PUT", vehicle, { token: bruno.token, body: { fuelUnit: "km_per_l" } })).body.error, "owner_only");
		const saved = await h.api("PUT", vehicle, { token: anna.token, body: { model: " Panda 1.2 ", fuelUnit: "km_per_l", fuelType: "petrol" } });
		assert.deepEqual(saved.body, { ...empty, model: "Panda 1.2", fuelUnit: "km_per_l", fuelType: "petrol" });
		assert.deepEqual((await h.api("GET", vehicle, { token: anna.token })).body, saved.body);

		// Values from a day: each trip with the ones of its day; consumption in either unit
		const rates = `/api/devices/${deviceId}/rates`;
		for (const body of [{ kind: "price", value: 0 }, { kind: "price", value: 11 }, { kind: "consumption", value: 0.5 },
			{ kind: "consumption", value: 1, unit: "km_per_l" }, { kind: "wear", value: -1 }, { kind: "tax", value: 1 },
			{ kind: "price", validFrom: "1999-12-31", value: 1 }, { kind: "price", validFrom: "yesterday", value: 1 }, { kind: "price", value: 1, extra: 1 }]) {
			assert.equal((await h.api("POST", rates, { token: anna.token, body })).status, 400, JSON.stringify(body));
		}
		assert.equal((await h.api("POST", rates, { token: bruno.token, body: { kind: "price", value: 1.8 } })).body.error, "owner_only");
		await h.api("POST", rates, { token: anna.token, body: { kind: "price", validFrom: iso(day - 10 * DAY), value: 1.6 } });
		await h.api("POST", rates, { token: anna.token, body: { kind: "price", validFrom: iso(day), value: 1.9 } });
		await h.api("POST", rates, { token: anna.token, body: { kind: "price", validFrom: iso(day), value: 2 } });
		// 20 km/l = 5 l/100 km; older and heavier consumption before the period
		await h.api("POST", rates, { token: anna.token, body: { kind: "consumption", validFrom: iso(day - 20 * DAY), value: 10, unit: "km_per_l" } });
		await h.api("POST", rates, { token: anna.token, body: { kind: "consumption", validFrom: iso(day - 10 * DAY), value: 20, unit: "km_per_l" } });
		await h.api("POST", rates, { token: anna.token, body: { kind: "wear", validFrom: iso(day - 10 * DAY), value: 0.1 } });
		const latest = (await h.api("POST", rates, { token: anna.token, body: { kind: "price", value: 1.8 } })).body;
		assert.deepEqual(latest.rates.price.map((item: { value: number }) => item.value), [1.8, 2, 1.6]);
		assert.deepEqual(latest.rates.consumption.map((item: { value: number }) => item.value), [5, 10]);
		assert.deepEqual([latest.current, latest.costPerKm], [{ price: 1.8, consumption: 5, wear: 0.1 }, 0.19]);
		const priced = (await h.api("GET", `/api/devices/${deviceId}/trips?${query}`, { token: anna.token })).body;
		const cost = priced.trips.find((item: { start: string }) => item.start === trip.start).cost;
		assert.ok(Math.abs(cost.fuelL - trip.distanceKm * 0.05) < 0.006);
		assert.ok(Math.abs(cost.fuelCost - trip.distanceKm * 0.1) < 0.011, JSON.stringify(cost));
		assert.ok(Math.abs(cost.wearCost - trip.distanceKm * 0.1) < 0.006);
		const sum = priced.trips.reduce((total: number, item: { cost: { cost: number } }) => total + item.cost.cost, 0);
		assert.ok(Math.abs(priced.totals.cost.cost - sum) < 0.001 && priced.totals.cost.cost > cost.cost);

		const removed = (await h.api("DELETE", `${rates}/price/${latest.rates.price[0].validFrom}`, { token: anna.token })).body;
		assert.deepEqual([removed.rates.price.length, removed.current.price], [2, 2]);
		assert.equal((await h.api("DELETE", `${rates}/price/${latest.rates.price[0].validFrom}`, { token: anna.token })).status, 404);
		assert.equal((await h.api("DELETE", `${rates}/price/today`, { token: anna.token })).status, 400);
		assert.equal((await h.api("DELETE", `${rates}/tax/${iso(day)}`, { token: anna.token })).status, 400);
		await h.sql`
			INSERT INTO vehicle_rates (device_id, kind, valid_from, value)
			SELECT ${deviceId}, 'wear', '2001-01-01'::date + n, 0.1 FROM generate_series(1, ${MAX_RATES - 1}) n`;
		assert.equal((await h.api("POST", rates, { token: anna.token, body: { kind: "wear", value: 0.2 } })).body.error, "too_many_rates");
		assert.equal((await h.api("POST", rates, { token: anna.token, body: { kind: "price", validFrom: iso(day - DAY), value: 1.9 } })).status, 200);
		await h.sql`DELETE FROM vehicle_rates WHERE device_id = ${deviceId} AND valid_from < '2010-01-01'`;

		// National average of the fuel: shown, and followed in the history when chosen
		await h.sql`INSERT INTO fuel_averages (fuel, week, price) VALUES ('petrol', '2026-11-09', 1.955), ('petrol', '2026-11-16', 1.97), ('diesel', '2026-11-16', 2.21)`;
		assert.deepEqual((await h.api("GET", vehicle, { token: anna.token })).body.average, { week: "2026-11-16", price: 1.97 });
		const auto = (await h.api("PUT", vehicle, { token: anna.token, body: { model: "Panda 1.2", fuelUnit: "km_per_l", fuelType: "petrol", fuelPriceAuto: true } })).body;
		assert.equal(auto.fuelPriceAuto, true);
		assert.deepEqual(auto.rates.price.find((item: { validFrom: string }) => item.validFrom === "2026-11-16"), { validFrom: "2026-11-16", value: 1.97 });
		assert.equal(await h.server.ctx.fuel.applyAuto(), 0);
		await h.api("PUT", vehicle, { token: anna.token, body: { model: "Panda 1.2", fuelUnit: "km_per_l", fuelType: "petrol" } });
		await h.api("DELETE", `${rates}/price/2026-11-16`, { token: anna.token });
		const costly = (await h.api("GET", `${logbook}?month=${month}`, { token: anna.token })).body as string;
		assert.match(costly, /,Litres,Fuel \(€\),Wear \(€\),Cost \(€\)\r\n/);

		// Tag removed
		await h.api("PUT", tag, { token: anna.token, body: { start: trip.start, purpose: null } });
		const [count] = await h.sql<{ count: number }[]>`SELECT count(*)::int AS count FROM trip_tags WHERE device_id = ${deviceId}`;
		assert.equal(count!.count, 1);
	});

	test("odometer and deadlines by date and km, reminders, done", async () => {
		const path = `/api/devices/${deviceId}/maintenance`;
		// Days of the time zone of the platform, as the backend counts them
		const today = Date.parse(new Date().toLocaleDateString("en-CA", { timeZone: h.server.ctx.config.TIMEZONE }));
		const date = (days: number) => iso(today + days * DAY);
		const notices = () => live.of("notification").filter(item => item.notification.kind === "maintenance");
		assert.equal((await h.api("GET", path, { token: bruno.token })).body.error, "owner_only");
		const phone = await h.api("POST", "/api/phones", { token: anna.token, body: { name: "Pixel" } });
		assert.equal((await h.api("GET", `/api/devices/${phone.body.id}/maintenance`, { token: anna.token })).body.error, "not_a_vehicle");

		// Recurring by km without odometer: the date stays
		const tyres = await h.api("POST", path, { token: anna.token, body: { kind: "tyres", dueDate: date(60), everyKm: 20000 } });
		assert.equal(tyres.status, 200, JSON.stringify(tyres.body));
		assert.equal(tyres.body.remainingKm, null);
		assert.deepEqual((await h.api("POST", `/api/maintenance/${tyres.body.id}/done`, { token: anna.token })).body.next.dueDate, date(60));

		// A custom deadline needs a description
		const custom = await h.api("POST", path, { token: anna.token, body: { kind: "other", title: " ", dueDate: date(30) } });
		assert.equal(custom.status, 400);
		const wash = await h.api("POST", path, { token: anna.token, body: { kind: "other", title: "Bollino blu", dueDate: date(300) } });
		assert.equal(wash.body.title, "Bollino blu");
		assert.equal((await h.api("PATCH", `/api/maintenance/${wash.body.id}`, { token: anna.token, body: { title: "" } })).body.error, "deadline_untitled");
		assert.equal((await h.api("PATCH", `/api/maintenance/${tyres.body.id}`, { token: anna.token, body: { kind: "other" } })).body.error, "deadline_untitled");
		assert.equal((await h.api("DELETE", `/api/maintenance/${wash.body.id}`, { token: anna.token })).status, 200);

		for (const body of [{ kind: "service" }, { kind: "car wash", dueKm: 10 }, { kind: "service", dueDate: "2026-02-30x" }, { kind: "tax", dueDate: date(1), everyMonths: 0 }]) {
			assert.equal((await h.api("POST", path, { token: anna.token, body })).status, 400, JSON.stringify(body));
		}
		assert.equal((await h.api("PUT", `/api/devices/${deviceId}/odometer`, { token: anna.token, body: { km: -1 } })).status, 400);
		assert.deepEqual((await h.api("PUT", `/api/devices/${deviceId}/odometer`, { token: anna.token, body: { km: 50000 } })).body, { odometerKm: 50000 });

		const service = await h.api("POST", path, { token: anna.token, body: { kind: "service", dueKm: 50500, everyKm: 15000, note: "Olio" } });
		assert.deepEqual([service.body.state, service.body.remainingKm], ["soon", 500]);
		const insurance = await h.api("POST", path, { token: anna.token, body: { kind: "insurance", dueDate: date(10) } });
		assert.deepEqual([insurance.body.state, insurance.body.remainingDays], ["soon", 10]);
		const inspection = await h.api("POST", path, { token: anna.token, body: { kind: "inspection", title: "Revisione 2026", dueDate: date(-1) } });
		assert.equal(inspection.body.state, "due");
		const tax = await h.api("POST", path, { token: anna.token, body: { kind: "tax", dueDate: date(100), everyMonths: 12, remindDays: 15 } });
		assert.equal(tax.body.state, "ok");

		const list = (await h.api("GET", path, { token: anna.token })).body;
		assert.equal(list.odometerKm, 50000);
		assert.deepEqual(list.items.map((item: { kind: string }) => item.kind), ["inspection", "insurance", "service", "tyres", "tax"]);
		assert.equal(list.log.length, 1);

		// Reminders: once per stage
		resetDailyJobs();
		await runJobs(h.server.ctx);
		await waitFor(() => notices().length === 3);
		const due = notices().find(item => item.notification.data.due === "due")!;
		assert.deepEqual([due.notification.data.title, due.notification.data.days], ["Revisione 2026", -1]);
		assert.equal(notices().find(item => item.notification.data.maintenance === "service")!.notification.data.km, 500);
		resetDailyJobs();
		await runJobs(h.server.ctx);
		await sleep(100);
		assert.equal(notices().length, 3);

		// Moved away: no notification, the reminder starts again
		const moved = await h.api("PATCH", `/api/maintenance/${insurance.body.id}`, { token: anna.token, body: { dueDate: date(200), note: "Nuova polizza" } });
		assert.deepEqual([moved.body.state, moved.body.note], ["ok", "Nuova polizza"]);
		resetDailyJobs();
		await runJobs(h.server.ctx);
		await sleep(100);
		assert.equal(notices().length, 3);
		const [stage] = await h.sql<{ notified_stage: number }[]>`SELECT notified_stage FROM maintenance WHERE id = ${insurance.body.id}`;
		assert.equal(stage!.notified_stage, 0);
		assert.equal((await h.api("PATCH", `/api/maintenance/${insurance.body.id}`, { token: anna.token, body: { dueDate: null } })).body.error, "deadline_empty");
		assert.equal((await h.api("PATCH", `/api/maintenance/${insurance.body.id}`, { token: bruno.token, body: { title: "X" } })).status, 404);
		assert.equal((await h.api("PATCH", `/api/maintenance/99999`, { token: anna.token, body: { title: "X" } })).status, 404);
		const changed = await h.api("PATCH", `/api/maintenance/${service.body.id}`, { token: anna.token, body: { everyMonths: 24, remindKm: 2000, kind: "service", title: "Tagliando" } });
		assert.deepEqual([changed.body.everyMonths, changed.body.remindKm, changed.body.title], [24, 2000, "Tagliando"]);

		// Done: recurring by km and months, one-off removed
		const next = (await h.api("POST", `/api/maintenance/${service.body.id}/done`, { token: anna.token, body: { note: "Filtri" } })).body.next;
		assert.equal(next.dueKm, 65000);
		// Every 24 months from today
		assert.equal(next.dueDate.slice(0, 4), String(Number(iso(Date.now()).slice(0, 4)) + 2));
		assert.equal((await h.api("POST", `/api/maintenance/${inspection.body.id}/done`, { token: anna.token, body: { km: 49900 } })).body.next, null);
		assert.equal((await h.api("POST", `/api/maintenance/${tax.body.id}/done`, { token: anna.token, body: { doneOn: "2026-01-15" } })).body.next.dueDate, "2027-01-15");
		assert.equal((await h.api("POST", `/api/maintenance/${tax.body.id}/done`, { token: anna.token, body: { doneOn: "yesterday" } })).status, 400);
		const after = (await h.api("GET", path, { token: anna.token })).body;
		assert.equal(after.items.length, 4);
		assert.deepEqual(after.log.slice(0, 2).map((item: { title: string; km: number }) => [item.title, item.km]), [["Revisione 2026", 49900], ["Tagliando", 50000]]);
		assert.equal((await h.api("DELETE", `/api/maintenance/${tyres.body.id}`, { token: anna.token })).status, 200);
		assert.equal((await h.api("DELETE", `/api/maintenance/${tyres.body.id}`, { token: anna.token })).status, 404);

		await h.sql`
			INSERT INTO maintenance (device_id, kind, due_date) SELECT ${deviceId}, 'other', now()::date + 400 FROM generate_series(1, ${MAX_DEADLINES - 3})`;
		assert.equal((await h.api("POST", path, { token: anna.token, body: { kind: "tax", dueDate: date(5) } })).body.error, "too_many_deadlines");

		// In the export of the data, removed with the tracker
		const exported = (await h.api("GET", "/api/account/export", { token: anna.token })).body;
		assert.ok(exported.dailyStats.length >= 10 && exported.maintenance.length > 0 && exported.maintenanceLog.length > 0 && exported.tripLog.length === 1);
		assert.equal(exported.vehicles.find((item: { deviceId: number }) => item.deviceId === deviceId).model, "Panda 1.2");
		assert.equal(exported.vehicleRates.filter((item: { deviceId: number }) => item.deviceId === deviceId).length, 6);
		assert.equal((await h.api("DELETE", `/api/devices/${deviceId}`, { token: anna.token })).status, 200);
		for (const table of ["daily_stats", "trip_tags", "maintenance", "maintenance_log", "vehicle_rates"]) {
			const [left] = await h.sql<{ count: number }[]>`SELECT count(*)::int AS count FROM ${h.sql(table)} WHERE device_id = ${deviceId}`;
			assert.equal(left!.count, 0, table);
		}
		const [car] = await h.sql<{ odometer_base: number | null; fuel_type: string | null; vehicle_model: string }[]>`
			SELECT odometer_base, fuel_type, vehicle_model FROM devices WHERE id = ${deviceId}`;
		assert.deepEqual([car!.odometer_base, car!.fuel_type, car!.vehicle_model], [null, null, ""]);
	});
});
