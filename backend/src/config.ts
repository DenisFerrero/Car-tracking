import { z } from "zod";

// Every setting comes from the environment (.env in development, docker compose in
// production). Invalid values stop the process at startup.

const list = z.string().transform(value => value.split(",").map(item => item.trim()).filter(Boolean));

const schema = z.object({
	NODE_ENV: z.enum(["development", "production", "test"]).default("development"),
	HOST: z.string().default("0.0.0.0"),
	PORT: z.coerce.number().int().min(0).max(65535).default(4000),
	LOG_LEVEL: z.enum(["fatal", "error", "warn", "info", "debug", "trace", "silent"]).default("info"),

	DATABASE_URL: z.string().url(),

	// Secret of the platform (min 32 characters): device keys and pairing codes are
	// derived from it, TOTP secrets are encrypted with it. Changing it means
	// reprogramming every tracker and enrolling every TOTP again.
	CRYPTO_MASTER_KEY: z.string().min(32),

	// Public address of the platform, e.g. https://tracking.example.com: WebAuthn relying
	// party (passkeys are bound to this domain) and allowed origin of the browser requests
	PUBLIC_URL: z.string().url().transform(value => value.replace(/\/+$/, "")),
	APP_NAME: z.string().default("Car Tracking"),
	// Proxies in front of the backend (Traefik): the client address comes from X-Forwarded-For
	TRUST_PROXY: z.string().default("loopback,uniquelocal"),

	// Android app: package name and SHA-256 fingerprints of the signing certificates, for
	// the passkeys in the app (Digital Asset Links, /.well-known/assetlinks.json)
	ANDROID_PACKAGE: z.string().default("com.cartracking.app"),
	ANDROID_CERT_SHA256: list.default([]),

	// Flutter web build served by the backend, empty to disable
	WEB_ROOT: z.string().default(""),

	// Time zone of the daily totals and of the times in the push notifications
	TIMEZONE: z.string().refine(value => {
		try {
			new Intl.DateTimeFormat("en", { timeZone: value });
			return true;
		} catch {
			return false;
		}
	}, "unknown time zone").default("Europe/Rome"),

	// Requests per minute and client address: every route, and the routes that verify
	// secrets (login, codes, pairing codes; claims and shares per 15 minutes)
	RATE_LIMIT: z.coerce.number().int().positive().default(300),
	AUTH_RATE_LIMIT: z.coerce.number().int().positive().default(10),

	// Data retention of the positions in days
	RETENTION_DAYS: z.coerce.number().int().min(7).default(365),
	// Phones are people: their positions are kept for less time
	PHONE_RETENTION_DAYS: z.coerce.number().int().min(1).default(30),
	// A tracker silent for longer is reported offline (heartbeat every 4 hours)
	OFFLINE_AFTER_HOURS: z.coerce.number().positive().default(9),
	// Monthly data plan of the SIM, for the traffic charts
	SIM_BUDGET_MB: z.coerce.number().positive().default(200),

	// Map tiles for the app, OpenStreetMap by default (fair use policy: light personal use)
	MAP_TILE_URL: z.string().default("https://tile.openstreetmap.org/{z}/{x}/{y}.png"),
	MAP_ATTRIBUTION: z.string().default("© OpenStreetMap contributors"),

	// Optional geolocation of the serving cells (MLS compatible API, e.g. BeaconDB):
	// cell ids are sent to that service. Empty = disabled.
	CELL_GEOLOCATION_URL: z.string().default(""),

	// Optional push notifications on Android (Firebase Cloud Messaging HTTP v1): path of the
	// service account JSON. Empty = notifications only inside the app.
	FCM_SERVICE_ACCOUNT_FILE: z.string().default(""),
	// Folder of the dumps of the "backup" service (read-only), for the administration page.
	// Empty = not shown
	BACKUP_DIR: z.string().default(""),
	// National average prices of the fuels (weekly survey of the Ministry, CSV), for the
	// costs of the trips. Empty = disabled
	FUEL_PRICES_URL: z.string().default("https://sisen.mase.gov.it/dgsaie/api/v1/weekly-prices/report/export?format=CSV&lang=it"),
	// GitHub repository of the project (owner/name): new firmware images and app versions
	// from its latest release. Empty = disabled. Optional token for the API rate limit
	GITHUB_REPO: z.string().regex(/^$|^[\w.-]+\/[\w.-]+$/, "owner/name").default(""),
	GITHUB_TOKEN: z.string().default(""),
	GITHUB_API_URL: z.string().url().default("https://api.github.com"),
	// Google endpoints, replaced only by the tests
	FCM_TOKEN_URL: z.string().url().default("https://oauth2.googleapis.com/token"),
	FCM_API_URL: z.string().url().default("https://fcm.googleapis.com")
});

export type Config = z.infer<typeof schema>;

export function loadConfig (env: NodeJS.ProcessEnv = process.env): Config {
	const result = schema.safeParse(env);
	if (!result.success) {
		const issues = result.error.issues.map(issue => `${issue.path.join(".")}: ${issue.message}`).join("\n  ");
		throw new Error(`Invalid configuration:\n  ${issues}`);
	}
	return result.data;
}
