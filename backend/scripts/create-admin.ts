import { z } from "zod";
import { hashToken, randomToken } from "../src/auth/secrets.ts";
import { connect, migrate } from "../src/db.ts";

// First administrator: prints an invite link, valid for 72 hours, where the password is
// chosen and the 2FA enrolled. Nothing secret is passed on the command line.
// Usage: npm run create-admin -- <email> "<name>"

const INVITE_TTL = 72 * 3600e3;

const [email, name] = process.argv.slice(2);
const args = z.object({ email: z.email(), name: z.string().trim().min(1).max(80) }).safeParse({ email, name: name ?? "Amministratore" });
const env = z.object({ DATABASE_URL: z.string().url(), PUBLIC_URL: z.string().url() }).safeParse(process.env);
if (!args.success || !env.success) {
	console.error("Usage: npm run create-admin -- <email> [name]   (DATABASE_URL and PUBLIC_URL must be set)");
	process.exit(1);
}

const sql = connect(env.data.DATABASE_URL);
try {
	await migrate(sql, () => {});
	const [existing] = await sql`SELECT id FROM users WHERE email = ${args.data.email}`;
	if (existing) {
		console.error(`A user with email ${args.data.email} already exists: use the access reset from the admin panel`);
		process.exit(1);
	}
	const token = randomToken();
	await sql`DELETE FROM invites WHERE email = ${args.data.email} AND user_id IS NULL`;
	await sql`
		INSERT INTO invites (token_hash, email, name, is_admin, expires_at)
		VALUES (${hashToken(token)}, ${args.data.email}, ${args.data.name}, true, ${new Date(Date.now() + INVITE_TTL)})`;
	console.log(`Invite for ${args.data.email} (administrator), valid for 72 hours:\n`);
	console.log(`${env.data.PUBLIC_URL.replace(/\/+$/, "")}/#/invite/${token}\n`);
	console.log("Open it to choose the password and configure the authenticator app and the passkey.");
} finally {
	await sql.end();
}
