from __future__ import annotations

import hashlib
import hmac
import re
import secrets
from pathlib import Path

from fastapi import FastAPI, File, Form, HTTPException, Request, Response, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse
from pydantic import BaseModel

from .config import load_settings
from .database import JobStore, TERMINAL_STATES

settings = load_settings()
store = JobStore(settings.database_path)
app = FastAPI(title="QE Calculator API")
allowed_origins = [origin for origin in __import__("os").environ.get("QE_CORS_ORIGINS", "http://127.0.0.1:5173,http://localhost:5173").split(",") if origin]
app.add_middleware(
    CORSMiddleware,
    allow_origins=allowed_origins,
    allow_credentials=True,
    allow_methods=["GET", "POST", "DELETE"],
    allow_headers=["Content-Type"],
)


class JobResponse(BaseModel):
    id: str
    material_label: str
    state: str
    state_reason: str | None = None
    created_at: str
    updated_at: str
    queue_position: int | None = None
    view_token: str | None = None


def browser_id(request: Request, response: Response) -> str:
    value = request.cookies.get("qe_browser_id")
    if value and len(value) >= 32:
        return value
    value = secrets.token_urlsafe(32)
    response.set_cookie("qe_browser_id", value, httponly=True, secure=settings.cookie_secure, samesite="lax", max_age=60 * 60 * 24 * 30)
    return value


def view_token(owner_id: str, job_id: str) -> str:
    payload = f"{owner_id}:{job_id}".encode()
    return hmac.new(settings.view_token_secret.encode(), payload, hashlib.sha256).hexdigest()


def job_response(job: dict) -> JobResponse:
    return JobResponse(
        id=job["id"], material_label=job["material_label"], state=job["state"],
        state_reason=job["state_reason"], created_at=job["created_at"], updated_at=job["updated_at"],
        queue_position=store.queue_position(job["id"]), view_token=view_token(job["owner_id"], job["id"]),
    )


def owned_job(request: Request, job_id: str, token: str) -> dict:
    job = store.get(job_id)
    if not job:
        raise HTTPException(404, "Job not found")
    if not secrets.compare_digest(request.cookies.get("qe_browser_id", ""), job["owner_id"]):
        raise HTTPException(404, "Job not found")
    if not secrets.compare_digest(hashlib.sha256(token.encode()).hexdigest(), job["view_token_hash"]):
        raise HTTPException(404, "Job not found")
    return job


@app.on_event("startup")
def startup() -> None:
    settings.jobs_root.mkdir(parents=True, exist_ok=True)
    store.initialize()


@app.get("/api/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


@app.post("/api/jobs", response_model=JobResponse, status_code=201)
async def create_job(request: Request, response: Response, material_label: str = Form(...), zip_file: UploadFile = File(...)) -> JobResponse:
    owner = browser_id(request, response)
    if not re.fullmatch(r"[A-Za-z0-9_-]{1,50}", material_label):
        raise HTTPException(422, "material_label must use only letters, digits, _ or -")
    if not zip_file.filename or not zip_file.filename.lower().endswith(".zip"):
        raise HTTPException(422, "A .zip file is required")
    # Create paths from a server-generated ID; never from the upload filename or label.
    job_root = settings.jobs_root / secrets.token_hex(16)
    upload_path = job_root / "upload" / "PWscf.zip"
    upload_path.parent.mkdir(parents=True)
    written = 0
    try:
        with upload_path.open("xb") as output:
            while chunk := await zip_file.read(1024 * 1024):
                written += len(chunk)
                if written > settings.max_upload_bytes:
                    raise HTTPException(413, "ZIP exceeds the upload size limit")
                output.write(chunk)
    except Exception:
        upload_path.unlink(missing_ok=True)
        raise
    finally:
        await zip_file.close()

    token = view_token(owner, job_root.name)
    job_id = store.create(
        owner_id=owner, material_label=material_label, filename=zip_file.filename,
        token_hash=hashlib.sha256(token.encode()).hexdigest(), work_dir=job_root / "run", upload_path=upload_path,
    )
    # The database ID differs from the filesystem nonce, so bind the stored token to its real ID.
    token = view_token(owner, job_id)
    with store.connection() as db:
        db.execute("UPDATE jobs SET view_token_hash = ? WHERE id = ?", (hashlib.sha256(token.encode()).hexdigest(), job_id))
    return job_response(store.get(job_id))


@app.get("/api/jobs", response_model=list[JobResponse])
def list_jobs(request: Request, response: Response) -> list[JobResponse]:
    owner = browser_id(request, response)
    return [job_response(job) for job in store.list_for_owner(owner)]


@app.get("/api/jobs/{job_id}", response_model=JobResponse)
def get_job(request: Request, job_id: str, token: str) -> JobResponse:
    return job_response(owned_job(request, job_id, token))


@app.delete("/api/jobs/{job_id}", response_model=JobResponse)
def cancel_job(request: Request, job_id: str, token: str) -> JobResponse:
    job = owned_job(request, job_id, token)
    if job["state"] in TERMINAL_STATES:
        raise HTTPException(409, "A completed job cannot be cancelled")
    return job_response(store.request_cancel(job_id))


@app.get("/api/jobs/{job_id}/artifacts/{name}")
def artifact(request: Request, job_id: str, name: str, token: str) -> FileResponse:
    job = owned_job(request, job_id, token)
    allowed = {"bands.png", "pdos.png", "scf.out", "band.out", "nscf.out", "pdos.out", "worker.log"}
    if name not in allowed:
        raise HTTPException(404, "Artifact not found")
    path = Path(job["work_dir"]).parent / "worker.log" if name == "worker.log" else Path(job["work_dir"]) / f"PWscf/{name}"
    if not path.is_file():
        raise HTTPException(404, "Artifact not available")
    return FileResponse(path)
