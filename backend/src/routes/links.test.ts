import assert from "node:assert/strict";
import { after, before, describe, test } from "node:test";
import { STATUS } from "../protocol/protocol.ts";
import { Harness, PUBLIC_URL } from "../test/harness.ts";
import type { User } from "../test/harness.ts";
import { MAX_ACTIVE_LINKS, purgeLinks } from "./links.ts";

// Temporary links to the live position: created by the owner for 1-24 hours, the page
// without an account shows only name and latest position, revoked or expired links are gone

describe("live links", { skip: !process.env.TEST_DATABASE_URL && "TEST_DATABASE_URL not set" }, () => {
	let h: Harness;
	let anna: User;
	let bruno: User;
	let vehicle: number;

	before(async () => {
		h = await Harness.start();
		anna = await h.onboard("anna@example.com", "Anna");
		bruno = await h.onboard("bruno@example.com", "Bruno");
		vehicle = (await h.api("POST", "/api/vehicles", { token: anna.token, body: { name: "Panda", color: "#FF5722" } })).body.id;
	});
	after(async () => {
		await h?.close();
	});

	const token = (url: string) => url.split("/l/")[1]!;
	const view = (value: string) => h.api("GET", `/api/public/links/${value}`);

	test("created by the owner, page without account: name and latest position only", async () => {
		const path = `/api/devices/${vehicle}/links`;
		for (const body of [{ hours: 0 }, { hours: 25 }, { hours: 1.5 }, { hours: 2, label: "x".repeat(41) }, {}]) {
			assert.equal((await h.api("POST", path, { token: anna.token, body })).status, 400, JSON.stringify(body));
		}
		assert.equal((await h.api("POST", path, { token: bruno.token, body: { hours: 2 } })).status, 404);
		await h.befriend(anna, bruno);
		await h.api("POST", `/api/devices/${vehicle}/shares`, { token: anna.token, body: { userId: bruno.id, expiresAt: null } });
		assert.equal((await h.api("POST", path, { token: bruno.token, body: { hours: 2 } })).body.error, "owner_only");
		assert.equal((await h.api("GET", path, { token: bruno.token })).body.error, "owner_only");

		const created = (await h.api("POST", path, { token: anna.token, body: { hours: 2, label: " Mamma " } })).body;
		assert.match(created.url, new RegExp(`^${PUBLIC_URL}/#/l/[A-Za-z0-9_-]{43}$`));
		assert.ok(Math.abs(Date.parse(created.expiresAt) - Date.now() - 2 * 3600e3) < 5000);
		assert.deepEqual(created.links.map((link: { label: string; token?: string }) => [link.label, link.token]), [["Mamma", undefined]]);
		assert.deepEqual((await h.api("GET", path, { token: anna.token })).body.max, MAX_ACTIVE_LINKS);

		// No position yet
		const empty = await view(token(created.url));
		assert.equal(empty.status, 200);
		assert.deepEqual(empty.body, { name: "Panda", color: "#FF5722", kind: "vehicle", expiresAt: created.expiresAt, position: null });
		await h.sql`
			INSERT INTO positions (time, device_id, lat, lon, speed, status) VALUES
				(now() - interval '3 minutes', ${vehicle}, 45.0, 7.6, 30, ${STATUS.MOVING}),
				(now() - interval '1 minute', ${vehicle}, 45.1, 7.7, 0, ${STATUS.ENGINE_OFF})`;
		const parked = (await view(token(created.url))).body.position;
		assert.deepEqual([parked.lat, parked.lon, parked.speed], [45.1, 7.7, null]);
		await h.sql`INSERT INTO positions (time, device_id, lat, lon, speed, status) VALUES (now(), ${vehicle}, 45.2, 7.8, 52, ${STATUS.MOVING})`;
		const moving = (await view(token(created.url))).body;
		assert.deepEqual([moving.position.lat, moving.position.speed], [45.2, 52]);
		// Nothing of the tracker, the account or the history
		assert.deepEqual(Object.keys(moving).sort(), ["color", "expiresAt", "kind", "name", "position"]);
		assert.deepEqual(Object.keys(moving.position).sort(), ["lat", "lon", "speed", "time"]);
		const [link] = (await h.api("GET", path, { token: anna.token })).body.links;
		assert.ok(link.lastViewedAt);

		for (const value of ["short", "x".repeat(200), "a".repeat(43).replace(/a$/, "!"), "b".repeat(43)]) {
			assert.equal((await view(value)).status, 404, value);
		}
	});

	test("at most a few active, revoked by the owner, expired, removed with the device", async () => {
		const path = `/api/devices/${vehicle}/links`;
		const urls: string[] = [];
		for (let n = (await h.api("GET", path, { token: anna.token })).body.links.length; n < MAX_ACTIVE_LINKS; n++) {
			urls.push((await h.api("POST", path, { token: anna.token, body: { hours: 1 } })).body.url);
		}
		assert.equal((await h.api("POST", path, { token: anna.token, body: { hours: 1 } })).body.error, "too_many_links");

		const [first] = (await h.api("GET", path, { token: anna.token })).body.links;
		assert.equal((await h.api("DELETE", `/api/links/${first.id}`, { token: bruno.token })).status, 404);
		const left = (await h.api("DELETE", `/api/links/${first.id}`, { token: anna.token })).body.links;
		assert.equal(left.length, MAX_ACTIVE_LINKS - 1);
		assert.equal((await h.api("DELETE", `/api/links/${first.id}`, { token: anna.token })).status, 404);
		assert.equal((await view(token(urls.at(-1)!))).status, 404);

		// Expired: gone from the page and the list, removed after a week
		await h.sql`UPDATE live_links SET expires_at = now() - interval '1 second' WHERE device_id = ${vehicle}`;
		assert.equal((await view(token(urls[0]!))).status, 404);
		assert.deepEqual((await h.api("GET", path, { token: anna.token })).body.links, []);
		await purgeLinks(h.server.ctx);
		const [kept] = await h.sql<{ count: number }[]>`SELECT count(*)::int AS count FROM live_links`;
		assert.equal(kept!.count, MAX_ACTIVE_LINKS);
		await h.sql`UPDATE live_links SET expires_at = now() - interval '8 days'`;
		await purgeLinks(h.server.ctx);
		const [purged] = await h.sql<{ count: number }[]>`SELECT count(*)::int AS count FROM live_links`;
		assert.equal(purged!.count, 0);

		// A phone too; links and device removed together
		const phone = (await h.api("POST", "/api/phones", { token: anna.token, body: { name: "Pixel" } })).body.id;
		const shared = (await h.api("POST", `/api/devices/${phone}/links`, { token: anna.token, body: { hours: 24 } })).body.url;
		assert.equal((await view(token(shared))).body.kind, "phone");
		await h.api("DELETE", `/api/devices/${phone}`, { token: anna.token });
		assert.equal((await view(token(shared))).status, 404);
		// A released tracker: links of the previous owner removed
		const tracker = await h.claim(anna, "860000000000401", "Golf");
		await h.api("POST", `/api/devices/${tracker}/links`, { token: anna.token, body: { hours: 3 } });
		await h.api("DELETE", `/api/devices/${tracker}`, { token: anna.token });
		const [released] = await h.sql<{ count: number }[]>`SELECT count(*)::int AS count FROM live_links WHERE device_id = ${tracker}`;
		assert.equal(released!.count, 0);
	});
});
