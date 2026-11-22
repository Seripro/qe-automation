import tempfile
import unittest
from pathlib import Path

from app.config import Settings
from app.database import JobStore
from app.worker import Worker


class WorkerRecoveryTests(unittest.TestCase):
    def test_only_one_worker_can_hold_the_runtime_lock(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            settings = Settings(
                repository_root=root,
                data_root=root / "runtime",
                max_upload_bytes=1,
                cookie_secure=False,
                stage_timeout_seconds=1,
                view_token_secret="test",
                qe_tools_venv=root,
            )
            first = Worker(settings)
            second = Worker(settings)
            first.acquire_worker_lock()
            try:
                with self.assertRaises(RuntimeError):
                    second.acquire_worker_lock()
            finally:
                first.release_worker_lock()
            second.acquire_worker_lock()
            second.release_worker_lock()

    def test_running_job_is_failed_and_queued_job_is_preserved(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            settings = Settings(
                repository_root=root,
                data_root=root / "runtime",
                max_upload_bytes=1,
                cookie_secure=False,
                stage_timeout_seconds=1,
                view_token_secret="test",
                qe_tools_venv=root,
            )
            store = JobStore(settings.database_path)
            store.initialize()
            running_id = store.create(
                owner_id="owner", material_label="Running", filename="input.zip", token_hash="token",
                work_dir=root / "running" / "run", upload_path=root / "running" / "upload" / "PWscf.zip",
            )
            queued_id = store.create(
                owner_id="owner", material_label="Queued", filename="input.zip", token_hash="token",
                work_dir=root / "queued" / "run", upload_path=root / "queued" / "upload" / "PWscf.zip",
            )
            store.transition(running_id, "SCF_RUNNING")

            Worker(settings).recover_interrupted_jobs()

            running = store.get(running_id)
            queued = store.get(queued_id)
            self.assertEqual(running["state"], "FAILED")
            self.assertIn("Worker restarted", running["state_reason"])
            self.assertEqual(queued["state"], "QUEUED")


if __name__ == "__main__":
    unittest.main()
