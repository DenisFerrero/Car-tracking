import {
	generateAuthenticationOptions,
	generateRegistrationOptions,
	verifyAuthenticationResponse,
	verifyRegistrationResponse
} from "@simplewebauthn/server";
import type { AuthenticationResponseJSON, RegistrationResponseJSON } from "@simplewebauthn/server";
import type { Config } from "../config.ts";
import type { Sql } from "../db.ts";
import { badRequest, unauthorized } from "../http/errors.ts";

// Passkeys (WebAuthn), always with user verification: fingerprint, face or PIN of the
// phone. A passkey is possession + biometrics, so it satisfies the 2FA alone.
//
// Relying party = host of PUBLIC_URL. The Android app signs the requests with the origin
// "android:apk-key-hash:<sha256 of the signing certificate>", and the domain must declare
// the app in /.well-known/assetlinks.json.

const CHALLENGE_TTL = 5 * 60e3;

export interface StoredPasskey {
	id: string;
	user_id: number;
	public_key: Buffer;
	counter: number;
	transports: string[];
}

export function androidOrigin (fingerprint: string): string {
	return "android:apk-key-hash:" + Buffer.from(fingerprint.replace(/:/g, ""), "hex").toString("base64url");
}

export class WebAuthn {
	readonly #sql: Sql;
	readonly rpID: string;
	readonly #rpName: string;
	readonly origins: string[];

	constructor (sql: Sql, config: Config) {
		this.#sql = sql;
		this.rpID = new URL(config.PUBLIC_URL).hostname;
		this.#rpName = config.APP_NAME;
		this.origins = [config.PUBLIC_URL, ...config.ANDROID_CERT_SHA256.map(androidOrigin)];
	}

	async #storeChallenge (challenge: string, purpose: "register" | "login", userId: number | null): Promise<void> {
		await this.#sql`DELETE FROM webauthn_challenges WHERE expires_at < now()`;
		await this.#sql`
			INSERT INTO webauthn_challenges (challenge, user_id, purpose, expires_at)
			VALUES (${challenge}, ${userId}, ${purpose}, ${new Date(Date.now() + CHALLENGE_TTL)})`;
	}

	/** Single use: the challenge is deleted while it's verified */
	async #takeChallenge (clientDataJSON: string, purpose: "register" | "login", userId: number | null): Promise<string> {
		let challenge: unknown;
		try {
			challenge = JSON.parse(Buffer.from(clientDataJSON, "base64url").toString("utf8")).challenge;
		} catch {
			throw badRequest("Invalid passkey response", "invalid_passkey");
		}
		if (typeof challenge !== "string") throw badRequest("Invalid passkey response", "invalid_passkey");

		const [row] = await this.#sql<{ user_id: number | null }[]>`
			DELETE FROM webauthn_challenges
			WHERE challenge = ${challenge} AND purpose = ${purpose} AND expires_at > now()
			RETURNING user_id`;
		if (!row || (userId !== null && row.user_id !== userId)) throw unauthorized("Request expired, try again", "challenge_expired");
		return challenge;
	}

	async registrationOptions (user: { id: number; email: string; name: string }) {
		const existing = await this.#sql<{ id: string; transports: string[] }[]>`SELECT id, transports FROM passkeys WHERE user_id = ${user.id}`;
		const options = await generateRegistrationOptions({
			rpName: this.#rpName,
			rpID: this.rpID,
			userName: user.email,
			userDisplayName: user.name,
			// Stable handle: the authenticators replace the old passkey of the same account
			userID: new TextEncoder().encode(`user-${user.id}`),
			attestationType: "none",
			excludeCredentials: existing.map(passkey => ({ id: passkey.id, transports: passkey.transports })),
			authenticatorSelection: { residentKey: "required", userVerification: "required" }
		});
		await this.#storeChallenge(options.challenge, "register", user.id);
		return options;
	}

	async register (userId: number, name: string, response: RegistrationResponseJSON): Promise<string> {
		const challenge = await this.#takeChallenge(response.response.clientDataJSON, "register", userId);
		let verification;
		try {
			verification = await verifyRegistrationResponse({
				response,
				expectedChallenge: challenge,
				expectedOrigin: this.origins,
				expectedRPID: this.rpID,
				requireUserVerification: true
			});
		} catch (error) {
			throw badRequest(`Invalid passkey: ${(error as Error).message}`, "invalid_passkey");
		}
		if (!verification.verified) throw badRequest("Invalid passkey", "invalid_passkey");

		const { credential, credentialBackedUp } = verification.registrationInfo;
		await this.#sql`
			INSERT INTO passkeys (id, user_id, name, public_key, counter, transports, backed_up)
			VALUES (${credential.id}, ${userId}, ${name}, ${Buffer.from(credential.publicKey)}, ${credential.counter},
				${credential.transports ?? []}, ${credentialBackedUp})`;
		return credential.id;
	}

	async authenticationOptions () {
		// Discoverable credentials: the phone shows the accounts, no email to type
		const options = await generateAuthenticationOptions({ rpID: this.rpID, userVerification: "required" });
		await this.#storeChallenge(options.challenge, "login", null);
		return options;
	}

	/** Returns the user of the passkey */
	async authenticate (response: AuthenticationResponseJSON): Promise<number> {
		const challenge = await this.#takeChallenge(response.response.clientDataJSON, "login", null);
		const [passkey] = await this.#sql<StoredPasskey[]>`
			SELECT id, user_id, public_key, counter, transports FROM passkeys WHERE id = ${response.id}`;
		if (!passkey) throw unauthorized("Unknown passkey", "invalid_credentials");

		let verification;
		try {
			verification = await verifyAuthenticationResponse({
				response,
				expectedChallenge: challenge,
				expectedOrigin: this.origins,
				expectedRPID: this.rpID,
				credential: {
					id: passkey.id,
					publicKey: new Uint8Array(passkey.public_key),
					counter: Number(passkey.counter),
					transports: passkey.transports
				},
				requireUserVerification: true
			});
		} catch {
			throw unauthorized("Invalid passkey", "invalid_credentials");
		}
		if (!verification.verified) throw unauthorized("Invalid passkey", "invalid_credentials");

		await this.#sql`
			UPDATE passkeys SET counter = ${verification.authenticationInfo.newCounter}, last_used_at = now()
			WHERE id = ${passkey.id}`;
		return passkey.user_id;
	}
}
