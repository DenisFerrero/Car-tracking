-- Summary of the month: a notification at the start of every month with the totals of the
-- month just ended (users who want it), one per user and month
ALTER TABLE users ADD COLUMN monthly_summary boolean NOT NULL DEFAULT true;
CREATE TABLE monthly_summaries (
	user_id integer NOT NULL REFERENCES users (id) ON DELETE CASCADE,
	month date NOT NULL,
	sent_at timestamptz NOT NULL DEFAULT now(),
	PRIMARY KEY (user_id, month)
);
