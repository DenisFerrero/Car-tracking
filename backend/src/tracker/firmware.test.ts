import assert from "node:assert/strict";
import crypto from "node:crypto";
import { after, before, describe, test } from "node:test";
import { FW_STATUS, TYPE, VERSION, encodeFirmwareRequest } from "../protocol/protocol.ts";
import { MAX_IMAGE_SIZE, compareVersions, splitFirmware } from "../services/firmware.ts";
import { Harness, SKIP, Tracker, sleep, waitFor } from "../test/harness.ts";
import type { User } from "../test/harness.ts";

const IMEI = "860000000000060";

/** ESP32 application image: magic byte, then random content */
function image (size: number): Buffer {
	const data = crypto.randomBytes(size);
	data[0] = 0xe9;
	return data;
}

const result = (status: number) => Buffer.from([(VERSION << 4) | TYPE.FW_RESULT, status]);

describe("firmware versions", () => {
	test("variant after the plus, numeric comparison", () => {
		assert.deepEqual(splitFirmware("2.3.0+lilygo"), { version: "2.3.0", variant: "lilygo" });
		assert.deepEqual(splitFirmware("2.2.0"), { version: "2.2.0", variant: "default" });
		assert.deepEqual(splitFirmware("2.2.0+"), { version: "2.2.0", variant: "default" });
		assert.equal(compareVersions("2.10.0", "2.9.9"), 1);
		assert.equal(compareVersions("2.3", "2.3.0"), 0);
		assert.equal(compareVersions("1.x", "1.0.1"), -1);
	});
});

describe("firmware updates over the air", { skip: SKIP }, () => {
	let h: Harness;
	let owner: User;
	let deviceId: number;
	let newer: Buffer;
	const ids: Record<string, number> = {};

	before(async () => {
		h = await Harness.start();
		owner = await h.onboard("owner@example.com", "Owner");
		deviceId = await h.claim(owner, IMEI);
	});
	after(async () => {
		await h?.close();
	});

	test("upload: validation", async () => {
		const firmware = h.server.ctx.firmware;
		newer = image(5000);
		for (const [version, variant, data, code] of [
			["v2", "default", newer, "invalid_version"],
			["2.3.0", "Default!", newer, "invalid_variant"],
			["2.3.0", "default", Buffer.alloc(5000), "invalid_image"],
			["2.3.0", "default", image(MAX_IMAGE_SIZE + 1), "image_too_big"]
		] as [string, string, Buffer, string][]) {
			await assert.rejects(firmware.upload(data, version, variant), { code });
		}
		ids.newer = (await firmware.upload(newer, "2.3.0", "default", "Fix GPS")).id;
		await assert.rejects(firmware.upload(newer, "2.3.0", "default"), { code: "version_exists" });
		ids.older = (await firmware.upload(image(3000), "2.1.0", "default")).id;
		ids.lilygo = (await firmware.upload(image(3000), "2.4.0", "lilygo")).id;
	});

	test("offer, download in windows, installation, new version", async () => {
		const tracker = await Tracker.connect(h, IMEI);
		await tracker.hello("2.2.0+default");

		const state = (await h.api("GET", `/api/devices/${deviceId}/firmware`, { token: owner.token })).body;
		assert.equal(state.version, "2.2.0");
		assert.deepEqual(state.available.map((item: { version: string }) => item.version), ["2.3.0"]);
		assert.equal(state.update, null);

		const install = (firmwareId: number) => h.api("POST", `/api/devices/${deviceId}/firmware`, { token: owner.token, body: { firmwareId } });
		assert.equal((await install(ids.lilygo!)).body.error, "wrong_variant");
		assert.equal((await install(ids.older!)).body.error, "not_newer");
		assert.equal((await install(99999)).status, 404);
		assert.equal((await h.api("POST", `/api/devices/${deviceId}/firmware`, { token: owner.token, body: { firmwareId: "1" } })).status, 400);

		// Before the offer: a request without an update is dropped
		tracker.raw(encodeFirmwareRequest(0, 1024));
		await sleep(50);
		assert.equal(tracker.chunks().length, 0);

		const live = await h.live(owner.token);
		const requested = await install(ids.newer!);
		assert.equal(requested.body.version, "2.3.0");
		await waitFor(() => tracker.offers().length === 1);
		const offer = tracker.offers()[0]!;
		assert.equal(offer.size, 5000);
		assert.equal(offer.version, "2.3.0");
		assert.deepEqual(offer.sha256, crypto.createHash("sha256").update(newer).digest());

		// Windows of 4 KB, then the rest; a window out of the image is dropped
		tracker.raw(encodeFirmwareRequest(0, 4096));
		await waitFor(() => tracker.chunks().length === 4);
		tracker.raw(encodeFirmwareRequest(4096, 5000));
		tracker.raw(encodeFirmwareRequest(4096, 904));
		await waitFor(() => tracker.chunks().length === 5);
		const chunks = tracker.chunks();
		assert.deepEqual(chunks.map(chunk => chunk.offset), [0, 1024, 2048, 3072, 4096]);
		assert.deepEqual(Buffer.concat(chunks.map(chunk => chunk.data)), newer);
		await waitFor(() => live.of("firmware").some(message => (message.update as { sent: number } | null)?.sent === 5000));

		tracker.raw(result(FW_STATUS.INSTALLED));
		await waitFor(() => live.of("firmware").some(message => (message.update as { status: string } | null)?.status === "installed"));
		await tracker.close();

		// After the reboot: the new version
		const rebooted = await Tracker.connect(h, IMEI);
		await rebooted.hello("2.3.0+default");
		await waitFor(() => live.of("firmware").some(message => (message.update as { status: string } | null)?.status === "done"));
		live.close();
		assert.equal(rebooted.offers().length, 0);
		const done = (await h.api("GET", `/api/devices/${deviceId}/firmware`, { token: owner.token })).body;
		assert.equal(done.update.sent, 5000);
		assert.notEqual(done.update.finishedAt, null);
		assert.deepEqual(done.available, []);
		await rebooted.close();

		const [traffic] = await h.sql<{ chunks: number }[]>`SELECT count(*)::int AS chunks FROM traffic WHERE device_id = ${deviceId} AND frame_type = 8`;
		assert.equal(traffic!.chunks, 5);
	});

	test("offered at the next connection; rolled back; failed; cancelled", async () => {
		const firmware = h.server.ctx.firmware;
		const next = (await firmware.upload(image(2000), "2.4.0", "default")).id;
		// Tracker offline: offered at the connection
		assert.equal((await h.api("POST", `/api/devices/${deviceId}/firmware`, { token: owner.token, body: { firmwareId: next } })).status, 200);
		const tracker = await Tracker.connect(h, IMEI);
		await tracker.hello("2.3.0+default");
		await waitFor(() => tracker.offers().length === 1);
		tracker.raw(result(FW_STATUS.INSTALLED));
		await sleep(50);
		await tracker.close();
		// The bootloader went back to the old image
		const again = await Tracker.connect(h, IMEI);
		await again.hello("2.3.0+default");
		await waitFor(async () => (await h.api("GET", `/api/devices/${deviceId}/firmware`, { token: owner.token })).body.update.status === "not_applied");

		// Hash mismatch reported by the tracker
		await h.api("POST", `/api/devices/${deviceId}/firmware`, { token: owner.token, body: { firmwareId: next } });
		await waitFor(() => again.offers().length === 1);
		again.raw(result(FW_STATUS.BAD_HASH));
		await waitFor(async () => (await h.api("GET", `/api/devices/${deviceId}/firmware`, { token: owner.token })).body.update.status === "bad_hash");
		again.raw(result(77));
		await again.close();

		await h.api("POST", `/api/devices/${deviceId}/firmware`, { token: owner.token, body: { firmwareId: next } });
		assert.equal((await h.api("DELETE", `/api/devices/${deviceId}/firmware`, { token: owner.token })).status, 200);
		assert.equal((await h.api("DELETE", `/api/devices/${deviceId}/firmware`, { token: owner.token })).status, 404);
		assert.equal((await h.api("GET", `/api/devices/${deviceId}/firmware`, { token: owner.token })).body.update, null);
	});

	test("administrator: list and removal of the images", async () => {
		const admin = await h.onboard("admin@example.com", "Admin", true);
		assert.equal((await h.api("GET", "/api/admin/firmware", { token: owner.token })).status, 403);
		const list = (await h.api("GET", "/api/admin/firmware", { token: admin.token })).body;
		assert.deepEqual(list.map((item: { version: string }) => item.version).sort(), ["2.1.0", "2.3.0", "2.4.0", "2.4.0"]);
		assert.match(list[0].sha256, /^[0-9a-f]{64}$/);
		assert.equal((await h.api("DELETE", `/api/admin/firmware/${ids.newer}`, { token: admin.token })).status, 200);
		assert.equal((await h.api("DELETE", `/api/admin/firmware/${ids.newer}`, { token: admin.token })).status, 404);
	});
});
