import { randomInt } from "node:crypto";
import type { FastifyInstance } from "fastify";
import { z } from "zod";
import type { Context } from "../context.ts";
import type { Sql } from "../db.ts";
import { badRequest, notFound, parse } from "../http/errors.ts";

// Friends. Users don't see each other: every user has a personal code (typed, or read
// from its QR code in the app). Whoever has it sends a friend request, the friendship
// starts when the owner of the code accepts it (two crossed requests: friends at once).
// Devices are shared only with friends. A new code makes the old one useless; removing
// a friend ends the shares between the two users, in both directions, and withdraws the
// dashboard layouts sent between them and not used yet.

// Crockford base32: no I, L, O, U (no confusion with 1 and 0 when typed)
const ALPHABET = "0123456789ABCDEFGHJKMNPQRSTVWXYZ";
const CODE_LENGTH = 10;
export const MAX_FRIENDS = 200;
/** Requests sent and not answered yet */
export const MAX_PENDING = 20;

/** 10 random symbols, 50 bits: with the rate limit, guessing a code is not feasible */
export function newFriendCode (): string {
	let code = "";
	for (let i = 0; i < CODE_LENGTH; i++) code += ALPHABET[randomInt(ALPHABET.length)];
	return code;
}

/** As typed or read from the QR code (CTF1:<code>): case, dashes, spaces, O/0 and I/L/1 */
export function normalizeFriendCode (input: string): string {
	return input.trim().toUpperCase().replace(/^CTF1:/, "").replace(/[\s-]/g, "")
		.replace(/O/g, "0").replace(/[IL]/g, "1");
}

const friendCode = z.string().max(40).transform(normalizeFriendCode)
	.pipe(z.string().length(CODE_LENGTH).regex(new RegExp(`^[${ALPHABET}]+$`)));
const userParams = z.strictObject({ id: z.coerce.number().int().positive().max(2 ** 31 - 1) });

export async function areFriends (sql: Sql, userId: number, friendId: number): Promise<boolean> {
	const [row] = await sql`SELECT 1 FROM friendships WHERE user_id = ${userId} AND friend_id = ${friendId}`;
	return row !== undefined;
}

export function registerFriendRoutes (app: FastifyInstance, ctx: Context): void {
	const { sql } = ctx;
	// Codes are secrets: a strict limit against guessing
	const CODE_LIMIT = { rateLimit: { max: ctx.config.AUTH_RATE_LIMIT, timeWindow: "15 minutes" } };

	/** Code of a user, created at the first request; renew = a new one */
	async function codeOf (userId: number, renew = false): Promise<string> {
		for (;;) {
			const [row] = await sql<{ friend_code: string | null }[]>`SELECT friend_code FROM users WHERE id = ${userId}`;
			if (row!.friend_code && !renew) return row!.friend_code;
			try {
				// A concurrent first request may set it first: then it's read again
				const [updated] = await sql<{ friend_code: string }[]>`
					UPDATE users SET friend_code = ${newFriendCode()}
					WHERE id = ${userId} AND (${renew} OR friend_code IS NULL) RETURNING friend_code`;
				if (updated) return updated.friend_code;
			} catch (error) {
				// The same random code of another user: retried with a new one
				if ((error as { code?: string }).code !== "23505") throw error;
			}
		}
	}

	const list = async (userId: number) => ({
		code: await codeOf(userId),
		friends: await sql`
			SELECT u.id, u.name, f.created_at AS "since" FROM friendships f JOIN users u ON u.id = f.friend_id
			WHERE f.user_id = ${userId} AND NOT u.disabled ORDER BY u.name, u.id`,
		incoming: await sql`
			SELECT u.id, u.name, r.created_at AS "since" FROM friend_requests r JOIN users u ON u.id = r.from_id
			WHERE r.to_id = ${userId} AND NOT u.disabled ORDER BY r.created_at DESC`,
		outgoing: await sql`
			SELECT u.id, u.name, r.created_at AS "since" FROM friend_requests r JOIN users u ON u.id = r.to_id
			WHERE r.from_id = ${userId} AND NOT u.disabled ORDER BY r.created_at DESC`
	});

	async function friendCount (userId: number): Promise<number> {
		const [row] = await sql<{ count: number }[]>`SELECT count(*)::int AS count FROM friendships WHERE user_id = ${userId}`;
		return row!.count;
	}

	/** Friendship in both directions, the requests between the two removed */
	async function befriend (a: { id: number; name: string }, b: { id: number; name: string }): Promise<void> {
		if (await friendCount(a.id) >= MAX_FRIENDS || await friendCount(b.id) >= MAX_FRIENDS) {
			throw badRequest(`At most ${MAX_FRIENDS} friends`, "too_many_friends");
		}
		await sql.begin(async tx => {
			await tx`DELETE FROM friend_requests WHERE (from_id = ${a.id} AND to_id = ${b.id}) OR (from_id = ${b.id} AND to_id = ${a.id})`;
			await tx`
				INSERT INTO friendships (user_id, friend_id) VALUES (${a.id}, ${b.id}), (${b.id}, ${a.id})
				ON CONFLICT DO NOTHING`;
		});
		ctx.hub.toUser(b.id, { type: "friends", userId: a.id, name: a.name, added: true });
		ctx.hub.toUser(a.id, { type: "friends", userId: b.id, name: b.name, added: true });
	}

	app.get("/api/friends", async (request) => list(request.auth!.user.id));

	/** New personal code: the old one no longer works (friends stay friends) */
	app.post("/api/friends/code", async (request) => ({ code: await codeOf(request.auth!.user.id, true) }));

	app.post("/api/friends", { config: CODE_LIMIT }, async (request) => {
		const body = parse(z.strictObject({ code: friendCode }), request.body);
		const user = request.auth!.user;
		const [friend] = await sql<{ id: number; name: string }[]>`
			SELECT id, name FROM users WHERE friend_code = ${body.code} AND NOT disabled`;
		if (!friend) throw notFound("No user with this code");
		if (friend.id === user.id) throw badRequest("This is your own code", "friend_self");
		if (await areFriends(sql, user.id, friend.id)) return { id: friend.id, name: friend.name, status: "friends" };

		// The other user asked first: friends at once
		const [crossed] = await sql`SELECT 1 FROM friend_requests WHERE from_id = ${friend.id} AND to_id = ${user.id}`;
		if (crossed) {
			await befriend(user, friend);
			return { id: friend.id, name: friend.name, status: "friends" };
		}
		if (await friendCount(user.id) >= MAX_FRIENDS) throw badRequest(`At most ${MAX_FRIENDS} friends`, "too_many_friends");
		const [pending] = await sql<{ count: number }[]>`SELECT count(*)::int AS count FROM friend_requests WHERE from_id = ${user.id}`;
		const inserted = pending!.count >= MAX_PENDING ? null : await sql`
			INSERT INTO friend_requests (from_id, to_id) VALUES (${user.id}, ${friend.id}) ON CONFLICT DO NOTHING RETURNING 1`;
		if (inserted === null) throw badRequest(`At most ${MAX_PENDING} pending requests`, "too_many_requests");
		// Name only: the code alone doesn't reveal anything else of the user
		if (inserted.length > 0) ctx.hub.toUser(friend.id, { type: "friends", userId: user.id, name: user.name, request: true });
		return { id: friend.id, name: friend.name, status: "requested" };
	});

	app.post("/api/friends/requests/:id/accept", async (request) => {
		const { id: fromId } = parse(userParams, request.params);
		const user = request.auth!.user;
		const [from] = await sql<{ id: number; name: string }[]>`
			SELECT u.id, u.name FROM friend_requests r JOIN users u ON u.id = r.from_id
			WHERE r.from_id = ${fromId} AND r.to_id = ${user.id} AND NOT u.disabled`;
		if (!from) throw notFound("Request not found");
		await befriend(user, from);
		return { id: from.id, name: from.name };
	});

	/** Declines a request received or withdraws one sent; the other user isn't told */
	app.delete("/api/friends/requests/:id", async (request) => {
		const { id: otherId } = parse(userParams, request.params);
		const userId = request.auth!.user.id;
		const removed = await sql`
			DELETE FROM friend_requests WHERE (from_id = ${otherId} AND to_id = ${userId}) OR (from_id = ${userId} AND to_id = ${otherId})`;
		if (removed.count === 0) throw notFound("Request not found");
		return { ok: true };
	});

	/** Ends the friendship and the shares between the two users */
	app.delete("/api/friends/:id", async (request) => {
		const { id: friendId } = parse(userParams, request.params);
		const userId = request.auth!.user.id;
		const shares = await sql.begin(async tx => {
			const removed = await tx`
				DELETE FROM friendships WHERE (user_id = ${userId} AND friend_id = ${friendId}) OR (user_id = ${friendId} AND friend_id = ${userId})`;
			if (removed.count === 0) throw notFound("Friend not found");
			// Viewer rows of each user on the devices owned by the other one
			const ended = await tx<{ device_id: number; user_id: number }[]>`
				DELETE FROM device_users v USING device_users o
				WHERE v.role = 'viewer' AND o.role = 'owner' AND o.device_id = v.device_id
					AND ((v.user_id = ${userId} AND o.user_id = ${friendId}) OR (v.user_id = ${friendId} AND o.user_id = ${userId}))
				RETURNING v.device_id, v.user_id`;
			await tx`
				DELETE FROM dashboard_shares
				WHERE (from_id = ${userId} AND to_id = ${friendId}) OR (from_id = ${friendId} AND to_id = ${userId})`;
			for (const share of ended) {
				await tx`DELETE FROM geofences WHERE device_id = ${share.device_id} AND user_id = ${share.user_id}`;
				await tx`DELETE FROM notification_settings WHERE device_id = ${share.device_id} AND user_id = ${share.user_id}`;
			}
			return ended;
		});
		await ctx.hub.refreshUser(userId);
		await ctx.hub.refreshUser(friendId);
		ctx.hub.toUser(friendId, { type: "friends", userId, added: false });
		ctx.hub.toUser(userId, { type: "friends", userId: friendId, added: false });
		return { ok: true, sharesEnded: shares.length };
	});
}
