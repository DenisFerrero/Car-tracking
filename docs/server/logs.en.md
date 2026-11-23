# Platform log

The backend keeps a **platform log** to analyse afterwards the errors to fix and what is slow
and worth optimising. It is not an access log nor a log of the activity of the users: it
holds only errors and slowness, **without personal data**, and is kept **30 days**
(`LOG_RETENTION_DAYS`).

## What it holds

| Kind | When | Details |
| :--- | :--- | :--- |
| **Errors** | every request ended with an error 500; every error of the services (periodic jobs, tracker gateway, push notifications, fuel prices, releases…) | route (`GET /api/devices/:id`), type, code and message of the error, stack |
| **Warnings** | warnings of the services: external services unreachable, push not delivered, trackers failing authentication, releases rejected… | message, service, useful fields (e.g. IMEI of the tracker, error code) |
| **Slow requests** | HTTP requests over `LOG_SLOW_REQUEST_MS` (default 1000 ms) | route, method, status, mean and maximum duration |
| **Slow queries** | queries with a mean duration over `LOG_SLOW_QUERY_MS` (default 100 ms) or a maximum ten times as much, collected every hour | normalised text of the query (no values), runs, mean, maximum and total duration, rows |

Equal entries of a few seconds (same kind, service, message and error) become **one row with
the count**: a burst of errors doesn't fill the database. Beyond 200 distinct entries every
10 seconds the others are only counted ("Log entries dropped").

**Never recorded**: request bodies, query strings, URLs with their values (only the route
pattern), IP addresses, emails, tokens, users. WebSocket connections (long by nature) and
paths without a route don't count as slow requests.

The same errors and warnings stay in the output of the container too (`docker compose logs
backend`, level `LOG_LEVEL`), which is neither kept nor grouped.

## Reading it in the app

*Account › Administration › Platform log* (administrators only): errors, warnings, slow
requests and slow queries of the last 24 hours, 7 or 30 days, grouped by service and message,
the most frequent first. For each group: how many times, first and last time, mean and
maximum duration; opened, the details of the latest occurrence (with the stack of the errors)
and **Copy** to paste them into a report.

## Alerts of new errors

Administrators get a **notification** (push and in the app) when the log records an error not
seen in the last 30 days (same service and message): "New error in the log · backup: Disk
full". Several new errors in the same write batch (a few seconds) give one notification; at
most **6 an hour**, the others stay only in the log. Warnings and errors already seen don't
notify. Tapping the notification opens the log; each administrator turns it off in *Account ›
Alerts of new errors*.

## Slow queries: pg_stat_statements

Slow queries come from `pg_stat_statements`, which the database must load at startup. The
`docker-compose.yml` already does it:

```yaml
timescaledb:
  command: postgres -c shared_preload_libraries=timescaledb,pg_stat_statements
```

On an existing installation update the `docker-compose.yml` and restart the database
(`docker compose up -d`): the backend creates the extension by itself. Without the library
slow queries aren't collected (the app says so) and the rest of the log works. Every hour the
backend reads the statistics of the queries of its own database and resets them.

## Settings

| Variable | Default | |
| :--- | :--- | :--- |
| `LOG_RETENTION_DAYS` | 30 | Days kept (1-365), TimescaleDB retention policy |
| `LOG_SLOW_REQUEST_MS` | 1000 | Threshold of a slow request |
| `LOG_SLOW_QUERY_MS` | 100 | Threshold of the mean duration of a slow query |

## Analysis with SQL

The log is the table `platform_log` (hypertable): `time`, `kind` (`error`, `warning`,
`slow_request`, `slow_query`), `source`, `message`, `count`, `duration_ms` (the longest one),
`details` (JSON). Some examples (`docker compose exec timescaledb psql -U car_tracking`):

```sql
-- Most frequent errors of the last 7 days
SELECT source, message, details ->> 'errorMessage' AS error, sum(count) AS times, max(time) AS last
FROM platform_log WHERE kind = 'error' AND time > now() - interval '7 days'
GROUP BY 1, 2, 3 ORDER BY times DESC LIMIT 20;

-- Slow routes: how many times, mean and maximum duration
SELECT message, sum(count) AS times,
	round(sum((details ->> 'avgMs')::float * count) / sum(count)) AS avg_ms, max(duration_ms) AS max_ms
FROM platform_log WHERE kind = 'slow_request' GROUP BY message ORDER BY times DESC;

-- Slow queries by total time
SELECT message, sum((details ->> 'calls')::int) AS calls, max((details ->> 'maxMs')::float) AS max_ms,
	sum((details ->> 'totalMs')::float) AS total_ms
FROM platform_log WHERE kind = 'slow_query' GROUP BY message ORDER BY total_ms DESC LIMIT 20;

-- Errors per day
SELECT time_bucket('1 day', time) AS day, sum(count) FROM platform_log WHERE kind = 'error' GROUP BY 1 ORDER BY 1;
```

The log is part of the database and so of the [backups](backup.md).
