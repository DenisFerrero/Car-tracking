-- Parking of a vehicle: where and since when, the end of the paid time when there is one
-- (ticket, disc; none when it's paid by the minute), a reminder some minutes before. Ends
-- when the vehicle leaves or by hand; one at a time per vehicle.
CREATE TABLE parkings (
	id serial PRIMARY KEY,
	device_id integer NOT NULL REFERENCES devices (id) ON DELETE CASCADE,
	user_id integer NOT NULL REFERENCES users (id) ON DELETE CASCADE,
	lat double precision CHECK (lat BETWEEN -90 AND 90),
	lon double precision CHECK (lon BETWEEN -180 AND 180),
	started_at timestamptz NOT NULL DEFAULT now(),
	expires_at timestamptz,
	remind_minutes integer NOT NULL DEFAULT 10 CHECK (remind_minutes BETWEEN 0 AND 120),
	note text NOT NULL DEFAULT '',
	reminded_at timestamptz,
	expired_notified_at timestamptz,
	ended_at timestamptz
);
CREATE UNIQUE INDEX parkings_active ON parkings (device_id) WHERE ended_at IS NULL;
CREATE INDEX parkings_due ON parkings (expires_at) WHERE ended_at IS NULL AND expires_at IS NOT NULL;

-- Proposal of a parking when the ignition goes off (trackers): a notification to the owner
ALTER TABLE devices ADD COLUMN parking_prompt boolean NOT NULL DEFAULT false;
