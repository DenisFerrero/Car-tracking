import pino from "pino";
import type { FastifyBaseLogger, FastifyInstance } from "fastify";
import { buildApp, createLogger } from "./app.ts";
import type { Config } from "./config.ts";
import type { Context } from "./context.ts";
import { connect, migrate } from "./db.ts";
import type { Sql } from "./db.ts";
import { SecretBox } from "./auth/secrets.ts";
import { WebAuthn } from "./auth/webauthn.ts";
import { DeviceSecrets } from "./crypto/device.ts";
import { Sessions } from "./http/session.ts";
import { Cells } from "./services/cells.ts";
import { Commands } from "./services/commands.ts";
import { Firmware } from "./services/firmware.ts";
import { Fcm } from "./services/fcm.ts";
import { FuelPrices } from "./services/fuel.ts";
import { Geofences } from "./services/geofences.ts";
import { Hub } from "./services/hub.ts";
import { Notifier } from "./services/notifier.ts";
import { Releases } from "./services/releases.ts";
import { notifyLongStops } from "./services/stops.ts";
import { updateDailyStats } from "./services/daily.ts";
import { checkVehicles } from "./services/vehicle.ts";
import { Gateway } from "./tracker/gateway.ts";
import type { GatewayTimeouts } from "./tracker/gateway.ts";

const JOB_INTERVAL = 10 * 60e3;
const SHARE_JOB_INTERVAL = 60e3;

export interface Server {
	app: FastifyInstance;
	ctx: Context;
	gateway: Gateway;
	/** Address the server listens on, e.g. http://127.0.0.1:4000 */
	address: string;
	close (): Promise<void>;
}

async function applyRetention (sql: Sql, days: number): Promise<void> {
	for (const table of ["positions", "traffic", "device_extra"]) {
		await sql`SELECT remove_retention_policy(${table}, if_exists => true)`;
		await sql`SELECT add_retention_policy(${table}, ${`${days} days`}::interval)`;
	}
}

/**
 * Ended temporary shares: removed with the arrival areas of the viewer on that device,
 * and the open connections of the viewer stop receiving the device
 */
export async function expireShares (ctx: Context): Promise<void> {
	const ended = await ctx.sql<{ device_id: number; user_id: number }[]>`
		DELETE FROM device_users WHERE expires_at <= now() RETURNING device_id, user_id`;
	for (const { device_id: deviceId, user_id: userId } of ended) {
		await ctx.sql`DELETE FROM geofences WHERE device_id = ${deviceId} AND user_id = ${userId}`;
		await ctx.sql`DELETE FROM notification_settings WHERE device_id = ${deviceId} AND user_id = ${userId}`;
		await ctx.hub.refreshUser(userId);
	}
}

/** Offline trackers, expired sessions, invites and challenges */
let lastDailyRun = 0;

/** Runs the hourly part of the jobs at the next run (tests) */
export function resetDailyJobs (): void {
	lastDailyRun = 0;
}

export async function runJobs (ctx: Context): Promise<void> {
	const offline = await ctx.sql<{ id: number; last_seen_at: Date }[]>`
		UPDATE devices SET offline_notified = true
		WHERE NOT offline_notified AND registered_at IS NOT NULL AND kind = 'tracker'
			AND last_seen_at < now() - ${`${ctx.config.OFFLINE_AFTER_HOURS} hours`}::interval
			AND EXISTS (SELECT 1 FROM device_users WHERE device_id = devices.id)
		RETURNING id, last_seen_at`;
	for (const device of offline) await ctx.notifier.notifyDevice(device.id, "offline", device.last_seen_at);
	await notifyLongStops(ctx);
	// Summaries of the days and checks of the cars: every hour is enough
	if (Date.now() - lastDailyRun >= 3600e3) {
		lastDailyRun = Date.now();
		await updateDailyStats(ctx);
		await checkVehicles(ctx);
		// Public data: each at most every 6 hours, failures only logged
		await ctx.fuel.refreshIfStale();
		await ctx.releases.checkIfDue();
	}

	// Positions of the phones: shorter retention than the trackers
	await ctx.sql`
		DELETE FROM positions WHERE device_id IN (SELECT id FROM devices WHERE kind = 'phone')
			AND time < now() - ${`${ctx.config.PHONE_RETENTION_DAYS} days`}::interval`;
	await ctx.sql`UPDATE devices SET paused_until = NULL WHERE paused_until < now()`;
	await ctx.sql`DELETE FROM sessions WHERE expires_at < now()`;
	await ctx.sql`DELETE FROM invites WHERE expires_at < now() - interval '30 days'`;
	await ctx.sql`DELETE FROM webauthn_challenges WHERE expires_at < now()`;
	await ctx.sql`DELETE FROM auth_events WHERE created_at < now() - interval '1 year'`;
	await ctx.sql`DELETE FROM notifications WHERE created_at < now() - interval '1 year'`;
}

export async function startServer (config: Config, log: FastifyBaseLogger = pino(createLogger(config.LOG_LEVEL)) as FastifyBaseLogger,
	trackerTimeouts: Partial<GatewayTimeouts> = {}): Promise<Server> {
	const sql = connect(config.DATABASE_URL);
	await migrate(sql, message => log.info(message));
	await applyRetention(sql, config.RETENTION_DAYS);

	const secrets = new DeviceSecrets(config.CRYPTO_MASTER_KEY);
	const commands = new Commands(sql, secrets, log);
	const hub = new Hub(sql, log, commands);
	const firmware = new Firmware(sql, secrets, commands, hub, log);
	const fcm = config.FCM_SERVICE_ACCOUNT_FILE ? new Fcm(config.FCM_SERVICE_ACCOUNT_FILE, { token: config.FCM_TOKEN_URL, api: config.FCM_API_URL }) : null;
	const notifier = new Notifier(sql, log, hub, fcm, config.TIMEZONE);
	const ctx: Context = {
		config,
		sql,
		log,
		secrets,
		box: new SecretBox(config.CRYPTO_MASTER_KEY),
		webauthn: new WebAuthn(sql, config),
		sessions: new Sessions(sql, config),
		hub,
		commands,
		firmware,
		notifier,
		geofences: new Geofences(sql, notifier, config.TIMEZONE),
		fuel: new FuelPrices(sql, log, config.FUEL_PRICES_URL),
		releases: new Releases(sql, log, firmware, notifier, { repo: config.GITHUB_REPO, apiUrl: config.GITHUB_API_URL, token: config.GITHUB_TOKEN })
	};

	const gateway = new Gateway(ctx, new Cells(sql, log, config.CELL_GEOLOCATION_URL), trackerTimeouts);
	commands.setDownlink(gateway);
	firmware.setDownlink(gateway);

	const app = await buildApp(ctx, gateway);
	const address = await app.listen({ host: config.HOST, port: config.PORT });
	log.info({ publicUrl: config.PUBLIC_URL, push: fcm !== null }, "Car tracking backend ready");

	const jobs = [
		setInterval(() => void runJobs(ctx).catch(error => log.error({ err: error }, "Jobs failed")), JOB_INTERVAL),
		setInterval(() => void expireShares(ctx).catch(error => log.error({ err: error }, "Share expiry failed")), SHARE_JOB_INTERVAL)
	];

	return {
		app,
		ctx,
		gateway,
		address,
		async close () {
			for (const job of jobs) clearInterval(job);
			hub.close();
			await gateway.close();
			await app.close();
			await sql.end({ timeout: 5 });
		}
	};
}
