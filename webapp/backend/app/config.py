from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class Settings:
    repository_root: Path
    data_root: Path
    max_upload_bytes: int
    cookie_secure: bool
    stage_timeout_seconds: int
    view_token_secret: str
    qe_tools_venv: Path

    @property
    def database_path(self) -> Path:
        return self.data_root / "jobs.sqlite3"

    @property
    def jobs_root(self) -> Path:
        return self.data_root / "jobs"


def load_settings() -> Settings:
    repository_root = Path(__file__).resolve().parents[3]
    data_root = Path(os.environ.get("QE_APP_DATA_ROOT", repository_root / "webapp" / "runtime"))
    return Settings(
        repository_root=repository_root,
        data_root=data_root,
        max_upload_bytes=int(os.environ.get("QE_MAX_UPLOAD_BYTES", 50 * 1024 * 1024)),
        cookie_secure=os.environ.get("QE_COOKIE_SECURE", "false").lower() == "true",
        stage_timeout_seconds=int(os.environ.get("QE_STAGE_TIMEOUT_SECONDS", 6 * 60 * 60)),
        view_token_secret=os.environ.get("QE_VIEW_TOKEN_SECRET", "development-only-change-me"),
        qe_tools_venv=Path(os.environ.get("QE_TOOLS_VENV", Path.home() / ".venvs" / "qe-tools-v1")),
    )
