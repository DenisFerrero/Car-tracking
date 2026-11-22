import type { FastifyBaseLogger } from "fastify";
import type { Config } from "./config.ts";
import type { Sql } from "./db.ts";
import type { DeviceSecrets } from "./crypto/device.ts";
import type { SecretBox } from "./auth/secrets.ts";
import type { WebAuthn } from "./auth/webauthn.ts";
import type { Sessions } from "./http/session.ts";
import type { Hub } from "./services/hub.ts";
import type { Commands } from "./services/commands.ts";
import type { Firmware } from "./services/firmware.ts";
import type { FuelPrices } from "./services/fuel.ts";
import type { Geofences } from "./services/geofences.ts";
import type { Notifier } from "./services/notifier.ts";
import type { PlatformLog } from "./services/platform-log.ts";
import type { Releases } from "./services/releases.ts";

/** Services shared by routes, tracker gateway and jobs */
export interface Context {
	config: Config;
	sql: Sql;
	log: FastifyBaseLogger;
	secrets: DeviceSecrets;
	box: SecretBox;
	webauthn: WebAuthn;
	sessions: Sessions;
	hub: Hub;
	commands: Commands;
	firmware: Firmware;
	notifier: Notifier;
	geofences: Geofences;
	fuel: FuelPrices;
	releases: Releases;
	platformLog: PlatformLog;
}

export async function logAuthEvent (ctx: Context, event: string, data: { userId?: number | null; email?: string; ip?: string; userAgent?: string }): Promise<void> {
	await ctx.sql`
		INSERT INTO auth_events (user_id, email, event, ip, user_agent)
		VALUES (${data.userId ?? null}, ${data.email ?? null}, ${event}, ${data.ip ?? null}, ${(data.userAgent ?? "").slice(0, 300)})`;
}
