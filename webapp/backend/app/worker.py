from __future__ import annotations

import argparse
import os
import signal
import subprocess
import time
from pathlib import Path

from .config import Settings, load_settings
from .database import JobStore


class Worker:
    def __init__(self, settings: Settings) -> None:
        self.settings = settings
        self.store = JobStore(settings.database_path)

    def run_forever(self) -> None:
        self.store.initialize()
        print("QE worker started; waiting for queued jobs.", flush=True)
        while True:
            job = self.store.claim_next()
            if job:
                print(f"Claimed job {job['id']}.", flush=True)
                self.run_job(job)
            else:
                time.sleep(1)

    def run_job(self, job: dict) -> None:
        work_dir = Path(job["work_dir"])
        job_root = work_dir.parent
        try:
            self.run_command(job, "VALIDATING", ["python3", str(self.settings.repository_root / "scripts" / "validate_qe_zip.py"), job["upload_path"]], job_root)
            self.run_command(job, "SCF_RUNNING", ["bash", str(self.settings.repository_root / "scripts" / "qe_mdx_scf_openmp.sh"), job["upload_path"]], job_root, {"MATERIAL_LABEL": job["material_label"], "RUN_NAME": job["id"], "WORK_DIR": str(work_dir)})
            self.run_command(job, "BAND_RUNNING", ["bash", str(self.settings.repository_root / "scripts" / "qe_mdx_band_openmp.sh"), str(work_dir)], work_dir)
            self.run_command(job, "PDOS_RUNNING", ["bash", str(self.settings.repository_root / "scripts" / "qe_mdx_pdos_openmp.sh"), str(work_dir)], work_dir)
            required = [work_dir / "PWscf" / name for name in ("bands.png", "pdos.png")]
            if not all(path.is_file() for path in required):
                raise RuntimeError("Expected result images were not generated")
            self.store.transition(job["id"], "COMPLETED")
            print(f"Job {job['id']} completed.", flush=True)
        except TimeoutError as error:
            self.store.transition(job["id"], "TIMED_OUT", reason=str(error))
        except Exception as error:
            if self.store.get(job["id"])["cancel_requested_at"]:
                self.store.transition(job["id"], "CANCELLED", reason=str(error))
            else:
                self.store.transition(job["id"], "FAILED", reason=str(error))
            print(f"Job {job['id']} stopped: {error}", flush=True)

    def run_command(self, job: dict, state: str, command: list[str], cwd: Path, extra_env: dict[str, str] | None = None) -> None:
        self.store.transition(job["id"], state)
        cwd.mkdir(parents=True, exist_ok=True)
        log_path = Path(job["work_dir"]).parent / "worker.log"
        environment = os.environ.copy()
        if extra_env:
            environment.update(extra_env)
        with log_path.open("a", encoding="utf-8") as log:
            log.write(f"\n--- {state}: {' '.join(command)} ---\n")
            process = subprocess.Popen(command, stdout=log, stderr=subprocess.STDOUT, cwd=cwd, env=environment, start_new_session=True)
            self.store.transition(job["id"], state, pid=process.pid, pgid=process.pid)
            deadline = time.monotonic() + self.settings.stage_timeout_seconds
            while process.poll() is None:
                current = self.store.get(job["id"])
                if current and current["cancel_requested_at"]:
                    self.stop_process(process)
                    raise RuntimeError("Cancelled by user")
                if time.monotonic() >= deadline:
                    self.stop_process(process)
                    raise TimeoutError(f"{state} exceeded its time limit")
                time.sleep(1)
            if process.returncode != 0:
                detail = self.log_tail(log_path)
                raise RuntimeError(f"{state} exited with status {process.returncode}: {detail}")

    @staticmethod
    def log_tail(log_path: Path, limit: int = 1_000) -> str:
        text = log_path.read_text(encoding="utf-8", errors="replace")
        return text[-limit:].strip().replace("\n", " ")

    @staticmethod
    def stop_process(process: subprocess.Popen) -> None:
        """Stop the whole QE process group, escalating only after a grace period."""
        os.killpg(process.pid, signal.SIGTERM)
        try:
            process.wait(timeout=30)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            process.wait(timeout=10)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--once", action="store_true")
    args = parser.parse_args()
    worker = Worker(load_settings())
    worker.store.initialize()
    if args.once:
        job = worker.store.claim_next()
        if job:
            worker.run_job(job)
    else:
        worker.run_forever()


if __name__ == "__main__":
    main()
