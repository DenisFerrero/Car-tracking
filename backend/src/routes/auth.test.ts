import assert from "node:assert/strict";
import { after, before, describe, test } from "node:test";
import { hashToken, randomToken } from "../auth/secrets.ts";
import { SoftAuthenticator } from "../test/authenticator.ts";
import { Harness, PASSWORD, PUBLIC_URL, SKIP, totp } from "../test/harness.ts";
import type { User } from "../test/harness.ts";

describe("authentication", { skip: SKIP }, () => {
	let h: Harness;
	let admin: User;

	before(async () => {
		h = await Harness.start();
	});
	after(() => h?.close());

	test("invite, mandatory TOTP enrollment, recovery codes", async () => {
		const token = await h.invite("admin@example.com", "Admin", true);
		assert.deepEqual((await h.api("GET", `/api/auth/invites/${token}`)).body, { email: "admin@example.com", name: "Admin", reset: false });
		assert.equal((await h.api("GET", `/api/auth/invites/${"x".repeat(43)}`)).status, 404);
		assert.equal((await h.api("GET", "/api/auth/invites/short")).status, 400);

		const weak = await h.api("POST", `/api/auth/invites/${token}`, { body: { password: "corta", client: "app" } });
		assert.equal(weak.status, 400);
		assert.equal(weak.body.error, "validation");

		const accepted = await h.api("POST", `/api/auth/invites/${token}`, { body: { password: PASSWORD, client: "app" } });
		assert.equal(accepted.body.stage, "enroll");
		// Nothing is usable before the 2FA
		const blocked = await h.api("GET", "/api/devices", { token: accepted.body.token });
		assert.equal(blocked.status, 401);
		assert.equal(blocked.body.error, "stage_enroll");
		// The invite works once
		assert.equal((await h.api("POST", `/api/auth/invites/${token}`, { body: { password: PASSWORD, client: "app" } })).status, 404);

		// Confirm before start
		const early = await h.api("POST", "/api/auth/enroll/confirm", { token: accepted.body.token, body: { code: "123456" } });
		assert.equal(early.body.error, "enroll_expired");

		const enroll = await h.api("POST", "/api/auth/enroll/start", { token: accepted.body.token });
		assert.match(enroll.body.uri, /^otpauth:\/\/totp\//);
		assert.equal((await h.api("POST", "/api/auth/enroll/confirm", { token: accepted.body.token, body: { code: "000000" } })).status, 401);
		const confirmed = await h.api("POST", "/api/auth/enroll/confirm", { token: accepted.body.token, body: { code: totp(enroll.body.secret) } });
		assert.equal(confirmed.body.stage, "full");
		assert.equal(confirmed.body.recoveryCodes.length, 10);
		// The enroll token was rotated
		assert.equal((await h.api("GET", "/api/devices", { token: accepted.body.token })).status, 401);
		const [row] = await h.sql<{ id: number }[]>`SELECT id FROM users WHERE email = 'admin@example.com'`;
		admin = { id: row!.id, token: confirmed.body.token, secret: enroll.body.secret, recoveryCodes: confirmed.body.recoveryCodes };
		assert.equal((await h.api("GET", "/api/devices", { token: admin.token })).status, 200);
	});

	test("invites for existing or expired accounts", async () => {
		const duplicate = await h.invite("admin@example.com", "Again");
		const conflict = await h.api("POST", `/api/auth/invites/${duplicate}`, { body: { password: PASSWORD, client: "app" } });
		assert.equal(conflict.status, 409);
		assert.equal(conflict.body.error, "email_taken");

		const token = randomToken();
		await h.sql`INSERT INTO invites (token_hash, email, name, expires_at) VALUES (${hashToken(token)}, 'old@example.com', 'Old', now() - interval '1 minute')`;
		assert.equal((await h.api("GET", `/api/auth/invites/${token}`)).status, 404);
	});

	test("password + TOTP login, replay, lockout and recovery code", async () => {
		const wrong = await h.api("POST", "/api/auth/login", { body: { email: "admin@example.com", password: "sbagliata sbagliata", client: "app" } });
		assert.equal(wrong.status, 401);
		assert.equal(wrong.body.error, "invalid_credentials");
		const unknown = await h.api("POST", "/api/auth/login", { body: { email: "nobody@example.com", password: PASSWORD } });
		assert.equal(unknown.status, 401);
		assert.equal(unknown.body.error, "invalid_credentials");

		const login = await h.api("POST", "/api/auth/login", { body: { email: "admin@example.com", password: PASSWORD, client: "app" } });
		assert.equal(login.body.stage, "mfa_pending");
		assert.equal((await h.api("GET", "/api/devices", { token: login.body.token })).body.error, "stage_mfa_pending");
		// The code used for the enrollment can't be used again
		const replay = await h.api("POST", "/api/auth/totp", { token: login.body.token, body: { code: totp(admin.secret) } });
		assert.equal(replay.status, 401);
		const ok = await h.api("POST", "/api/auth/totp", { token: login.body.token, body: { code: totp(admin.secret, 30e3) } });
		assert.equal(ok.body.stage, "full");
		assert.ok(ok.body.token);

		const second = await h.api("POST", "/api/auth/login", { body: { email: "admin@example.com", password: PASSWORD, client: "app" } });
		const bad = await h.api("POST", "/api/auth/recovery", { token: second.body.token, body: { code: "AAAA-BBBB-CCCC" } });
		assert.equal(bad.status, 401);
		const recovered = await h.api("POST", "/api/auth/recovery", { token: second.body.token, body: { code: admin.recoveryCodes[0]!.toLowerCase() } });
		assert.equal(recovered.body.recoveryCodesLeft, 9);
		const reused = await h.api("POST", "/api/auth/login", { body: { email: "admin@example.com", password: PASSWORD, client: "app" } });
		assert.equal((await h.api("POST", "/api/auth/recovery", { token: reused.body.token, body: { code: admin.recoveryCodes[0] } })).status, 401);

		// Five failures lock the account; the lock grows with the failures
		const victim = await h.onboard("victim@example.com", "Victim");
		for (let i = 0; i < 5; i++) await h.api("POST", "/api/auth/login", { body: { email: "victim@example.com", password: "wrong password!" } });
		const locked = await h.api("POST", "/api/auth/login", { body: { email: "victim@example.com", password: PASSWORD } });
		assert.equal(locked.status, 429);
		assert.equal(locked.body.error, "locked");
		const [state] = await h.sql<{ locked_until: Date }[]>`SELECT locked_until FROM users WHERE id = ${victim.id}`;
		assert.ok(state!.locked_until.getTime() > Date.now() + 10 * 60e3);

		// Locked during the TOTP step too
		await h.sql`UPDATE users SET locked_until = NULL, failed_logins = 0 WHERE id = ${victim.id}`;
		const pending = await h.api("POST", "/api/auth/login", { body: { email: "victim@example.com", password: PASSWORD } , headers: {} });
		const pendingToken = (await h.api("POST", "/api/auth/login", { body: { email: "victim@example.com", password: PASSWORD, client: "app" } })).body.token;
		assert.equal(pending.body.stage, "mfa_pending");
		await h.sql`UPDATE users SET locked_until = now() + interval '1 hour' WHERE id = ${victim.id}`;
		assert.equal((await h.api("POST", "/api/auth/totp", { token: pendingToken, body: { code: "123456" } })).status, 429);
		assert.equal((await h.api("POST", "/api/auth/recovery", { token: pendingToken, body: { code: "123456" } })).status, 429);
		await h.sql`UPDATE users SET locked_until = NULL WHERE id = ${victim.id}`;
		assert.equal((await h.api("POST", "/api/auth/totp", { token: pendingToken, body: { code: "000000" } })).status, 401);

		// Disabled accounts can't log in
		await h.sql`UPDATE users SET disabled = true WHERE id = ${victim.id}`;
		assert.equal((await h.api("POST", "/api/auth/login", { body: { email: "victim@example.com", password: PASSWORD } })).status, 401);
		assert.equal((await h.api("GET", "/api/devices", { token: victim.token })).status, 401);
		await h.sql`UPDATE users SET disabled = false WHERE id = ${victim.id}`;
	});

	test("browser session: HttpOnly cookie, Origin check, logout", async () => {
		const login = await h.api("POST", "/api/auth/login", { body: { email: "admin@example.com", password: PASSWORD, client: "web" } });
		assert.equal(login.body.token, undefined);
		const cookie = login.headers.get("set-cookie") ?? "";
		assert.match(cookie, /ct_session=[^;]+; .*HttpOnly/i);
		assert.match(cookie, /SameSite=Strict/i);
		const header = cookie.split(";")[0]!;

		const noOrigin = await h.api("POST", "/api/auth/totp", { headers: { cookie: header }, body: { code: "123456" } });
		assert.equal(noOrigin.status, 403);
		assert.equal(noOrigin.body.error, "bad_origin");
		const session = await h.api("GET", "/api/auth/session", { headers: { cookie: header } });
		assert.equal(session.body.stage, "mfa_pending");
		// A cookie token can't be used as bearer, a bearer token can't be a cookie
		assert.equal((await h.api("GET", "/api/auth/session", { token: header.split("=")[1] })).body.stage, null);
		assert.equal((await h.api("GET", "/api/auth/session", { headers: { cookie: `ct_session=${admin.token}` } })).body.stage, null);
		// Unknown cookie: cleared
		const stale = await h.api("GET", "/api/auth/session", { headers: { cookie: "ct_session=nope" } });
		assert.match(stale.headers.get("set-cookie") ?? "", /ct_session=;/);

		// A TOTP step works once: start again from the current one
		await h.sql`UPDATE users SET totp_last_step = 0 WHERE id = ${admin.id}`;
		const full = await h.api("POST", "/api/auth/totp", { headers: { cookie: header, origin: PUBLIC_URL }, body: { code: totp(admin.secret) } });
		assert.equal(full.body.stage, "full");
		const fullCookie = (full.headers.get("set-cookie") ?? "").split(";")[0]!;
		const me = await h.api("GET", "/api/auth/session", { headers: { cookie: fullCookie } });
		assert.equal(me.body.user.email, "admin@example.com");
		assert.equal(me.body.user.locale, null);

		// Idle sessions are renewed after a while
		await h.sql`UPDATE sessions SET last_seen_at = now() - interval '1 hour' WHERE token_hash = ${hashToken(fullCookie.split("=")[1]!)}`;
		const renewed = await h.api("GET", "/api/devices", { headers: { cookie: fullCookie } });
		assert.match(renewed.headers.get("set-cookie") ?? "", /ct_session=/);

		const logout = await h.api("POST", "/api/auth/logout", { headers: { cookie: fullCookie, origin: PUBLIC_URL } });
		assert.equal(logout.status, 200);
		assert.equal((await h.api("GET", "/api/devices", { headers: { cookie: fullCookie } })).status, 401);
		assert.equal((await h.api("POST", "/api/auth/logout")).status, 200);
	});

	test("passkeys: registration with step up, login, errors", async () => {
		const user = await h.onboard("passkey@example.com", "Passkey");
		const authenticator = new SoftAuthenticator(PUBLIC_URL, "localhost");

		// Old login: a TOTP code is required
		const old = await h.session(user.id, "app", 30 * 60e3);
		const stepUp = await h.api("POST", "/api/account/passkeys/options", { token: old, body: {} });
		assert.equal(stepUp.body.error, "step_up_required");
		const badCode = await h.api("POST", "/api/account/passkeys/options", { token: old, body: { code: "000000" } });
		assert.equal(badCode.body.error, "invalid_code");
		const withCode = await h.api("POST", "/api/account/passkeys/options", { token: old, body: { code: totp(user.secret, 30e3) } });
		assert.equal(withCode.status, 200);

		const options = await h.api("POST", "/api/account/passkeys/options", { token: user.token });
		assert.equal(options.body.rp.id, "localhost");
		// Wrong origin
		const foreign = await h.api("POST", "/api/account/passkeys", { token: user.token, body: { name: "Phone", response: authenticator.register(options.body, { origin: "https://evil.example" }) } });
		assert.equal(foreign.body.error, "invalid_passkey");
		// The challenge was used
		const again = await h.api("POST", "/api/account/passkeys", { token: user.token, body: { name: "Phone", response: authenticator.register(options.body) } });
		assert.equal(again.body.error, "challenge_expired");
		const broken = await h.api("POST", "/api/account/passkeys", { token: user.token, body: { name: "Phone", response: { id: "x", response: { clientDataJSON: "%%%" } } } });
		assert.equal(broken.body.error, "invalid_passkey");
		const noChallenge = await h.api("POST", "/api/account/passkeys", {
			token: user.token,
			body: { name: "Phone", response: { id: "x", response: { clientDataJSON: Buffer.from("{}").toString("base64url") } } }
		});
		assert.equal(noChallenge.body.error, "invalid_passkey");
		// Without user verification
		const fresh = await h.api("POST", "/api/account/passkeys/options", { token: user.token });
		const unverified = await h.api("POST", "/api/account/passkeys", { token: user.token, body: { name: "Phone", response: authenticator.register(fresh.body, { flags: 0x41 }) } });
		assert.equal(unverified.body.error, "invalid_passkey");

		const good = await h.api("POST", "/api/account/passkeys/options", { token: user.token });
		const added = await h.api("POST", "/api/account/passkeys", { token: user.token, body: { name: "Phone", response: authenticator.register(good.body) } });
		assert.equal(added.status, 200, JSON.stringify(added.body));
		assert.equal(added.body.id, authenticator.id);
		// The second registration excludes the existing passkey
		const exclude = await h.api("POST", "/api/account/passkeys/options", { token: user.token });
		assert.equal(exclude.body.excludeCredentials[0].id, authenticator.id);

		// Login with the passkey: no password, no TOTP
		const login = await h.api("POST", "/api/auth/passkey/options", { body: {} });
		const verified = await h.api("POST", "/api/auth/passkey/verify", { body: { response: authenticator.authenticate(login.body), client: "app" } });
		assert.equal(verified.status, 200, JSON.stringify(verified.body));
		assert.equal(verified.body.stage, "full");
		assert.equal((await h.api("GET", "/api/devices", { token: verified.body.token })).status, 200);

		const forged = await h.api("POST", "/api/auth/passkey/options", { body: {} });
		assert.equal((await h.api("POST", "/api/auth/passkey/verify", { body: { response: authenticator.authenticate(forged.body, { badSignature: true }) } })).body.error, "invalid_credentials");
		const unknown = new SoftAuthenticator(PUBLIC_URL, "localhost");
		const third = await h.api("POST", "/api/auth/passkey/options", { body: {} });
		assert.equal((await h.api("POST", "/api/auth/passkey/verify", { body: { response: unknown.authenticate(third.body) } })).body.error, "invalid_credentials");
		const noUv = await h.api("POST", "/api/auth/passkey/options", { body: {} });
		assert.equal((await h.api("POST", "/api/auth/passkey/verify", { body: { response: authenticator.authenticate(noUv.body, { flags: 0x01 }) } })).body.error, "invalid_credentials");

		// Disabled accounts: the passkey doesn't open them
		await h.sql`UPDATE users SET disabled = true WHERE id = ${user.id}`;
		const disabled = await h.api("POST", "/api/auth/passkey/options", { body: {} });
		assert.equal((await h.api("POST", "/api/auth/passkey/verify", { body: { response: authenticator.authenticate(disabled.body) } })).status, 401);
		await h.sql`UPDATE users SET disabled = false WHERE id = ${user.id}`;

		// Account page: rename and delete (step up)
		const account = await h.api("GET", "/api/account", { token: user.token });
		assert.equal(account.body.passkeys.length, 1);
		const path = `/api/account/passkeys/${encodeURIComponent(authenticator.id)}`;
		assert.equal((await h.api("PATCH", path, { token: user.token, body: { name: "Pixel" } })).status, 200);
		assert.equal((await h.api("PATCH", "/api/account/passkeys/nope", { token: user.token, body: { name: "Pixel" } })).status, 404);
		const older = await h.session(user.id, "app", 30 * 60e3);
		assert.equal((await h.api("DELETE", path, { token: older, body: {} })).body.error, "step_up_required");
		assert.equal((await h.api("DELETE", path, { token: user.token, body: {} })).status, 200);
		assert.equal((await h.api("DELETE", path, { token: user.token, body: {} })).status, 404);
	});

	test("account: profile, language, password, TOTP, recovery codes, sessions, push", async () => {
		const user = await h.onboard("account@example.com", "Account");
		const other = await h.session(user.id);

		const account = await h.api("GET", "/api/account", { token: user.token });
		assert.equal(account.body.user.name, "Account");
		assert.equal(account.body.recoveryCodesLeft, 10);
		assert.equal(account.body.sessions.length, 2);
		assert.equal(account.body.pushEnabled, false);

		assert.equal((await h.api("PATCH", "/api/account", { token: user.token, body: { name: "Nuovo nome", locale: "it" } })).status, 200);
		assert.equal((await h.api("PATCH", "/api/account", { token: user.token, body: { locale: "de" } })).status, 400);
		assert.equal((await h.api("PATCH", "/api/account", { token: user.token, body: { name: "x", extra: 1 } })).status, 400);
		const session = await h.api("GET", "/api/auth/session", { token: user.token });
		assert.equal(session.body.user.locale, "it");
		assert.equal(session.body.user.name, "Nuovo nome");

		// Password: current one verified, recent login or code, other sessions closed
		const wrong = await h.api("POST", "/api/account/password", { token: user.token, body: { current: "wrong", password: "another long password" } });
		assert.equal(wrong.body.error, "invalid_password");
		const stale = await h.session(user.id, "app", 3600e3);
		assert.equal((await h.api("POST", "/api/account/password", { token: stale, body: { current: PASSWORD, password: "another long password" } })).body.error, "step_up_required");
		const changed = await h.api("POST", "/api/account/password", { token: user.token, body: { current: PASSWORD, password: "another long password" } });
		assert.equal(changed.status, 200);
		assert.equal((await h.api("GET", "/api/account", { token: other })).status, 401);
		const relogin = await h.api("POST", "/api/auth/login", { body: { email: "account@example.com", password: "another long password" } });
		assert.equal(relogin.body.stage, "mfa_pending");

		// Recovery codes regenerated
		const codes = await h.api("POST", "/api/account/recovery-codes", { token: user.token, body: {} });
		assert.equal(codes.body.recoveryCodes.length, 10);
		assert.notDeepEqual(codes.body.recoveryCodes, user.recoveryCodes);

		// New authenticator app
		assert.equal((await h.api("POST", "/api/account/totp/confirm", { token: user.token, body: { code: "123456" } })).body.error, "enroll_expired");
		const start = await h.api("POST", "/api/account/totp/start", { token: user.token, body: {} });
		assert.equal((await h.api("POST", "/api/account/totp/confirm", { token: user.token, body: { code: "000000" } })).body.error, "invalid_code");
		assert.equal((await h.api("POST", "/api/account/totp/confirm", { token: user.token, body: { code: totp(start.body.secret) } })).status, 200);

		// Sessions
		const third = await h.session(user.id);
		const list = (await h.api("GET", "/api/account", { token: user.token })).body.sessions as { id: string; current: boolean }[];
		const target = list.find(item => !item.current)!;
		assert.equal((await h.api("DELETE", `/api/account/sessions/${target.id}`, { token: user.token })).status, 200);
		assert.equal((await h.api("DELETE", `/api/account/sessions/${target.id}`, { token: user.token })).status, 404);
		assert.equal((await h.api("DELETE", "/api/account/sessions/xyz", { token: user.token })).status, 400);
		await h.session(user.id);
		assert.equal((await h.api("POST", "/api/account/sessions/revoke-others", { token: user.token })).status, 200);
		assert.equal((await h.api("GET", "/api/account", { token: third })).status, 401);
		assert.equal((await h.api("GET", "/api/account", { token: user.token })).body.sessions.length, 1);

		// Push token, replaced on conflict
		assert.equal((await h.api("POST", "/api/account/push-tokens", { token: user.token, body: { token: "t".repeat(40) } })).status, 200);
		assert.equal((await h.api("POST", "/api/account/push-tokens", { token: user.token, body: { token: "t".repeat(40) } })).status, 200);
		assert.equal((await h.api("POST", "/api/account/push-tokens", { token: user.token, body: { token: "short" } })).status, 400);
	});

	test("administration: only admins, invites, users, access reset", async () => {
		const user = await h.onboard("mario@example.com", "Mario");
		assert.equal((await h.api("GET", "/api/admin/users", { token: user.token })).status, 403);

		const users = await h.api("GET", "/api/admin/users", { token: admin.token });
		assert.ok(users.body.some((item: { email: string }) => item.email === "mario@example.com"));
		// Backups not configured in the tests (BACKUP_DIR empty)
		assert.equal((await h.api("GET", "/api/admin/backup", { token: user.token })).status, 403);
		assert.deepEqual((await h.api("GET", "/api/admin/backup", { token: admin.token })).body,
			{ configured: false, lastSuccess: null, lastOffsite: null, stale: true, latest: null, files: 0, totalBytes: 0 });

		const created = await h.api("POST", "/api/admin/invites", { token: admin.token, body: { email: "nuovo@example.com", name: "Nuovo" } });
		assert.match(created.body.link, /\/#\/invite\/[\w-]{40,}$/);
		assert.equal((await h.api("POST", "/api/admin/invites", { token: admin.token, body: { email: "mario@example.com", name: "Mario" } })).body.error, "email_taken");
		assert.equal((await h.api("POST", "/api/admin/invites", { token: admin.token, body: { email: "not an email", name: "X" } })).status, 400);
		const invites = await h.api("GET", "/api/admin/invites", { token: admin.token });
		const invite = invites.body.find((item: { email: string }) => item.email === "nuovo@example.com");
		assert.equal((await h.api("DELETE", `/api/admin/invites/${invite.id}`, { token: admin.token })).status, 200);
		assert.equal((await h.api("GET", "/api/admin/invites", { token: admin.token })).body.some((item: { email: string }) => item.email === "nuovo@example.com"), false);

		// Changes of the users
		assert.equal((await h.api("PATCH", `/api/admin/users/${admin.id}`, { token: admin.token, body: { disabled: true } })).body.error, "self");
		assert.equal((await h.api("PATCH", "/api/admin/users/999999", { token: admin.token, body: { disabled: true } })).status, 404);
		const live = await h.live(user.token);
		assert.equal((await h.api("PATCH", `/api/admin/users/${user.id}`, { token: admin.token, body: { disabled: true } })).status, 200);
		await new Promise(resolve => setTimeout(resolve, 100));
		assert.equal(live.closed?.code, 4001);
		assert.equal((await h.api("GET", "/api/devices", { token: user.token })).status, 401);
		assert.equal((await h.api("PATCH", `/api/admin/users/${user.id}`, { token: admin.token, body: { disabled: false, isAdmin: true } })).status, 200);
		const [promoted] = await h.sql<{ is_admin: boolean }[]>`SELECT is_admin FROM users WHERE id = ${user.id}`;
		assert.equal(promoted!.is_admin, true);
		await h.api("PATCH", `/api/admin/users/${user.id}`, { token: admin.token, body: { isAdmin: false } });

		// Access reset: the old sessions end when the link is used
		const fresh = await h.session(user.id);
		assert.equal((await h.api("POST", "/api/admin/users/999999/reset", { token: admin.token })).status, 404);
		const reset = await h.api("POST", `/api/admin/users/${user.id}/reset`, { token: admin.token });
		const resetToken = reset.body.link.split("/").at(-1);
		assert.equal((await h.api("GET", `/api/auth/invites/${resetToken}`)).body.reset, true);
		const used = await h.api("POST", `/api/auth/invites/${resetToken}`, { body: { password: "nuova password lunga", client: "app" } });
		assert.equal(used.body.stage, "enroll");
		assert.equal((await h.api("GET", "/api/devices", { token: fresh })).status, 401);

		const events = await h.api("GET", `/api/admin/users/${user.id}/events`, { token: admin.token });
		assert.ok(events.body.some((event: { event: string }) => event.event === "access_reset"));

		assert.equal((await h.api("DELETE", `/api/admin/users/${admin.id}`, { token: admin.token })).body.error, "self");
		assert.equal((await h.api("DELETE", `/api/admin/users/${user.id}`, { token: admin.token })).status, 200);
		assert.equal((await h.api("DELETE", `/api/admin/users/${user.id}`, { token: admin.token })).status, 404);
	});
});
