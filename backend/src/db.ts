import fs from "node:fs/promises";
import path from "node:path";
import postgres from "postgres";

export type Sql = postgres.Sql;
/** Queries inside sql.begin() */
export type Tx = postgres.TransactionSql;

/**
 * Deletes in the compressed chunks of a transaction: TimescaleDB stops a statement that
 * decompresses more than 100k rows, the history of a tracker over the months goes beyond
 */
export async function allowDecompression (tx: Tx): Promise<void> {
	await tx`SET LOCAL timescaledb.max_tuples_decompressed_per_dml_transaction = 0`;
}

export function connect (url: string): Sql {
	return postgres(url, {
		max: 10,
		idle_timeout: 30,
		// BIGINT (cell ids, counters) as JS numbers: they stay below 2^53
		types: { bigint: { to: 20, from: [20], parse: (value: string) => Number(value), serialize: (value: number) => String(value) } },
		transform: { undefined: null },
		onnotice: () => {}
	});
}

const MIGRATIONS = path.join(import.meta.dirname, "..", "migrations");

/**
 * Applies the migrations/*.sql files not applied yet, in name order, each one in a
 * transaction. An advisory lock serializes concurrent starts.
 */
export async function migrate (sql: Sql, log: (message: string) => void = console.log): Promise<void> {
	await sql`CREATE TABLE IF NOT EXISTS schema_migrations (name text PRIMARY KEY, applied_at timestamptz NOT NULL DEFAULT now())`;

	const files = (await fs.readdir(MIGRATIONS)).filter(file => file.endsWith(".sql")).sort();
	await sql.begin(async tx => {
		await tx`SELECT pg_advisory_xact_lock(727274)`;
		const applied = new Set((await tx<{ name: string }[]>`SELECT name FROM schema_migrations`).map(row => row.name));
		for (const file of files) {
			if (applied.has(file)) continue;
			log(`Applying migration ${file}`);
			await tx.unsafe(await fs.readFile(path.join(MIGRATIONS, file), "utf8"));
			await tx`INSERT INTO schema_migrations (name) VALUES (${file})`;
		}
	});
}
