import { WebSocket } from "ws";
import { DeviceSecrets } from "../src/crypto/device.ts";
import { COMMAND, DIRECTION_DOWNLINK, RESULT, STATUS, TYPE, decodeAck, decodeCommand, decryptFrame, encodeCommandResult,
	encodeHello, encodeTelemetry, parseFrame } from "../src/protocol/protocol.ts";
import type { Point } from "../src/protocol/protocol.ts";

// Simulates a tracker with the binary protocol of the firmware: HELLO, ACK, a short drive
// sent in batches, then it stays connected answering the commands for a while. Prints the
// bytes exchanged.
// Usage: npm run simulate -- [IMEI] [ws url] [seconds connected]
// Default: 863820040182648 ws://localhost:4000/tracker 30

const imei = process.argv[2] ?? "863820040182648";
const url = process.argv[3] ?? "ws://localhost:4000/tracker";
const linger = Number(process.argv[4] ?? 30);

const BATCH_SIZE = 6;
const SAMPLE_SECONDS = 10;
const POINTS = 60;

const masterKey = process.env.CRYPTO_MASTER_KEY ?? "";
if (masterKey.length < 32) {
	console.error("CRYPTO_MASTER_KEY is not set");
	process.exit(1);
}
const secrets = new DeviceSecrets(masterKey);
const key = secrets.deviceKey(imei);
let counter = Math.floor(Date.now() / 1000);
let deviceId = 0;

// Frames exchanged, without the WebSocket / TLS / TCP overhead
let sent = 0;
let received = 0;
const socket = new WebSocket(url);
socket.binaryType = "nodebuffer";
await new Promise((resolve, reject) => {
	socket.once("open", resolve);
	socket.once("error", reject);
});
socket.on("close", (code, reason) => {
	console.log(`Connection closed: ${code} ${reason.toString()}`);
	process.exit(code === 1000 ? 0 : 1);
});
console.log(`Connected to ${url}`);
// Keepalive like the firmware
setInterval(() => socket.ping(), 60e3).unref();

function publish (frame: Buffer): void {
	sent += frame.length;
	socket.send(frame);
}

socket.on("message", (payload: Buffer) => {
	received += payload.length;
	const frame = parseFrame(payload);
	const plaintext = decryptFrame(frame, key, DIRECTION_DOWNLINK);
	if (!plaintext) {
		console.error("Frame not authenticated: is CRYPTO_MASTER_KEY the same of the server?");
		return;
	}
	if (frame.type === TYPE.ACK && deviceId === 0) {
		deviceId = decodeAck(plaintext);
		console.log(`ACK received, device id ${deviceId}`);
		drive();
	} else if (frame.type === TYPE.COMMAND) {
		const commands = decodeCommand(plaintext);
		const names = Object.fromEntries(Object.entries(COMMAND).map(([name, id]) => [id, name]));
		console.log("Commands:", commands.map(command => `${names[command.id] ?? command.id}${command.seconds !== undefined ? ` ${command.seconds}s` : ""}`).join(", "));
		if (deviceId) {
			publish(encodeCommandResult(key, deviceId, counter++, Math.floor(Date.now() / 1000), frame.counter, RESULT.OK));
		}
	}
});

publish(encodeHello(key, imei, counter++, Math.floor(Date.now() / 1000), {
	manufacturer: "Simulator", model: "Node", revision: "1", firmware: "sim-3.0"
}));
console.log("HELLO sent, waiting for the ACK...");

function drive (): void {
	const start = Date.now() - POINTS * SAMPLE_SECONDS * 1000;
	const points: Point[] = Array.from({ length: POINTS }, (_, i) => ({
		time: new Date(start + i * SAMPLE_SECONDS * 1000),
		lat: 45.4642 + i * 0.0008,
		lon: 9.19 + Math.sin(i / 8) * 0.0012 + i * 0.0006,
		altitude: 120 + Math.round(Math.sin(i / 10) * 4),
		pressure: 1013.2 - i * 0.01,
		temperature: 21.5 + i * 0.05,
		speed: 40 + (i % 15),
		satellites: 6 + (i % 7),
		signal: -75 - (i % 30),
		voltage: 12.6,
		events: 0,
		cell: i % 20 === 0 ? { mcc: 222, mnc: 1, area: 16001, id: 123456789 } : null,
		stale: false,
		status: i === POINTS - 1 ? STATUS.ENGINE_OFF : STATUS.MOVING
	}));

	let bytes = 0;
	for (let i = 0; i < points.length; i += BATCH_SIZE) {
		const frame = encodeTelemetry(key, deviceId, counter++, points.slice(i, i + BATCH_SIZE));
		bytes += frame.length;
		publish(frame);
	}
	console.log(`${POINTS} points in ${Math.ceil(POINTS / BATCH_SIZE)} frames, ${bytes} payload bytes (${(bytes / POINTS).toFixed(1)} bytes/point)`);
	console.log(`Connected for ${linger} s to receive the commands...`);
	setTimeout(() => {
		console.log(`Frame bytes: sent ${sent}, received ${received}`);
		socket.close(1000);
	}, linger * 1000);
}
