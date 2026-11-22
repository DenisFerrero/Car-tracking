import type { FastifyInstance } from "fastify";
import { z } from "zod";
import type { Context } from "../context.ts";
import { badRequest, notFound, parse } from "../http/errors.ts";
import { requireTracker } from "../services/access.ts";
import { FirmwareError } from "../services/firmware.ts";
import { idParams } from "./devices.ts";

// Firmware updates: the owner of a tracker sees the newer versions of its variant and
// installs one, or lets the tracker update itself; the administrator lists and removes the
// images (from the GitHub releases or uploaded with npm run firmware, see
// scripts/firmware.ts). Latest version of the Android app.

function apiError (error: unknown): never {
	if (error instanceof FirmwareError) throw error.code === "not_found" ? notFound(error.message) : badRequest(error.message, error.code);
	throw error;
}

export function registerFirmwareRoutes (app: FastifyInstance, ctx: Context): void {
	const { sql, firmware } = ctx;

	const trackerFirmware = async (id: number) => {
		const [device] = await sql<{ firmware: string }[]>`SELECT firmware FROM devices WHERE id = ${id}`;
		return device!.firmware;
	};

	app.get("/api/devices/:id/firmware", async (request) => {
		const { id } = parse(idParams, request.params);
		await requireTracker(sql, request.auth!.user, id);
		return firmware.state(id, await trackerFirmware(id));
	});

	app.post("/api/devices/:id/firmware", async (request) => {
		const { id } = parse(idParams, request.params);
		const body = parse(z.strictObject({ firmwareId: z.number().int().positive().max(2 ** 31 - 1) }), request.body);
		await requireTracker(sql, request.auth!.user, id);
		return firmware.request(id, await trackerFirmware(id), body.firmwareId, request.auth!.user.id).catch(apiError);
	});

	app.delete("/api/devices/:id/firmware", async (request) => {
		const { id } = parse(idParams, request.params);
		await requireTracker(sql, request.auth!.user, id);
		if (!(await firmware.cancel(id))) throw notFound("No update pending");
		return { ok: true };
	});

	/** Automatic updates of a tracker (builds with AUTO_UPDATE ask once a day) */
	app.put("/api/devices/:id/firmware/auto", async (request) => {
		const { id } = parse(idParams, request.params);
		const { enabled } = parse(z.strictObject({ enabled: z.boolean() }), request.body);
		await requireTracker(sql, request.auth!.user, id);
		await firmware.setAutoUpdate(id, enabled);
		return firmware.state(id, await trackerFirmware(id));
	});

	/** Latest Android app of the releases: the app offers it when newer than itself */
	app.get("/api/app/release", async () => ({ release: await ctx.releases.app() }));

	app.get("/api/admin/firmware", async () => firmware.list());

	/** Reads the latest release of the repository now instead of within 6 hours */
	app.post("/api/admin/releases/check", async () => {
		if (!ctx.releases.enabled) throw badRequest("GITHUB_REPO not configured", "releases_disabled");
		return { added: await ctx.releases.check() };
	});

	app.delete("/api/admin/firmware/:id", async (request) => {
		const { id } = parse(idParams, request.params);
		if (!(await firmware.remove(id))) throw notFound();
		return { ok: true };
	});
}
