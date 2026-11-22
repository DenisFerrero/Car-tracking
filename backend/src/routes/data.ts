import type { FastifyInstance } from "fastify";
import { z } from "zod";
import type { Context } from "../context.ts";
import { badRequest, parse } from "../http/errors.ts";
import { requireDevice, viewerPosition } from "../services/access.ts";
import type { PositionRow } from "../services/access.ts";
import { CONNECTION_COST, FRAME_OVERHEAD, bucketFor, toCsv, toGpx, toLogbook, tripsOfKind } from "../services/analytics.ts";
import { hasCosts, sumCosts, tripCost, vehicleProfile } from "../services/costs.ts";
import { refreshDay } from "../services/daily.ts";
import type { ExportPoint, TrackPoint } from "../services/analytics.ts";
import { deviceName } from "../services/notifier.ts";

// History and analysis of a device, for its owner. Periods up to 93 days; the
// aggregations run in TimescaleDB (time_bucket), the trips are computed here (phones:
// split by the stops longer than 5 minutes). Viewers of a share get only the track of
// the last 24 hours since the start of the share. The owner exports the period as GPX
// (trips) or CSV (all the points).

const MAX_PERIOD_DAYS = 93;
const HISTORY_LIMIT = 50000;
const VIEWER_HISTORY_MS = 24 * 3600e3;

const idParams = z.strictObject({ id: z.coerce.number().int().positive().max(2 ** 31 - 1) });
const date = z.iso.datetime({ offset: true }).transform(value => new Date(value));
const period = z.strictObject({ from: date, to: date }).refine(value => value.from < value.to, "from must precede to");

// Haversine in SQL between a point and the previous one (lag): no PostGIS needed
const STEP_METERS = `2 * 6371000 * asin(sqrt(
	power(sin(radians(lat - prev_lat) / 2), 2) +
	cos(radians(prev_lat)) * cos(radians(lat)) * power(sin(radians(lon - prev_lon) / 2), 2)))`;

export function registerDataRoutes (app: FastifyInstance, ctx: Context): void {
	const { sql } = ctx;

	type Request = { params: unknown; query: unknown; auth: { user: Parameters<typeof requireDevice>[1] } | null };

	const range = (request: Request) => {
		const { id } = parse(idParams, request.params);
		const value = parse(period, request.query);
		if (value.to.getTime() - value.from.getTime() > MAX_PERIOD_DAYS * 86400e3) {
			throw badRequest(`Period of ${MAX_PERIOD_DAYS} days at most`, "period_too_long");
		}
		return { id, ...value };
	};

	const load = async (request: Request) => {
		const value = range(request);
		const access = await requireDevice(sql, request.auth!.user, value.id, "owner");
		return { ...value, kind: access.kind };
	};

	const tripsOf = tripsOfKind;

	app.get("/api/devices/:id/positions", async (request) => {
		const { id, from, to } = range(request);
		const access = await requireDevice(sql, request.auth!.user, id);
		if (access.role === "viewer") {
			const start = new Date(Math.max(from.getTime(), access.since.getTime(), Date.now() - VIEWER_HISTORY_MS));
			const rows = start < to ? await sql<PositionRow[]>`
				SELECT time, lat, lon, speed, status, stale FROM positions
				WHERE device_id = ${id} AND time BETWEEN ${start} AND ${to} AND lat IS NOT NULL
				ORDER BY time LIMIT ${HISTORY_LIMIT}` : [];
			return { positions: rows.map(viewerPosition), truncated: false };
		}
		// Stale points without coordinates get the position estimated from the cell
		const rows = await sql`
			SELECT p.time, p.lat, p.lon, p.altitude, p.speed, p.pressure, p.temperature, p.voltage, p.satellites,
				p.signal, p.events, p.status, p.stale, p.accuracy, p.mcc, p.mnc, p.cell_area, p.cell_id,
				c.lat AS cell_lat, c.lon AS cell_lon, c.accuracy AS cell_accuracy
			FROM positions p
			LEFT JOIN cells c ON p.cell_id IS NOT NULL AND c.mcc = p.mcc AND c.mnc = p.mnc AND c.area = p.cell_area AND c.cell_id = p.cell_id
			WHERE p.device_id = ${id} AND p.time BETWEEN ${from} AND ${to}
			ORDER BY p.time LIMIT ${HISTORY_LIMIT + 1}`;
		const truncated = rows.length > HISTORY_LIMIT;
		return { positions: truncated ? rows.slice(0, HISTORY_LIMIT) : rows, truncated };
	});

	/** Time series for the charts */
	app.get("/api/devices/:id/stats", async (request) => {
		const { id, from, to } = await load(request);
		const bucket = bucketFor(from, to);
		const series = await sql`
			WITH steps AS (
				SELECT time, lat, lon, lag(lat) OVER w AS prev_lat, lag(lon) OVER w AS prev_lon
				FROM positions WHERE device_id = ${id} AND time BETWEEN ${from} AND ${to} AND NOT stale AND lat IS NOT NULL
				WINDOW w AS (ORDER BY time)
			), distance AS (
				SELECT time_bucket(${bucket}::interval, time) AS bucket, sum(${sql.unsafe(STEP_METERS)}) AS meters
				FROM steps WHERE prev_lat IS NOT NULL GROUP BY 1
			), values AS (
				SELECT time_bucket(${bucket}::interval, time) AS bucket,
					count(*)::int AS points,
					round(avg(speed) FILTER (WHERE status = 0))::int AS avg_speed,
					max(speed)::int AS max_speed,
					round(avg(altitude))::int AS altitude,
					round(avg(signal))::int AS avg_signal,
					min(signal)::int AS min_signal,
					round(avg(satellites), 1)::float AS avg_satellites,
					min(satellites)::int AS min_satellites,
					round(avg(temperature)::numeric, 1)::float AS temperature,
					round(avg(pressure)::numeric, 1)::float AS pressure,
					round(avg(voltage)::numeric, 2)::float AS voltage,
					round(min(voltage)::numeric, 2)::float AS min_voltage,
					(count(*) FILTER (WHERE stale))::int AS stale_points,
					bit_or(events)::int AS events
				FROM positions WHERE device_id = ${id} AND time BETWEEN ${from} AND ${to}
				GROUP BY 1
			)
			SELECT v.*, round(COALESCE(d.meters, 0))::int AS meters
			FROM values v LEFT JOIN distance d USING (bucket) ORDER BY v.bucket`;
		return { bucket, series };
	});

	app.get("/api/devices/:id/trips", async (request) => {
		const { id, from, to, kind } = await load(request);
		const points = await sql<TrackPoint[]>`
			SELECT time, lat, lon, speed, status, stale FROM positions
			WHERE device_id = ${id} AND time BETWEEN ${from} AND ${to} ORDER BY time`;
		const tags = await sql<{ start: Date; purpose: string | null; note: string }[]>`
			SELECT start, purpose, note FROM trip_tags WHERE device_id = ${id} AND start BETWEEN ${from} AND ${to}`;
		const byStart = new Map(tags.map(tag => [tag.start.getTime(), tag]));
		// Trip log: purpose and note of each trip; cost when the owner entered consumption or
		// wear, with the values valid on the day of the trip
		const profile = await vehicleProfile(sql, id);
		const costs = hasCosts(profile) ? profile : null;
		const localDay = (time: Date) => time.toLocaleDateString("sv-SE", { timeZone: ctx.config.TIMEZONE });
		const trips = tripsOf(kind, points).map(trip => {
			const tag = byStart.get(trip.start.getTime());
			return {
				...trip, purpose: tag?.purpose ?? null, note: tag?.note ?? "", cost: costs && tripCost(trip.distanceKm, costs, localDay(trip.start))
			};
		});

		// Totals per day in the time zone of the platform
		const days = new Map<string, { day: string; distanceKm: number; drivingMin: number; trips: number }>();
		for (const trip of trips) {
			const day = localDay(trip.start);
			const total = days.get(day) ?? { day, distanceKm: 0, drivingMin: 0, trips: 0 };
			total.distanceKm = Math.round((total.distanceKm + trip.distanceKm) * 1000) / 1000;
			total.drivingMin += trip.durationMin;
			total.trips += 1;
			days.set(day, total);
		}
		const distanceKm = trips.reduce((sum, trip) => sum + trip.distanceKm, 0);
		return {
			trips,
			days: [...days.values()],
			totals: {
				distanceKm: Math.round(distanceKm * 10) / 10,
				drivingMin: trips.reduce((sum, trip) => sum + trip.durationMin, 0),
				maxSpeed: trips.reduce((max, trip) => Math.max(max, trip.maxSpeed), 0),
				trips: trips.length,
				cost: costs && sumCosts(trips.map(trip => trip.cost!))
			}
		};
	});

	/** File of the period: GPX with a segment per trip, or CSV with every point */
	app.get("/api/devices/:id/export", async (request, reply) => {
		// The format apart, the rest is the period
		const { format, ...query } = parse(z.looseObject({ format: z.enum(["gpx", "csv"]) }), request.query);
		const { id, from, to, kind } = await load({ params: request.params, query, auth: request.auth });
		const points = await sql<ExportPoint[]>`
			SELECT time, lat, lon, speed, status, stale, altitude, accuracy, satellites, signal, voltage FROM positions
			WHERE device_id = ${id} AND time BETWEEN ${from} AND ${to} ORDER BY time`;
		const trips = tripsOf(kind, points);
		const [device] = await sql<{ name: string; imei: string | null }[]>`SELECT name, imei FROM devices WHERE id = ${id}`;
		const name = deviceName(device!);
		const file = `${name.replace(/[^\p{L}\p{N}_-]+/gu, "_")}-${from.toISOString().slice(0, 10)}.${format}`;
		reply.header("content-disposition", `attachment; filename="${encodeURIComponent(file)}"`);
		reply.type(format === "gpx" ? "application/gpx+xml; charset=utf-8" : "text/csv; charset=utf-8");
		return format === "gpx" ? toGpx(name, points, trips) : toCsv(points, trips);
	});

	/** Distributions of signal, satellites and speed, and quality of the fix */
	app.get("/api/devices/:id/distribution", async (request) => {
		const { id, from, to } = await load(request);
		const where = sql`device_id = ${id} AND time BETWEEN ${from} AND ${to}`;
		const [signal, satellites, speed, quality] = await Promise.all([
			sql`SELECT (floor(signal / 5.0) * 5)::int AS value, count(*)::int AS count FROM positions
				WHERE ${where} AND signal IS NOT NULL GROUP BY 1 ORDER BY 1`,
			sql`SELECT satellites AS value, count(*)::int AS count FROM positions
				WHERE ${where} AND satellites IS NOT NULL GROUP BY 1 ORDER BY 1`,
			sql`SELECT (floor(speed / 10.0) * 10)::int AS value, count(*)::int AS count FROM positions
				WHERE ${where} AND speed IS NOT NULL AND status = 0 GROUP BY 1 ORDER BY 1`,
			sql`SELECT count(*)::int AS total, (count(*) FILTER (WHERE stale))::int AS stale,
				(count(*) FILTER (WHERE NOT stale AND satellites < 6))::int AS weak_fix,
				(count(*) FILTER (WHERE signal < -105))::int AS weak_signal
				FROM positions WHERE ${where}`
		]);
		return { signal, satellites, speed, quality: quality[0] };
	});

	/**
	 * Coverage map: average signal and satellites on a grid of about 500 m, to find the
	 * places where the tracker loses the network or the fix
	 */
	app.get("/api/devices/:id/coverage", async (request) => {
		const { id, from, to } = await load(request);
		const cells = await sql`
			SELECT round(lat::numeric, 3)::float AS lat, round(lon::numeric, 3)::float AS lon, count(*)::int AS points,
				round(avg(signal))::int AS avg_signal, min(signal)::int AS min_signal,
				round(avg(satellites), 1)::float AS avg_satellites, min(satellites)::int AS min_satellites,
				(count(*) FILTER (WHERE stale))::int AS stale
			FROM positions
			WHERE device_id = ${id} AND time BETWEEN ${from} AND ${to} AND lat IS NOT NULL
			GROUP BY 1, 2 ORDER BY 3 DESC LIMIT 5000`;
		return { gridDegrees: 0.001, cells };
	});

	/** Estimated data usage of the SIM per day, and projection of the current month */
	/** Trip log: a trip marked business or personal, with a note; nothing = tag removed */
	app.put("/api/devices/:id/trips/tag", async (request) => {
		const { id } = parse(idParams, request.params);
		const body = parse(z.strictObject({
			start: z.iso.datetime({ offset: true }).transform(value => new Date(value)),
			purpose: z.enum(["business", "personal"]).nullable(),
			note: z.string().trim().max(200).default("")
		}), request.body);
		const access = await requireDevice(sql, request.auth!.user, id, "owner");
		if (body.purpose === null && body.note === "") {
			await sql`DELETE FROM trip_tags WHERE device_id = ${id} AND start = ${body.start}`;
		} else {
			await sql`
				INSERT INTO trip_tags (device_id, start, purpose, note) VALUES (${id}, ${body.start}, ${body.purpose}, ${body.note})
				ON CONFLICT (device_id, start) DO UPDATE SET purpose = excluded.purpose, note = excluded.note`;
		}
		// Business / personal km of that day in the statistics
		const day = body.start.toLocaleDateString("sv-SE", { timeZone: ctx.config.TIMEZONE });
		await refreshDay(sql, ctx.config.TIMEZONE, { id, kind: access.kind }, day);
		return { ok: true };
	});

	/** Trip log of a month as CSV for the spreadsheets (reimbursements), in the language of the user */
	app.get("/api/devices/:id/logbook", async (request, reply) => {
		const { id } = parse(idParams, request.params);
		const { month } = parse(z.strictObject({ month: z.string().regex(/^\d{4}-(0[1-9]|1[0-2])$/) }), request.query);
		const access = await requireDevice(sql, request.auth!.user, id, "owner");
		const [bounds] = await sql<{ start: Date; end: Date }[]>`
			SELECT (${month + "-01"}::date::timestamp AT TIME ZONE ${ctx.config.TIMEZONE}) AS start,
				((${month + "-01"}::date + interval '1 month')::timestamp AT TIME ZONE ${ctx.config.TIMEZONE}) AS end`;
		const points = await sql<TrackPoint[]>`
			SELECT time, lat, lon, speed, status, stale FROM positions
			WHERE device_id = ${id} AND time >= ${bounds!.start} AND time < ${bounds!.end} ORDER BY time`;
		const tags = await sql<{ start: Date; purpose: "business" | "personal" | null; note: string }[]>`
			SELECT start, purpose, note FROM trip_tags WHERE device_id = ${id} AND start >= ${bounds!.start} AND start < ${bounds!.end}`;
		const [device] = await sql<{ name: string; imei: string | null }[]>`SELECT name, imei FROM devices WHERE id = ${id}`;
		const csv = toLogbook(tripsOf(access.kind, points), tags, request.auth!.user.locale, ctx.config.TIMEZONE, await vehicleProfile(sql, id));
		const name = deviceName(device!).replace(/[^\w.-]+/g, "_");
		reply.header("content-type", "text/csv; charset=utf-8");
		reply.header("content-disposition", `attachment; filename="${name}-${month}.csv"`);
		return csv;
	});

	app.get("/api/devices/:id/traffic", async (request) => {
		const { id, from, to } = await load(request);
		const daily = await sql<{ day: string; frames: number; uplink: number; downlink: number; connections: number }[]>`
			SELECT to_char(time_bucket('1 day', time, ${ctx.config.TIMEZONE}), 'YYYY-MM-DD') AS day,
				(count(*) FILTER (WHERE frame_type <> 0))::int AS frames,
				COALESCE(sum(bytes) FILTER (WHERE uplink), 0)::int AS uplink,
				COALESCE(sum(bytes) FILTER (WHERE NOT uplink), 0)::int AS downlink,
				(count(*) FILTER (WHERE frame_type = 0))::int AS connections
			FROM traffic WHERE device_id = ${id} AND time BETWEEN ${from} AND ${to}
			GROUP BY 1 ORDER BY 1`;
		const estimate = (row: { frames: number; uplink: number; downlink: number; connections: number }) =>
			row.uplink + row.downlink + row.frames * FRAME_OVERHEAD + row.connections * CONNECTION_COST;

		const [month] = await sql<{ frames: number; uplink: number; downlink: number; connections: number; days: number }[]>`
			SELECT (count(*) FILTER (WHERE frame_type <> 0))::int AS frames,
				COALESCE(sum(bytes) FILTER (WHERE uplink), 0)::int AS uplink,
				COALESCE(sum(bytes) FILTER (WHERE NOT uplink), 0)::int AS downlink,
				(count(*) FILTER (WHERE frame_type = 0))::int AS connections,
				extract(day FROM now() AT TIME ZONE ${ctx.config.TIMEZONE})::int AS days
			FROM traffic WHERE device_id = ${id}
				AND time >= date_trunc('month', now() AT TIME ZONE ${ctx.config.TIMEZONE}) AT TIME ZONE ${ctx.config.TIMEZONE}`;
		const monthBytes = month ? estimate(month) : 0;
		const now = new Date();
		const daysInMonth = new Date(now.getFullYear(), now.getMonth() + 1, 0).getDate();

		return {
			budgetBytes: ctx.config.SIM_BUDGET_MB * 1024 * 1024,
			frameOverhead: FRAME_OVERHEAD,
			connectionCost: CONNECTION_COST,
			daily: daily.map(row => ({ ...row, estimatedBytes: estimate(row) })),
			month: {
				estimatedBytes: monthBytes,
				projectedBytes: month && month.days > 0 ? Math.round(monthBytes / month.days * daysInMonth) : 0
			}
		};
	});
}
