import fs from "node:fs";
import path from "node:path";
import Fastify from "fastify";
import type { FastifyInstance } from "fastify";
import cookie from "@fastify/cookie";
import helmet from "@fastify/helmet";
import rateLimit from "@fastify/rate-limit";
import fastifyStatic from "@fastify/static";
import websocket from "@fastify/websocket";
import type { Context } from "./context.ts";
import type { Gateway } from "./tracker/gateway.ts";
import { ApiError, errorHandler } from "./http/errors.ts";
import { Sessions, registerAuth } from "./http/session.ts";
import { registerAccountRoutes } from "./routes/account.ts";
import { registerAdminRoutes } from "./routes/admin.ts";
import { registerAuthRoutes } from "./routes/auth.ts";
import { registerDataRoutes } from "./routes/data.ts";
import { registerDeviceRoutes } from "./routes/devices.ts";
import { registerExtraRoutes } from "./routes/extra.ts";
import { registerFirmwareRoutes } from "./routes/firmware.ts";
import { registerVehicleRoutes } from "./routes/vehicle.ts";
import { registerFriendRoutes } from "./routes/friends.ts";
import { registerGeofenceRoutes } from "./routes/geofences.ts";
import { registerNotificationRoutes } from "./routes/notifications.ts";
import { registerPhoneRoutes } from "./routes/phones.ts";

// HTTP server: REST API (/api), realtime channel (/api/live), binary WebSocket of the
// trackers (/tracker) and the Flutter web app. TLS is terminated by the proxy (Traefik).
//
// Protections, cheapest first: rate limit per client address (in memory, before any
// session lookup), body and parameter size limits, timeouts against slow clients,
// session and stage of every /api route, zod validation of every input.

const MAX_WS_MESSAGE = 64 * 1024;

export function createLogger (level: string) {
	return {
		level,
		// Tokens and cookies never end up in the logs
		redact: ["req.headers.authorization", "req.headers.cookie", "res.headers[\"set-cookie\"]"]
	};
}

function trustProxy (value: string): string[] | boolean {
	if (value === "true") return true;
	if (value === "false" || value === "") return false;
	return value.split(",").map(item => item.trim());
}

export async function buildApp (ctx: Context, gateway: Gateway): Promise<FastifyInstance> {
	const { config } = ctx;
	const app = Fastify({
		loggerInstance: ctx.log,
		trustProxy: trustProxy(config.TRUST_PROXY),
		bodyLimit: 64 * 1024,
		// Passkey ids travel in the path
		routerOptions: { maxParamLength: 1500 },
		// Slow clients (slowloris): the whole request within 30 s, idle sockets closed
		requestTimeout: 30e3,
		connectionTimeout: 120e3,
		keepAliveTimeout: 65e3,
		onProtoPoisoning: "error",
		onConstructorPoisoning: "error"
	});
	app.setErrorHandler(errorHandler);

	const tileOrigin = new URL(config.MAP_TILE_URL.replace(/\{[a-z]\}/g, "a")).origin;
	await app.register(helmet, {
		contentSecurityPolicy: {
			directives: {
				defaultSrc: ["'self'"],
				// CanvasKit (WebAssembly) of Flutter, served by the backend
				scriptSrc: ["'self'", "'wasm-unsafe-eval'"],
				styleSrc: ["'self'", "'unsafe-inline'"],
				imgSrc: ["'self'", "data:", "blob:", tileOrigin],
				// Flutter downloads the fallback fonts (Noto) from Google Fonts
				connectSrc: ["'self'", tileOrigin, "https://fonts.gstatic.com"],
				fontSrc: ["'self'", "https://fonts.gstatic.com"],
				workerSrc: ["'self'", "blob:"],
				frameAncestors: ["'none'"],
				objectSrc: ["'none'"],
				baseUri: ["'self'"],
				// Only behind TLS: on plain http (local tests) it would break every request
				upgradeInsecureRequests: config.PUBLIC_URL.startsWith("https://") ? [] : null
			}
		},
		crossOriginEmbedderPolicy: false,
		// Only the origin, never the path: the OSM tile policy requires the Referer of web apps
		referrerPolicy: { policy: "strict-origin-when-cross-origin" },
		strictTransportSecurity: config.PUBLIC_URL.startsWith("https://") ? { maxAge: 31536000 } : false
	});
	await app.register(cookie);

	// The global rate limit is an application hook added before the one of the sessions: a
	// flood of random tokens never reaches the database (route hooks would run after the
	// session lookup). The routes that verify secrets add stricter limits in their config.
	// The trackers have their own limits (src/tracker/gateway.ts).
	await app.register(rateLimit, {
		global: false,
		errorResponseBuilder: (_request, context) => new ApiError(429, "rate_limited", `Too many requests, retry in ${context.after}`)
	});
	// createRateLimit only counts: the stricter route limits still run after it
	const globalLimit = app.createRateLimit({ max: config.RATE_LIMIT, timeWindow: "1 minute" });
	app.addHook("onRequest", async (request, reply) => {
		if (request.url === "/tracker") return;
		const limit = await globalLimit(request);
		if (limit.isAllowed || !limit.isExceeded) return;
		reply.header("retry-after", limit.ttlInSeconds);
		throw new ApiError(429, "rate_limited", `Too many requests, retry in ${limit.ttlInSeconds} seconds`);
	});
	registerAuth(app, ctx.sessions, config);
	await app.register(websocket, { options: { maxPayload: MAX_WS_MESSAGE } });

	app.get("/healthz", { config: { auth: "none" } }, async () => ({ ok: true }));

	app.get("/api/config", { config: { auth: "none" } }, async () => ({
		appName: config.APP_NAME,
		mapTileUrl: config.MAP_TILE_URL,
		mapAttribution: config.MAP_ATTRIBUTION,
		simBudgetMb: config.SIM_BUDGET_MB,
		offlineAfterHours: config.OFFLINE_AFTER_HOURS,
		pushEnabled: ctx.notifier.pushEnabled,
		cellGeolocation: config.CELL_GEOLOCATION_URL !== ""
	}));

	// Digital Asset Links: the Android app can use the passkeys of this domain
	app.get("/.well-known/assetlinks.json", async () => config.ANDROID_CERT_SHA256.length === 0 ? [] : [{
		relation: ["delegate_permission/common.handle_all_urls", "delegate_permission/common.get_login_creds"],
		target: { namespace: "android_app", package_name: config.ANDROID_PACKAGE, sha256_cert_fingerprints: config.ANDROID_CERT_SHA256 }
	}]);

	// Trackers: one binary frame of the protocol per WebSocket message
	app.get("/tracker", { websocket: true }, (socket, request) => gateway.handleWebSocket(socket, request.ip));

	// Realtime channel of the app. Browsers can't set headers on a WebSocket: cookie
	// sessions are accepted only from the platform origin (no cross-site hijacking).
	app.get("/api/live", { websocket: true }, (socket, request) => {
		if (Sessions.tokenOf(request)?.viaCookie && request.headers.origin !== config.PUBLIC_URL) {
			socket.close(4003, "bad origin");
			return;
		}
		void ctx.hub.attach(socket, request.auth!.user);
	});

	registerAuthRoutes(app, ctx);
	registerAccountRoutes(app, ctx);
	registerAdminRoutes(app, ctx);
	registerDeviceRoutes(app, ctx, gateway);
	registerPhoneRoutes(app, ctx);
	registerFriendRoutes(app, ctx);
	registerFirmwareRoutes(app, ctx);
	registerExtraRoutes(app, ctx);
	registerDataRoutes(app, ctx);
	registerVehicleRoutes(app, ctx);
	registerGeofenceRoutes(app, ctx);
	registerNotificationRoutes(app, ctx);

	if (config.WEB_ROOT) {
		const root = path.resolve(config.WEB_ROOT);
		if (!fs.existsSync(path.join(root, "index.html"))) throw new Error(`WEB_ROOT ${root} has no index.html`);
		await app.register(fastifyStatic, {
			root,
			wildcard: true,
			// .br / .gz files written by scripts/compress-web.ts at build time
			preCompressed: true,
			// The Flutter build has no content hashes in the file names (main.dart.js...):
			// every file is revalidated (ETag), an update is never mixed with old files
			setHeaders: (reply) => {
				reply.header("cache-control", "no-cache");
			}
		});
		app.setNotFoundHandler((request, reply) => {
			if (request.method === "GET" && !request.url.startsWith("/api/")) return reply.sendFile("index.html");
			return reply.status(404).send({ error: "not_found", message: "Not found" });
		});
	}

	return app;
}
