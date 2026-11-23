-- Refuels of a vehicle (trackers and vehicles without tracker): litres, amount paid,
-- odometer, full tank or not. Between two full tanks the litres put in give the real
-- consumption; the amount gives the price per litre.
CREATE TABLE refuels (
	id serial PRIMARY KEY,
	device_id integer NOT NULL REFERENCES devices (id) ON DELETE CASCADE,
	day date NOT NULL,
	litres double precision NOT NULL CHECK (litres > 0 AND litres <= 500),
	-- Amount paid in euro, NULL when not entered
	cost double precision CHECK (cost >= 0 AND cost <= 10000),
	odometer_km integer CHECK (odometer_km >= 0 AND odometer_km <= 5000000),
	full_tank boolean NOT NULL DEFAULT true,
	note text NOT NULL DEFAULT '',
	created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX refuels_device ON refuels (device_id, day);

-- Where a value of the costs comes from: entered by the owner, the national average of the
-- week, or computed from the refuels (recomputed at every change of the refuels; a value of
-- the owner on the same day wins)
ALTER TABLE vehicle_rates ADD COLUMN source text NOT NULL DEFAULT 'manual' CHECK (source IN ('manual', 'auto', 'refuel'));
-- Price and consumption of the trips from the refuels
ALTER TABLE devices ADD COLUMN rates_from_refuels boolean NOT NULL DEFAULT true;

