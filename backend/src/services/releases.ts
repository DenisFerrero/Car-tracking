import { createHash } from "node:crypto";
import type { FastifyBaseLogger } from "fastify";
import { z } from "zod";
import type { Sql } from "../db.ts";
import { FirmwareError, MAX_IMAGE_SIZE, VERSION_PATTERN, compareVersions, splitFirmware } from "./firmware.ts";
import type { Firmware } from "./firmware.ts";
import type { Notifier } from "./notifier.ts";

// Latest release of the repository (GITHUB_REPO, e.g. owner/car-tracking, from the
// environment: the name of the repository can change). Its assets, attached by
// .github/workflows/release.yml:
// - firmware-<variant>.bin: new firmware images, the owners of the trackers of that
//   variant are notified (or the trackers update themselves, AUTO_UPDATE)
// - *.apk: the Android app, offered by the app when it's newer than the installed one
// Tag v2.4.0 → version 2.4.0. Drafts and pre-releases are not "latest" for GitHub.

const CHECK_MS = 6 * 3600e3;
const FIRMWARE_ASSET = /^firmware-([a-z0-9_-]{1,30})\.bin$/;

const releaseSchema = z.object({
	tag_name: z.string(),
	name: z.string().nullable().optional(),
	html_url: z.string().url(),
	published_at: z.string(),
	assets: z.array(z.object({
		name: z.string(),
		size: z.number(),
		browser_download_url: z.string().url(),
		// "sha256:<hex>", computed by GitHub
		digest: z.string().nullable().optional()
	}))
});

export interface ReleasesConfig {
	repo: string;
	apiUrl: string;
	token: string;
}

export class Releases {
	readonly #sql: Sql;
	readonly #log: FastifyBaseLogger;
	readonly #firmware: Firmware;
	readonly #notifier: Notifier;
	readonly #config: ReleasesConfig;
	#lastCheck = 0;

	constructor (sql: Sql, log: FastifyBaseLogger, firmware: Firmware, notifier: Notifier, config: ReleasesConfig) {
		this.#sql = sql;
		this.#log = log;
		this.#firmware = firmware;
		this.#notifier = notifier;
		this.#config = config;
	}

	get enabled (): boolean {
		return this.#config.repo !== "";
	}

	/** Latest app release known, null when none */
	async app (): Promise<{ version: string; url: string; apkUrl: string; publishedAt: Date } | null> {
		const [row] = await this.#sql<{ version: string; url: string; apkUrl: string; publishedAt: Date }[]>`
			SELECT version, url, apk_url AS "apkUrl", published_at AS "publishedAt" FROM app_release`;
		return row ?? null;
	}

	async checkIfDue (now = Date.now()): Promise<void> {
		if (!this.enabled || now - this.#lastCheck < CHECK_MS) return;
		this.#lastCheck = now;
		try {
			await this.check();
		} catch (error) {
			this.#log.warn({ err: error }, "Releases not checked");
		}
	}

	/** Reads the latest release: new firmware images and app version. Returns the images added */
	async check (): Promise<number> {
		const response = await fetch(`${this.#config.apiUrl}/repos/${this.#config.repo}/releases/latest`, {
			headers: {
				accept: "application/vnd.github+json",
				"user-agent": "car-tracking-backend",
				...this.#config.token ? { authorization: `Bearer ${this.#config.token}` } : {}
			},
			signal: AbortSignal.timeout(30e3)
		});
		// No release yet
		if (response.status === 404) return 0;
		if (!response.ok) throw new Error(`GitHub: HTTP ${response.status}`);
		const release = releaseSchema.parse(await response.json());
		const version = release.tag_name.replace(/^v/, "");
		if (!VERSION_PATTERN.test(version)) {
			this.#log.warn({ tag: release.tag_name }, "Release tag is not a version");
			return 0;
		}

		const apk = release.assets.find(asset => asset.name.endsWith(".apk"));
		if (apk) {
			await this.#sql`
				INSERT INTO app_release (version, url, apk_url, published_at) VALUES (${version}, ${release.html_url}, ${apk.browser_download_url}, ${release.published_at})
				ON CONFLICT (id) DO UPDATE SET version = excluded.version, url = excluded.url, apk_url = excluded.apk_url,
					published_at = excluded.published_at, checked_at = now()`;
		}

		let added = 0;
		for (const asset of release.assets) {
			const variant = FIRMWARE_ASSET.exec(asset.name)?.[1];
			if (!variant || asset.size > MAX_IMAGE_SIZE) continue;
			const [known] = await this.#sql`SELECT 1 FROM firmware_images WHERE version = ${version} AND variant = ${variant}`;
			if (known) continue;
			const data = Buffer.from(await (await this.#download(asset.browser_download_url)).arrayBuffer());
			const expected = asset.digest?.startsWith("sha256:") ? asset.digest.slice(7) : null;
			if (expected && createHash("sha256").update(data).digest("hex") !== expected) {
				this.#log.warn({ asset: asset.name }, "Firmware asset with a wrong digest");
				continue;
			}
			try {
				await this.#firmware.upload(data, version, variant, release.name ?? release.tag_name, release.html_url);
			} catch (error) {
				if (!(error instanceof FirmwareError)) throw error;
				this.#log.warn({ asset: asset.name, err: error }, "Firmware asset rejected");
				continue;
			}
			added += 1;
			this.#log.info({ version, variant }, "Firmware downloaded from the release");
			await this.#announce(version, variant);
		}
		return added;
	}

	async #download (url: string): Promise<Response> {
		const response = await fetch(url, { headers: { "user-agent": "car-tracking-backend" }, signal: AbortSignal.timeout(120e3) });
		if (!response.ok) throw new Error(`GitHub download: HTTP ${response.status}`);
		return response;
	}

	/** Owners of the trackers of a variant with an older version: told that it's there */
	async #announce (version: string, variant: string): Promise<void> {
		const trackers = await this.#sql<{ id: number; firmware: string; auto_update: boolean; update_checked_at: Date | null }[]>`
			SELECT id, firmware, auto_update, update_checked_at FROM devices WHERE kind = 'tracker' AND registered_at IS NOT NULL`;
		for (const tracker of trackers) {
			const current = splitFirmware(tracker.firmware);
			if (current.variant !== variant || compareVersions(version, current.version) <= 0) continue;
			// Trackers that ask every day install it by themselves
			const automatic = tracker.auto_update && tracker.update_checked_at !== null;
			await this.#notifier.notifyDevice(tracker.id, "firmware", new Date(), undefined, { version, automatic });
		}
	}
}
