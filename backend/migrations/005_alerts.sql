-- Arrival areas active only in some hours of some days, in TIMEZONE:
-- { "days": [1..7] (Monday = 1), "from": "HH:MM", "to": "HH:MM" }, from > to across
-- midnight, from = to the whole day; NULL = always
ALTER TABLE geofences ADD COLUMN schedule jsonb;

-- Alerts chosen by each user for each device they see:
-- - low battery of a shared phone (viewers): threshold in %, NULL = off; notified once
--   per discharge (again after a charge 10 points above the threshold)
-- - long stop: hours standing still outside the areas of the user, NULL = off; the start
--   of the stop already notified (one notification per stop)
ALTER TABLE device_users ADD COLUMN battery_alert integer DEFAULT 20 CHECK (battery_alert BETWEEN 5 AND 50);
ALTER TABLE device_users ADD COLUMN battery_alerted boolean NOT NULL DEFAULT false;
ALTER TABLE device_users ADD COLUMN stop_alert_hours integer CHECK (stop_alert_hours BETWEEN 1 AND 72);
ALTER TABLE device_users ADD COLUMN stop_alerted_at timestamptz;
