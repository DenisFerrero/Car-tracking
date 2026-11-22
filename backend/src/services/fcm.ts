import crypto from "node:crypto";
import fs from "node:fs";

// Firebase Cloud Messaging HTTP v1, without the Google SDK: a JWT signed with the key of
// the service account gives an OAuth token (cached for 50 minutes).

interface ServiceAccount {
	project_id: string;
	client_email: string;
	private_key: string;
}

export type PushResult = "ok" | "invalid_token" | "error";

export interface FcmEndpoints {
	token: string;
	api: string;
}

export class Fcm {
	readonly #account: ServiceAccount;
	readonly #endpoints: FcmEndpoints;
	#token: { value: string; expires: number } | null = null;

	constructor (file: string, endpoints: FcmEndpoints) {
		this.#endpoints = endpoints;
		const account = JSON.parse(fs.readFileSync(file, "utf8")) as Partial<ServiceAccount>;
		if (!account.project_id || !account.client_email || !account.private_key) {
			throw new Error(`${file} is not a Firebase service account`);
		}
		this.#account = account as ServiceAccount;
	}

	async #accessToken (): Promise<string> {
		if (this.#token && this.#token.expires > Date.now()) return this.#token.value;

		const now = Math.floor(Date.now() / 1000);
		const encode = (value: object) => Buffer.from(JSON.stringify(value)).toString("base64url");
		const unsigned = `${encode({ alg: "RS256", typ: "JWT" })}.${encode({
			iss: this.#account.client_email,
			scope: "https://www.googleapis.com/auth/firebase.messaging",
			aud: this.#endpoints.token,
			iat: now,
			exp: now + 3600
		})}`;
		const signature = crypto.sign("RSA-SHA256", Buffer.from(unsigned), this.#account.private_key).toString("base64url");

		const response = await fetch(this.#endpoints.token, {
			method: "POST",
			headers: { "content-type": "application/x-www-form-urlencoded" },
			body: new URLSearchParams({ grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer", assertion: `${unsigned}.${signature}` }),
			signal: AbortSignal.timeout(10e3)
		});
		if (!response.ok) throw new Error(`FCM authentication failed: ${response.status}`);
		const body = await response.json() as { access_token: string };
		this.#token = { value: body.access_token, expires: Date.now() + 50 * 60e3 };
		return body.access_token;
	}

	/** The notification carries only title and short text, never coordinates */
	async send (token: string, title: string, body: string, data: Record<string, string>): Promise<PushResult> {
		const response = await fetch(`${this.#endpoints.api}/v1/projects/${this.#account.project_id}/messages:send`, {
			method: "POST",
			headers: { authorization: `Bearer ${await this.#accessToken()}`, "content-type": "application/json" },
			body: JSON.stringify({
				message: {
					token,
					notification: { title, body },
					data,
					// Default channel of firebase_messaging: the app creates no custom channel
					android: { priority: "high" }
				}
			}),
			signal: AbortSignal.timeout(10e3)
		});
		if (response.ok) return "ok";
		if (response.status === 404 || response.status === 400) return "invalid_token";
		return "error";
	}
}
