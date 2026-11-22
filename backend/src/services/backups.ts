import fs from "node:fs/promises";
import path from "node:path";

// State of the backups made by the "backup" service (backup/backup.sh) in the folder shared
// read-only with the backend: shown to the administrator, so that a backup that stopped
// working doesn't go unnoticed.

/** A good dump at least once a day, with some margin */
const STALE_MS = 26 * 3600e3;
const FOLDERS = ["daily", "weekly", "monthly"] as const;

export interface BackupState {
	configured: boolean;
	lastSuccess: Date | null;
	lastOffsite: Date | null;
	/** No good dump in the last 26 hours */
	stale: boolean;
	latest: { name: string; size: number } | null;
	files: number;
	totalBytes: number;
}

async function readTime (file: string): Promise<Date | null> {
	try {
		const time = new Date((await fs.readFile(file, "utf8")).trim());
		return Number.isNaN(time.getTime()) ? null : time;
	} catch {
		return null;
	}
}

export async function backupState (dir: string, now = Date.now()): Promise<BackupState> {
	if (!dir) return { configured: false, lastSuccess: null, lastOffsite: null, stale: true, latest: null, files: 0, totalBytes: 0 };
	const dumps: { name: string; size: number; time: number }[] = [];
	for (const folder of FOLDERS) {
		const names = await fs.readdir(path.join(dir, folder)).catch(() => [] as string[]);
		for (const name of names.filter(item => item.endsWith(".dump"))) {
			const stat = await fs.stat(path.join(dir, folder, name));
			dumps.push({ name: `${folder}/${name}`, size: stat.size, time: stat.mtimeMs });
		}
	}
	const lastSuccess = await readTime(path.join(dir, "last-success"));
	const latest = dumps.filter(dump => dump.name.startsWith("daily/")).sort((a, b) => b.time - a.time)[0];
	return {
		configured: true,
		lastSuccess,
		lastOffsite: await readTime(path.join(dir, "last-offsite")),
		stale: lastSuccess === null || now - lastSuccess.getTime() > STALE_MS,
		latest: latest ? { name: latest.name, size: latest.size } : null,
		files: dumps.length,
		totalBytes: dumps.reduce((sum, dump) => sum + dump.size, 0)
	};
}
