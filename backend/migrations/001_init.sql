-- Schema of the platform. Time series (positions, traffic) are TimescaleDB hypertables,
-- everything else plain tables. Retention of the time series is set at startup from
-- RETENTION_DAYS (src/main.ts).

CREATE EXTENSION IF NOT EXISTS timescaledb;
CREATE EXTENSION IF NOT EXISTS citext;

-- ---------------------------------------------------------------- users and auth

CREATE TABLE users (
	id serial PRIMARY KEY,
	email citext NOT NULL UNIQUE,
	name text NOT NULL,
	is_admin boolean NOT NULL DEFAULT false,
	-- argon2id; NULL until the invite is accepted
	password_hash text,
	-- TOTP secret encrypted with the master key (AES-256-GCM); the 2FA is mandatory, an
	-- account without TOTP can only complete the enrollment
	totp_secret bytea,
	-- Secret shown during the enrollment, saved in totp_secret after the first valid code
	totp_pending bytea,
	-- Last accepted TOTP step: a code is accepted only once
	totp_last_step bigint NOT NULL DEFAULT 0,
	disabled boolean NOT NULL DEFAULT false,
	-- Language of the app and of the push notifications; NULL until the app detects it
	locale text CHECK (locale IN ('it', 'en')),
	failed_logins integer NOT NULL DEFAULT 0,
	locked_until timestamptz,
	created_at timestamptz NOT NULL DEFAULT now()
);

-- Invite links (new users) and access reset links (user_id set: the user chooses a new
-- password and enrolls the 2FA again)
CREATE TABLE invites (
	-- sha256 of the token sent to the user
	token_hash bytea PRIMARY KEY,
	user_id integer REFERENCES users (id) ON DELETE CASCADE,
	email citext NOT NULL,
	name text NOT NULL,
	is_admin boolean NOT NULL DEFAULT false,
	created_by integer REFERENCES users (id) ON DELETE SET NULL,
	expires_at timestamptz NOT NULL,
	created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE passkeys (
	id text PRIMARY KEY,               -- credential id, base64url
	user_id integer NOT NULL REFERENCES users (id) ON DELETE CASCADE,
	name text NOT NULL,
	public_key bytea NOT NULL,
	counter bigint NOT NULL DEFAULT 0,
	transports text[] NOT NULL DEFAULT '{}',
	backed_up boolean NOT NULL DEFAULT false,
	created_at timestamptz NOT NULL DEFAULT now(),
	last_used_at timestamptz
);
CREATE INDEX passkeys_user ON passkeys (user_id);

CREATE TABLE recovery_codes (
	user_id integer NOT NULL REFERENCES users (id) ON DELETE CASCADE,
	code_hash bytea NOT NULL,
	used_at timestamptz,
	PRIMARY KEY (user_id, code_hash)
);

CREATE TABLE sessions (
	-- sha256 of the token: a database dump doesn't give usable sessions
	token_hash bytea PRIMARY KEY,
	user_id integer NOT NULL REFERENCES users (id) ON DELETE CASCADE,
	-- 'web' (cookie) or 'app' (bearer token in the secure storage of the phone)
	client text NOT NULL CHECK (client IN ('web', 'app')),
	-- 'mfa_pending': password verified, waiting for the TOTP; 'enroll': password verified,
	-- TOTP to configure; 'full': authenticated
	stage text NOT NULL CHECK (stage IN ('mfa_pending', 'enroll', 'full')),
	user_agent text NOT NULL DEFAULT '',
	ip inet,
	created_at timestamptz NOT NULL DEFAULT now(),
	last_seen_at timestamptz NOT NULL DEFAULT now(),
	-- Last strong authentication: sensitive changes (password, passkeys) require a recent one
	authenticated_at timestamptz NOT NULL DEFAULT now(),
	expires_at timestamptz NOT NULL
);
CREATE INDEX sessions_user ON sessions (user_id);

-- WebAuthn challenges, single use, a few minutes
CREATE TABLE webauthn_challenges (
	challenge text PRIMARY KEY,
	user_id integer REFERENCES users (id) ON DELETE CASCADE,
	purpose text NOT NULL CHECK (purpose IN ('register', 'login')),
	expires_at timestamptz NOT NULL
);

CREATE TABLE auth_events (
	id bigserial PRIMARY KEY,
	user_id integer REFERENCES users (id) ON DELETE CASCADE,
	email citext,
	event text NOT NULL,
	ip inet,
	user_agent text NOT NULL DEFAULT '',
	created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX auth_events_user ON auth_events (user_id, created_at DESC);

-- ---------------------------------------------------------------- devices

CREATE TABLE devices (
	id serial PRIMARY KEY,
	imei text NOT NULL UNIQUE CHECK (imei ~ '^[0-9]{15}$'),
	name text NOT NULL DEFAULT '',
	color text NOT NULL DEFAULT '#1E88E5',
	manufacturer text NOT NULL DEFAULT '',
	model text NOT NULL DEFAULT '',
	revision text NOT NULL DEFAULT '',
	firmware text NOT NULL DEFAULT '',
	-- First HELLO received: the wizard waits for it
	registered_at timestamptz,
	last_seen_at timestamptz,
	-- Offline notification already sent for the current silence
	offline_notified boolean NOT NULL DEFAULT false,
	-- Counter of the frames sent to the tracker (ACK and COMMAND share the key and the
	-- direction, so they share the counter too): max(unix seconds, previous + 1)
	downlink_counter bigint NOT NULL DEFAULT 0,
	created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE device_users (
	device_id integer NOT NULL REFERENCES devices (id) ON DELETE CASCADE,
	user_id integer NOT NULL REFERENCES users (id) ON DELETE CASCADE,
	-- owner: the user who added the tracker (commands, settings, history, sharing);
	-- viewer: a share, only the current position and a few non sensitive values
	role text NOT NULL CHECK (role IN ('owner', 'viewer')),
	-- End of a temporary share, NULL = until revoked
	expires_at timestamptz CHECK (role = 'viewer' OR expires_at IS NULL),
	created_by integer REFERENCES users (id) ON DELETE SET NULL,
	created_at timestamptz NOT NULL DEFAULT now(),
	PRIMARY KEY (device_id, user_id)
);
CREATE INDEX device_users_user ON device_users (user_id);
-- One owner per tracker
CREATE UNIQUE INDEX device_users_owner ON device_users (device_id) WHERE role = 'owner';

-- Commands for the trackers. Pending ones are sent when the tracker subscribes to its
-- command topic; a newer command supersedes the older pending ones.
CREATE TABLE commands (
	id bigserial PRIMARY KEY,
	device_id integer NOT NULL REFERENCES devices (id) ON DELETE CASCADE,
	counter bigint NOT NULL,
	-- [{ "id": 1, "seconds": 600 }, ...] as in server/protocol
	payload jsonb NOT NULL,
	created_by integer REFERENCES users (id) ON DELETE SET NULL,
	created_at timestamptz NOT NULL DEFAULT now(),
	sent_at timestamptz,
	result smallint,
	result_at timestamptz,
	superseded boolean NOT NULL DEFAULT false,
	UNIQUE (device_id, counter)
);
CREATE INDEX commands_pending ON commands (device_id) WHERE result IS NULL AND NOT superseded;

-- ---------------------------------------------------------------- time series

CREATE TABLE positions (
	time timestamptz NOT NULL,
	-- No foreign key on the hypertables: every new chunk would add the trigger of the key
	-- to devices, locking it (deadlock with the commands, which lock their device row).
	-- Devices are never deleted; a released tracker loses its rows explicitly.
	device_id integer NOT NULL,
	-- NULL when the tracker never had a fix (only the cell locates it)
	lat double precision,
	lon double precision,
	altitude smallint,
	speed smallint,                   -- km/h
	pressure real,                    -- hPa
	temperature real,                 -- °C
	voltage real,                     -- V, vehicle battery
	satellites smallint,
	signal smallint,                  -- dBm
	events smallint NOT NULL DEFAULT 0,
	status smallint NOT NULL,         -- 0 moving, 1 engine off, 2 heartbeat, 3 alarm
	-- Position of the last fix, the GNSS had no fix at this time
	stale boolean NOT NULL DEFAULT false,
	mcc smallint,
	mnc smallint,
	cell_area integer,
	cell_id bigint,
	PRIMARY KEY (device_id, time)
);
SELECT create_hypertable('positions', 'time', chunk_time_interval => interval '7 days');
ALTER TABLE positions SET (timescaledb.compress, timescaledb.compress_segmentby = 'device_id', timescaledb.compress_orderby = 'time');
SELECT add_compression_policy('positions', interval '14 days');

-- Bytes received and sent per frame, for the data usage charts (200 MB SIM)
CREATE TABLE traffic (
	time timestamptz NOT NULL,
	-- No foreign key on the hypertables: every new chunk would add the trigger of the key
	-- to devices, locking it (deadlock with the commands, which lock their device row).
	-- Devices are never deleted; a released tracker loses its rows explicitly.
	device_id integer NOT NULL,
	-- frame type of the protocol, 0 = MQTT connection
	frame_type smallint NOT NULL,
	uplink boolean NOT NULL,
	bytes integer NOT NULL
);
SELECT create_hypertable('traffic', 'time', chunk_time_interval => interval '30 days');
CREATE INDEX traffic_device ON traffic (device_id, time DESC);
ALTER TABLE traffic SET (timescaledb.compress, timescaledb.compress_segmentby = 'device_id');
SELECT add_compression_policy('traffic', interval '30 days');

-- ---------------------------------------------------------------- notifications

CREATE TABLE notifications (
	id bigserial PRIMARY KEY,
	user_id integer NOT NULL REFERENCES users (id) ON DELETE CASCADE,
	device_id integer REFERENCES devices (id) ON DELETE CASCADE,
	-- motion, tilt, power_lost, low_battery, offline, online, geofence_enter, geofence_exit
	kind text NOT NULL,
	-- Values of the text, localized by the app: { device, area, time }
	data jsonb NOT NULL DEFAULT '{}',
	lat double precision,
	lon double precision,
	created_at timestamptz NOT NULL DEFAULT now(),
	read_at timestamptz
);
CREATE INDEX notifications_user ON notifications (user_id, created_at DESC);

-- Arrival areas: a user is notified when a device enters (or leaves) a circle, e.g.
-- "almost home". Owners and viewers can create them on the devices they see.
CREATE TABLE geofences (
	id serial PRIMARY KEY,
	user_id integer NOT NULL REFERENCES users (id) ON DELETE CASCADE,
	device_id integer NOT NULL REFERENCES devices (id) ON DELETE CASCADE,
	name text NOT NULL,
	lat double precision NOT NULL CHECK (lat BETWEEN -90 AND 90),
	lon double precision NOT NULL CHECK (lon BETWEEN -180 AND 180),
	radius integer NOT NULL CHECK (radius BETWEEN 50 AND 50000),   -- meters
	notify_enter boolean NOT NULL DEFAULT true,
	notify_exit boolean NOT NULL DEFAULT false,
	-- Side of the border at the last position evaluated, NULL until the first one
	inside boolean,
	-- Time of that position: older points (offline queue sent later) are skipped
	checked_at timestamptz,
	created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX geofences_device ON geofences (device_id);
CREATE INDEX geofences_user ON geofences (user_id, device_id);

-- Kinds of notification each user wants, per device; no row = every kind
CREATE TABLE notification_settings (
	user_id integer NOT NULL REFERENCES users (id) ON DELETE CASCADE,
	device_id integer NOT NULL REFERENCES devices (id) ON DELETE CASCADE,
	kinds text[] NOT NULL,
	PRIMARY KEY (user_id, device_id)
);

-- Firebase Cloud Messaging tokens of the phones
CREATE TABLE push_tokens (
	token text PRIMARY KEY,
	user_id integer NOT NULL REFERENCES users (id) ON DELETE CASCADE,
	-- Removed with the session that registered it
	session_hash bytea REFERENCES sessions (token_hash) ON DELETE CASCADE,
	created_at timestamptz NOT NULL DEFAULT now()
);

-- Position of the serving cells, cache of CELL_GEOLOCATION_URL
CREATE TABLE cells (
	mcc smallint NOT NULL,
	mnc smallint NOT NULL,
	area integer NOT NULL,
	cell_id bigint NOT NULL,
	-- NULL when the service doesn't know the cell
	lat double precision,
	lon double precision,
	accuracy integer,
	fetched_at timestamptz NOT NULL DEFAULT now(),
	PRIMARY KEY (mcc, mnc, area, cell_id)
);
