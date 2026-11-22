#!/usr/bin/env bash
# Start the local-only API, worker, and Vite development server together.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPOSITORY_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
BACKEND_DIR="${REPOSITORY_ROOT}/webapp/backend"
FRONTEND_DIR="${REPOSITORY_ROOT}/webapp/frontend"
BACKEND_PYTHON="${BACKEND_DIR}/.venv/bin/python"
RUNTIME_DIR="${QE_APP_DATA_ROOT:-${REPOSITORY_ROOT}/webapp/runtime}"
LOG_DIR="${RUNTIME_DIR}/logs"
API_PID=""
WORKER_PID=""
VITE_PID=""

export QE_APP_DATA_ROOT="${RUNTIME_DIR}"
export QE_VIEW_TOKEN_SECRET="${QE_VIEW_TOKEN_SECRET:-development-only-change-before-public}"
export QE_COOKIE_SECURE="false"

require_file() {
    if [[ ! -e "$1" ]]; then
        echo "Error: required file or directory was not found: $1" >&2
        exit 2
    fi
}

has_active_jobs() {
    PYTHONPATH="${BACKEND_DIR}" "${BACKEND_PYTHON}" - <<'PY'
from app.config import load_settings
from app.database import JobStore, RUNNING_STATES

store = JobStore(load_settings().database_path)
store.initialize()
active = [job for job in store.list_for_owner("__unused__")]
with store.connection() as db:
    count = db.execute(
        "SELECT COUNT(*) FROM jobs WHERE state IN ({})".format(",".join("?" for _ in ({"QUEUED"} | RUNNING_STATES))),
        tuple({"QUEUED"} | RUNNING_STATES),
    ).fetchone()[0]
raise SystemExit(0 if count else 1)
PY
}

stop_pid() {
    local pid="$1"
    if [[ -n "${pid}" ]] && kill -0 "${pid}" 2>/dev/null; then
        kill "${pid}" 2>/dev/null || true
        wait "${pid}" 2>/dev/null || true
    fi
}

cleanup() {
    local status=$?
    trap - EXIT INT TERM
    stop_pid "${VITE_PID}"
    stop_pid "${API_PID}"
    if has_active_jobs; then
        echo "A queued or running job exists; worker PID ${WORKER_PID} was left running." >&2
        echo "Wait for it to reach a terminal state before stopping the worker." >&2
    else
        stop_pid "${WORKER_PID}"
    fi
    exit "${status}"
}

trap cleanup EXIT INT TERM

require_file "${BACKEND_PYTHON}"
require_file "${FRONTEND_DIR}/node_modules"
mkdir -p "${LOG_DIR}"

(
    cd "${BACKEND_DIR}"
    exec "${BACKEND_PYTHON}" -m uvicorn app.main:app --host 127.0.0.1 --port 8000
) >>"${LOG_DIR}/api.log" 2>&1 &
API_PID=$!

(
    cd "${BACKEND_DIR}"
    # The worker must survive a terminal disconnect while it owns a QE process.
    exec nohup "${BACKEND_PYTHON}" -m app.worker
) >>"${LOG_DIR}/worker.log" 2>&1 &
WORKER_PID=$!

(
    cd "${FRONTEND_DIR}"
    exec npm run dev -- --host 127.0.0.1 --port 5173 --strictPort
) >>"${LOG_DIR}/frontend.log" 2>&1 &
VITE_PID=$!

sleep 1
for process in "${API_PID}" "${WORKER_PID}" "${VITE_PID}"; do
    if ! kill -0 "${process}" 2>/dev/null; then
        echo "Error: a development process stopped during startup. See ${LOG_DIR}." >&2
        exit 1
    fi
done

echo "QE web development services started."
echo "Frontend: http://127.0.0.1:5173"
echo "Logs: ${LOG_DIR}"
echo "PIDs: api=${API_PID}, worker=${WORKER_PID}, frontend=${VITE_PID}"
echo "Press Ctrl+C to stop. A worker with active jobs is intentionally left running."

wait "${VITE_PID}"
