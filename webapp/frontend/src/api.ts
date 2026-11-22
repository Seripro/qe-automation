export type JobState = "QUEUED" | "VALIDATING" | "SCF_RUNNING" | "BAND_RUNNING" | "PDOS_RUNNING" | "COMPLETED" | "FAILED" | "CANCELLED" | "TIMED_OUT";

export type Job = {
  id: string;
  material_label: string;
  state: JobState;
  state_reason: string | null;
  created_at: string;
  updated_at: string;
  queue_position: number | null;
  view_token: string | null;
};

async function request<T>(path: string, init?: RequestInit): Promise<T> {
  const response = await fetch(path, { credentials: "include", ...init });
  if (!response.ok) throw new Error(await response.text() || `HTTP ${response.status}`);
  return response.json() as Promise<T>;
}

export const listJobs = () => request<Job[]>("/api/jobs");

export async function createJob(materialLabel: string, zipFile: File): Promise<Job> {
  const form = new FormData();
  form.append("material_label", materialLabel);
  form.append("zip_file", zipFile);
  return request<Job>("/api/jobs", { method: "POST", body: form });
}

export const cancelJob = (job: Job) => request<Job>(`/api/jobs/${job.id}?token=${encodeURIComponent(job.view_token ?? "")}`, { method: "DELETE" });

export async function artifactText(job: Job, name: "worker.log" | "scf.out" | "band.out" | "nscf.out" | "pdos.out"): Promise<string> {
  const response = await fetch(artifactUrl(job, name), { credentials: "include" });
  if (!response.ok) throw new Error("ログを取得できませんでした。");
  return response.text();
}

export function artifactUrl(job: Job, name: string): string {
  return `/api/jobs/${job.id}/artifacts/${name}?token=${encodeURIComponent(job.view_token ?? "")}`;
}
