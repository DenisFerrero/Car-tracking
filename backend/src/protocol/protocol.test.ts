import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { DeviceSecrets } from "../crypto/device.ts";
import * as protocol from "./protocol.ts";
import type { Point } from "./protocol.ts";

const secrets = new DeviceSecrets("test-master-key-with-at-least-32-characters");
const IMEI = "863820040182648";
const KEY = secrets.deviceKey(IMEI);

function drive (count: number, start = Date.UTC(2026, 10, 20, 8, 0, 0)): Point[] {
	return Array.from({ length: count }, (_, i) => ({
		time: new Date(start + i * 5000),
		lat: Math.round((45.46421 + i * 0.00041) * 1e5) / 1e5,
		lon: Math.round((9.19003 + i * 0.00052) * 1e5) / 1e5,
		altitude: 120 + (i % 3),
		pressure: Math.round((1013.2 - i / 10) * 10) / 10,
		temperature: Math.round((21.5 + i / 10) * 10) / 10,
		speed: 45 + i,
		satellites: null,
		signal: null,
		voltage: null,
		events: 0,
		cell: null,
		stale: false,
		status: protocol.STATUS.MOVING
	}));
}

function roundTrip (points: Point[], deviceId = 7, counter = 1): Point[] {
	const frame = protocol.parseFrame(protocol.encodeTelemetry(KEY, deviceId, counter, points));
	const plaintext = protocol.decryptFrame(frame, KEY);
	assert.ok(plaintext);
	return protocol.decodeTelemetry(plaintext, frame.timestamp);
}

describe("device secrets", () => {
	it("derives a different key for every IMEI", () => {
		assert.equal(KEY.length, 32);
		assert.ok(!secrets.deviceKey("863820040182649").equals(KEY));
	});

	it("verifies pairing codes ignoring case, dashes and ambiguous characters", () => {
		const code = secrets.pairingCode(IMEI);
		assert.match(code, /^[0-9A-Z]{4}-[0-9A-Z]{4}$/);
		assert.ok(secrets.verifyPairingCode(IMEI, code));
		assert.ok(secrets.verifyPairingCode(IMEI, code.toLowerCase().replace("-", " ")));
		assert.ok(!secrets.verifyPairingCode(IMEI, "AAAA-AAAA"));
		assert.ok(!secrets.verifyPairingCode("863820040182649", code));
	});

	it("keeps the derivations of the first server (compatible with the provisioned trackers)", () => {
		// Same values of the previous JavaScript implementation with this master key
		const reference = new DeviceSecrets("cross-check-master-key-at-least-32-chars");
		assert.equal(reference.deviceKey(IMEI).toString("hex"), "156e8fe933ab0522b0ef5d1968de7b91953044a04019db63cbb4e9dc394e8855");
		assert.equal(reference.pairingCode(IMEI), "6MDF-SV3C");
	});
});

describe("protocol", () => {
	it("round trips a HELLO frame", () => {
		const info = { manufacturer: "SIMCOM", model: "A7670E", revision: "R1", firmware: "2.0.0" };
		const frame = protocol.parseFrame(protocol.encodeHello(KEY, IMEI, 7, 1763625600, info));
		assert.equal(frame.type, protocol.TYPE.HELLO);
		assert.equal(frame.imei, IMEI);
		assert.deepEqual(protocol.decodeHello(protocol.decryptFrame(frame, KEY)!), info);
	});

	it("round trips a TELEMETRY batch with optional fields", () => {
		const points = drive(6);
		points[2]!.pressure = null;
		points[2]!.temperature = null;
		points[4]!.altitude = null;
		points[5]!.status = protocol.STATUS.ENGINE_OFF;

		const decoded = roundTrip(points, 42, 1000);
		assert.equal(decoded.length, 6);
		decoded.forEach((point, i) => {
			const expected = points[i]!;
			assert.deepEqual(point.time, expected.time);
			assert.ok(Math.abs(point.lat - expected.lat) < 1e-9);
			assert.ok(Math.abs(point.lon - expected.lon) < 1e-9);
			assert.equal(point.altitude, expected.altitude);
			assert.equal(point.pressure, expected.pressure);
			assert.equal(point.speed, expected.speed);
			assert.equal(point.status, expected.status);
		});
	});

	it("round trips satellites, signal, voltage, events, cell and stale", () => {
		const points = drive(4);
		Object.assign(points[0]!, { satellites: 9, signal: -71, voltage: 12.64 });
		Object.assign(points[1]!, { satellites: 11 });
		Object.assign(points[2]!, { signal: -95, voltage: 11.72, events: protocol.EVENT.MOTION | protocol.EVENT.TILT, status: protocol.STATUS.ALARM });
		Object.assign(points[3]!, { stale: true, cell: { mcc: 222, mnc: 10, area: 0x5a1b, id: 26834437 } });

		const decoded = roundTrip(points);
		assert.deepEqual(decoded.map(p => p.satellites), [9, 11, null, null]);
		assert.deepEqual(decoded.map(p => p.signal), [-71, null, -95, null]);
		assert.deepEqual(decoded.map(p => p.voltage), [12.64, null, 11.72, null]);
		assert.deepEqual(decoded.map(p => p.events), [0, 0, 3, 0]);
		assert.deepEqual(decoded.map(p => p.stale), [false, false, false, true]);
		assert.deepEqual(decoded[3]!.cell, { mcc: 222, mnc: 10, area: 0x5a1b, id: 26834437 });
	});

	it("round trips a COMMAND on the downlink and its result on the uplink", () => {
		const commands = [
			{ id: protocol.COMMAND.LIVE, seconds: 300 },
			{ id: protocol.COMMAND.ANTITHEFT, seconds: 7200 },
			{ id: protocol.COMMAND.LOCATE }
		];
		const buffer = protocol.encodeCommand(KEY, 1763625600, 1763625600, commands);
		const frame = protocol.parseFrame(buffer);
		assert.equal(frame.type, protocol.TYPE.COMMAND);
		assert.equal(protocol.decryptFrame(frame, KEY), null);
		assert.deepEqual(protocol.decodeCommand(protocol.decryptFrame(frame, KEY, protocol.DIRECTION_DOWNLINK)!), commands);
		assert.ok(buffer.length < 30);

		const result = protocol.parseFrame(protocol.encodeCommandResult(KEY, 7, 99, 1763625601, 1763625600, protocol.RESULT.OK));
		assert.equal(result.type, protocol.TYPE.COMMAND_RESULT);
		assert.equal(result.deviceId, 7);
		assert.deepEqual(protocol.decodeCommandResult(protocol.decryptFrame(result, KEY)!), { counter: 1763625600, result: 0 });
	});

	it("rejects unknown extended flags", () => {
		const plaintext = Buffer.from([0x80, 0, 2, 2, 0x40]);
		assert.throws(() => protocol.decodeTelemetry(plaintext, 1763625600), protocol.ProtocolError);
	});

	it("encodes negative coordinates and keeps frames small", () => {
		const points = drive(3).map(point => ({ ...point, lat: -point.lat, lon: -point.lon - 100 }));
		const decoded = roundTrip(points);
		assert.ok(Math.abs(decoded[2]!.lat - points[2]!.lat) < 1e-9);
		assert.ok(Math.abs(decoded[2]!.lon - points[2]!.lon) < 1e-9);

		const single = protocol.encodeTelemetry(KEY, 1, 1, drive(1));
		const batch = protocol.encodeTelemetry(KEY, 1, 2, drive(12));
		assert.ok(single.length <= 45);
		assert.ok((batch.length - single.length) / 11 < 10, "every point after the first one costs less than 10 bytes");
	});

	it("rejects tampered frames, wrong keys and wrong directions", () => {
		const encoded = protocol.encodeTelemetry(KEY, 42, 1000, drive(2));

		const otherDevice = Buffer.from(encoded);
		otherDevice[1] = 43;  // the device id is authenticated as AAD
		assert.equal(protocol.decryptFrame(protocol.parseFrame(otherDevice), KEY), null);

		const flipped = Buffer.from(encoded);
		flipped[12]! ^= 1;
		assert.equal(protocol.decryptFrame(protocol.parseFrame(flipped), KEY), null);

		const frame = protocol.parseFrame(encoded);
		assert.equal(protocol.decryptFrame(frame, secrets.deviceKey("863820040182649")), null);
		assert.equal(protocol.decryptFrame(frame, KEY, protocol.DIRECTION_DOWNLINK), null);
	});

	it("round trips an ACK on the downlink direction", () => {
		const frame = protocol.parseFrame(protocol.encodeAck(KEY, 300, 5, 1763625600));
		assert.equal(frame.type, protocol.TYPE.ACK);
		assert.equal(protocol.decryptFrame(frame, KEY), null);
		assert.equal(protocol.decodeAck(protocol.decryptFrame(frame, KEY, protocol.DIRECTION_DOWNLINK)!), 300);
	});

	it("rejects malformed frames", () => {
		assert.throws(() => protocol.parseFrame(Buffer.alloc(5)), protocol.ProtocolError);
		assert.throws(() => protocol.parseFrame(Buffer.from("{\"x\":1,\"y\":2,\"d\":1,\"pad\":\"....\"}")), protocol.ProtocolError);
		assert.throws(() => protocol.parseFrame(Buffer.alloc(2048)), protocol.ProtocolError);
		assert.throws(() => protocol.decodeTelemetry(Buffer.from([0x05, 0, 0, 0]), 1763625600), protocol.ProtocolError);
	});
});
