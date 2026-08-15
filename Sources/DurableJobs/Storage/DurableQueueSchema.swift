import GRDB

enum DurableQueueSchema {
    static func migrator() -> DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("durable-queue-v1") { db in
            try db.execute(sql: """
                CREATE TABLE durable_queue_jobs (
                    id TEXT PRIMARY KEY NOT NULL,
                    type_identifier TEXT NOT NULL,
                    payload BLOB NOT NULL,
                    payload_version INTEGER NOT NULL,
                    queue_name TEXT NOT NULL,
                    state TEXT NOT NULL CHECK (state IN ('blocked', 'queued', 'running', 'succeeded', 'failed', 'cancelled')),
                    lane TEXT NOT NULL,
                    priority INTEGER NOT NULL DEFAULT 0,
                    available_at INTEGER NOT NULL,
                    deadline_at INTEGER,
                    timeout_seconds REAL,
                    attempt_count INTEGER NOT NULL DEFAULT 0,
                    max_attempts INTEGER NOT NULL,
                    retry_policy BLOB NOT NULL,
                    requires_network INTEGER NOT NULL DEFAULT 0 CHECK (requires_network IN (0, 1)),
                    requires_power INTEGER NOT NULL DEFAULT 0 CHECK (requires_power IN (0, 1)),
                    unique_key TEXT,
                    idempotency_key TEXT NOT NULL,
                    lease_token TEXT,
                    lease_expires_at INTEGER,
                    cancel_requested INTEGER NOT NULL DEFAULT 0 CHECK (cancel_requested IN (0, 1)),
                    stop_reason TEXT,
                    progress REAL NOT NULL DEFAULT 0 CHECK (progress >= 0 AND progress <= 1),
                    chain_id TEXT,
                    batch_id TEXT,
                    recurring_id TEXT,
                    recurring_occurrence_at INTEGER,
                    created_at INTEGER NOT NULL,
                    updated_at INTEGER NOT NULL,
                    finished_at INTEGER,
                    last_failure_kind TEXT,
                    last_failure_message TEXT,
                    last_failure_at INTEGER,
                    failure_hook_pending INTEGER NOT NULL DEFAULT 0 CHECK (failure_hook_pending IN (0, 1)),
                    failure_hook_token TEXT,
                    failure_hook_expires_at INTEGER,
                    failure_hook_attempt_count INTEGER NOT NULL DEFAULT 0,
                    failure_hook_available_at INTEGER NOT NULL DEFAULT 0
                ) STRICT
                """)
            try db.execute(sql: """
                CREATE INDEX durable_queue_jobs_ready
                ON durable_queue_jobs(state, queue_name, lane, available_at, priority DESC, created_at, id)
                """)
            try db.execute(sql: """
                CREATE INDEX durable_queue_jobs_expired_lease
                ON durable_queue_jobs(state, lease_expires_at)
                """)
            try db.execute(sql: """
                CREATE INDEX durable_queue_jobs_history
                ON durable_queue_jobs(state, finished_at)
                """)
            try db.execute(sql: """
                CREATE INDEX durable_queue_jobs_active_unique
                ON durable_queue_jobs(queue_name, unique_key, state, created_at)
                WHERE unique_key IS NOT NULL
                """)
            try db.execute(sql: """
                CREATE TABLE durable_queue_controls (
                    queue_name TEXT PRIMARY KEY NOT NULL,
                    is_paused INTEGER NOT NULL CHECK (is_paused IN (0, 1)),
                    maximum_concurrency INTEGER CHECK (maximum_concurrency IS NULL OR maximum_concurrency > 0),
                    updated_at INTEGER NOT NULL
                ) STRICT
                """)
            try db.execute(sql: """
                CREATE TABLE durable_queue_locks (
                    lock_key TEXT PRIMARY KEY NOT NULL,
                    owner_token TEXT NOT NULL,
                    expires_at INTEGER NOT NULL,
                    duration_milliseconds INTEGER NOT NULL DEFAULT 90000,
                    updated_at INTEGER NOT NULL
                ) STRICT
                """)
            try db.execute(sql: """
                CREATE INDEX durable_queue_jobs_failure_hooks
                ON durable_queue_jobs(
                    failure_hook_pending,
                    failure_hook_available_at,
                    failure_hook_expires_at,
                    finished_at,
                    id
                )
                """)
            try db.execute(sql: """
                CREATE TABLE durable_queue_job_tags (
                    job_id TEXT NOT NULL REFERENCES durable_queue_jobs(id) ON DELETE CASCADE,
                    tag TEXT NOT NULL,
                    PRIMARY KEY (job_id, tag)
                ) STRICT
                """)
            try db.execute(sql: """
                CREATE INDEX durable_queue_job_tags_lookup
                ON durable_queue_job_tags(tag, job_id)
                """)
            try db.execute(sql: """
                CREATE TABLE durable_queue_dependencies (
                    job_id TEXT NOT NULL REFERENCES durable_queue_jobs(id) ON DELETE CASCADE,
                    prerequisite_id TEXT NOT NULL REFERENCES durable_queue_jobs(id) ON DELETE CASCADE,
                    behavior TEXT NOT NULL CHECK (behavior IN ('onSuccess', 'runRegardless')),
                    PRIMARY KEY (job_id, prerequisite_id)
                ) STRICT
                """)
            try db.execute(sql: """
                CREATE INDEX durable_queue_dependencies_prerequisite
                ON durable_queue_dependencies(prerequisite_id, job_id)
                """)
            try db.execute(sql: """
                CREATE TABLE durable_queue_recurring (
                    id TEXT PRIMARY KEY NOT NULL,
                    request BLOB NOT NULL,
                    lane TEXT NOT NULL,
                    interval_seconds REAL NOT NULL,
                    flex_seconds REAL NOT NULL DEFAULT 0,
                    missed_run_policy TEXT NOT NULL CHECK (missed_run_policy IN ('latest', 'all')),
                    maximum_catch_up INTEGER NOT NULL DEFAULT 1,
                    next_run_at INTEGER NOT NULL,
                    is_paused INTEGER NOT NULL DEFAULT 0 CHECK (is_paused IN (0, 1)),
                    created_at INTEGER NOT NULL,
                    updated_at INTEGER NOT NULL
                ) STRICT
                """)
            try db.execute(sql: """
                CREATE INDEX durable_queue_recurring_due
                ON durable_queue_recurring(is_paused, lane, next_run_at, id)
                """)
            try db.execute(sql: """
                CREATE UNIQUE INDEX durable_queue_jobs_recurring_occurrence
                ON durable_queue_jobs(recurring_id, recurring_occurrence_at)
                WHERE recurring_id IS NOT NULL
                """)
            try db.execute(sql: """
                CREATE TABLE durable_queue_batches (
                    id TEXT PRIMARY KEY NOT NULL,
                    completion_job_id TEXT REFERENCES durable_queue_jobs(id) ON DELETE SET NULL,
                    created_at INTEGER NOT NULL,
                    updated_at INTEGER NOT NULL
                ) STRICT
                """)
            try db.execute(sql: """
                CREATE INDEX durable_queue_jobs_batch
                ON durable_queue_jobs(batch_id, state)
                WHERE batch_id IS NOT NULL
                """)
            try db.execute(sql: """
                CREATE TABLE durable_queue_attempts (
                    id INTEGER PRIMARY KEY,
                    job_id TEXT NOT NULL REFERENCES durable_queue_jobs(id) ON DELETE CASCADE,
                    attempt INTEGER NOT NULL,
                    started_at INTEGER NOT NULL,
                    finished_at INTEGER,
                    outcome TEXT,
                    message TEXT
                ) STRICT
                """)
            try db.execute(sql: """
                CREATE TABLE durable_queue_rate_limits (
                    rate_key TEXT PRIMARY KEY NOT NULL,
                    window_started_at INTEGER NOT NULL,
                    hit_count INTEGER NOT NULL,
                    updated_at INTEGER NOT NULL
                ) STRICT
                """)
            try db.execute(sql: """
                CREATE TABLE durable_queue_exception_throttles (
                    throttle_key TEXT PRIMARY KEY NOT NULL,
                    exception_count INTEGER NOT NULL,
                    last_exception_at INTEGER NOT NULL,
                    updated_at INTEGER NOT NULL
                ) STRICT
                """)
        }
        return migrator
    }
}
