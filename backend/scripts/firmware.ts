import fs from "node:fs";
import pino from "pino";
import type { FastifyBaseLogger } from "fastify";
import { z } from "zod";
import { DeviceSecrets } from "../src/crypto/device.ts";
import { connect, migrate } from "../src/db.ts";
import { Commands } from "../src/services/commands.ts";
import { Firmware, FirmwareError } from "../src/services/firmware.ts";
import { Hub } from "../src/services/hub.ts";

// Uploads a firmware image for the updates over the air. The image is the .bin of
// arduino-cli compile --export-binaries (firmware.ino.bin), built with DEVICE_KEY all
// zeros: every tracker keeps its own key in the NVS. The owners then install it from
// the app, on the trackers that report the same variant.
// Usage: npm run firmware -- <firmware.ino.bin> <version> [variant] ["notes"]

const [file, version, variant, notes] = process.argv.slice(2);
const env = z.object({ DATABASE_URL: z.string().url(), CRYPTO_MASTER_KEY: z.string().min(32) }).safeParse(process.env);
if (!file || !version || !env.success) {
	console.error("Usage: npm run firmware -- <firmware.ino.bin> <version> [variant] [notes]   (DATABASE_URL and CRYPTO_MASTER_KEY must be set)");
	process.exit(1);
}

const sql = connect(env.data.DATABASE_URL);
try {
	await migrate(sql, () => {});
	const log = pino({ level: "silent" }) as FastifyBaseLogger;
	const secrets = new DeviceSecrets(env.data.CRYPTO_MASTER_KEY);
	const commands = new Commands(sql, secrets, log);
	const hub = new Hub(sql, log, commands);
	const uploaded = await new Firmware(sql, secrets, commands, hub, log).upload(fs.readFileSync(file), version, variant ?? "default", notes ?? "");
	hub.close();
	console.log(`Firmware ${version} (${variant ?? "default"}) uploaded, id ${uploaded.id}, SHA-256 ${uploaded.sha256}`);
} catch (error) {
	if (!(error instanceof FirmwareError)) throw error;
	console.error(error.message);
	process.exitCode = 1;
} finally {
	await sql.end();
}
