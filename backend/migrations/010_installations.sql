-- Trackers installed in the vehicles of the users. The row of a vehicle with a tracker
-- (kind 'tracker') holds the hardware of the tracker (IMEI, firmware, downlink counter):
-- moving the tracker moves these columns to another vehicle, which becomes kind
-- 'tracker', while the previous one becomes kind 'vehicle' and keeps its history
-- (positions, km, deadlines, costs, areas, shares).
CREATE TABLE tracker_installations (
	id serial PRIMARY KEY,
	imei text NOT NULL,
	vehicle_id integer NOT NULL REFERENCES devices (id) ON DELETE CASCADE,
	installed_at timestamptz NOT NULL DEFAULT now(),
	removed_at timestamptz
);
CREATE INDEX tracker_installations_vehicle ON tracker_installations (vehicle_id, installed_at DESC);
CREATE UNIQUE INDEX tracker_installations_current ON tracker_installations (imei) WHERE removed_at IS NULL;

-- Trackers already paired: installed since the pairing
INSERT INTO tracker_installations (imei, vehicle_id, installed_at)
SELECT d.imei, d.id, du.created_at FROM devices d JOIN device_users du ON du.device_id = d.id AND du.role = 'owner'
WHERE d.kind = 'tracker';

-- Vehicles kept for their history (e.g. sold car): hidden from the map
ALTER TABLE devices ADD COLUMN archived_at timestamptz;
