// In memory counters per key (client address) with a temporary ban: cheap protection that
// runs before any database query or password check.

interface Entry {
	count: number;
	windowStart: number;
	bannedUntil: number;
}

export class Throttle {
	readonly #limit: number;
	readonly #windowMs: number;
	readonly #banMs: number;
	readonly #entries = new Map<string, Entry>();

	/** More than `limit` hits within `windowMs` ban the key for `banMs` */
	constructor (limit: number, windowMs: number, banMs: number) {
		this.#limit = limit;
		this.#windowMs = windowMs;
		this.#banMs = banMs;
	}

	isBanned (key: string, now = Date.now()): boolean {
		return (this.#entries.get(key)?.bannedUntil ?? 0) > now;
	}

	/** Counts a hit, false when the key is (now) banned */
	hit (key: string, now = Date.now()): boolean {
		let entry = this.#entries.get(key);
		if (!entry || now - entry.windowStart > this.#windowMs) {
			entry = { count: 0, windowStart: now, bannedUntil: entry?.bannedUntil ?? 0 };
			this.#entries.set(key, entry);
		}
		if (entry.bannedUntil > now) return false;
		entry.count += 1;
		if (entry.count > this.#limit) {
			entry.bannedUntil = now + this.#banMs;
			return false;
		}
		return true;
	}

	/** Drops the old entries, called periodically */
	sweep (now = Date.now()): void {
		for (const [key, entry] of this.#entries) {
			if (entry.bannedUntil <= now && now - entry.windowStart > this.#windowMs) this.#entries.delete(key);
		}
	}

	get size (): number {
		return this.#entries.size;
	}
}
