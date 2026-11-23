import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import crypto from "node:crypto";
import fs from "node:fs";
import http from "node:http";
import os from "node:os";
import path from "node:path";
import { describe, test } from "node:test";
import type { FastifyError, FastifyReply, FastifyRequest } from "fastify";
import { loadConfig } from "./config.ts";
import { ApiError, errorHandler } from "./http/errors.ts";
import { LOCALES, isLocale, notificationText } from "./i18n.ts";
import type { NotificationKind } from "./i18n.ts";
import { phoneTrack, splitTrips, toCsv, toGpx, toLogbook } from "./services/analytics.ts";
import { convertConsumption, rateOn, sumCosts, tripCost } from "./services/costs.ts";
import type { Rate, VehicleProfile } from "./services/costs.ts";
import { parseWeeklyPrices } from "./services/fuel.ts";
import { plural } from "./i18n.ts";
import { restVoltage } from "./services/daily.ts";
import { batteryHealth, deadlineState } from "./services/vehicle.ts";
import { summarize } from "./routes/vehicle.ts";
import { backupState } from "./services/backups.ts";
import { Fcm } from "./services/fcm.ts";
import { inSchedule, localTime, scheduleSchema } from "./services/schedule.ts";
import { Throttle } from "./services/throttle.ts";

// Unit tests without database

const KINDS: NotificationKind[] = ["motion", "tilt", "power_lost", "low_battery", "offline", "online", "geofence_enter", "geofence_exit", "phone_battery", "long_stop",
	"battery_health"];

describe("car: battery, deadlines, trip log, summaries", () => {
	const point = (time: string, status: number, voltage: number | null) =>
		({ time: new Date(time), lat: 45, lon: 9, speed: 0, status, stale: false, voltage });

	test("resting voltage: parked for 2 hours, median", () => {
		const points = [
			point("2026-11-20T01:00:00Z", 2, 12.3),
			point("2026-11-20T08:00:00Z", 0, 14.2),
			point("2026-11-20T09:00:00Z", 2, 12.9),
			point("2026-11-20T11:00:00Z", 2, 12.5),
			point("2026-11-20T12:00:00Z", 2, null),
			point("2026-11-20T13:00:00Z", 2, 12.4)
		];
		// 01:00 counts only with a movement known before the day
		assert.equal(restVoltage(points, null), 12.45);
		assert.equal(restVoltage(points, new Date("2026-11-19T20:00:00Z")), 12.4);
		assert.equal(restVoltage(points.slice(1, 3), null), null);
	});

	test("battery health from the days", () => {
		const days = (values: (number | null)[]) => values.map((restVoltage, i) => ({ day: `2026-11-${String(i + 1).padStart(2, "0")}`, restVoltage }));
		assert.deepEqual(batteryHealth(days([12.6, null, 12.5])), { state: "unknown", average: null, trendPerMonth: null });
		assert.deepEqual(batteryHealth(days([12.6, 12.6, 12.5])), { state: "good", average: 12.57, trendPerMonth: null });
		assert.equal(batteryHealth(days([12.3, 12.3, 12.3])).state, "fair");
		const falling = batteryHealth(days([12.6, 12.55, 12.5, 12.45, 12.4, 12.35, 12.3, 12.25, 12.2, 12.15]));
		assert.equal(falling.trendPerMonth, -1.5);
		assert.equal(falling.state, "fair");
		assert.equal(batteryHealth(days([12.1, 12.0, 12.1])).state, "low");
	});

	test("deadlines: days and km left, state", () => {
		const item = { due_date: "2026-12-01", due_km: 60000, remind_days: 30, remind_km: 1000 };
		assert.deepEqual(deadlineState(item, 50000, "2026-10-01"), { remainingDays: 61, remainingKm: 10000, state: "ok" });
		assert.equal(deadlineState(item, 59500, "2026-10-01").state, "soon");
		assert.equal(deadlineState(item, 50000, "2026-11-15").state, "soon");
		assert.equal(deadlineState(item, 50000, "2026-12-01").state, "due");
		assert.equal(deadlineState(item, 60010, "2026-10-01").state, "due");
		assert.deepEqual(deadlineState({ ...item, due_date: null }, null, "2026-10-01"), { remainingDays: null, remainingKm: null, state: "ok" });
	});

	test("costs of a trip: price, consumption and wear of the day, sums", () => {
		const rates = (...items: [string, number][]): Rate[] => items.map(([validFrom, value]) => ({ validFrom, value }));
		const profile: VehicleProfile = {
			model: "Panda", fuelUnit: "l_per_100km", fuelType: null, fuelPriceAuto: false, ratesFromRefuels: false,
			rates: { price: rates(["2026-10-01", 1.85], ["2026-11-01", 2]), consumption: rates(["2026-01-01", 6]), wear: rates(["2026-01-01", 0.12]) }
		};
		assert.deepEqual(tripCost(100, profile, "2026-10-31"), { fuelL: 6, fuelCost: 11.1, wearCost: 12, cost: 23.1 });
		assert.deepEqual(tripCost(100, profile, "2026-11-01"), { fuelL: 6, fuelCost: 12, wearCost: 12, cost: 24 });
		// Before the first value: the first one
		assert.equal(rateOn(profile.rates.price, "2025-01-01"), 1.85);
		assert.equal(rateOn([], "2026-11-01"), null);
		assert.equal(convertConsumption(20), 5);
		assert.equal(convertConsumption(5), 20);
		// Consumption and wear change too: a heavier car from December
		const later = { ...profile, rates: { ...profile.rates, consumption: rates(["2026-01-01", 6], ["2026-12-01", 7]), wear: rates(["2026-12-01", 0.15]) } };
		assert.deepEqual(tripCost(100, later, "2026-11-30"), { fuelL: 6, fuelCost: 12, wearCost: 15, cost: 27 });
		assert.deepEqual(tripCost(100, later, "2026-12-01"), { fuelL: 7, fuelCost: 14, wearCost: 15, cost: 29 });
		assert.deepEqual(tripCost(10, { ...profile, rates: { ...profile.rates, consumption: rates(["2026-01-01", 6.25]) } }, "2026-10-02"),
			{ fuelL: 0.63, fuelCost: 1.16, wearCost: 1.2, cost: 2.36 });
		assert.deepEqual(tripCost(10, { ...profile, rates: { ...profile.rates, price: [], wear: [] } }, "2026-10-02"), { fuelL: 0.6, fuelCost: null, wearCost: null, cost: null });
		assert.deepEqual(tripCost(10, { ...profile, rates: { ...profile.rates, consumption: [] } }, "2026-10-02"), { fuelL: null, fuelCost: null, wearCost: 1.2, cost: 1.2 });
		assert.deepEqual(sumCosts([tripCost(100, profile, "2026-10-31"), tripCost(100, profile, "2026-11-02")]),
			{ fuelL: 12, fuelCost: 23.1, wearCost: 24, cost: 47.1 });
		assert.deepEqual(sumCosts([]), { fuelL: null, fuelCost: null, wearCost: null, cost: null });
	});

	test("weekly national fuel prices of the Ministry", () => {
		const csv = [
			"DATA_RILEVAZIONE,BENZINA,GASOLIO_AUTO,GPL,METANO",
			'2026-11-09,"1.955,2","2.201,4","833,1","1.890,0"',
			'2026-11-16,"1.969,6","2.210,01","835,66","1.897,98"',
			"2026-11-23,,,,",
			'not a date,"1.000,0",,,',
			'2026-11-30,"12,5","99.999,0","abc",'
		].join("\r\n");
		const weeks = parseWeeklyPrices(csv);
		assert.deepEqual(weeks.map(week => week.week), ["2026-11-30", "2026-11-23", "2026-11-16", "2026-11-09"]);
		assert.deepEqual(weeks[2]!.prices, { petrol: 1.97, diesel: 2.21, lpg: 0.836 });
		// Outside 0.1-10 €/l, empty or invalid: not a price
		assert.deepEqual(weeks[0]!.prices, {});
		assert.deepEqual(weeks[1]!.prices, {});
		assert.throws(() => parseWeeklyPrices("A,B\n1,2"), /Unknown format/);
		assert.throws(() => parseWeeklyPrices(""), /Unknown format/);
	});

	test("singular and plural of the notifications", () => {
		assert.equal(plural("it", 1, { one: "# giorno", other: "# giorni" }), "1 giorno");
		assert.equal(plural("it", 0, { one: "# giorno", other: "# giorni" }), "0 giorni");
		assert.equal(plural("en", 2, { other: "# days" }), "2 days");
		const text = (locale: string, data: object) => notificationText(locale, "maintenance", { device: "Panda", time: "2026-11-20T08:00:00Z", ...data }, "UTC").body;
		assert.equal(text("it", { days: 1 }), "Panda: tra 1 giorno");
		assert.equal(text("it", { days: -1, km: -1 }), "Panda: scaduta da 1 giorno o superata di 1 km");
		assert.equal(text("en", { days: -3 }), "Panda: overdue by 3 days");
		assert.equal(text("en", { days: 1 }), "Panda: in 1 day");
		const firmware = (locale: string, automatic: boolean) => notificationText(locale, "firmware", { device: "Panda", time: "2026-11-20T08:00:00Z", version: "2.4.0", automatic }, "UTC");
		assert.deepEqual(firmware("it", true), { title: "Nuovo firmware 2.4.0", body: "Panda lo installerà da solo entro un giorno" });
		assert.equal(firmware("en", false).body, "Install it on Panda from the page of the device");
		assert.equal(firmware("it", false).body, "Installalo su Panda dalla pagina del dispositivo");
		assert.equal(firmware("en", true).body, "Panda will install it by itself within a day");
	});

	test("trip log CSV in Italian and English, weekly and monthly totals", () => {
		const trip = (start: string, km: number) => ({
			start: new Date(start), end: new Date(Date.parse(start) + 20 * 60e3), startLat: 45.1, startLon: 9.2, endLat: 45.2, endLon: 9.3,
			distanceKm: km, durationMin: 20, maxSpeed: 60, avgSpeed: 30, points: 20
		});
		const trips = [trip("2026-11-02T07:00:00Z", 12.34), trip("2026-11-03T16:00:00Z", 5), trip("2026-11-04T16:00:00Z", 1)];
		const tags = [{ start: trips[0]!.start, purpose: "business" as const, note: 'Cliente "Rossi"' }, { start: trips[1]!.start, purpose: "personal" as const, note: "" }];
		const italian = toLogbook(trips, tags, "it", "Europe/Rome").split("\r\n");
		assert.equal(italian[1], '2026-11-02;08:00;08:20;45.10000 9.20000;45.20000 9.30000;12,3;20;Lavoro;"Cliente ""Rossi"""');
		assert.equal(italian[3], "2026-11-04;17:00;17:20;45.10000 9.20000;45.20000 9.30000;1,0;20;;");
		assert.deepEqual(italian.slice(5, 9).map(line => line.split(";")[5]), ["12,3", "5,0", "1,0", "18,3"]);
		const english = toLogbook(trips, [], null, "UTC").split("\r\n");
		assert.equal(english[0], "Date,Start,End,From (lat, lon),To (lat, lon),Km,Duration (min),Purpose,Note");
		assert.equal(english[1], "2026-11-02,07:00,07:20,45.10000 9.20000,45.20000 9.30000,12.3,20,,");
		// Without consumption and wear: no columns of the costs
		const price = [{ validFrom: "2026-10-01", value: 1.8 }, { validFrom: "2026-11-04", value: 2 }];
		const empty: VehicleProfile = { model: "", fuelUnit: "l_per_100km", fuelType: null, fuelPriceAuto: false, ratesFromRefuels: false, rates: { price, consumption: [], wear: [] } };
		assert.equal(toLogbook(trips, [], null, "UTC", empty).split("\r\n")[0], english[0]);
		// 5 l/100 km at 1.80 €/l, 2 €/l from the 4th; wear 0.10 €/km; totals = sums of the trips
		const costly = toLogbook(trips, tags, "it", "Europe/Rome",
			{ ...empty, rates: { price, consumption: [{ validFrom: "2026-01-01", value: 5 }], wear: [{ validFrom: "2026-01-01", value: 0.1 }] } }).split("\r\n");
		assert.match(costly[0]!, /;Note;Litri;Carburante \(€\);Usura \(€\);Costo \(€\)$/);
		assert.match(costly[1]!, /;0,62;1,11;1,23;2,34$/);
		assert.match(costly[3]!, /;0,05;0,10;0,10;0,20$/);
		assert.match(costly[5]!, /^Totale lavoro;;;;;12,3;;;;0,62;1,11;1,23;2,34$/);
		assert.match(costly[7]!, /^Non indicato;;;;;1,0;;;;0,05;0,10;0,10;0,20$/);
		assert.match(costly[8]!, /^Totale;;;;;18,3;;;;0,92;1,66;1,83;3,49$/);
		const english2 = toLogbook(trips, [], "en", "UTC", { ...empty, rates: { price: [], consumption: [{ validFrom: "2026-01-01", value: 6 }], wear: [] } }).split("\r\n");
		assert.match(english2[0]!, /,Litres,Fuel \(€\),Wear \(€\),Cost \(€\)$/);
		assert.match(english2[1]!, /,0\.74,,,$/);

		const day = (iso: string, km: number, voltage: number | null) => ({
			day: iso, distanceKm: km, businessKm: km / 2, personalKm: 0, drivingMin: 30, trips: 1, maxSpeed: 50 + km,
			restVoltage: voltage, minVoltage: null, trafficBytes: 1000, alarms: 1
		});
		const months = summarize([day("2026-10-31", 10, 12.4), day("2026-11-01", 20, null), day("2026-11-02", 30, 12.6)], value => value.slice(0, 7));
		assert.deepEqual(months[1], {
			period: "2026-11", distanceKm: 50, businessKm: 25, personalKm: 0, drivingMin: 60, trips: 2, maxSpeed: 80,
			trafficBytes: 2000, alarms: 2, restVoltage: 12.6, days: 2
		});
		assert.equal(months[0]!.restVoltage, 12.4);
	});
});

describe("state of the backups", () => {
	test("dumps, last success and off-site copy, stale", async () => {
		const dir = fs.mkdtempSync(path.join(os.tmpdir(), "ct-backups-"));
		try {
			assert.equal((await backupState(dir)).stale, true);
			assert.equal((await backupState(dir)).latest, null);
			for (const folder of ["daily", "weekly", "monthly"]) fs.mkdirSync(path.join(dir, folder));
			fs.writeFileSync(path.join(dir, "daily", "2026-11-20_0330.dump"), Buffer.alloc(100));
			fs.writeFileSync(path.join(dir, "daily", "notes.txt"), "x");
			fs.utimesSync(path.join(dir, "daily", "2026-11-20_0330.dump"), new Date("2026-11-20T03:30:00Z"), new Date("2026-11-20T03:30:00Z"));
			fs.writeFileSync(path.join(dir, "daily", "2026-11-21_0330.dump"), Buffer.alloc(150));
			fs.writeFileSync(path.join(dir, "weekly", "2026-11-16_0330.dump"), Buffer.alloc(80));
			fs.writeFileSync(path.join(dir, "last-success"), "2026-11-21T03:30:12+01:00\n");
			fs.writeFileSync(path.join(dir, "last-offsite"), "broken");
			fs.writeFileSync(path.join(dir, "last-verify"), "not json");
			assert.equal((await backupState(dir)).verify, null);
			fs.writeFileSync(path.join(dir, "last-verify"), JSON.stringify({ time: "2026-11-21T03:40:00+01:00", ok: "yes" }));
			assert.equal((await backupState(dir)).verify, null);
			const verify = { time: "2026-11-15T03:41:07+01:00", file: "daily/2026-11-15_0330.dump", ok: true, seconds: 41, users: 3, devices: 5, positions: 120000, error: "" };
			fs.writeFileSync(path.join(dir, "last-verify"), `${JSON.stringify(verify)}
`);
			const state = await backupState(dir, Date.parse("2026-11-21T12:00:00Z"));
			assert.deepEqual(state, {
				configured: true,
				lastSuccess: new Date("2026-11-21T02:30:12Z"),
				lastOffsite: null,
				stale: false,
				verify: { ...verify, time: new Date("2026-11-15T02:41:07Z") },
				verifyStale: false,
				latest: { name: "daily/2026-11-21_0330.dump", size: 150 },
				files: 3,
				totalBytes: 330
			});
			const later = await backupState(dir, Date.parse("2026-11-25T12:00:00Z"));
			assert.deepEqual([later.stale, later.verifyStale], [true, true]);
			fs.writeFileSync(path.join(dir, "last-verify"), JSON.stringify({ ...verify, ok: false, error: "restore failed" }));
			assert.equal((await backupState(dir, Date.parse("2026-11-15T12:00:00Z"))).verifyStale, true);
			assert.deepEqual(await backupState(""), {
				configured: false, lastSuccess: null, lastOffsite: null, stale: true, verify: null, verifyStale: false, latest: null, files: 0, totalBytes: 0
			});
		} finally {
			fs.rmSync(dir, { recursive: true, force: true });
		}
	});
});

describe("schedules of the arrival areas", () => {
	const rome = "Europe/Rome";
	// Monday 23 November 2026, winter time (UTC+1)
	const at = (day: number, clock: string) => new Date(`2026-11-${22 + day}T${clock}:00+01:00`);

	test("local day and time in the time zone", () => {
		assert.deepEqual(localTime(at(1, "08:30"), rome), { day: 1, minutes: 510 });
		assert.deepEqual(localTime(at(7, "23:59"), rome), { day: 7, minutes: 1439 });
		assert.deepEqual(localTime(new Date("2026-11-23T00:30:00Z"), "UTC"), { day: 1, minutes: 30 });
	});

	test("windows in a day, across midnight, whole days", () => {
		const school = scheduleSchema.parse({ days: [5, 1, 2, 3, 4, 1], from: "07:30", to: "08:30" });
		assert.deepEqual(school.days, [1, 2, 3, 4, 5]);
		assert.equal(inSchedule(school, at(1, "07:30"), rome), true);
		assert.equal(inSchedule(school, at(1, "08:30"), rome), false);
		assert.equal(inSchedule(school, at(6, "08:00"), rome), false);

		// Friday night to Saturday morning, Sunday night to Monday morning
		const night = scheduleSchema.parse({ days: [5, 7], from: "23:00", to: "06:00" });
		assert.equal(inSchedule(night, at(5, "23:30"), rome), true);
		assert.equal(inSchedule(night, at(6, "05:59"), rome), true);
		assert.equal(inSchedule(night, at(6, "23:30"), rome), false);
		assert.equal(inSchedule(night, at(1, "03:00"), rome), true);
		assert.equal(inSchedule(night, at(1, "12:00"), rome), false);
		assert.equal(inSchedule(night, at(5, "03:00"), rome), false);

		const weekend = scheduleSchema.parse({ days: [6, 7], from: "00:00", to: "00:00" });
		assert.equal(inSchedule(weekend, at(7, "15:00"), rome), true);
		assert.equal(inSchedule(weekend, at(1, "00:00"), rome), false);
		assert.equal(inSchedule(null, at(1, "00:00"), rome), true);

		for (const wrong of [{ days: [], from: "07:00", to: "08:00" }, { days: [0], from: "07:00", to: "08:00" }, { days: [1], from: "24:00", to: "08:00" },
			{ days: [1], from: "7:00", to: "08:00" }, { days: [1], from: "07:00" }]) {
			assert.equal(scheduleSchema.safeParse(wrong).success, false, JSON.stringify(wrong));
		}
	});
});

describe("trips of the phones and export", () => {
	test("short stops stay in the trip, a long stop closes it", () => {
		const t0 = Date.parse("2026-01-01T08:00:00Z");
		const at = (minute: number, moving: boolean, step: number) =>
			({ time: new Date(t0 + minute * 60e3), lat: 45 + step * 0.005, lon: 9, speed: moving ? 30 : 0, status: moving ? 0 : 1, stale: false });
		const points = [];
		let step = 0;
		for (let minute = 0; minute <= 60; minute++) {
			const moving = minute <= 10 || (minute >= 13 && minute <= 20) || minute >= 51;
			if (moving) step++;
			points.push(at(minute, moving, step));
		}
		const track = phoneTrack(points);
		assert.deepEqual([track[11]!.status, track[21]!.status, track[22]!.status], [0, 1, 2]);
		assert.equal(points[22]!.status, 1, "the input is not changed");
		const trips = splitTrips(track);
		assert.deepEqual(trips.map(trip => [trip.start.getTime() - t0, trip.end.getTime() - t0].map(ms => ms / 60e3)), [[0, 21], [51, 60]]);
	});

	test("GPX escapes the name, CSV leaves empty fields", () => {
		assert.match(toGpx("A&B <x>", [], []), /<name>A&amp;B &lt;x&gt;<\/name>/);
		const point = { time: new Date(0), lat: null, lon: null, speed: null, status: 2, stale: true, altitude: null, accuracy: null, satellites: null, signal: null, voltage: null };
		assert.equal(toCsv([point], []).split("\r\n")[1], "1970-01-01T00:00:00.000Z,,,,,,,,,2,1,");
	});
});

describe("languages", () => {
	test("every kind has a text in every language, with local time", () => {
		const data = { device: "Panda", area: "Casa", battery: 20, hours: 4, time: "2026-11-21T08:05:00Z" };
		for (const locale of LOCALES) {
			assert.ok(notificationText(locale, "maintenance", { ...data, due: "soon", days: 3 }, "UTC").title.length > 0);
			for (const kind of KINDS) {
				const text = notificationText(locale, kind, data, "Europe/Rome");
				assert.ok(text.title.length > 0 && text.body.includes("09:05"), `${locale} ${kind}: ${JSON.stringify(text)}`);
			}
		}
		assert.equal(notificationText("it", "geofence_enter", data, "Europe/Rome").title, "Panda è arrivato");
		assert.equal(notificationText("it", "phone_battery", data, "Europe/Rome").title, "Panda: batteria al 20%");
		assert.equal(notificationText("it", "long_stop", data, "Europe/Rome").title, "Panda è fermo da più di 4 ore");
		assert.equal(notificationText("it", "long_stop", { ...data, hours: 1 }, "Europe/Rome").title, "Panda è fermo da più di un'ora");
		assert.equal(notificationText("en", "long_stop", data, "Europe/Rome").title, "Panda has been stopped for over 4 hours");
		assert.equal(notificationText("en", "long_stop", { ...data, hours: 1 }, "Europe/Rome").title, "Panda has been stopped for over an hour");
		assert.deepEqual(notificationText("it", "battery_health", { ...data, voltage: 12.1 }, "Europe/Rome"),
			{ title: "Batteria dell'auto da controllare", body: "Panda: tensione a riposo media 12,10 V (ore 09:05)" });
		assert.equal(notificationText("en", "battery_health", { ...data, voltage: 12.1 }, "Europe/Rome").body, "Panda: mean resting voltage 12.10 V (at 09:05)");
		const deadline = (extra: object, locale = "it") => notificationText(locale, "maintenance", { ...data, maintenance: "service", ...extra }, "UTC");
		assert.deepEqual(deadline({ due: "soon", days: 10, km: 1500 }), { title: "Scadenza vicina: Tagliando", body: "Panda: tra 10 giorni o tra 1.500 km" });
		assert.deepEqual(deadline({ due: "due", days: 0, title: "Revisione 2026" }), { title: "Scadenza: Revisione 2026", body: "Panda: oggi" });
		assert.deepEqual(deadline({ due: "due", days: -3, km: -20 }), { title: "Scadenza: Tagliando", body: "Panda: scaduta da 3 giorni o superata di 20 km" });
		assert.deepEqual(deadline({ due: "soon", days: 10, km: 1500 }, "en"), { title: "Coming up: Service", body: "Panda: in 10 days or in 1,500 km" });
		assert.deepEqual(deadline({ due: "due", days: -3, km: -20, maintenance: "unknown" }, "en"), { title: "Due: Deadline", body: "Panda: overdue by 3 days or 20 km over" });
		assert.equal(deadline({ due: "due", days: 0 }, "en").body, "Panda: today");
		assert.equal(notificationText("en", "maintenance", { ...data, due: "due" }, "UTC").title, "Due: Deadline");
		// Unknown or missing language: English
		assert.equal(notificationText(null, "tilt", data, "UTC").title, "Car lifted or tilted");
		assert.equal(notificationText("fr", "tilt", data, "UTC").body, "Panda, at 08:05");
		assert.equal(isLocale("it"), true);
		assert.equal(isLocale(3), false);
	});
});

describe("throttle", () => {
	test("bans after the limit, forgets old entries", () => {
		const throttle = new Throttle(2, 1000, 5000);
		assert.equal(throttle.hit("a", 0), true);
		assert.equal(throttle.hit("a", 10), true);
		assert.equal(throttle.hit("a", 20), false);
		assert.equal(throttle.isBanned("a", 30), true);
		assert.equal(throttle.hit("a", 2000), false);
		assert.equal(throttle.isBanned("a", 6000), false);
		// New window after the ban
		assert.equal(throttle.hit("a", 6000), true);
		assert.equal(throttle.hit("b", 0), true);
		assert.equal(throttle.size, 2);
		throttle.sweep(3000);
		assert.equal(throttle.size, 1);
		throttle.sweep(10000);
		assert.equal(throttle.size, 0);
	});
});

describe("configuration", () => {
	const base = { DATABASE_URL: "postgres://localhost/x", CRYPTO_MASTER_KEY: "k".repeat(32), PUBLIC_URL: "https://cars.example.com/" };

	test("defaults and normalization", () => {
		const config = loadConfig(base);
		assert.equal(config.PUBLIC_URL, "https://cars.example.com");
		assert.equal(config.TIMEZONE, "Europe/Rome");
		assert.equal(config.RATE_LIMIT, 300);
		assert.deepEqual(loadConfig({ ...base, ANDROID_CERT_SHA256: "AA, BB,," }).ANDROID_CERT_SHA256, ["AA", "BB"]);
	});

	test("invalid values are reported together", () => {
		assert.throws(() => loadConfig({ ...base, TIMEZONE: "Mars/Olympus", CRYPTO_MASTER_KEY: "short" }), (error: Error) =>
			/TIMEZONE: unknown time zone/.test(error.message) && /CRYPTO_MASTER_KEY/.test(error.message));
	});
});

describe("error handler", () => {
	const reply = () => {
		const sent: { status?: number; body?: unknown } = {};
		const object = {
			status (code: number) { sent.status = code; return object; },
			send (body: unknown) { sent.body = body; return object; }
		};
		return { sent, reply: object as unknown as FastifyReply };
	};
	const logged: unknown[][] = [];
	const request = { method: "GET", routeOptions: {}, log: { error: (...args: unknown[]) => logged.push(args) } } as unknown as FastifyRequest;

	test("API errors, framework errors, internal errors without details", () => {
		const api = reply();
		errorHandler(new ApiError(409, "email_taken", "Taken"), request, api.reply);
		assert.deepEqual(api.sent, { status: 409, body: { error: "email_taken", message: "Taken" } });

		const framework = reply();
		errorHandler(Object.assign(new Error("Body too large"), { statusCode: 413, code: "FST_ERR_CTP_BODY_TOO_LARGE" }), request, framework.reply);
		assert.deepEqual(framework.sent, { status: 413, body: { error: "fst_err_ctp_body_too_large", message: "Body too large" } });

		const anonymous = reply();
		errorHandler(Object.assign(new Error("Nope"), { statusCode: 418 }) as FastifyError, request, anonymous.reply);
		assert.deepEqual(anonymous.sent.body, { error: "error", message: "Nope" });

		const internal = reply();
		errorHandler(new Error("password=secret in the query") as FastifyError, request, internal.reply);
		assert.deepEqual(internal.sent, { status: 500, body: { error: "internal", message: "Internal error" } });
		// In the log (and the platform log) by route, without a route: unknown
		assert.equal(logged.length, 1);
		assert.equal(logged[0]![1], "GET (unknown)");
	});
});

describe("push", () => {
	const account = (content: object) => {
		const file = path.join(os.tmpdir(), `ct-account-${crypto.randomUUID()}.json`);
		fs.writeFileSync(file, JSON.stringify(content));
		return file;
	};

	test("service account checked, token cached, errors mapped", async () => {
		assert.throws(() => new Fcm(account({ project_id: "x" }), { token: "", api: "" }), /not a Firebase service account/);

		const statuses = [200, 500];
		let tokens = 0;
		let tokenStatus = 500;
		const server = http.createServer((request, response) => {
			request.resume();
			request.on("end", () => {
				if (request.url === "/token") {
					tokens++;
					response.writeHead(tokenStatus, { "content-type": "application/json" });
					response.end(JSON.stringify({ access_token: "t" }));
					return;
				}
				response.writeHead(statuses.shift() ?? 400);
				response.end("{}");
			});
		});
		await new Promise<void>(resolve => server.listen(0, "127.0.0.1", resolve));
		const url = `http://127.0.0.1:${(server.address() as { port: number }).port}`;
		try {
			const { privateKey } = crypto.generateKeyPairSync("rsa", { modulusLength: 2048 });
			const fcm = new Fcm(account({
				project_id: "p", client_email: "a@p.iam.gserviceaccount.com", private_key: privateKey.export({ type: "pkcs8", format: "pem" })
			}), { token: `${url}/token`, api: url });
			await assert.rejects(fcm.send("device", "Title", "Body", {}), /FCM authentication failed: 500/);
			tokenStatus = 200;
			assert.equal(await fcm.send("device", "Title", "Body", {}), "ok");
			assert.equal(await fcm.send("device", "Title", "Body", {}), "error");
			assert.equal(await fcm.send("device", "Title", "Body", {}), "invalid_token");
			assert.equal(tokens, 2);
		} finally {
			await new Promise(resolve => server.close(resolve));
		}
	});
});

describe("web compression script", () => {
	test("command line", () => {
		const root = fs.mkdtempSync(path.join(os.tmpdir(), "ct-compress-"));
		try {
			fs.writeFileSync(path.join(root, "app.js"), "x".repeat(4096));
			fs.writeFileSync(path.join(root, "image.png"), Buffer.alloc(4096));
			const output = execFileSync(process.execPath, ["scripts/compress-web.ts", root], { encoding: "utf8" });
			assert.match(output, /Compressed 1 files/);
			assert.ok(fs.existsSync(path.join(root, "app.js.br")));
			assert.equal(fs.existsSync(path.join(root, "image.png.br")), false);
			assert.throws(() => execFileSync(process.execPath, ["scripts/compress-web.ts"], { stdio: "pipe" }));
		} finally {
			fs.rmSync(root, { recursive: true, force: true });
		}
	});
});
