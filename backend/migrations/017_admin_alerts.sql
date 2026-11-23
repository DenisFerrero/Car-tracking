-- Administrators: a push notification when the platform log gets an error never seen in
-- the last 30 days (turned off per administrator)
ALTER TABLE users ADD COLUMN admin_alerts boolean NOT NULL DEFAULT true;
