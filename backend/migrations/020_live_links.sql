-- Temporary links to the live position of a device for who has no account ("I'm on my way"):
-- 1-24 hours, revocable, only the latest position (no history, no data of the tracker).
-- The token is stored as its hash.
CREATE TABLE live_links (
	id serial PRIMARY KEY,
	device_id integer NOT NULL REFERENCES devices (id) ON DELETE CASCADE,
	user_id integer NOT NULL REFERENCES users (id) ON DELETE CASCADE,
	token_hash bytea NOT NULL UNIQUE,
	label text NOT NULL DEFAULT '',
	expires_at timestamptz NOT NULL,
	revoked_at timestamptz,
	created_at timestamptz NOT NULL DEFAULT now(),
	last_viewed_at timestamptz
);
CREATE INDEX live_links_device ON live_links (device_id);
