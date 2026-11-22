-- Phones as devices and friends.

-- ---------------------------------------------------------------- phones

-- A phone shares its own position with the app, without a tracker: no IMEI, no commands,
-- no alarms. Its positions go to the same hypertable, with the accuracy of the fix.
ALTER TABLE devices ADD COLUMN kind text NOT NULL DEFAULT 'tracker' CHECK (kind IN ('tracker', 'phone'));
ALTER TABLE devices ALTER COLUMN imei DROP NOT NULL;
ALTER TABLE devices ADD CONSTRAINT devices_identity CHECK ((kind = 'tracker') = (imei IS NOT NULL));

-- Radius of the fix in meters (phones; NULL for the trackers)
ALTER TABLE positions ADD COLUMN accuracy integer;

-- ---------------------------------------------------------------- friends

-- Users don't see each other: they become friends with the code of one of them (typed or
-- read from its QR code), and share their devices only with friends. NULL until the user
-- opens the friends page; a new code makes the old one useless.
ALTER TABLE users ADD COLUMN friend_code text UNIQUE;

-- Both directions are stored: (a, b) and (b, a)
CREATE TABLE friendships (
	user_id integer NOT NULL REFERENCES users (id) ON DELETE CASCADE,
	friend_id integer NOT NULL REFERENCES users (id) ON DELETE CASCADE,
	created_at timestamptz NOT NULL DEFAULT now(),
	PRIMARY KEY (user_id, friend_id),
	CHECK (user_id <> friend_id)
);

-- The shares that already exist make their users friends
INSERT INTO friendships (user_id, friend_id)
SELECT DISTINCT o.user_id, v.user_id FROM device_users o
JOIN device_users v ON v.device_id = o.device_id AND v.role = 'viewer'
WHERE o.role = 'owner'
ON CONFLICT DO NOTHING;
INSERT INTO friendships (user_id, friend_id)
SELECT friend_id, user_id FROM friendships
ON CONFLICT DO NOTHING;
