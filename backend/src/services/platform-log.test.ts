import assert from "node:assert/strict";
import { after, before, describe, test } from "node:test";
import { Harness, sleep, waitFor } from "../test/harness.ts";
import type { User } from "../test/harness.ts";
import { PlatformLog } from "./platform-log.ts";

// Platform log: warnings and errors of the services and of the requests, slow requests
// and queries, added up in memory and written in batches; read by the administrators

test("log calls as entries: errors, private fields, sources", async () => {
	const log = new PlatformLog(1000, 100);
	const entries: unknown[] = [];
	// Without a database nothing is written
	await log.flush();
	log.record = (kind, source, message, details) => void entries.push({ kind, source, message, details });
	log.fromLog("warn", "app", [{ err: new Error("timeout"), ip: "1.2.3.4", email: "a@b.c", imei: "860000000000001", component: "fuel", nested: { a: 1 } }, "Fuel prices not updated"]);
	log.fromLog("error", "app", [new TypeError("boom")]);
	log.fromLog("fatal", "jobs", ["Stopped"]);
	log.fromLog("error", "app", [{ err: "plain" }]);
	log.fromLog("warn", "app", [{}]);
	const [fuel, boom, stopped, plain, empty] = entries as { kind: string; source: string; message: string; details: Record<string, unknown> }[];
	assert.equal(fuel!.kind, "warning");
	assert.equal(fuel!.source, "fuel");
	assert.equal(fuel!.message, "Fuel prices not updated");
	assert.equal(fuel!.details.errorMessage, "timeout");
	assert.equal(fuel!.details.imei, "860000000000001");
	assert.equal(fuel!.details.ip, undefined);
	assert.equal(fuel!.details.email, undefined);
	assert.equal(fuel!.details.nested, undefined);
	assert.deepEqual([boom!.kind, boom!.message, boom!.details.error], ["error", "boom", "TypeError"]);
	assert.match(String(boom!.details.stack), /TypeError: boom/);
	assert.deepEqual([stopped!.source, stopped!.message], ["jobs", "Stopped"]);
	assert.deepEqual(plain!.details, { error: "plain" });
	assert.equal(empty!.message, "(no message)");
});

describe("platform log", { skip: !process.env.TEST_DATABASE_URL && "TEST_DATABASE_URL not set" }, () => {
	let h: Harness;
	let admin: User;
	let user: User;

	type Row = { kind: string; source: string; message: string; count: number; duration_ms: number | null; details: Record<string, unknown> };
	const rows = async (kind: string) => {
		await h.server.ctx.platformLog.flush();
		return h.sql<Row[]>`SELECT kind, source, message, count, duration_ms, details FROM platform_log WHERE kind = ${kind} ORDER BY time`;
	};

	before(async () => {
		h = await Harness.start({ LOG_SLOW_REQUEST_MS: "1", LOG_SLOW_QUERY_MS: "1" });
		admin = await h.onboard("admin@example.com", "Admin", true);
		user = await h.onboard("user@example.com", "Utente");
	});
	after(async () => {
		await h?.close();
	});

	test("errors never seen before: notified to the administrators who want them, a few an hour", async () => {
		await h.sql`TRUNCATE platform_log`;
		const adminLive = await h.live(admin.token);
		const userLive = await h.live(user.token);
		const alerts = () => adminLive.of("notification").filter(item => item.notification.kind === "platform_error");
		const log = h.server.ctx.log.child({ component: "backup" });
		log.error("Disk full");
		await rows("error");
		await waitFor(() => alerts().length === 1);
		assert.deepEqual(alerts()[0]!.notification.data.source, "backup");
		assert.deepEqual([alerts()[0]!.notification.data.message, alerts()[0]!.notification.data.others, alerts()[0]!.notification.deviceId], ["Disk full", 0, null]);
		// Seen in the last days: not new; warnings never
		log.error("Disk full");
		log.warn("Slow disk");
		await rows("error");
		// Two new ones in the same batch: one notification
		log.error("Dump failed");
		log.error("Upload failed");
		await rows("error");
		await waitFor(() => alerts().length === 2);
		assert.equal(alerts()[1]!.notification.data.others, 1);
		assert.equal(userLive.of("notification").length, 0);

		// The preference: administrators only
		const account = async (token: string) => (await h.api("GET", "/api/account", { token })).body.adminAlerts;
		assert.deepEqual([await account(admin.token), await account(user.token)], [true, null]);
		assert.equal((await h.api("PATCH", "/api/account", { token: user.token, body: { adminAlerts: true } })).status, 403);
		await h.api("PATCH", "/api/account", { token: admin.token, body: { adminAlerts: false } });
		assert.equal(await account(admin.token), false);
		log.error("Quiet failure");
		await rows("error");
		await h.api("PATCH", "/api/account", { token: admin.token, body: { adminAlerts: true } });
		// At most 6 batches an hour, the one nobody received included: 3 more, the others stay in the log
		for (let n = 0; n < 6; n++) {
			log.error(`Failure ${n}`);
			await rows("error");
		}
		await sleep(200);
		assert.equal(alerts().length, 5);
		assert.ok((await rows("error")).some(row => row.message === "Failure 5"));
		adminLive.close();
		userLive.close();
	});

	test("requests failed and slow, by route pattern", async () => {
		await h.sql`TRUNCATE platform_log`;
		await h.sql`ALTER TABLE dashboards RENAME TO dashboards_moved`;
		try {
			for (let n = 0; n < 2; n++) assert.equal((await h.api("GET", "/api/dashboards", { token: user.token })).status, 500);
		} finally {
			await h.sql`ALTER TABLE dashboards_moved RENAME TO dashboards`;
		}
		// Two failures in one row with their count, without the user or the URL
		const errors = (await rows("error")).filter(row => row.source === "http");
		assert.equal(errors.length, 1);
		assert.equal(errors[0]!.message, "GET /api/dashboards");
		assert.equal(errors[0]!.count, 2);
		assert.equal(errors[0]!.details.status, 500);
		assert.match(String(errors[0]!.details.errorMessage), /dashboards/);
		assert.ok(String(errors[0]!.details.stack).length > 0);

		await h.api("GET", "/api/devices/12345/positions?from=2026-01-01", { token: user.token });
		const slow = await rows("slow_request");
		const positions = slow.find(row => row.message === "GET /api/devices/:id/positions");
		assert.ok(positions, JSON.stringify(slow.map(row => row.message)));
		assert.equal(positions.details.status, 400);
		assert.ok(positions.duration_ms! >= 1);
		assert.equal(typeof positions.details.avgMs, "number");
		// Paths without a route: not logged
		await h.api("GET", "/api/nothing-here", { token: user.token });
		assert.equal((await rows("slow_request")).some(row => row.message.includes("nothing-here")), false);
	});

	test("warnings and errors of the services, too many distinct entries", async () => {
		await h.sql`TRUNCATE platform_log`;
		const log = h.server.ctx.log.child({ component: "fuel" });
		log.warn({ err: new Error("HTTP 503"), ip: "1.2.3.4" }, "Fuel prices not updated");
		log.child({ deviceId: 1 }).error("Failed");
		const warnings = await rows("warning");
		assert.deepEqual(warnings.map(row => [row.source, row.message, row.details.errorMessage, row.details.ip]), [["fuel", "Fuel prices not updated", "HTTP 503", undefined]]);
		assert.deepEqual((await rows("error")).map(row => [row.source, row.message]), [["fuel", "Failed"]]);

		for (let n = 0; n < 205; n++) h.server.ctx.platformLog.record("error", "test", `Error ${n}`);
		assert.equal((await rows("error")).length, 201);
		assert.deepEqual((await rows("warning")).at(-1)!.message, "Log entries dropped (too many distinct)");
		assert.equal((await rows("warning")).at(-1)!.count, 5);
	});

	test("slow queries from pg_stat_statements", async () => {
		await h.sql`TRUNCATE platform_log`;
		const platform = h.server.ctx.platformLog;
		await h.sql`SELECT pg_sleep(0.02)`;
		await platform.snapshotQueries(h.sql);
		if (platform.slowQueriesAvailable) {
			const queries = await rows("slow_query");
			const sleep = queries.find(row => row.message.includes("pg_sleep"));
			assert.ok(sleep, JSON.stringify(queries.map(row => row.message)));
			assert.ok(sleep.duration_ms! >= 20);
			assert.equal(sleep.details.calls, 1);
			// Reset: counted once
			await platform.snapshotQueries(h.sql);
			assert.equal((await rows("slow_query")).filter(row => row.message.includes("pg_sleep")).length, 1);
		}
		// Not loaded: only the other entries
		await h.sql`DROP EXTENSION IF EXISTS pg_stat_statements`;
		await platform.snapshotQueries(h.sql);
		assert.equal(platform.slowQueriesAvailable, false);
		await h.sql`CREATE EXTENSION IF NOT EXISTS pg_stat_statements`;
	});

	test("read by the administrators, grouped", async () => {
		await h.sql`TRUNCATE platform_log`;
		await h.sql`
			INSERT INTO platform_log (time, kind, source, message, count, duration_ms, details) VALUES
				(now() - interval '2 hours', 'slow_request', 'http', 'GET /api/devices', 3, 2000, '{"status": 200, "avgMs": 1500}'),
				(now() - interval '1 hour', 'slow_request', 'http', 'GET /api/devices', 1, 3000, '{"status": 200, "avgMs": 3000}'),
				(now(), 'slow_request', 'http', 'GET /api/dashboards', 1, 1200, '{"status": 200, "avgMs": 1200}'),
				(now() - interval '20 days', 'slow_request', 'http', 'GET /api/old', 9, 5000, '{}'),
				(now(), 'slow_query', 'db', 'SELECT 1', 2, 150, '{"calls": 40, "maxMs": 900}')`;
		const read = (query: string, token = admin.token) => h.api("GET", `/api/admin/logs?${query}`, { token });
		const slow = await read("kind=slow_request");
		assert.equal(slow.status, 200);
		assert.equal(slow.body.retentionDays, 30);
		assert.equal(slow.body.slowRequestMs, 1);
		assert.deepEqual(slow.body.groups.map((group: { message: string }) => group.message), ["GET /api/devices", "GET /api/dashboards"]);
		const devices = slow.body.groups[0];
		assert.equal(devices.count, 4);
		assert.equal(devices.maxMs, 3000);
		assert.equal(devices.avgMs, 1875);
		assert.ok(Date.parse(devices.first) < Date.parse(devices.last));
		assert.equal(devices.details.avgMs, 3000);
		assert.equal((await read("kind=slow_request&days=30")).body.groups.length, 3);

		const queries = (await read("kind=slow_query&days=1")).body;
		assert.deepEqual([queries.groups[0].calls, queries.groups[0].maxMs, queries.groups[0].avgMs], [40, 900, 150]);
		assert.equal(typeof queries.slowQueries, "boolean");

		assert.equal((await read("kind=slow_request", user.token)).status, 403);
		assert.equal((await read("kind=debug")).status, 400);
		assert.equal((await read("kind=error&days=31")).status, 400);
	});
});
