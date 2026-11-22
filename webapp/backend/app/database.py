from __future__ import annotations

import sqlite3
from datetime import UTC, datetime
from pathlib import Path
from uuid import uuid4

TERMINAL_STATES = {"COMPLETED", "FAILED", "CANCELLED", "TIMED_OUT"}
RUNNING_STATES = {"VALIDATING", "SCF_RUNNING", "BAND_RUNNING", "PDOS_RUNNING"}


def now() -> str:
    return datetime.now(UTC).isoformat()


class JobStore:
    def __init__(self, path: Path) -> None:
        self.path = path

    def connection(self) -> sqlite3.Connection:
        connection = sqlite3.connect(self.path)
        connection.row_factory = sqlite3.Row
        return connection

    def initialize(self) -> None:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        with self.connection() as db:
            db.execute(
                """CREATE TABLE IF NOT EXISTS jobs (
                    id TEXT PRIMARY KEY, owner_id TEXT NOT NULL, material_label TEXT NOT NULL,
                    input_zip_name TEXT NOT NULL, input_zip_sha256 TEXT,
                    view_token_hash TEXT NOT NULL, state TEXT NOT NULL, state_reason TEXT,
                    work_dir TEXT NOT NULL, upload_path TEXT NOT NULL,
                    process_id INTEGER, process_group_id INTEGER, exit_code INTEGER,
                    created_at TEXT NOT NULL, started_at TEXT, finished_at TEXT, updated_at TEXT NOT NULL,
                    cancel_requested_at TEXT
                )"""
            )
            db.execute("CREATE INDEX IF NOT EXISTS jobs_owner_created ON jobs(owner_id, created_at)")
            db.execute("CREATE INDEX IF NOT EXISTS jobs_state_created ON jobs(state, created_at)")

    def create(self, *, owner_id: str, material_label: str, filename: str, token_hash: str,
               work_dir: Path, upload_path: Path) -> str:
        job_id = uuid4().hex
        timestamp = now()
        with self.connection() as db:
            db.execute(
                """INSERT INTO jobs (id, owner_id, material_label, input_zip_name, view_token_hash,
                   state, work_dir, upload_path, created_at, updated_at)
                   VALUES (?, ?, ?, ?, ?, 'QUEUED', ?, ?, ?, ?)""",
                (job_id, owner_id, material_label, filename, token_hash, str(work_dir), str(upload_path), timestamp, timestamp),
            )
        return job_id

    def get(self, job_id: str) -> dict | None:
        with self.connection() as db:
            row = db.execute("SELECT * FROM jobs WHERE id = ?", (job_id,)).fetchone()
        return dict(row) if row else None

    def list_for_owner(self, owner_id: str) -> list[dict]:
        with self.connection() as db:
            rows = db.execute("SELECT * FROM jobs WHERE owner_id = ? ORDER BY created_at DESC", (owner_id,)).fetchall()
        return [dict(row) for row in rows]

    def queue_position(self, job_id: str) -> int | None:
        job = self.get(job_id)
        if not job or job["state"] != "QUEUED":
            return None
        with self.connection() as db:
            row = db.execute("SELECT COUNT(*) AS count FROM jobs WHERE state = 'QUEUED' AND created_at <= ?", (job["created_at"],)).fetchone()
        return int(row["count"])

    def claim_next(self) -> dict | None:
        """Atomically reserve the oldest queued job for the single worker."""
        with self.connection() as db:
            db.execute("BEGIN IMMEDIATE")
            row = db.execute("SELECT * FROM jobs WHERE state = 'QUEUED' ORDER BY created_at LIMIT 1").fetchone()
            if not row:
                return None
            timestamp = now()
            db.execute("UPDATE jobs SET state = 'VALIDATING', started_at = ?, updated_at = ? WHERE id = ?", (timestamp, timestamp, row["id"]))
            claimed = db.execute("SELECT * FROM jobs WHERE id = ?", (row["id"],)).fetchone()
        return dict(claimed)

    def interrupted_jobs(self) -> list[dict]:
        """Return jobs left in an in-progress state by a stopped worker."""
        placeholders = ",".join("?" for _ in RUNNING_STATES)
        with self.connection() as db:
            rows = db.execute(
                f"SELECT * FROM jobs WHERE state IN ({placeholders}) ORDER BY created_at",
                tuple(sorted(RUNNING_STATES)),
            ).fetchall()
        return [dict(row) for row in rows]

    def transition(self, job_id: str, state: str, *, reason: str | None = None,
                   pid: int | None = None, pgid: int | None = None, exit_code: int | None = None) -> None:
        if state not in {"QUEUED", *RUNNING_STATES, *TERMINAL_STATES}:
            raise ValueError(f"unknown state: {state}")
        fields = ["state = ?", "updated_at = ?", "state_reason = ?"]
        values: list[object] = [state, now(), reason]
        if pid is not None:
            fields.append("process_id = ?")
            values.append(pid)
        if pgid is not None:
            fields.append("process_group_id = ?")
            values.append(pgid)
        if exit_code is not None:
            fields.append("exit_code = ?")
            values.append(exit_code)
        if state in TERMINAL_STATES:
            fields.append("finished_at = ?")
            values.append(now())
        values.append(job_id)
        with self.connection() as db:
            db.execute(f"UPDATE jobs SET {', '.join(fields)} WHERE id = ?", values)

    def request_cancel(self, job_id: str) -> dict | None:
        job = self.get(job_id)
        if not job or job["state"] in TERMINAL_STATES:
            return job
        if job["state"] == "QUEUED":
            self.transition(job_id, "CANCELLED", reason="Cancelled before execution")
        else:
            with self.connection() as db:
                db.execute("UPDATE jobs SET cancel_requested_at = ?, updated_at = ? WHERE id = ?", (now(), now(), job_id))
        return self.get(job_id)
