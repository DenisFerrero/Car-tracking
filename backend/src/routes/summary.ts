import type { FastifyInstance } from "fastify";
import { z } from "zod";
import type { Context } from "../context.ts";
import { badRequest, parse } from "../http/errors.ts";
import { today } from "../services/daily.ts";
import { monthSummary } from "../services/summary.ts";

// Summary of a month of the user (devices owned): opened from the notification of the
// start of the month, or any month of the last 3 years

const MAX_MONTHS_BACK = 36;
const monthParams = z.strictObject({ month: z.string().regex(/^\d{4}-(0[1-9]|1[0-2])$/) });

export function registerSummaryRoutes (app: FastifyInstance, ctx: Context): void {
	const { sql } = ctx;
	const tz = ctx.config.TIMEZONE;

	app.get("/api/summary/:month", async (request) => {
		const { month } = parse(monthParams, request.params);
		const current = (await today(sql, tz)).slice(0, 7);
		const back = (Number(current.slice(0, 4)) - Number(month.slice(0, 4))) * 12 + Number(current.slice(5)) - Number(month.slice(5));
		if (back < 0 || back > MAX_MONTHS_BACK) throw badRequest(`A month of the last ${MAX_MONTHS_BACK}`, "month_out_of_range");
		return monthSummary(sql, tz, request.auth!.user.id, month);
	});
}
