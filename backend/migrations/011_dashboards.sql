-- Dashboards of the users: widgets chosen from the catalog of metrics
-- (src/services/metrics.ts), saved as JSON { version, period, widgets } and validated by
-- the backend. Each dashboard belongs to one user; one of them can be the current one,
-- shown in the analysis of every vehicle instead of the standard one.
CREATE TABLE dashboards (
	id serial PRIMARY KEY,
	user_id integer NOT NULL REFERENCES users (id) ON DELETE CASCADE,
	name text NOT NULL,
	layout jsonb NOT NULL,
	is_current boolean NOT NULL DEFAULT false,
	created_at timestamptz NOT NULL DEFAULT now(),
	updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX dashboards_user ON dashboards (user_id, id);
CREATE UNIQUE INDEX dashboards_current ON dashboards (user_id) WHERE is_current;

-- Layouts sent to friends: a copy of the widgets without the vehicles of the sender (every
-- widget on "all"), until the friend uses it with its own vehicles or declines it. Deleting
-- the dashboard withdraws the layouts not used yet; a new send replaces the old copy.
CREATE TABLE dashboard_shares (
	id serial PRIMARY KEY,
	dashboard_id integer NOT NULL REFERENCES dashboards (id) ON DELETE CASCADE,
	from_id integer NOT NULL REFERENCES users (id) ON DELETE CASCADE,
	to_id integer NOT NULL REFERENCES users (id) ON DELETE CASCADE,
	name text NOT NULL,
	layout jsonb NOT NULL,
	created_at timestamptz NOT NULL DEFAULT now(),
	UNIQUE (dashboard_id, to_id)
);
CREATE INDEX dashboard_shares_to ON dashboard_shares (to_id, id);
