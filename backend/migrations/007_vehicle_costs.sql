-- Costs of the trips, entered by the owner: model of the vehicle, fuel (for the national
-- average price), unit preferred for the consumption (litres per 100 km or km per litre)
ALTER TABLE devices ADD COLUMN vehicle_model text NOT NULL DEFAULT '';
ALTER TABLE devices ADD COLUMN fuel_unit text NOT NULL DEFAULT 'l_per_100km' CHECK (fuel_unit IN ('l_per_100km', 'km_per_l'));
ALTER TABLE devices ADD COLUMN fuel_type text CHECK (fuel_type IN ('petrol', 'diesel', 'lpg'));
-- The weekly national average price is added to the history of the fuel price
ALTER TABLE devices ADD COLUMN fuel_price_auto boolean NOT NULL DEFAULT false;

-- Values that change over time: price of the fuel per litre, consumption (always in
-- l/100 km) and wear per km (tyres, maintenance, depreciation: e.g. the ACI tables).
-- A trip uses the values valid on its day (local day in TIMEZONE); trips before the
-- first value use the first one
CREATE TABLE vehicle_rates (
	device_id integer NOT NULL REFERENCES devices (id) ON DELETE CASCADE,
	kind text NOT NULL CHECK (kind IN ('price', 'consumption', 'wear')),
	valid_from date NOT NULL,
	value double precision NOT NULL CHECK (value >= 0 AND value <= 100),
	PRIMARY KEY (device_id, kind, valid_from)
);

-- National average prices per litre, weekly survey of the Ministry (MASE), Mondays
CREATE TABLE fuel_averages (
	fuel text NOT NULL,
	week date NOT NULL,
	price double precision NOT NULL,
	PRIMARY KEY (fuel, week)
);
