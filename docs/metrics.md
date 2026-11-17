# Prometheus metrics

Gunky serves Prometheus metrics at `GET /metrics` in the [text exposition format](https://prometheus.io/docs/instrumenting/exposition_formats/).

## Enabling and securing it

The endpoint is off by default. Set a long random token to turn it on:

```bash
# .env (or the web container's environment)
GUNKY_METRICS_TOKEN=$(openssl rand -hex 32)
```

- With no `GUNKY_METRICS_TOKEN`, `/metrics` answers **404**.
- Requests must send `Authorization: Bearer <token>`. A missing or wrong token gets **401**. The token is not accepted as a query parameter, so it doesn't end up in access logs.
- Responses are `Cache-Control: no-store` and never set a session cookie.

Check it by hand:

```bash
curl -H "Authorization: Bearer $GUNKY_METRICS_TOKEN" https://gunky.example.org/metrics
```

### Prometheus scrape config

```yaml
scrape_configs:
  - job_name: gunky
    scheme: https
    metrics_path: /metrics
    scrape_interval: 60s
    authorization:
      type: Bearer
      credentials_file: /etc/prometheus/secrets/gunky_metrics_token
    static_configs:
      - targets: [ "gunky.example.org" ]
```

Every scrape runs a few dozen small database queries and reads Sidekiq's Redis keys. A 30–60 second interval is plenty.

## How it's collected

Metrics are computed on each scrape. Nothing is held in web-process memory, so the numbers are the same whichever process answers.

- **Database:** item, vote, user, activity-log, and storage numbers come straight from PostgreSQL.
- **Sidekiq and Redis:** queue, server, retry, dead, and cron numbers come from Sidekiq's own API.
- **Per-job execution stats:** `JobMetrics::ServerMiddleware` runs in every Sidekiq worker and records each job attempt's class, queue, outcome, exception class, and duration in one Redis hash (`gunky:metrics:jobs`). The counters live in Redis because Sidekiq runs in a different container from the web server. They are per *attempt*: a job that fails twice and then succeeds counts two failures and one success. A job interrupted by a Sidekiq shutdown is re-queued, so it isn't counted. Clear the counters with `bin/rails runner 'JobMetrics.reset!'`; Prometheus treats that like a counter reset.

Each data source is collected separately. If Redis is down you still get the database metrics, and `gunky_metrics_collector_up{collector="sidekiq"}` drops to 0.

## Metric reference

Every metric starts with `gunky_`. "Window" labels are `24h`, `7d`, and `30d`.

### Scrape health

| Metric | Type | Labels | Meaning |
|---|---|---|---|
| `gunky_up` | gauge | | Always 1 when the web process answers |
| `gunky_build_info` | gauge | `version`, `ruby_version`, `rails_version`, `sidekiq_version`, `environment` | Always 1; carries version info |
| `gunky_time_seconds` | gauge | | Web server wall clock, for checking clock skew |
| `gunky_metrics_collector_up` | gauge | `collector` | 1 if that collector succeeded on this scrape, 0 if it raised |
| `gunky_metrics_collector_duration_seconds` | gauge | `collector` | Time spent in each collector |
| `gunky_metrics_scrape_duration_seconds` | gauge | | Time to build the whole response |

Collectors: `app`, `items`, `users`, `activity_log`, `settings`, `storage`, `database`, `web`, `sidekiq`, `jobs`, `redis`.

### Items and votes

| Metric | Type | Labels | Meaning |
|---|---|---|---|
| `gunky_items` | gauge | `disposition`, `lost_found_state` | Items by Gunky disposition (`pending`, `mine`, `foster`, `kill`, `cancelled`) and Lost+Found state |
| `gunky_item_outcomes` | gauge | `outcome` | Resolved giveaway outcomes, the same numbers as the Winners page (`new_homes`, `picked_up`, `awaiting_pickup`, `kept_for_space`, `trashed`, `owners_found`, `cancelled`, `total`) |
| `gunky_items_created` | gauge | `window` | Items created within the window |
| `gunky_item_last_created_timestamp_seconds` | gauge | | When the newest item was created |
| `gunky_items_with_photo` | gauge | | Items with a photo |
| `gunky_items_with_ai_description` | gauge | | Items with an AI description |
| `gunky_items_posted_to_slack` | gauge | | Items with a Gunky poll in Slack |
| `gunky_items_lost_found_posted_to_slack` | gauge | | Items with a Lost+Found post in Slack |
| `gunky_items_expiration_overdue` | gauge | | Pending items whose expiration date has passed. If this is above 0 after 6:00, `ExpireItemsJob` isn't running |
| `gunky_items_killed_not_disposed` | gauge | | Items voted to trash but not yet marked disposed |
| `gunky_items_awaiting_pickup` | gauge | | Items with at least one winner who hasn't picked up |
| `gunky_active_items_by_location` | gauge | `location` | Pending Gunky items plus active Lost+Found items, by location. Names not in Settings → Locations are grouped as `other`; a blank location is `none` |
| `gunky_locations` | gauge | | Configured locations |
| `gunky_lost_found_to_move` | gauge | | Promoted items still on the Lost+Found shelf |
| `gunky_lost_found_hold_elapsed` | gauge | | Unclaimed items past their hold date, waiting for promotion |
| `gunky_lost_found_pickup_overdue` | gauge | | Claimed items past their pickup deadline |
| `gunky_votes` | gauge | `choice` | Votes by choice (`mine`, `foster`, `kill`) |
| `gunky_votes_awaiting_pickup` | gauge | | Winning votes not yet picked up |
| `gunky_votes_cast` | gauge | `window` | Votes cast within the window |

### Users

Gunky has no accounts. A "user" is a Slack member who voted or claimed a Lost+Found item.

| Metric | Type | Labels | Meaning |
|---|---|---|---|
| `gunky_users` | gauge | `role` | Distinct users: `voter`, `winner`, `lost_found_claimant`, and `all` (voted or claimed) |
| `gunky_active_users` | gauge | `window` | Distinct users who voted or claimed within the window |
| `gunky_slack_member_cache_entries` | gauge | | Slack members in the local name cache |
| `gunky_slack_member_cache_oldest_timestamp_seconds` | gauge | | When the stalest cache entry was refreshed |

### Activity log (uploads, Slack API, AI)

| Metric | Type | Labels | Meaning |
|---|---|---|---|
| `gunky_activity_log_entries_total` | counter | `category`, `action`, `succeeded` | Activity log entries. Failed Slack calls show up as `action="<call>_failed"`, `succeeded="false"` |
| `gunky_activity_log_last_failure_timestamp_seconds` | gauge | `category` | When each category last failed |
| `gunky_activity_log_last_success_timestamp_seconds` | gauge | `category` | When each category last succeeded |

### Configuration

| Metric | Type | Labels | Meaning |
|---|---|---|---|
| `gunky_feature_enabled` | gauge | `feature` | 1 if configured: `slack`, `slack_interactions`, `ai_agent`, `receipt_printer`, `duplicate_hints`, `admin_auth`, `sentry` |
| `gunky_lost_found_hold_days` | gauge | | Lost+Found hold period |
| `gunky_lost_found_pickup_days` | gauge | | Lost+Found pickup window |

### Background jobs

Recorded by the Sidekiq middleware.

| Metric | Type | Labels | Meaning |
|---|---|---|---|
| `gunky_job_executions_total` | counter | `job_class`, `queue`, `status` | Finished job attempts (`status` is `success` or `failure`) |
| `gunky_job_failures_total` | counter | `job_class`, `error_class` | Failed attempts by exception class |
| `gunky_job_duration_seconds` | histogram | `job_class` | Attempt duration. Buckets: 0.05 s to 300 s |
| `gunky_job_last_success_timestamp_seconds` | gauge | `job_class` | When each job class last succeeded |
| `gunky_job_last_failure_timestamp_seconds` | gauge | `job_class` | When each job class last failed |
| `gunky_cron_job_enabled` | gauge | `job`, `job_class` | Whether each scheduled job is enabled |
| `gunky_cron_job_last_enqueue_timestamp_seconds` | gauge | `job`, `job_class` | When each scheduled job was last enqueued |

### Sidekiq servers and queues

| Metric | Type | Labels | Meaning |
|---|---|---|---|
| `gunky_sidekiq_jobs_processed_total` | counter | | Sidekiq's lifetime processed count |
| `gunky_sidekiq_jobs_failed_total` | counter | | Sidekiq's lifetime failed-attempt count |
| `gunky_sidekiq_jobs` | gauge | `set` | Jobs `enqueued`, `scheduled`, waiting to `retry`, `dead`, and `busy` (running now) |
| `gunky_sidekiq_queue_size` | gauge | `queue` | Jobs waiting in each queue |
| `gunky_sidekiq_queue_latency_seconds` | gauge | `queue` | Age of the oldest waiting job |
| `gunky_sidekiq_set_jobs_by_class` | gauge | `set`, `job_class`, `error_class` | Retry and dead set contents, by job and error. Counts stop at 5,000 jobs per set |
| `gunky_sidekiq_processes` | gauge | | Sidekiq servers with a recent heartbeat |
| `gunky_sidekiq_process_concurrency` | gauge | `hostname`, `pid`, `tag`, `queues` | Worker threads per server |
| `gunky_sidekiq_process_busy` | gauge | same | Busy threads per server |
| `gunky_sidekiq_process_resident_memory_bytes` | gauge | same | Memory per server |
| `gunky_sidekiq_process_last_heartbeat_timestamp_seconds` | gauge | same | Last heartbeat per server |
| `gunky_sidekiq_process_start_time_seconds` | gauge | same | Start time per server |
| `gunky_sidekiq_process_quiet` | gauge | same | 1 while a server is quiet (shutting down) |

### Web process, database, storage, Redis

Puma runs in single mode, so the process answering the scrape is the whole web server.

| Metric | Type | Labels | Meaning |
|---|---|---|---|
| `gunky_puma_threads` | gauge | `state` | Puma thread pool: `running`, `max`, `capacity` (free), `busy` |
| `gunky_puma_backlog` | gauge | | Requests waiting for a thread |
| `gunky_puma_requests_total` | counter | | Requests handled since boot |
| `gunky_web_process_start_time_seconds` | gauge | | When the web process booted |
| `gunky_web_process_resident_memory_bytes` | gauge | | Web process memory (Linux only) |
| `gunky_ruby_gc_runs_total` | counter | `kind` | Ruby GC runs (`minor`, `major`) |
| `gunky_ruby_heap_live_slots` | gauge | | Live Ruby heap slots |
| `gunky_database_size_bytes` | gauge | | PostgreSQL database size |
| `gunky_database_table_rows` | gauge | `table` | Rows in the main tables |
| `gunky_database_pool` | gauge | `state` | ActiveRecord connection pool: `size`, `connections`, `busy`, `idle`, `waiting`, `dead` |
| `gunky_active_storage_blobs` | gauge | | Stored files (photos and variants) |
| `gunky_active_storage_bytes` | gauge | | Total bytes stored |
| `gunky_redis_info` | gauge | `version` | Always 1; carries the Redis version |
| `gunky_redis_used_memory_bytes` | gauge | | Redis memory use |
| `gunky_redis_connected_clients` | gauge | | Redis client connections |
| `gunky_redis_uptime_seconds` | gauge | | Redis uptime |

## Example alerts

```yaml
groups:
  - name: gunky
    rules:
      - alert: GunkyMetricsCollectorDown
        expr: gunky_metrics_collector_up == 0
        for: 10m
      - alert: GunkyNoSidekiq
        expr: gunky_sidekiq_processes == 0
        for: 5m
      - alert: GunkyQueueBackedUp
        expr: gunky_sidekiq_queue_latency_seconds > 300
        for: 10m
      - alert: GunkyJobsFailing
        expr: sum by (job_class) (increase(gunky_job_executions_total{status="failure"}[1h])) > 3
      - alert: GunkyExpireItemsNotRunning
        expr: gunky_items_expiration_overdue > 0
        for: 2h
      - alert: GunkySlackErrors
        expr: sum(increase(gunky_activity_log_entries_total{category="slack",succeeded="false"}[1h])) > 5
```

Useful queries:

- 95th-percentile job time per class: `histogram_quantile(0.95, sum by (job_class, le) (rate(gunky_job_duration_seconds_bucket[1h])))`
- Job failure ratio: `sum by (job_class) (rate(gunky_job_executions_total{status="failure"}[1h])) / sum by (job_class) (rate(gunky_job_executions_total[1h]))`
- AI describe failures per day: `increase(gunky_activity_log_entries_total{category="ai",succeeded="false"}[1d])`
