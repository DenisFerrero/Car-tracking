import type { FastifyInstance, FastifyReply, FastifyRequest } from "fastify";
import type { Config } from "../config.ts";
import type { Sql } from "../db.ts";
import { hashToken, randomToken } from "../auth/secrets.ts";
import { ApiError, forbidden, unauthorized } from "./errors.ts";

// Sessions: opaque random tokens, stored hashed. The browser keeps the token in an
// HttpOnly cookie (not readable by scripts), the Android app in the encrypted storage and
// sends it as a bearer token.
//
// Stages: 'mfa_pending' (password verified, TOTP required), 'enroll' (password verified,
// TOTP to configure: the 2FA is mandatory), 'full'.

export type Stage = "mfa_pending" | "enroll" | "full";
export type Client = "web" | "app";

export interface AuthUser {
	id: number;
	email: string;
	name: string;
	isAdmin: boolean;
	/** it / en, null until the app detects the language of the device */
	locale: string | null;
}

export interface Auth {
	user: AuthUser;
	stage: Stage;
	client: Client;
	tokenHash: Buffer;
	authenticatedAt: Date;
}

declare module "fastify" {
	interface FastifyRequest {
		auth: Auth | null;
	}
	interface FastifyContextConfig {
		// Stage required by the route, 'full' when missing; 'none' for public routes
		auth?: Stage | "none";
	}
}

export const COOKIE = "ct_session";

// Idle timeout (renewed with the use) and absolute lifetime
const LIFETIME = {
	web: { idle: 7 * 86400e3, max: 30 * 86400e3 },
	app: { idle: 30 * 86400e3, max: 180 * 86400e3 }
};
const PENDING_LIFETIME = 10 * 60e3;
const RENEW_EVERY = 5 * 60e3;

// Password changes and new passkeys require an authentication younger than this
export const RECENT_AUTH = 15 * 60e3;

interface SessionRow {
	user_id: number;
	email: string;
	name: string;
	is_admin: boolean;
	locale: string | null;
	disabled: boolean;
	stage: Stage;
	client: Client;
	created_at: Date;
	last_seen_at: Date;
	authenticated_at: Date;
	expires_at: Date;
}

export class Sessions {
	readonly #sql: Sql;
	readonly #config: Config;

	constructor (sql: Sql, config: Config) {
		this.#sql = sql;
		this.#config = config;
	}

	async create (request: FastifyRequest, reply: FastifyReply, userId: number, stage: Stage, client: Client): Promise<string> {
		const token = randomToken();
		const now = Date.now();
		const expires = new Date(now + (stage === "full" ? LIFETIME[client].idle : PENDING_LIFETIME));
		await this.#sql`
			INSERT INTO sessions (token_hash, user_id, client, stage, user_agent, ip, expires_at)
			VALUES (${hashToken(token)}, ${userId}, ${client}, ${stage}, ${(request.headers["user-agent"] ?? "").slice(0, 300)}, ${request.ip}, ${expires})`;
		if (client === "web") this.#setCookie(reply, token, expires);
		return token;
	}

	/** Moves the current session to a new stage with a new token (no session fixation) */
	async upgrade (request: FastifyRequest, reply: FastifyReply, stage: Stage): Promise<string> {
		const auth = request.auth!;
		await this.#sql`DELETE FROM sessions WHERE token_hash = ${auth.tokenHash}`;
		return this.create(request, reply, auth.user.id, stage, auth.client);
	}

	async destroy (request: FastifyRequest, reply: FastifyReply): Promise<void> {
		if (request.auth) await this.#sql`DELETE FROM sessions WHERE token_hash = ${request.auth.tokenHash}`;
		reply.clearCookie(COOKIE, { path: "/" });
	}

	async destroyAll (userId: number, except?: Buffer): Promise<void> {
		if (except) await this.#sql`DELETE FROM sessions WHERE user_id = ${userId} AND token_hash <> ${except}`;
		else await this.#sql`DELETE FROM sessions WHERE user_id = ${userId}`;
	}

	#setCookie (reply: FastifyReply, token: string, expires: Date): void {
		reply.setCookie(COOKIE, token, {
			path: "/",
			httpOnly: true,
			secure: this.#config.PUBLIC_URL.startsWith("https://"),
			sameSite: "strict",
			expires
		});
	}

	/** Token of the request: bearer header (app) or cookie (browser) */
	static tokenOf (request: FastifyRequest): { token: string; viaCookie: boolean } | null {
		const header = request.headers.authorization;
		if (header?.startsWith("Bearer ")) return { token: header.slice(7).trim(), viaCookie: false };
		const cookie = request.cookies[COOKIE];
		return cookie ? { token: cookie, viaCookie: true } : null;
	}

	async resolve (request: FastifyRequest, reply: FastifyReply): Promise<Auth | null> {
		const found = Sessions.tokenOf(request);
		if (!found) return null;

		const tokenHash = hashToken(found.token);
		const [row] = await this.#sql<SessionRow[]>`
			SELECT s.user_id, u.email, u.name, u.is_admin, u.locale, u.disabled, s.stage, s.client, s.created_at,
				s.last_seen_at, s.authenticated_at, s.expires_at
			FROM sessions s JOIN users u ON u.id = s.user_id
			WHERE s.token_hash = ${tokenHash}`;
		const now = Date.now();
		if (!row || row.disabled || row.expires_at.getTime() <= now) {
			if (found.viaCookie) reply.clearCookie(COOKIE, { path: "/" });
			return null;
		}
		// A cookie session can't be used with a bearer header and vice versa
		if ((row.client === "web") !== found.viaCookie) return null;

		if (row.stage === "full" && now - row.last_seen_at.getTime() > RENEW_EVERY) {
			const lifetime = LIFETIME[row.client];
			const expires = new Date(Math.min(now + lifetime.idle, row.created_at.getTime() + lifetime.max));
			await this.#sql`UPDATE sessions SET last_seen_at = now(), expires_at = ${expires}, ip = ${request.ip} WHERE token_hash = ${tokenHash}`;
			if (row.client === "web") this.#setCookie(reply, found.token, expires);
		}

		return {
			user: { id: row.user_id, email: row.email, name: row.name, isAdmin: row.is_admin, locale: row.locale },
			stage: row.stage,
			client: row.client,
			tokenHash,
			authenticatedAt: row.authenticated_at
		};
	}

	async markAuthenticated (tokenHash: Buffer): Promise<void> {
		await this.#sql`UPDATE sessions SET authenticated_at = now() WHERE token_hash = ${tokenHash}`;
	}
}

const SAFE_METHODS = new Set(["GET", "HEAD", "OPTIONS"]);

/**
 * Authentication of every /api route according to config.auth. Cookie sessions must come
 * from the platform origin on the state changing requests (CSRF): the browsers always send
 * Origin on POST / PUT / PATCH / DELETE.
 */
export function registerAuth (app: FastifyInstance, sessions: Sessions, config: Config): void {
	app.decorateRequest("auth", null);

	app.addHook("onRequest", async (request: FastifyRequest, reply: FastifyReply) => {
		// Web app files, assetlinks and the tracker endpoint have no session
		if (!request.url.startsWith("/api/")) return;
		const required = request.routeOptions.config.auth ?? "full";
		const viaCookie = Sessions.tokenOf(request)?.viaCookie ?? false;
		if (viaCookie && !SAFE_METHODS.has(request.method)) {
			const origin = request.headers.origin;
			if (origin !== config.PUBLIC_URL) throw forbidden("Invalid request origin", "bad_origin");
		}

		request.auth = await sessions.resolve(request, reply);
		if (required === "none") return;
		if (!request.auth) throw unauthorized();
		if (request.auth.stage !== required) {
			throw new ApiError(401, `stage_${request.auth.stage}`, "Complete the authentication");
		}
	});
}

export function requireAdmin (request: FastifyRequest): void {
	if (!request.auth?.user.isAdmin) throw forbidden();
}
