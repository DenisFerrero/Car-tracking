-- Summary of a device per day (local day in TIMEZONE), computed by the job for the past
-- days: statistics over months, health of the car battery, odometer
CREATE TABLE daily_stats (
	device_id integer NOT NULL REFERENCES devices (id) ON DELETE CASCADE,
	day date NOT NULL,
	distance_km double precision NOT NULL,
	-- From the trip log: trips marked business / personal
	business_km double precision NOT NULL,
	personal_km double precision NOT NULL,
	driving_min integer NOT NULL,
	trips integer NOT NULL,
	max_speed integer NOT NULL,
	-- Trackers: median voltage of the car battery parked for at least 2 hours (no surface
	-- charge), lowest voltage of the day
	rest_voltage double precision,
	min_voltage double precision,
	-- Estimated bytes on the SIM, points with alarm events
	traffic_bytes bigint NOT NULL,
	alarms integer NOT NULL,
	PRIMARY KEY (device_id, day)
);

-- Trip log: purpose and note of a trip, by its start (trips are computed from the positions)
CREATE TABLE trip_tags (
	device_id integer NOT NULL REFERENCES devices (id) ON DELETE CASCADE,
	start timestamptz NOT NULL,
	purpose text CHECK (purpose IN ('business', 'personal')),
	note text NOT NULL DEFAULT '',
	PRIMARY KEY (device_id, start)
);

-- Odometer: reading entered by the owner minus the km of that day before the reading;
-- current value = base + km of the days since odometer_day
ALTER TABLE devices ADD COLUMN odometer_base double precision;
ALTER TABLE devices ADD COLUMN odometer_day date;
-- Low resting voltage of the car battery: notified at most once every 14 days
ALTER TABLE devices ADD COLUMN battery_health_alerted_at timestamptz;

-- Deadlines of a car: by date (inspection, insurance, tax) and/or by km (service, tyres);
-- recurring ones move forward when marked done
CREATE TABLE maintenance (
	id serial PRIMARY KEY,
	device_id integer NOT NULL REFERENCES devices (id) ON DELETE CASCADE,
	kind text NOT NULL CHECK (kind IN ('service', 'inspection', 'insurance', 'tax', 'tyres', 'other')),
	title text NOT NULL DEFAULT '',
	due_date date,
	due_km integer,
	every_months integer CHECK (every_months BETWEEN 1 AND 120),
	every_km integer CHECK (every_km BETWEEN 100 AND 200000),
	-- Notified this many days / km before
	remind_days integer NOT NULL DEFAULT 30,
	remind_km integer NOT NULL DEFAULT 1000,
	-- 0 nothing sent, 1 "soon" sent, 2 "due" sent
	notified_stage smallint NOT NULL DEFAULT 0,
	note text NOT NULL DEFAULT '',
	created_at timestamptz NOT NULL DEFAULT now(),
	CHECK (due_date IS NOT NULL OR due_km IS NOT NULL)
);
CREATE INDEX maintenance_device ON maintenance (device_id);

CREATE TABLE maintenance_log (
	id serial PRIMARY KEY,
	device_id integer NOT NULL REFERENCES devices (id) ON DELETE CASCADE,
	kind text NOT NULL,
	title text NOT NULL,
	done_on date NOT NULL,
	km integer,
	note text NOT NULL DEFAULT '',
	created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX maintenance_log_device ON maintenance_log (device_id, done_on DESC);
