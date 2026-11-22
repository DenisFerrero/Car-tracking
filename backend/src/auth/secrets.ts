import crypto from "node:crypto";
import { hash, verify } from "@node-rs/argon2";
import { Secret, TOTP } from "otpauth";

// Primitives of the authentication: random tokens, password hashing, encryption of the
// TOTP secrets at rest, TOTP and recovery codes.

export function randomToken (bytes = 32): string {
	return crypto.randomBytes(bytes).toString("base64url");
}

/** Tokens are stored hashed: a database dump doesn't give usable sessions or invites */
export function hashToken (token: string): Buffer {
	return crypto.createHash("sha256").update(token).digest();
}

// argon2id with the OWASP minimum parameters (19 MiB, 2 passes): ~30 ms per login
const ARGON2 = { memoryCost: 19456, timeCost: 2, parallelism: 1 };
// Verified when the email doesn't exist: same response time for existing and missing users
const DUMMY_HASH = "$argon2id$v=19$m=19456,t=2,p=1$pWFyDhdlBfDiFczlg1yvBQ$YxZVypF9WCO/AVS0FDE0wwG3pZzEFWpbUhEeuSpXTOw";

export const PASSWORD_MIN_LENGTH = 12;

export function hashPassword (password: string): Promise<string> {
	return hash(password, ARGON2);
}

export async function verifyPassword (passwordHash: string | null, password: string): Promise<boolean> {
	try {
		const valid = await verify(passwordHash ?? DUMMY_HASH, password);
		return valid && passwordHash !== null;
	} catch {
		return false;
	}
}

/** AES-256-GCM with a key derived from the master key, for the TOTP secrets */
export class SecretBox {
	readonly #key: Buffer;

	constructor (masterKey: string) {
		this.#key = Buffer.from(crypto.hkdfSync("sha256", masterKey, "car-tracking", "totp-secrets/v1", 32));
	}

	seal (plaintext: string): Buffer {
		const iv = crypto.randomBytes(12);
		const cipher = crypto.createCipheriv("aes-256-gcm", this.#key, iv);
		const ciphertext = Buffer.concat([cipher.update(plaintext, "utf8"), cipher.final()]);
		return Buffer.concat([iv, cipher.getAuthTag(), ciphertext]);
	}

	open (sealed: Buffer): string {
		const decipher = crypto.createDecipheriv("aes-256-gcm", this.#key, sealed.subarray(0, 12));
		decipher.setAuthTag(sealed.subarray(12, 28));
		return Buffer.concat([decipher.update(sealed.subarray(28)), decipher.final()]).toString("utf8");
	}
}

// Standard parameters, supported by every authenticator app (Aegis, Google Authenticator...)
const TOTP_OPTIONS = { algorithm: "SHA1", digits: 6, period: 30 };

export function newTotpSecret (): string {
	return new Secret({ size: 20 }).base32;
}

export function totpUri (secret: string, issuer: string, account: string): string {
	return new TOTP({ ...TOTP_OPTIONS, issuer, label: account, secret: Secret.fromBase32(secret) }).toString();
}

/**
 * Verifies a code (±1 step for the clock drift). Returns the step of the code, or null:
 * the caller stores it and passes it as lastStep, a code is accepted only once.
 */
export function verifyTotp (secret: string, code: string, lastStep: number, now = Date.now()): number | null {
	const token = code.replace(/\s/g, "");
	if (!/^\d{6}$/.test(token)) return null;
	const delta = TOTP.validate({ ...TOTP_OPTIONS, token, secret: Secret.fromBase32(secret), timestamp: now, window: 1 });
	if (delta === null) return null;
	const step = TOTP.counter({ period: TOTP_OPTIONS.period, timestamp: now }) + delta;
	return step > lastStep ? step : null;
}

// Crockford base32 without ambiguous characters, 60 bits per code
const CODE_ALPHABET = "0123456789ABCDEFGHJKMNPQRSTVWXYZ";
export const RECOVERY_CODE_COUNT = 10;

export function newRecoveryCodes (): string[] {
	return Array.from({ length: RECOVERY_CODE_COUNT }, () => {
		const bytes = crypto.randomBytes(12);
		let code = "";
		for (let i = 0; i < 12; i++) code += CODE_ALPHABET[bytes[i]! % 32];
		return `${code.slice(0, 4)}-${code.slice(4, 8)}-${code.slice(8)}`;
	});
}

export function hashRecoveryCode (code: string): Buffer {
	const normalized = code.toUpperCase().replace(/O/g, "0").replace(/[IL]/g, "1").replace(/[^0-9A-Z]/g, "");
	return hashToken(normalized);
}
