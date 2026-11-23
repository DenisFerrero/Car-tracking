import { execFileSync, execSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { connect, migrate } from "../src/db.ts";
import type { Sql } from "../src/db.ts";

// Upgrade of a database full of data, as the backend does at startup on a server: the
// schema of a previous version with its data (the load test seed of that version, when it
// has one), then the migrations of this checkout. Every row of every table and column that
// was there must still be there, unchanged; a second start applies nothing.
//   npm run check-upgrade                 previous version: the latest release (tag v*), else the parent commit
//   npm run check-upgrade -- v2.4.0       a given version
// The database: a TimescaleDB container started for the check, or UPGRADE_DATABASE_URL (a
// dedicated database whose name ends with _upgrade: it is emptied).

const MASTER_KEY = "upgrade-check-master-key-0123456789abcdef";
const IMAGE = "timescale/timescaledb:2.24.0-pg17";
const CONTAINER = "ct-upgrade-db";
const BACKEND = path.join(import.meta.dirname, "..");

const git = (...args: string[]) => execFileSync("git", args, { cwd: BACKEND, encoding: "utf8" }).trim();
const tryGit = (...args: string[]) => {
	try {
		return git(...args);
	} catch {
		return null;
	}
};

const ref = process.argv[2] ?? tryGit("describe", "--tags", "--abbrev=0", "--match", "v*") ?? "HEAD~1";
if (tryGit("rev-parse", "--verify", "--quiet", `${ref}^{commit}`) === null) {
	console.error(`${ref} is not a commit of this repository (in the CI: checkout with fetch-depth 0)`);
	process.exit(1);
}

let url = process.env.UPGRADE_DATABASE_URL ?? "";
let started = false;
const work = fs.mkdtempSync(path.join(os.tmpdir(), "upgrade-"));

function cleanup (): void {
	fs.rmSync(work, { recursive: true, force: true });
	if (started) execFileSync("docker", ["rm", "-f", CONTAINER], { stdio: "ignore" });
}

/** A process of the previous version (its scripts, the modules of this checkout) */
function previous (script: string, args: string[] = []): void {
	execFileSync(process.execPath, [path.join(work, "backend", "scripts", script), ...args], {
		stdio: "inherit",
		env: { ...process.env, DATABASE_URL: url, CRYPTO_MASTER_KEY: MASTER_KEY }
	});
}

interface Table {
	name: string;
	columns: string[];
	rows: number;
	hash: string;
}

/** Rows and hash of every table of the schema, on the given columns (default: all of them) */
async function fingerprint (sql: Sql, only: Map<string, string[]> | null = null): Promise<Map<string, Table>> {
	const tables = await sql<{ name: string; columns: string[] }[]>`
		SELECT c.table_name AS name, array_agg(c.column_name::text ORDER BY c.ordinal_position) AS columns
		FROM information_schema.columns c JOIN information_schema.tables t USING (table_schema, table_name)
		WHERE c.table_schema = 'public' AND t.table_type = 'BASE TABLE' AND c.table_name <> 'schema_migrations'
		GROUP BY c.table_name ORDER BY c.table_name`;
	const result = new Map<string, Table>();
	for (const table of tables) {
		const columns = only ? only.get(table.name) : table.columns;
		if (!columns) continue;
		const missing = columns.filter(column => !table.columns.includes(column));
		if (missing.length) {
			result.set(table.name, { name: table.name, columns: table.columns, rows: -1, hash: `missing columns: ${missing.join(", ")}` });
			continue;
		}
		// Names from the catalog of the database
		const quote = (name: string) => `"${name.replace(/"/g, '""')}"`;
		const [row] = await sql.unsafe<{ rows: number; hash: string }[]>(`
			SELECT count(*)::int AS rows, md5(coalesce(string_agg(r, E'\\n' ORDER BY r), '')) AS hash
			FROM (SELECT ROW(${columns.map(quote).join(", ")})::text AS r FROM ${quote(table.name)}) x`);
		result.set(table.name, { name: table.name, columns, rows: row!.rows, hash: row!.hash });
	}
	return result;
}

try {
	console.log(`Upgrade from ${ref} (${git("rev-parse", "--short", ref)}) to the checkout`);
	execSync(`git archive --format=tar ${ref} backend | tar -x -C "${work}"`, { cwd: git("rev-parse", "--show-toplevel"), stdio: ["ignore", "inherit", "inherit"] });
	fs.symlinkSync(path.join(BACKEND, "node_modules"), path.join(work, "backend", "node_modules"), "junction");

	if (url) {
		if (!/_upgrade$/.test(new URL(url).pathname)) throw new Error("UPGRADE_DATABASE_URL: the name of the database must end with _upgrade (it is emptied)");
	} else {
		execFileSync("docker", ["rm", "-f", CONTAINER], { stdio: "ignore" });
		execFileSync("docker", ["run", "-d", "--name", CONTAINER, "-p", "55434:5432", "-e", "POSTGRES_PASSWORD=upgrade", "-e", "POSTGRES_DB=ct_upgrade",
			IMAGE, "postgres", "-c", "shared_preload_libraries=timescaledb,pg_stat_statements"], { stdio: "ignore" });
		started = true;
		url = "postgres://postgres:upgrade@127.0.0.1:55434/ct_upgrade";
	}
	const sql = connect(url);
	for (let attempt = 0; ; attempt++) {
		try {
			await sql`SELECT 1`;
			// The first initialization restarts the server once
			if (started && attempt === 0) await new Promise(resolve => setTimeout(resolve, 3000));
			await sql`SELECT 1`;
			break;
		} catch (error) {
			if (attempt >= 60) throw error;
			await new Promise(resolve => setTimeout(resolve, 1000));
		}
	}
	await sql.unsafe("DROP SCHEMA IF EXISTS public CASCADE; CREATE SCHEMA public;");

	// The previous version: its migrations and its data
	previous("migrate.ts");
	if (fs.existsSync(path.join(work, "backend", "scripts", "load.ts"))) {
		previous("load.ts", ["--url", "http://127.0.0.1:9", "--allow-remote", "--trackers", "12", "--users", "4", "--days", "21", "--minutes", "0"]);
	} else {
		console.log("No load test seed in that version: only the schema is checked");
	}
	const applied = (await sql<{ name: string }[]>`SELECT name FROM schema_migrations ORDER BY name`).map(row => row.name);
	const before = await fingerprint(sql);

	// This checkout, as at the start of the backend
	const startedAt = performance.now();
	const pending: string[] = [];
	await migrate(sql, message => pending.push(message.replace("Applying migration ", "")));
	const ms = Math.round(performance.now() - startedAt);
	await migrate(sql, message => {
		throw new Error(`A second start applied ${message}`);
	});

	const after = await fingerprint(sql, new Map([...before.values()].map(table => [table.name, table.columns])));
	const problems: string[] = [];
	for (const table of before.values()) {
		const now = after.get(table.name);
		if (!now) problems.push(`${table.name}: table gone`);
		else if (now.rows < 0) problems.push(`${table.name}: ${now.hash}`);
		else if (now.rows !== table.rows || now.hash !== table.hash) {
			problems.push(`${table.name}: ${table.rows} rows before, ${now.rows} after${now.rows === table.rows ? " (values changed)" : ""}`);
		}
	}
	const rows = [...before.values()].reduce((sum, table) => sum + table.rows, 0);
	console.log(`${applied.length} migrations of ${ref}, ${before.size} tables with ${rows} rows`);
	console.log(pending.length ? `Applied ${pending.join(", ")} in ${ms} ms` : "No new migrations");
	await sql.end();
	if (problems.length) {
		console.error(`Data changed by the upgrade:\n  ${problems.join("\n  ")}`);
		process.exitCode = 1;
	} else {
		console.log("Every row and column of before is unchanged");
	}
} catch (error) {
	console.error(error instanceof Error ? error.message : error);
	process.exitCode = 1;
} finally {
	cleanup();
}
