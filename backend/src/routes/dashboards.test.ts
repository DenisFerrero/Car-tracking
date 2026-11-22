import assert from "node:assert/strict";
import { after, before, describe, test } from "node:test";
import { MAX_WIDGETS, readLayout, resolvePeriod, weekOf } from "../services/metrics.ts";
import { Harness, waitFor } from "../test/harness.ts";
import type { User } from "../test/harness.ts";
import { MAX_DASHBOARDS, MAX_RECEIVED } from "./dashboards.ts";

// Custom dashboards: saved layouts, values of the widgets of the catalog, access to the
// devices checked at every request

const IMEI = "860000000000078";

test("periods of the dashboards in local days", () => {
	const today = "2026-03-15";
	assert.deepEqual(resolvePeriod("today", today), { from: today, to: today });
	assert.equal(resolvePeriod("7d", today).from, "2026-03-09");
	assert.equal(resolvePeriod("30d", today).from, "2026-02-14");
	assert.equal(resolvePeriod("90d", today).from, "2025-12-16");
	assert.equal(resolvePeriod("12m", today).from, "2025-04-01");
	assert.equal(resolvePeriod("ytd", today).from, "2026-01-01");
	// A fixed period ends today at most
	assert.deepEqual(resolvePeriod({ from: "2026-03-01", to: "2026-04-30" }, today), { from: "2026-03-01", to: today });
	assert.deepEqual(resolvePeriod({ from: "2026-01-01", to: "2026-01-31" }, today), { from: "2026-01-01", to: "2026-01-31" });
	assert.equal(weekOf("2026-11-22"), "2026-11-16");
	assert.equal(weekOf("2026-11-16"), "2026-11-16");
});

test("saved layouts: widgets no longer valid are dropped", () => {
	assert.deepEqual(readLayout(null), { version: 1, period: "30d", widgets: [] });
	const layout = readLayout({
		version: 1,
		period: "1y",
		widgets: [{ id: "a", metric: "gone", view: "number", devices: "all" }, { id: "b", metric: "distance", view: "number", devices: "all" }]
	});
	assert.equal(layout.period, "30d");
	assert.deepEqual(layout.widgets.map(widget => widget.id), ["b"]);
	assert.equal(layout.widgets[0]!.width, 1);
});

describe("dashboards", { skip: !process.env.TEST_DATABASE_URL && "TEST_DATABASE_URL not set" }, () => {
	let h: Harness;
	let anna: User;
	let bruno: User;
	let tracker: number;
	let vehicle: number;
	let today: string;

	const widget = (fields: Record<string, unknown>) => ({ id: "w", view: "number", devices: "all", ...fields });
	const data = async (user: User, widgets: Record<string, unknown>[], period: unknown = "7d") => {
		const response = await h.api("POST", "/api/dashboards/data", { token: user.token, body: { period, widgets } });
		assert.equal(response.status, 200, JSON.stringify(response.body));
		return response.body.results;
	};
	const one = async (user: User, fields: Record<string, unknown>, period: unknown = "7d") => (await data(user, [widget(fields)], period)).w;

	before(async () => {
		h = await Harness.start();
		anna = await h.onboard("anna@example.com", "Anna");
		bruno = await h.onboard("bruno@example.com", "Bruno");
		await h.befriend(anna, bruno);
		tracker = await h.claim(anna, IMEI, "Panda");
		vehicle = (await h.api("POST", "/api/vehicles", { token: anna.token, body: { name: "Punto" } })).body.id;
		await h.api("POST", `/api/devices/${tracker}/shares`, { token: anna.token, body: { userId: bruno.id, expiresAt: null } });
		const tz = h.server.ctx.config.TIMEZONE;
		today = (await h.sql<{ day: string }[]>`SELECT to_char(now() AT TIME ZONE ${tz}, 'YYYY-MM-DD') AS day`)[0]!.day;

		// Ten past days of 10 km; today nothing (points without a trip)
		for (let n = 1; n <= 10; n++) {
			await h.sql`
				INSERT INTO daily_stats (device_id, day, distance_km, business_km, personal_km, driving_min, trips, max_speed,
					rest_voltage, min_voltage, traffic_bytes, alarms)
				VALUES (${tracker}, ${today}::date - ${n}::int, 10, 4, 6, 20, 1, ${50 + n}, 12.3, 12.1, 1000, 1)`;
		}
		// Consumption 5 l/100 km at 2 €/l: 1 € per day
		await h.sql`INSERT INTO vehicle_rates (device_id, kind, valid_from, value) VALUES (${tracker}, 'consumption', '2000-01-01', 5), (${tracker}, 'price', '2000-01-01', 2)`;
		const points = [[3, -80, 8, 12.5, 40, 100], [2, -90, 9, 12.6, 50, 200], [1, -100, 10, 12.7, 60, 300]];
		for (const [hours, signal, satellites, voltage, speed, altitude] of points) {
			await h.sql`
				INSERT INTO positions (time, device_id, lat, lon, speed, altitude, signal, satellites, voltage, status, stale, events)
				VALUES (now() - make_interval(hours => ${hours!}), ${tracker}, 45, 9, ${speed!}, ${altitude!}, ${signal!}, ${satellites!}, ${voltage!}, 0, false, 0)`;
		}
		for (const [minutes, rpm] of [[90, "x"], [60, 1000], [30, 3000]] as const) {
			await h.sql`INSERT INTO device_extra (time, device_id, data) VALUES (now() - make_interval(mins => ${minutes}), ${tracker}, ${h.sql.json({ rpm })})`;
		}
		await h.api("PUT", `/api/devices/${vehicle}/odometer`, { token: anna.token, body: { km: 50000 } });
		const inDays = (days: number) => new Date(Date.parse(today) + days * 86400e3).toISOString().slice(0, 10);
		await h.api("POST", `/api/devices/${vehicle}/maintenance`, { token: anna.token, body: { kind: "insurance", dueDate: inDays(200) } });
		await h.api("POST", `/api/devices/${vehicle}/maintenance`, { token: anna.token, body: { kind: "tax", dueDate: inDays(10) } });
		await h.api("POST", `/api/devices/${vehicle}/maintenance`, { token: anna.token, body: { kind: "service", dueKm: 49000 } });
	});

	after(async () => {
		await h?.close();
	});

	test("saved, listed, renamed and deleted by their user only", async () => {
		const layout = { version: 1, period: "30d", widgets: [widget({ metric: "distance", title: "Km" })] };
		const created = await h.api("POST", "/api/dashboards", { token: anna.token, body: { name: " Flotta ", layout } });
		assert.equal(created.status, 200);
		assert.equal(created.body.name, "Flotta");
		assert.deepEqual(created.body.layout.widgets[0], {
			id: "w", metric: "distance", view: "number", devices: "all", period: null, title: "Km", width: 1, height: 1
		});
		const id = created.body.id;

		const updated = await h.api("PUT", `/api/dashboards/${id}`, {
			token: anna.token, body: { name: "Auto", layout: { version: 1, widgets: [widget({ metric: "trips", width: 2, height: 2 })] } }
		});
		assert.equal(updated.body.layout.period, "30d");
		assert.equal(updated.body.layout.widgets[0].width, 2);
		assert.deepEqual((await h.api("GET", "/api/dashboards", { token: anna.token })).body.map((item: { name: string }) => item.name), ["Auto"]);
		assert.deepEqual((await h.api("GET", "/api/dashboards", { token: bruno.token })).body, []);
		assert.equal((await h.api("PUT", `/api/dashboards/${id}`, { token: bruno.token, body: { name: "X", layout } })).status, 404);
		assert.equal((await h.api("DELETE", `/api/dashboards/${id}`, { token: bruno.token })).status, 404);

		// Widgets of metrics removed from the catalog disappear, the rest stays
		await h.sql`UPDATE dashboards SET layout = jsonb_set(layout, '{widgets}', layout -> 'widgets' || '[{"id": "old", "metric": "gone"}]') WHERE id = ${id}`;
		assert.equal((await h.api("GET", "/api/dashboards", { token: anna.token })).body[0].layout.widgets.length, 1);

		// In the copy of the personal data
		const exported = await h.api("GET", "/api/account/export", { token: anna.token });
		assert.equal(exported.body.dashboards[0].name, "Auto");

		assert.equal((await h.api("DELETE", `/api/dashboards/${id}`, { token: anna.token })).status, 200);
		assert.equal((await h.api("DELETE", `/api/dashboards/${id}`, { token: anna.token })).status, 404);
	});

	test("layouts validated: metrics, views, options, limits", async () => {
		const save = (widgets: unknown[], extra: Record<string, unknown> = {}) =>
			h.api("POST", "/api/dashboards", { token: anna.token, body: { name: "X", layout: { version: 1, widgets, ...extra } } });
		const invalid = [
			widget({ metric: "nope" }),
			widget({ metric: "deadlines" }),
			widget({ metric: "status", view: "line" }),
			widget({ metric: "extra" }),
			widget({ metric: "distance", key: "rpm" }),
			widget({ metric: "distance", agg: "max" }),
			widget({ metric: "distance", bucket: "day" }),
			widget({ metric: "distance", view: "bars", bucket: "hour" }),
			widget({ metric: "distance", devices: [1, 1] }),
			widget({ metric: "distance", devices: [] }),
			widget({ metric: "distance", width: 5 }),
			widget({ metric: "distance", period: { from: "2026-02-01", to: "2026-01-01" } }),
			widget({ metric: "distance", period: { from: "1999-12-31", to: "2000-01-31" } }),
			widget({ metric: "distance", id: "with space" }),
			widget({ metric: "distance", sql: "1" })
		];
		for (const item of invalid) assert.equal((await save([item])).status, 400, JSON.stringify(item));
		assert.equal((await save([widget({ metric: "distance" }), widget({ metric: "trips" })])).status, 400);
		assert.equal((await save(Array.from({ length: MAX_WIDGETS + 1 }, (_, n) => widget({ metric: "trips", id: `w${n}` })))).status, 400);
		assert.equal((await save([], { version: 2 })).status, 400);
		assert.equal((await h.api("POST", "/api/dashboards", { token: anna.token, body: { name: "", layout: { version: 1, widgets: [] } } })).status, 400);
		assert.equal((await h.api("POST", "/api/dashboards/data", { token: anna.token, body: { widgets: [] } })).status, 400);

		for (let n = 0; n < MAX_DASHBOARDS; n++) assert.equal((await save([])).status, 200);
		assert.equal((await save([])).body.error, "too_many_dashboards");
		await h.sql`DELETE FROM dashboards`;
	});

	test("daily values: total, per vehicle, over days, weeks and months", async () => {
		const total = await one(anna, { metric: "distance" });
		assert.equal(total.status, "ok");
		assert.equal(total.value, 60);
		assert.deepEqual(total.devices.map((device: { id: number }) => device.id), [tracker, vehicle]);
		assert.equal(total.devices[0].name, "Panda");
		assert.deepEqual(total.unavailable, []);
		assert.equal(total.to, today);

		const perVehicle = await one(anna, { metric: "driving", view: "table" });
		assert.deepEqual(perVehicle.values, [{ deviceId: tracker, value: 120 }, { deviceId: vehicle, value: 0 }]);
		assert.equal((await one(anna, { metric: "maxSpeed" })).value, 56);
		assert.equal((await one(anna, { metric: "restVoltage", devices: [tracker] })).value, 12.3);
		assert.equal((await one(anna, { metric: "businessKm" })).value, 24);
		assert.equal((await one(anna, { metric: "personalKm", view: "vehicles" })).values[0].value, 36);
		assert.equal((await one(anna, { metric: "trips" })).value, 6);
		assert.equal((await one(anna, { metric: "alarms" })).value, 6);
		assert.ok((await one(anna, { metric: "traffic" })).value >= 6000);

		const days = await one(anna, { metric: "distance", view: "bars", devices: [tracker] });
		assert.equal(days.bucket, "1 day");
		assert.equal(days.series[0].points.length, 7);
		assert.deepEqual(days.series[0].points.at(-1), [today, 0]);
		const weeks = await one(anna, { metric: "distance", view: "line", devices: [tracker], bucket: "week" }, "30d");
		assert.equal(weeks.bucket, "1 week");
		assert.equal(weeks.series[0].points.reduce((sum: number, [, value]: [string, number]) => sum + value, 0), 100);
		assert.ok(weeks.series[0].points.every(([day]: [string]) => weekOf(day) === day));
		const months = await one(anna, { metric: "distance", view: "bars", devices: [tracker] }, "12m");
		assert.equal(months.bucket, "1 month");
		assert.ok(months.series[0].points.every(([day]: [string]) => day.endsWith("-01")));
		assert.equal((await one(anna, { metric: "distance", view: "bars", devices: [tracker] }, "90d")).bucket, "1 week");
		assert.equal((await one(anna, { metric: "distance", view: "bars", devices: [tracker], bucket: "month" })).bucket, "1 month");

		// A past period doesn't compute today; the widget period wins over the dashboard one
		const yesterday = new Date(Date.parse(today) - 86400e3).toISOString().slice(0, 10);
		assert.equal((await one(anna, { metric: "distance", devices: [tracker], period: { from: yesterday, to: yesterday } }, "90d")).value, 10);
		assert.equal((await one(anna, { metric: "distance", devices: [tracker] }, "today")).value, 0);
		assert.equal((await one(anna, { metric: "distance", period: { from: "2020-01-01", to: today } })).error, "period_too_long");
	});

	test("costs from the km of each day", async () => {
		assert.equal((await one(anna, { metric: "cost", devices: [tracker] })).value, 6);
		assert.equal((await one(anna, { metric: "fuelCost", devices: [tracker] })).value, 6);
		assert.equal((await one(anna, { metric: "fuel", devices: [tracker] })).value, 3);
		assert.equal((await one(anna, { metric: "wearCost", devices: [tracker] })).value, null);
		// No consumption nor wear: nothing to compute
		assert.deepEqual((await one(anna, { metric: "cost", view: "table" })).values[1], { deviceId: vehicle, value: null });
	});

	test("points aggregated: average, minimum, maximum, last, over time", async () => {
		assert.equal((await one(anna, { metric: "signal" })).value, -90);
		assert.equal((await one(anna, { metric: "signal", agg: "min" })).value, -100);
		assert.equal((await one(anna, { metric: "signal", agg: "max" })).value, -80);
		assert.equal((await one(anna, { metric: "signal", agg: "last" })).value, -100);
		assert.equal((await one(anna, { metric: "satellites" })).value, 9);
		assert.equal((await one(anna, { metric: "voltage", agg: "last" })).value, 12.7);
		assert.equal((await one(anna, { metric: "speed", agg: "max" })).value, 60);
		assert.equal((await one(anna, { metric: "altitude" })).value, 200);
		assert.equal((await one(anna, { metric: "temperature" })).value, null);
		assert.equal((await one(anna, { metric: "pressure", view: "table" })).values[0].value, null);
		// "all" without trackers: nothing to read
		assert.equal((await one(bruno, { metric: "signal" })).value, null);
		assert.deepEqual((await one(bruno, { metric: "signal", view: "table" })).values, []);
		assert.deepEqual((await one(bruno, { metric: "signal", view: "line" })).series, []);

		const perVehicle = await one(anna, { metric: "altitude", view: "vehicles" });
		assert.deepEqual(perVehicle.values, [{ deviceId: tracker, value: 200 }, { deviceId: vehicle, value: null }]);

		const hours = await one(anna, { metric: "signal", view: "line", bucket: "hour" });
		assert.equal(hours.bucket, "1 hour");
		assert.equal(hours.series[0].points.length, 3);
		assert.ok(!Number.isNaN(Date.parse(hours.series[0].points[0][0])));
		assert.equal((await one(anna, { metric: "signal", view: "line" })).bucket, "1 hour");
		assert.ok(["2 minutes", "10 minutes"].includes((await one(anna, { metric: "signal", view: "line" }, "today")).bucket));
		// Too many hours in 90 days: bigger buckets
		assert.equal((await one(anna, { metric: "signal", view: "line", bucket: "hour" }, "90d")).bucket, "6 hours");
		assert.equal((await one(anna, { metric: "signal", view: "bars", bucket: "month" })).bucket, "1 month");
		assert.equal((await one(anna, { metric: "signal" }, "12m")).error, "period_too_long");
	});

	test("extra data: numeric values of a field", async () => {
		assert.equal((await one(anna, { metric: "extra", key: "rpm" })).value, 2000);
		assert.equal((await one(anna, { metric: "extra", key: "rpm", agg: "last" })).value, 3000);
		assert.equal((await one(anna, { metric: "extra", key: "speed" })).value, null);
		assert.equal((await one(anna, { metric: "extra", key: "rpm", view: "line", bucket: "day" })).series[0].points.length >= 1, true);
	});

	test("current state: odometer, deadlines, status", async () => {
		assert.equal((await one(anna, { metric: "odometer", devices: [vehicle] })).value, 50000);
		assert.deepEqual((await one(anna, { metric: "odometer", view: "table" })).values, [
			{ deviceId: tracker, value: null }, { deviceId: vehicle, value: 50000 }
		]);
		const deadlines = await one(anna, { metric: "deadlines", view: "list" });
		assert.deepEqual(deadlines.items.map((item: { kind: string; state: string }) => [item.kind, item.state]),
			[["service", "due"], ["tax", "soon"], ["insurance", "ok"]]);
		assert.equal(deadlines.items[0].remainingKm, -1000);
		assert.equal(deadlines.items[0].deviceId, vehicle);

		const status = await one(bruno, { metric: "status", view: "map" });
		assert.deepEqual(status.devices.map((device: { id: number }) => device.id), [tracker]);
		assert.equal((await one(anna, { metric: "deadlines", view: "list", devices: [tracker] })).items.length, 0);
	});

	test("devices not available: deleted, only shared, of another kind, archived", async () => {
		// Bruno sees only the position of the tracker of Anna
		const shared = await one(bruno, { metric: "distance", devices: [tracker, 999999] });
		assert.deepEqual(shared.devices, []);
		assert.deepEqual(shared.unavailable, [tracker, 999999]);
		assert.equal(shared.value, null);
		assert.deepEqual((await one(bruno, { metric: "status", view: "list", devices: [tracker] })).unavailable, []);
		assert.deepEqual((await one(anna, { metric: "signal", devices: [tracker, vehicle] })).unavailable, [vehicle]);

		// More widgets at once, each with its result
		const results = await data(anna, [widget({ id: "a", metric: "trips" }), widget({ id: "b", metric: "signal", period: "12m" })]);
		assert.equal(results.a.status, "ok");
		assert.deepEqual(results.b, { status: "error", error: "period_too_long" });

		// Archived vehicles stay only where chosen explicitly
		await h.api("PATCH", `/api/devices/${vehicle}`, { token: anna.token, body: { archived: true } });
		assert.deepEqual((await one(anna, { metric: "distance" })).devices.map((device: { id: number }) => device.id), [tracker]);
		assert.deepEqual((await one(anna, { metric: "distance", devices: [vehicle] })).devices.map((device: { id: number }) => device.id), [vehicle]);

		// Share revoked: the widget of Bruno stays, the tracker becomes unavailable
		await h.api("DELETE", `/api/devices/${tracker}/shares/${bruno.id}`, { token: anna.token });
		assert.deepEqual((await one(bruno, { metric: "status", view: "map", devices: [tracker] })).unavailable, [tracker]);
	});
	test("one current dashboard per user", async () => {
		const layout = { version: 1, widgets: [widget({ metric: "distance" })] };
		const first = (await h.api("POST", "/api/dashboards", { token: anna.token, body: { name: "Uno", layout } })).body;
		const second = (await h.api("POST", "/api/dashboards", { token: anna.token, body: { name: "Due", layout } })).body;
		assert.equal(first.current, false);
		const current = async (id: number, value: unknown, user = anna) =>
			h.api("PUT", `/api/dashboards/${id}/current`, { token: user.token, body: { current: value } });
		assert.equal((await current(first.id, true)).body.current, true);
		assert.equal((await current(second.id, true)).body.current, true);
		const listed = async () => (await h.api("GET", "/api/dashboards", { token: anna.token })).body
			.filter((item: { current: boolean }) => item.current).map((item: { name: string }) => item.name);
		assert.deepEqual(await listed(), ["Due"]);
		// Saving keeps the mark; unmarked, no current one
		await h.api("PUT", `/api/dashboards/${second.id}`, { token: anna.token, body: { name: "Due", layout } });
		assert.deepEqual(await listed(), ["Due"]);
		assert.equal((await current(second.id, false)).body.current, false);
		assert.deepEqual(await listed(), []);
		assert.equal((await current(second.id, true, bruno)).status, 404);
		assert.equal((await current(second.id, "yes")).status, 400);
		const exported = await h.api("GET", "/api/account/export", { token: anna.token });
		assert.equal(exported.body.dashboards.some((item: { current: boolean }) => item.current), false);
		await h.api("DELETE", `/api/dashboards/${first.id}`, { token: anna.token });
		await h.api("DELETE", `/api/dashboards/${second.id}`, { token: anna.token });
	});

	test("layouts sent to friends, used with their own vehicles", async () => {
		const carla = await h.onboard("carla@example.com", "Carla");
		const golf = (await h.api("POST", "/api/vehicles", { token: bruno.token, body: { name: "Golf" } })).body.id;
		const layout = {
			version: 1,
			period: "90d",
			widgets: [widget({ id: "a", metric: "distance", devices: [tracker, vehicle] }), widget({ id: "b", metric: "signal", devices: [tracker] })]
		};
		const dashboard = (await h.api("POST", "/api/dashboards", { token: anna.token, body: { name: "Flotta", layout } })).body;
		const share = (user: User, id: number, friendId: number) =>
			h.api("POST", `/api/dashboards/${id}/share`, { token: user.token, body: { friendId } });

		// Only to friends, only own dashboards
		assert.equal((await share(anna, dashboard.id, carla.id)).status, 404);
		assert.equal((await share(bruno, dashboard.id, anna.id)).status, 404);
		assert.equal((await share(anna, dashboard.id, 0)).status, 400);
		const live = await h.live(bruno.token);
		assert.equal((await share(anna, dashboard.id, bruno.id)).status, 200);
		await waitFor(() => live.of("dashboardShare").length === 1);
		assert.deepEqual(live.of("dashboardShare")[0], { type: "dashboardShare", name: "Anna", dashboard: "Flotta" });
		live.close();
		// Sent again: one copy, the new version
		await h.api("PUT", `/api/dashboards/${dashboard.id}`, { token: anna.token, body: { name: "Flotta 2", layout } });
		await share(anna, dashboard.id, bruno.id);

		// Without the vehicles of Anna
		const received = (await h.api("GET", "/api/dashboards/shares", { token: bruno.token })).body;
		assert.equal(received.length, 1);
		assert.equal(received[0].from, "Anna");
		assert.equal(received[0].name, "Flotta 2");
		assert.equal(received[0].layout.period, "90d");
		assert.deepEqual(received[0].layout.widgets.map((item: { devices: unknown }) => item.devices), ["all", "all"]);
		assert.deepEqual((await h.api("GET", "/api/dashboards/shares", { token: anna.token })).body, []);

		// Used with own devices only: not the tracker shared with Bruno
		const accept = (id: number, body: unknown, user = bruno) => h.api("POST", `/api/dashboards/shares/${id}/accept`, { token: user.token, body });
		assert.equal((await accept(received[0].id, { name: "Mia", devices: [tracker] })).status, 404);
		assert.equal((await accept(received[0].id, { name: "Mia", devices: [golf] }, carla)).status, 404);
		assert.equal((await accept(received[0].id, { name: "", devices: "all" })).status, 400);
		assert.equal((await accept(99999, { name: "Mia", devices: "all" })).status, 404);
		const used = await accept(received[0].id, { name: "Mia", devices: [golf, golf] });
		assert.equal(used.status, 200, JSON.stringify(used.body));
		assert.equal(used.body.name, "Mia");
		assert.equal(used.body.current, false);
		// Signal: no tracker among the vehicles chosen, the widget stays on them
		assert.deepEqual(used.body.layout.widgets.map((item: { devices: unknown }) => item.devices), [[golf], [golf]]);
		assert.deepEqual((await h.api("GET", "/api/dashboards/shares", { token: bruno.token })).body, []);
		assert.equal((await accept(received[0].id, { name: "Mia", devices: "all" })).status, 404);

		// Used on all the vehicles
		await share(anna, dashboard.id, bruno.id);
		const again = (await h.api("GET", "/api/dashboards/shares", { token: bruno.token })).body[0];
		assert.deepEqual((await accept(again.id, { name: "Tutti", devices: "all" })).body.layout.widgets[1].devices, "all");

		// Declined, by the friend only
		await share(anna, dashboard.id, bruno.id);
		const third = (await h.api("GET", "/api/dashboards/shares", { token: bruno.token })).body[0];
		assert.equal((await h.api("DELETE", `/api/dashboards/shares/${third.id}`, { token: anna.token })).status, 404);
		assert.equal((await h.api("DELETE", `/api/dashboards/shares/${third.id}`, { token: bruno.token })).status, 200);
		assert.equal((await h.api("DELETE", `/api/dashboards/shares/${third.id}`, { token: bruno.token })).status, 404);

		// Withdrawn when the dashboard is deleted or the friendship ends
		await share(anna, dashboard.id, bruno.id);
		const other = (await h.api("POST", "/api/dashboards", { token: anna.token, body: { name: "Altra", layout } })).body;
		await share(anna, other.id, bruno.id);
		await h.api("DELETE", `/api/dashboards/${dashboard.id}`, { token: anna.token });
		assert.deepEqual((await h.api("GET", "/api/dashboards/shares", { token: bruno.token })).body.map((item: { name: string }) => item.name), ["Altra"]);
		await h.befriend(carla, bruno);
		const own = (await h.api("POST", "/api/dashboards", { token: carla.token, body: { name: "Di Carla", layout: { version: 1, widgets: [] } } })).body;
		await share(carla, own.id, bruno.id);
		await h.api("DELETE", `/api/friends/${anna.id}`, { token: bruno.token });
		assert.deepEqual((await h.api("GET", "/api/dashboards/shares", { token: bruno.token })).body.map((item: { name: string }) => item.name), ["Di Carla"]);

		// At most some layouts waiting for a friend
		await h.befriend(carla, anna);
		await h.sql`
			WITH d AS (INSERT INTO dashboards (user_id, name, layout) SELECT ${carla.id}, 'X', '{}' FROM generate_series(1, ${MAX_RECEIVED}) RETURNING id)
			INSERT INTO dashboard_shares (dashboard_id, from_id, to_id, name, layout) SELECT id, ${carla.id}, ${anna.id}, 'X', '{"widgets": [{"metric": "gone"}]}' FROM d`;
		const full = await share(carla, own.id, anna.id);
		assert.equal(full.status, 400);
		assert.equal(full.body.error, "too_many_dashboard_shares");
		// Layouts saved with widgets no longer valid: dropped when read
		assert.ok((await h.api("GET", "/api/dashboards/shares", { token: anna.token })).body.every((item: { layout: { widgets: unknown[] } }) => item.layout.widgets.length === 0));
	});
});
