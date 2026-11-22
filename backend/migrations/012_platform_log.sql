-- Log of the platform for the analysis afterwards: errors and warnings of the backend,
-- slow HTTP requests (by route pattern), slow queries (from pg_stat_statements). Equal
-- entries of a few seconds are one row with their count; duration_ms = the longest one.
-- Kept LOG_RETENTION_DAYS days (retention policy set at startup). No personal data.
CREATE TABLE platform_log (
	time timestamptz NOT NULL DEFAULT now(),
	kind text NOT NULL CHECK (kind IN ('error', 'warning', 'slow_request', 'slow_query')),
	source text NOT NULL,
	message text NOT NULL,
	count integer NOT NULL DEFAULT 1,
	duration_ms double precision,
	details jsonb NOT NULL DEFAULT '{}'
);
SELECT create_hypertable('platform_log', 'time', chunk_time_interval => interval '1 day');
CREATE INDEX platform_log_kind ON platform_log (kind, time DESC);
