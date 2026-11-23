import type { FastifyBaseLogger } from "fastify";
import type { Sql } from "../db.ts";

// Log of the platform, for the analysis afterwards of the errors to fix and of what is
// slow: errors and warnings of the backend (every log.warn/error of the services and the
// requests failed with 500), HTTP requests slower than a threshold, queries slower than
// a threshold (from pg_stat_statements, when the database loads it). Kept for some days
// (retention of the hypertable). Equal entries are added up in memory and written every
// few seconds as one row with a count, so a burst of errors doesn't flood the database.
// No personal data: no bodies, query strings, addresses, emails or tokens; requests by
// route pattern (/api/devices/:id), not by URL.

export type LogKind = "error" | "warning" | "slow_request" | "slow_query";
export const LOG_KINDS = ["error", "warning", "slow_request", "slow_query"] as const;

const FLUSH_INTERVAL = 10e3;
/** Distinct entries per flush; the rest is counted in one entry */
const MAX_PER_FLUSH = 200;
/** Slow queries kept per snapshot */
const MAX_QUERIES = 20;
const MAX_TEXT = 2000;
const MAX_STACK = 4000;
/** Fields of the log calls never written to the platform log */
const PRIVATE = new Set(["ip", "email", "token", "password", "code", "secret", "userAgent", "req", "res"]);
/** An error is new when the same source and message is not in the log of these days */
const NEW_ERROR_DAYS = 30;

export interface NewError {
	source: string;
	message: string;
	count: number;
}

interface Pending {
	kind: LogKind;
	source: string;
	message: string;
	count: number;
	maxMs: number | null;
	sumMs: number;
	details: Record<string, unknown>;
}

const clip = (text: string, max = MAX_TEXT) => text.length > max ? `${text.slice(0, max)}…` : text;

/** An error as plain fields: name, code, message, stack */
function errorFields (error: unknown): Record<string, unknown> {
	if (!(error instanceof Error)) return { error: clip(String(error)) };
	const code = (error as { code?: unknown }).code;
	return {
		error: error.name,
		...(typeof code === "string" || typeof code === "number" ? { code } : {}),
		errorMessage: clip(error.message),
		...(error.stack ? { stack: clip(error.stack, MAX_STACK) } : {})
	};
}

export class PlatformLog {
	readonly #pending = new Map<string, Pending>();
	#sql: Sql | null = null;
	#timer: NodeJS.Timeout | null = null;
	#dropped = 0;
	#onNewErrors: ((errors: NewError[]) => Promise<void>) | null = null;
	/** pg_stat_statements loaded by the database */
	slowQueriesAvailable = false;

	readonly slowRequestMs: number;
	readonly slowQueryMs: number;

	constructor (slowRequestMs: number, slowQueryMs: number) {
		this.slowRequestMs = slowRequestMs;
		this.slowQueryMs = slowQueryMs;
	}

	/** Starts writing to the database; errors never seen in the last days go to onNewErrors */
	start (sql: Sql, onNewErrors: ((errors: NewError[]) => Promise<void>) | null = null): void {
		this.#sql = sql;
		this.#onNewErrors = onNewErrors;
		this.#timer = setInterval(() => void this.flush().catch(() => {}), FLUSH_INTERVAL);
		this.#timer.unref();
	}

	async stop (): Promise<void> {
		if (this.#timer) clearInterval(this.#timer);
		this.#timer = null;
		await this.flush().catch(() => {});
	}

	record (kind: LogKind, source: string, message: string, details: Record<string, unknown> = {}, durationMs: number | null = null): void {
		message = clip(message);
		const key = `${kind}\u0000${source}\u0000${message}\u0000${String(details.errorMessage ?? "")}`;
		let item = this.#pending.get(key);
		if (!item) {
			if (this.#pending.size >= MAX_PER_FLUSH) {
				this.#dropped++;
				return;
			}
			item = { kind, source, message, count: 0, maxMs: null, sumMs: 0, details };
			this.#pending.set(key, item);
		}
		item.count++;
		// The latest details, the longest duration
		item.details = details;
		if (durationMs !== null) {
			item.sumMs += durationMs;
			if (item.maxMs === null || durationMs > item.maxMs) item.maxMs = durationMs;
		}
	}

	/** A call log.warn / log.error / log.fatal of pino: (object, message) or (message) or (error) */
	fromLog (level: "warn" | "error" | "fatal", source: string, args: unknown[]): void {
		const [first, second] = args;
		const fields: Record<string, unknown> = {};
		let message = typeof second === "string" ? second : typeof first === "string" ? first : "";
		if (first instanceof Error) {
			Object.assign(fields, errorFields(first));
			message ||= first.message;
		} else if (first !== null && typeof first === "object") {
			for (const [name, value] of Object.entries(first)) {
				if (name === "err") Object.assign(fields, errorFields(value));
				else if (name === "component") source = String(value);
				else if (!PRIVATE.has(name) && (value === null || ["string", "number", "boolean"].includes(typeof value))) fields[name] = value;
			}
		}
		this.record(level === "warn" ? "warning" : "error", source, message || "(no message)", fields);
	}

	/** A request over the threshold */
	request (method: string, route: string, status: number, durationMs: number): void {
		if (durationMs < this.slowRequestMs) return;
		this.record("slow_request", "http", `${method} ${route}`, { method, route, status }, Math.round(durationMs));
	}

	/** Writes the entries added up since the last time */
	async flush (): Promise<void> {
		if (!this.#sql) return;
		if (this.#dropped > 0) {
			const dropped = this.#dropped;
			this.#dropped = 0;
			const key = "dropped";
			this.#pending.set(key, { kind: "warning", source: "log", message: "Log entries dropped (too many distinct)", count: dropped, maxMs: null, sumMs: 0, details: {} });
		}
		if (this.#pending.size === 0) return;
		const rows = [...this.#pending.values()].map(item => ({
			kind: item.kind,
			source: item.source,
			message: item.message,
			count: item.count,
			duration_ms: item.maxMs,
			details: item.maxMs === null ? item.details : { ...item.details, avgMs: Math.round(item.sumMs / item.count) }
		}));
		this.#pending.clear();
		const sql = this.#sql;
		const errors = rows.filter(row => row.kind === "error");
		let fresh: NewError[] = [];
		if (this.#onNewErrors && errors.length) {
			const seen = await sql<{ source: string; message: string }[]>`
				SELECT DISTINCT source, message FROM platform_log
				WHERE kind = 'error' AND time > now() - make_interval(days => ${NEW_ERROR_DAYS})
					AND (source, message) IN (SELECT * FROM jsonb_to_recordset(${sql.json(errors.map(({ source, message }) => ({ source, message })))})
						AS t (source text, message text))`;
			const known = new Set(seen.map(row => `${row.source}\u0000${row.message}`));
			fresh = errors.filter(row => !known.has(`${row.source}\u0000${row.message}`))
				.map(({ source, message, count }) => ({ source, message, count }));
		}
		await sql`
			INSERT INTO platform_log (kind, source, message, count, duration_ms, details)
			SELECT * FROM jsonb_to_recordset(${sql.json(rows as never)})
				AS t (kind text, source text, message text, count integer, duration_ms double precision, details jsonb)`;
		// A failure of the alert is not logged as an error: it would be new again at every flush
		if (fresh.length) await this.#onNewErrors!(fresh).catch(() => {});
	}

	/**
	 * Queries of this database slower than the threshold since the last snapshot, from
	 * pg_stat_statements (then reset): mean and maximum duration, calls, rows. At startup
	 * only the reset (record = false): the statistics before belong to another run.
	 */
	async snapshotQueries (sql: Sql, record = true): Promise<void> {
		try {
			const rows = await sql<{ query: string; calls: number; mean: number; max: number; total: number; rows: number }[]>`
				SELECT query, calls, mean_exec_time AS mean, max_exec_time AS max, total_exec_time AS total, rows
				FROM pg_stat_statements
				WHERE dbid = (SELECT oid FROM pg_database WHERE datname = current_database())
					AND (mean_exec_time >= ${this.slowQueryMs} OR max_exec_time >= ${this.slowQueryMs * 10})
					AND query NOT LIKE '%pg_stat_statements%'
				ORDER BY total_exec_time DESC LIMIT ${MAX_QUERIES}`;
			await sql`SELECT pg_stat_statements_reset(0, (SELECT oid FROM pg_database WHERE datname = current_database()), 0)`;
			this.slowQueriesAvailable = true;
			for (const row of record ? rows : []) {
				this.record("slow_query", "db", row.query.replace(/\s+/g, " ").trim(), {
					calls: row.calls,
					maxMs: Math.round(row.max),
					totalMs: Math.round(row.total),
					rows: row.rows
				}, Math.round(row.mean));
			}
		} catch {
			// Not loaded by the database (shared_preload_libraries): only the other entries
			this.slowQueriesAvailable = false;
		}
	}
}

/**
 * The logger of the services with every warning and error also in the platform log; its
 * children too, with the source from the binding "component"
 */
export function capturing (log: FastifyBaseLogger, platform: PlatformLog, source = "app"): FastifyBaseLogger {
	return new Proxy(log, {
		get (target, property) {
			if (property === "warn" || property === "error" || property === "fatal") {
				return (...args: unknown[]) => {
					platform.fromLog(property, source, args);
					return (target[property] as (...values: unknown[]) => void)(...args);
				};
			}
			if (property === "child") {
				return (bindings: Record<string, unknown>, options?: object) =>
					capturing(target.child(bindings, options), platform, typeof bindings.component === "string" ? bindings.component : source);
			}
			const value = Reflect.get(target, property, target);
			return typeof value === "function" ? value.bind(target) : value;
		}
	});
}
