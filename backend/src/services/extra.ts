import { z } from "zod";
import type { Context } from "../context.ts";

// Extra data of the trackers (EXTRA frames): a JSON object read from another board of the
// vehicle, stored as it comes and shown to the owner. No processing and no charts: new
// fields of the board need no change of firmware or backend.

export const MAX_EXTRA_KEYS = 50;
// Frames of the firmware are at most 480 bytes: the same limit on the stored text
export const MAX_EXTRA_BYTES = 480;
// Readings without a valid clock (tracker not yet synchronized): stored at reception
const MAX_FUTURE_MS = 10 * 60e3;

export const extraData = z.record(z.string().trim().min(1).max(64), z.json())
	.refine(value => Object.keys(value).length <= MAX_EXTRA_KEYS, `at most ${MAX_EXTRA_KEYS} fields`)
	.refine(value => Buffer.byteLength(JSON.stringify(value)) <= MAX_EXTRA_BYTES, `at most ${MAX_EXTRA_BYTES} bytes`);

/** Stores a reading and sends it to the open connections of the owners; false when invalid */
export async function storeExtra (ctx: Context, deviceId: number, timestamp: number, payload: unknown): Promise<boolean> {
	const parsed = extraData.safeParse(payload);
	if (!parsed.success) return false;
	const now = Date.now();
	const reported = timestamp * 1000;
	const time = new Date(reported > now + MAX_FUTURE_MS || reported < now - ctx.config.RETENTION_DAYS * 86400e3 ? now : reported);
	const inserted = await ctx.sql`
		INSERT INTO device_extra (time, device_id, data) VALUES (${time}, ${deviceId}, ${ctx.sql.json(parsed.data as never)})
		ON CONFLICT (device_id, time) DO NOTHING`;
	// Owner only: viewers see the position, not the data of the vehicle
	if (inserted.count === 1) ctx.hub.toDevice(deviceId, { type: "extra", deviceId, time, data: parsed.data });
	return true;
}
