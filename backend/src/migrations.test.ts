import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { describe, test } from "node:test";

// The migrations upgrade databases full of data: they only add (tables, nullable columns or
// columns with a default, indexes, policies). A statement that can lose data or fail on the
// rows already there (drop, rename, change of type, new NOT NULL or constraint, data
// changes) needs a comment "-- additive: <why it's safe>" on the line before it, reviewed
// with the change. Statements on a table created in the same migration are free: it's empty.
// The upgrade of a database with data is tried by scripts/check-upgrade.sh (CI).

const DIRECTORY = path.join(import.meta.dirname, "..", "migrations");

// Applied before this check, reviewed: they keep every row
const REVIEWED: Record<string, string> = {
	"002_phones_friends.sql": "imei DROP NOT NULL: relaxes, phones have no IMEI",
	"009_vehicles.sql": "devices_kind_check dropped and added again with one more kind: widens"
};

const RISKY: [RegExp, string][] = [
	[/\bDROP\s+(TABLE|SCHEMA|TYPE|VIEW|MATERIALIZED\s+VIEW|FUNCTION)\b/i, "drops an object"],
	[/\bDROP\s+COLUMN\b/i, "drops a column"],
	[/\bDROP\s+CONSTRAINT\b/i, "drops a constraint"],
	[/\bDROP\s+NOT\s+NULL\b/i, "changes a column"],
	[/\bRENAME\b/i, "renames"],
	[/\bALTER\s+COLUMN\s+\w+\s+(SET\s+DATA\s+)?TYPE\b/i, "changes the type of a column"],
	[/\bSET\s+NOT\s+NULL\b/i, "makes a column NOT NULL"],
	[/\bADD\s+CONSTRAINT\b/i, "adds a constraint the existing rows may break"],
	[/\bCREATE\s+UNIQUE\s+INDEX\b/i, "adds a unique index the existing rows may break"],
	[/\b(TRUNCATE|DELETE\s+FROM|UPDATE\s+\w+\s+SET)\b/i, "changes data"]
];

export interface Finding {
	file: string;
	statement: string;
	reason: string;
}

/** Statements of a migration without comments, each with the "-- additive:" note above it */
export function statements (text: string): { sql: string; reviewed: boolean }[] {
	const result: { sql: string; reviewed: boolean }[] = [];
	let current = "";
	let reviewed = false;
	// $$ bodies (functions, DO blocks) as one statement
	let quoted = false;
	for (const line of text.split(/\r?\n/)) {
		const trimmed = line.trim();
		if (!quoted && trimmed.startsWith("--")) {
			if (/^--\s*additive:\s*\S/i.test(trimmed) && current.trim() === "") reviewed = true;
			continue;
		}
		const code = quoted ? line : line.replace(/--.*$/, "");
		if ((code.match(/\$\$/g)?.length ?? 0) % 2 === 1) quoted = !quoted;
		current += `${code}\n`;
		if (!quoted && code.trimEnd().endsWith(";")) {
			if (current.trim().replace(/;$/, "").trim()) result.push({ sql: current.trim(), reviewed });
			current = "";
			reviewed = false;
		}
	}
	if (current.trim()) result.push({ sql: current.trim(), reviewed });
	return result;
}

/** Statements that can lose data or fail on a database with rows, not marked as reviewed */
export function findRisky (file: string, text: string): Finding[] {
	const created = new Set([...text.matchAll(/CREATE\s+TABLE\s+(?:IF\s+NOT\s+EXISTS\s+)?(\w+)/gi)].map(match => match[1]!.toLowerCase()));
	const findings: Finding[] = [];
	for (const { sql, reviewed } of statements(text)) {
		if (reviewed) continue;
		// On a table of this migration (empty)
		const target = /\b(?:ALTER\s+TABLE|ON|INTO|UPDATE|FROM|TRUNCATE)\s+(?:ONLY\s+)?(\w+)/i.exec(sql)?.[1]?.toLowerCase();
		if (target && created.has(target) && !/\bDROP\s+TABLE\b/i.test(sql)) continue;
		for (const [pattern, reason] of RISKY) {
			if (pattern.test(sql)) findings.push({ file, statement: sql.replace(/\s+/g, " ").slice(0, 120), reason });
		}
		// A new NOT NULL column needs a default for the rows already there
		for (const column of sql.matchAll(/\bADD\s+COLUMN\s+(?:IF\s+NOT\s+EXISTS\s+)?(\w+)([^,;]*)/gi)) {
			if (/\bNOT\s+NULL\b/i.test(column[2]!) && !/\bDEFAULT\b/i.test(column[2]!)) {
				findings.push({ file, statement: sql.replace(/\s+/g, " ").slice(0, 120), reason: `NOT NULL column ${column[1]} without a default` });
			}
			// Unique and nullable starts with NULLs, never equal; with a default every row gets the same value
			if (/\bUNIQUE\b/i.test(column[2]!) && /\bDEFAULT\b/i.test(column[2]!)) {
				findings.push({ file, statement: sql.replace(/\s+/g, " ").slice(0, 120), reason: `unique column ${column[1]} with a default` });
			}
		}
	}
	return findings;
}

describe("migrations", () => {
	const files = fs.readdirSync(DIRECTORY).filter(file => file.endsWith(".sql")).sort();

	test("numbered, one per number", () => {
		const numbers = files.map(file => file.slice(0, 3));
		for (const file of files) assert.match(file, /^\d{3}_[a-z0-9_]+\.sql$/);
		assert.equal(new Set(numbers).size, numbers.length, "two migrations with the same number");
	});

	test("additive: risky statements only with a reviewed note", () => {
		const findings = files.filter(file => !(file in REVIEWED))
			.flatMap(file => findRisky(file, fs.readFileSync(path.join(DIRECTORY, file), "utf8")));
		assert.deepEqual(findings, [], `Not additive (add "-- additive: <why>" above the statement only when it keeps every row):\n${
			findings.map(item => `${item.file}: ${item.reason}: ${item.statement}`).join("\n")}`);
	});

	test("the check finds what loses data or fails on existing rows", () => {
		const risky = (text: string) => findRisky("x.sql", text).map(item => item.reason);
		assert.deepEqual(risky("ALTER TABLE devices DROP COLUMN name;"), ["drops a column"]);
		assert.deepEqual(risky("DROP TABLE refuels;"), ["drops an object"]);
		assert.deepEqual(risky("ALTER TABLE users RENAME COLUMN name TO full_name;"), ["renames"]);
		assert.deepEqual(risky("ALTER TABLE users ALTER COLUMN name TYPE varchar(20);"), ["changes the type of a column"]);
		assert.deepEqual(risky("ALTER TABLE users ALTER COLUMN locale SET NOT NULL;"), ["makes a column NOT NULL"]);
		assert.deepEqual(risky("ALTER TABLE users ADD COLUMN age int NOT NULL;"), ["NOT NULL column age without a default"]);
		assert.deepEqual(risky("ALTER TABLE users ADD COLUMN code text DEFAULT 'a' UNIQUE;"), ["unique column code with a default"]);
		assert.deepEqual(risky("CREATE UNIQUE INDEX users_name ON users (name);"), ["adds a unique index the existing rows may break"]);
		assert.deepEqual(risky("DELETE FROM sessions;\nUPDATE users SET locale = 'it';"), ["changes data", "changes data"]);
		assert.deepEqual(risky("ALTER TABLE devices ADD CONSTRAINT positive CHECK (battery >= 0);"), ["adds a constraint the existing rows may break"]);
		// Safe
		assert.deepEqual(risky("ALTER TABLE users ADD COLUMN age int;\nALTER TABLE users ADD COLUMN on boolean NOT NULL DEFAULT true;"), []);
		assert.deepEqual(risky("ALTER TABLE users ADD COLUMN token bytea UNIQUE;"), []);
		assert.deepEqual(risky("CREATE INDEX users_name ON users (name);\nCREATE TABLE a (id int);\nALTER TABLE a ADD CONSTRAINT x UNIQUE (id);"), []);
		assert.deepEqual(risky("CREATE TABLE b (id int);\nINSERT INTO b VALUES (1);\nDELETE FROM b WHERE id = 2;"), []);
		// Reviewed: the note right above the statement
		assert.deepEqual(risky("-- additive: widens the kinds\nALTER TABLE devices DROP CONSTRAINT k;\nALTER TABLE devices DROP COLUMN x;"), ["drops a column"]);
		// Comments and $$ bodies
		assert.deepEqual(risky("-- DROP TABLE users;\nSELECT 1; -- DELETE FROM users\nDO $$ BEGIN\n  PERFORM 1;\nEND $$;"), []);
		assert.equal(statements("DO $$ BEGIN\n  PERFORM 1;\nEND $$;\nSELECT 2").length, 2);
	});
});
