-- Electric and hybrid vehicles: the quantity of a refuel is in kWh for an electric one (a
-- charge, at home or at a public station), its consumption in kWh/100 km and its price per
-- kWh. A hybrid without plug runs on petrol.
-- additive: widens the fuel types, every value stored stays valid
ALTER TABLE devices DROP CONSTRAINT devices_fuel_type_check;
-- additive: same values as before plus electric and hybrid
ALTER TABLE devices ADD CONSTRAINT devices_fuel_type_check CHECK (fuel_type IN ('petrol', 'diesel', 'lpg', 'electric', 'hybrid'));
ALTER TABLE refuels ADD COLUMN place text CHECK (place IN ('home', 'public'));

-- Mileage allowance for the business km (€/km, e.g. from the ACI tables), over time like
-- the other values of the costs
-- additive: widens the kinds, every value stored stays valid
ALTER TABLE vehicle_rates DROP CONSTRAINT vehicle_rates_kind_check;
-- additive: same kinds as before plus reimbursement
ALTER TABLE vehicle_rates ADD CONSTRAINT vehicle_rates_kind_check CHECK (kind IN ('price', 'consumption', 'wear', 'reimbursement'));
