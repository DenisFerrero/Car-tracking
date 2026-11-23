import type { FastifyError, FastifyReply, FastifyRequest } from "fastify";
import { z } from "zod";

/** Error sent to the client as { error: code, message } with the given status */
export class ApiError extends Error {
	readonly statusCode: number;
	readonly code: string;

	constructor (statusCode: number, code: string, message: string) {
		super(message);
		this.statusCode = statusCode;
		this.code = code;
	}
}

export const badRequest = (message: string, code = "bad_request") => new ApiError(400, code, message);
export const unauthorized = (message = "Authentication required", code = "unauthorized") => new ApiError(401, code, message);
export const forbidden = (message = "Not allowed", code = "forbidden") => new ApiError(403, code, message);
// 404 instead of 403 for the devices of other users: it doesn't disclose which ids exist
export const notFound = (message = "Not found") => new ApiError(404, "not_found", message);
export const conflict = (message: string, code = "conflict") => new ApiError(409, code, message);

/** Validates a body / query / params, 400 with the first issue */
export function parse<T extends z.ZodType> (schema: T, data: unknown): z.infer<T> {
	const result = schema.safeParse(data);
	if (!result.success) {
		const issue = result.error.issues[0];
		const field = issue?.path.join(".");
		throw badRequest(field ? `${field}: ${issue?.message}` : (issue?.message ?? "Invalid request"), "validation");
	}
	return result.data;
}

// The database can't be reached: network errors of the connection, the timeouts and closed
// connections of postgres.js, the server shutting down or still starting (SQLSTATE 57P0x, 08xxx)
const UNAVAILABLE_CODES = new Set(["ECONNREFUSED", "ENOTFOUND", "EAI_AGAIN", "ETIMEDOUT", "ECONNRESET", "EHOSTUNREACH", "CONNECT_TIMEOUT",
	"CONNECTION_CLOSED", "CONNECTION_ENDED", "CONNECTION_DESTROYED", "57P01", "57P02", "57P03"]);

export function databaseUnavailable (error: unknown): boolean {
	const code = (error as { code?: unknown } | null)?.code;
	return typeof code === "string" && (UNAVAILABLE_CODES.has(code) || /^08[0-9A-Z]{3}$/.test(code));
}

export function errorHandler (error: FastifyError | ApiError, request: FastifyRequest, reply: FastifyReply): void {
	if (error instanceof ApiError) {
		reply.status(error.statusCode).send({ error: error.code, message: error.message });
		return;
	}
	const status = error.statusCode ?? 500;
	if (status >= 500 && databaseUnavailable(error)) {
		// 503 with a retry: the app says the service is down for a moment, not a bug
		const route = `${request.method} ${request.routeOptions.url ?? "(unknown)"}`;
		request.log.error({ err: error, component: "http", status: 503 }, route);
		reply.status(503).header("retry-after", "10").send({ error: "unavailable", message: "Service temporarily unavailable" });
		return;
	}
	if (status >= 500) {
		// Also in the platform log, by route pattern (no URL, body or user)
		const route = `${request.method} ${request.routeOptions.url ?? "(unknown)"}`;
		request.log.error({ err: error, component: "http", status: 500 }, route);
		reply.status(500).send({ error: "internal", message: "Internal error" });
		return;
	}
	// Fastify errors (rate limit, body too large, invalid JSON): message without internals
	reply.status(status).send({ error: error.code?.toLowerCase() ?? "error", message: error.message });
}
