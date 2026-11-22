-- Friend requests, state of the phones, firmware updates over the air.

-- ---------------------------------------------------------------- friend requests

-- The code of a user makes a request: the friendship starts only when the other user
-- accepts it (two requests between the same users are an immediate friendship)
CREATE TABLE friend_requests (
	from_id integer NOT NULL REFERENCES users (id) ON DELETE CASCADE,
	to_id integer NOT NULL REFERENCES users (id) ON DELETE CASCADE,
	created_at timestamptz NOT NULL DEFAULT now(),
	PRIMARY KEY (from_id, to_id),
	CHECK (from_id <> to_id)
);
CREATE INDEX friend_requests_to ON friend_requests (to_id);

-- ---------------------------------------------------------------- phones

-- Last battery level (%) sent by the phone, and the pause chosen from its notification
ALTER TABLE devices ADD COLUMN battery smallint CHECK (battery BETWEEN 0 AND 100);
ALTER TABLE devices ADD COLUMN paused_until timestamptz;

-- ---------------------------------------------------------------- firmware

-- Images uploaded by the administrator (npm run firmware), installed by the owners on
-- their trackers: the server offers the image in a frame authenticated with the key of
-- the tracker (size + SHA-256), the tracker downloads it on the same connection and
-- installs it only if the SHA-256 matches. variant = build of the firmware (board and
-- connection mode), reported by the tracker after the "+" of its version (2.3.0+default)
CREATE TABLE firmware_images (
	id serial PRIMARY KEY,
	version text NOT NULL,
	variant text NOT NULL,
	size integer NOT NULL,
	sha256 bytea NOT NULL,
	data bytea NOT NULL,
	notes text NOT NULL DEFAULT '',
	created_at timestamptz NOT NULL DEFAULT now(),
	UNIQUE (version, variant)
);

-- Update requested for a tracker: done when the HELLO reports the new version
CREATE TABLE firmware_updates (
	device_id integer PRIMARY KEY REFERENCES devices (id) ON DELETE CASCADE,
	firmware_id integer NOT NULL REFERENCES firmware_images (id) ON DELETE CASCADE,
	requested_by integer REFERENCES users (id) ON DELETE SET NULL,
	requested_at timestamptz NOT NULL DEFAULT now(),
	-- Bytes sent so far (the download resumes from here after a lost connection)
	sent integer NOT NULL DEFAULT 0,
	-- FW_RESULT of the tracker: installed (rebooting) or the reason of the failure
	status text,
	finished_at timestamptz
);
