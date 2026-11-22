-- Vehicles without a tracker: the car of a user, fed by the phone of its owner while
-- driving (sharing "from the vehicle"). Trips, costs, odometer, deadlines and areas work
-- like on a tracker; no commands, alarms, modem or firmware.
ALTER TABLE devices DROP CONSTRAINT devices_kind_check;
ALTER TABLE devices ADD CONSTRAINT devices_kind_check CHECK (kind IN ('tracker', 'phone', 'vehicle'));
