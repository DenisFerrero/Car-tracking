-- Extra data of the trackers: a JSON object read from another board of the vehicle
-- (e.g. on a serial line), stored as it comes and shown to the owner, no processing
CREATE TABLE device_extra (
	time timestamptz NOT NULL,
	device_id integer NOT NULL REFERENCES devices (id) ON DELETE CASCADE,
	data jsonb NOT NULL,
	PRIMARY KEY (device_id, time)
);
SELECT create_hypertable('device_extra', 'time', chunk_time_interval => interval '30 days');

-- Firmware images downloaded from the releases of the repository (GITHUB_REPO):
-- the release they come from
ALTER TABLE firmware_images ADD COLUMN release_url text NOT NULL DEFAULT '';

-- Automatic updates: the tracker asks once a day (only builds with AUTO_UPDATE 1) and
-- installs the newest image of its variant if the owner allows it
ALTER TABLE devices ADD COLUMN auto_update boolean NOT NULL DEFAULT true;
ALTER TABLE devices ADD COLUMN update_checked_at timestamptz;

-- Latest release of the Android app on GitHub, shown by the app to offer the update
CREATE TABLE app_release (
	id boolean PRIMARY KEY DEFAULT true CHECK (id),
	version text NOT NULL,
	url text NOT NULL,
	apk_url text NOT NULL,
	published_at timestamptz NOT NULL,
	checked_at timestamptz NOT NULL DEFAULT now()
);

-- Update started by the tracker (UPDATE_CHECK), not by the owner
ALTER TABLE firmware_updates ADD COLUMN automatic boolean NOT NULL DEFAULT false;
