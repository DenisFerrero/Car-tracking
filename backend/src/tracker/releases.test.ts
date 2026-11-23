import assert from "node:assert/strict";
import crypto from "node:crypto";
import http from "node:http";
import type { AddressInfo } from "node:net";
import { after, before, describe, test } from "node:test";
import { FW_STATUS, TYPE, VERSION, encodeExtra, encodeUpdateCheck } from "../protocol/protocol.ts";
import { resetDailyJobs, runJobs } from "../server.ts";
import { Harness, SKIP, Tracker, sleep, waitFor } from "../test/harness.ts";
import type { User } from "../test/harness.ts";

// Automatic firmware updates (UPDATE_CHECK), extra data of the trackers (EXTRA), latest
// release of the repository (firmware images and app), national fuel prices: the public
// sources are a local server

const IMEI = "860000000000078";
const OTHER_IMEI = "860000000000086";

function image (size: number): Buffer {
	const data = crypto.randomBytes(size);
	data[0] = 0xe9;
	return data;
}

const result = (status: number) => Buffer.from([(VERSION << 4) | TYPE.FW_RESULT, status]);

interface Route {
	status?: number;
	type?: string;
	body: string | Buffer;
}

describe("automatic updates, extra data, releases, fuel prices", { skip: SKIP }, () => {
	let h: Harness;
	let owner: User;
	let deviceId: number;
	let server: http.Server;
	let base: string;
	const routes = new Map<string, Route>();
	const requests: string[] = [];

	before(async () => {
		server = http.createServer((request, response) => {
			requests.push(request.url!);
			const route = routes.get(request.url!);
			response.writeHead(route?.status ?? (route ? 200 : 404), { "content-type": route?.type ?? "application/json" });
			response.end(route?.body ?? "{}");
		});
		await new Promise<void>(resolve => server.listen(0, "127.0.0.1", resolve));
		base = `http://127.0.0.1:${(server.address() as AddressInfo).port}`;
		h = await Harness.start({ GITHUB_REPO: "me/car-tracking", GITHUB_API_URL: base, FUEL_PRICES_URL: `${base}/fuel.csv` });
		owner = await h.onboard("auto@example.com", "Auto");
		deviceId = await h.claim(owner, IMEI);
	});
	after(async () => {
		await h?.close();
		server?.close();
	});

	test("daily check of the tracker: newest image, owner switch, failed image not retried", async () => {
		const firmware = h.server.ctx.firmware;
		const state = () => h.api("GET", `/api/devices/${deviceId}/firmware`, { token: owner.token }).then(response => response.body);
		const tracker = await Tracker.connect(h, IMEI);
		await tracker.hello("2.0.0+lilygo-sim");
		const check = () => tracker.raw(encodeUpdateCheck(tracker.key, tracker.deviceId, tracker.counter++, Math.floor(Date.now() / 1000)));
		assert.deepEqual([(await state()).autoUpdate, (await state()).updateCheckedAt], [true, null]);

		// Nothing newer yet
		check();
		await waitFor(async () => (await state()).updateCheckedAt !== null);
		assert.equal(tracker.offers().length, 0);

		await firmware.upload(image(2000), "2.1.0", "lilygo-sim");
		const newest = (await firmware.upload(image(2000), "2.2.0", "lilygo-sim")).id;
		await firmware.upload(image(2000), "2.9.0", "default");

		// Stopped by the owner
		const off = await h.api("PUT", `/api/devices/${deviceId}/firmware/auto`, { token: owner.token, body: { enabled: false } });
		assert.equal(off.body.autoUpdate, false);
		assert.equal((await h.api("PUT", `/api/devices/${deviceId}/firmware/auto`, { token: owner.token, body: { enabled: "no" } })).status, 400);
		check();
		await sleep(100);
		assert.equal(tracker.offers().length, 0);

		await h.api("PUT", `/api/devices/${deviceId}/firmware/auto`, { token: owner.token, body: { enabled: true } });
		check();
		await waitFor(() => tracker.offers().length === 1);
		assert.equal(tracker.offers()[0]!.version, "2.2.0");
		const update = (await state()).update;
		assert.deepEqual([update.automatic, update.firmwareId], [true, newest]);
		// Already pending: offered again
		check();
		await waitFor(() => tracker.offers().length === 2);

		// Rolled back: the same image is not tried again
		tracker.raw(result(FW_STATUS.INSTALLED));
		await waitFor(async () => (await state()).update.status === "installed");
		await tracker.close();
		const again = await Tracker.connect(h, IMEI);
		await again.hello("2.0.0+lilygo-sim");
		await waitFor(async () => (await state()).update.status === "not_applied");
		again.raw(encodeUpdateCheck(again.key, again.deviceId, again.counter++, Math.floor(Date.now() / 1000)));
		await sleep(100);
		assert.equal(again.offers().length, 0);
		assert.equal(await firmware.autoUpdate(99999), null);
		await again.close();
	});

	test("extra data: stored as it comes, latest value of each field, owner only", async () => {
		const tracker = await Tracker.connect(h, IMEI);
		await tracker.hello("2.0.0+lilygo-sim");
		const live = await h.live(owner.token);
		const now = Math.floor(Date.now() / 1000);
		const extra = (json: string, timestamp = now) => tracker.raw(encodeExtra(tracker.key, tracker.deviceId, tracker.counter++, timestamp, json));
		extra(JSON.stringify({ rpm: 820, coolant: 88.5, dtc: ["P0420"] }), now - 120);
		extra(JSON.stringify({ rpm: 900, fuelLevel: 41 }), now - 60);
		// Clock not synchronized: stored at reception
		extra(JSON.stringify({ door: "open" }), 0);
		await waitFor(() => live.of("extra").length === 3);
		assert.deepEqual(live.of("extra")[0]!.data, { rpm: 820, coolant: 88.5, dtc: ["P0420"] });

		// Not a JSON object, too many fields, too big, not UTF-8: dropped, the connection stays
		extra("[1, 2]");
		extra("not json");
		extra(JSON.stringify(Object.fromEntries(Array.from({ length: 51 }, (_, i) => [`k${i}`, i]))));
		extra(JSON.stringify({ text: "x".repeat(500) }));
		await sleep(100);
		assert.equal(tracker.closed, null);
		extra(JSON.stringify({ rpm: 0 }), now - 60);

		const path = `/api/devices/${deviceId}/extra`;
		const data = (await h.api("GET", path, { token: owner.token })).body;
		assert.equal(data.items.length, 3);
		assert.deepEqual(data.items[0].data, { door: "open" });
		assert.ok(Date.now() - Date.parse(data.items[0].time) < 60e3);
		assert.deepEqual(Object.fromEntries(data.latest.map((item: { key: string; value: unknown }) => [item.key, item.value])),
			{ coolant: 88.5, door: "open", dtc: ["P0420"], fuelLevel: 41, rpm: 900 });
		const period = await h.api("GET", `${path}?from=${new Date((now - 90) * 1000).toISOString()}&to=${new Date((now - 30) * 1000).toISOString()}&limit=5`, { token: owner.token });
		assert.deepEqual(period.body.items.map((item: { data: { rpm: number } }) => item.data.rpm), [900]);
		assert.equal((await h.api("GET", `${path}?limit=0`, { token: owner.token })).status, 400);
		const viewer = await h.onboard("viewer-extra@example.com", "Viewer");
		assert.equal((await h.api("GET", path, { token: viewer.token })).status, 404);
		live.close();
		await tracker.close();
	});

	test("latest release: firmware images, notification, app version", async () => {
		const asset = (name: string, data: Buffer, digest = `sha256:${crypto.createHash("sha256").update(data).digest("hex")}`) => {
			routes.set(`/download/${name}`, { body: data, type: "application/octet-stream" });
			return { name, size: data.length, browser_download_url: `${base}/download/${name}`, digest };
		};
		const good = image(3000);
		const release = (tag: string, assets: object[]) => routes.set("/repos/me/car-tracking/releases/latest", {
			body: JSON.stringify({ tag_name: tag, name: `Car tracking ${tag}`, html_url: `https://github.com/me/car-tracking/releases/tag/${tag}`, published_at: "2026-11-20T10:00:00Z", assets })
		});
		const releases = h.server.ctx.releases;

		// No release yet, then a failure of GitHub
		assert.equal(await releases.check(), 0);
		routes.set("/repos/me/car-tracking/releases/latest", { status: 500, body: "{}" });
		await assert.rejects(releases.check(), /HTTP 500/);
		release("nightly", []);
		assert.equal(await releases.check(), 0);

		const live = await h.live(owner.token);
		const other = await h.claim(owner, OTHER_IMEI, "Punto");
		const tracker = await Tracker.connect(h, OTHER_IMEI);
		await tracker.hello("2.3.0+lilygo-wifi-sim");
		await tracker.close();
		release("v2.5.0", [
			asset("firmware-lilygo-sim.bin", good),
			asset("firmware-lilygo-wifi-sim.bin", image(2000), "sha256:00"),
			asset("firmware-broken.bin", Buffer.alloc(300)),
			{ name: "firmware-huge.bin", size: 3 * 1024 * 1024, browser_download_url: `${base}/download/huge` },
			asset("checksums.txt", Buffer.from("x")),
			asset("car-tracking-2.5.0.apk", Buffer.from("apk"))
		]);
		const admin = await h.onboard("admin-releases@example.com", "Admin", true);
		assert.deepEqual((await h.api("POST", "/api/admin/releases/check", { token: admin.token })).body, { added: 1 });
		assert.equal((await h.api("POST", "/api/admin/releases/check", { token: owner.token })).status, 403);
		const images = (await h.api("GET", "/api/admin/firmware", { token: admin.token })).body;
		const downloaded = images.find((item: { version: string; variant: string }) => item.version === "2.5.0");
		assert.deepEqual([downloaded.variant, downloaded.notes, downloaded.releaseUrl],
			["lilygo-sim", "Car tracking v2.5.0", "https://github.com/me/car-tracking/releases/tag/v2.5.0"]);
		// Owner of the tracker with that variant: it asks every day, it installs by itself
		await waitFor(() => live.of("notification").some(item => item.notification.kind === "firmware"));
		const notice = live.of("notification").find(item => item.notification.kind === "firmware")!;
		assert.deepEqual([notice.notification.deviceId, notice.notification.data.version, notice.notification.data.automatic], [deviceId, "2.5.0", true]);
		assert.equal(live.of("notification").filter(item => item.notification.kind === "firmware" && item.notification.deviceId === other).length, 0);
		live.close();
		// Already known: nothing downloaded again
		const downloads = requests.filter(url => url.startsWith("/download/firmware-lilygo-sim")).length;
		assert.equal(await releases.check(), 0);
		assert.equal(requests.filter(url => url.startsWith("/download/firmware-lilygo-sim")).length, downloads);

		assert.deepEqual((await h.api("GET", "/api/app/release", { token: owner.token })).body.release, {
			version: "2.5.0", url: "https://github.com/me/car-tracking/releases/tag/v2.5.0",
			apkUrl: `${base}/download/car-tracking-2.5.0.apk`, publishedAt: "2026-11-20T10:00:00.000Z"
		});

		// A download that fails stops the check (retried at the next one)
		release("v2.6.0", [{ name: "firmware-lilygo-sim.bin", size: 10, browser_download_url: `${base}/download/missing` }]);
		await assert.rejects(releases.check(), /HTTP 404/);
		await releases.checkIfDue();
		await releases.checkIfDue();
	});

	test("national fuel prices: downloaded when old, followed by the vehicles", async () => {
		routes.set("/fuel.csv", {
			type: "text/csv; charset=ISO-8859-1",
			body: Buffer.from('DATA_RILEVAZIONE,BENZINA,GASOLIO_AUTO,GPL\r\n2026-11-09,"1.955,2","2.201,4","833,1"\r\n2026-11-16,"1.969,6","2.210,01","835,66"\r\n', "latin1")
		});
		await h.api("PUT", `/api/devices/${deviceId}/vehicle`, { token: owner.token, body: { fuelUnit: "l_per_100km", fuelType: "diesel", fuelPriceAuto: true } });
		const fuel = h.server.ctx.fuel;
		assert.equal(await fuel.refreshIfStale(), 2);
		const vehicle = (await h.api("GET", `/api/devices/${deviceId}/vehicle`, { token: owner.token })).body;
		assert.deepEqual(vehicle.average, { week: "2026-11-16", price: 2.21 });
		assert.deepEqual(vehicle.rates.price, [{ validFrom: "2026-11-16", value: 2.21, source: "auto" }]);
		// Tried at most every 6 hours
		assert.equal(await fuel.refreshIfStale(), 0);
		// Recent weeks: not downloaded again; errors only logged
		const monday = new Date();
		monday.setUTCDate(monday.getUTCDate() - 1);
		await h.sql`INSERT INTO fuel_averages (fuel, week, price) VALUES ('petrol', ${monday.toISOString().slice(0, 10)}, 1.9)`;
		assert.equal(await fuel.refreshIfStale(Date.now() + 7 * 3600e3), 0);
		await h.sql`DELETE FROM fuel_averages WHERE price = 1.9`;
		routes.set("/fuel.csv", { status: 503, body: "" });
		assert.equal(await fuel.refreshIfStale(Date.now() + 14 * 3600e3), 0);
		routes.set("/fuel.csv", { body: "DATA_RILEVAZIONE,BENZINA\r\n" });
		assert.equal(await fuel.refresh(), 0);
		// The jobs run both checks
		resetDailyJobs();
		await runJobs(h.server.ctx);
	});
});
