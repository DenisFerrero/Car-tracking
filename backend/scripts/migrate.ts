import { connect, migrate } from "../src/db.ts";

// Applies the pending migrations (the backend does it at startup too).
// Usage: npm run migrate

const url = process.env.DATABASE_URL;
if (!url) {
	console.error("DATABASE_URL is not set");
	process.exit(1);
}
const sql = connect(url);
try {
	await migrate(sql);
	console.log("Database up to date");
} finally {
	await sql.end();
}
