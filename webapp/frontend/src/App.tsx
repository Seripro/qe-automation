import { FormEvent, useEffect, useState } from "react";
import {
  artifactText,
  artifactUrl,
  cancelJob,
  createJob,
  Job,
  listJobs,
} from "./api";

const activeStates = new Set([
  "QUEUED",
  "VALIDATING",
  "SCF_RUNNING",
  "BAND_RUNNING",
  "PDOS_RUNNING",
]);
const labels: Record<string, string> = {
  QUEUED: "待機中",
  VALIDATING: "入力を確認中",
  SCF_RUNNING: "SCF計算中",
  BAND_RUNNING: "バンド計算中",
  PDOS_RUNNING: "PDOS計算中",
  COMPLETED: "完了",
  FAILED: "失敗",
  CANCELLED: "キャンセル済み",
  TIMED_OUT: "時間切れ",
};

function formatTime(value: string) {
  return new Intl.DateTimeFormat("ja-JP", {
    dateStyle: "short",
    timeStyle: "short",
  }).format(new Date(value));
}

export default function App() {
  const [jobs, setJobs] = useState<Job[]>([]);
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [material, setMaterial] = useState("");
  const [file, setFile] = useState<File | null>(null);
  const [message, setMessage] = useState("");
  const [submitting, setSubmitting] = useState(false);
  const [log, setLog] = useState("");

  const refresh = async () => {
    try {
      const next = await listJobs();
      setJobs(next);
      setSelectedId((current) => current ?? next[0]?.id ?? null);
    } catch (error) {
      setMessage(
        error instanceof Error
          ? error.message
          : "ジョブ一覧を取得できませんでした。",
      );
    }
  };

  useEffect(() => {
    void refresh();
    const timer = window.setInterval(() => void refresh(), 4000);
    return () => window.clearInterval(timer);
  }, []);
  const selected = jobs.find((job) => job.id === selectedId) ?? null;

  const submit = async (event: FormEvent) => {
    event.preventDefault();
    if (!file) {
      setMessage("PWscf.zip を選択してください。");
      return;
    }
    setSubmitting(true);
    setMessage("");
    setLog("");
    try {
      const job = await createJob(material, file);
      setJobs((current) => [job, ...current]);
      setSelectedId(job.id);
      setMaterial("");
      setFile(null);
      setMessage("ジョブを受け付けました。");
    } catch (error) {
      setMessage(
        error instanceof Error ? error.message : "アップロードに失敗しました。",
      );
    } finally {
      setSubmitting(false);
    }
  };

  const loadLog = async () => {
    if (!selected) return;
    try {
      setLog(await artifactText(selected, "worker.log"));
    } catch (error) {
      setLog(
        error instanceof Error ? error.message : "ログを取得できませんでした。",
      );
    }
  };

  return (
    <main>
      <header>
        <strong>QE Calculator</strong>
      </header>
      <section className="workspace">
        <div className="primary">
          <form onSubmit={submit}>
            <label>
              物質名ラベル
              <input
                value={material}
                onChange={(event) => setMaterial(event.target.value)}
                placeholder="例: MgB2"
                pattern="[A-Za-z0-9_-]+"
                maxLength={50}
                required
              />
            </label>
            <label>
              PWscf.zip
              <input
                type="file"
                accept=".zip,application/zip"
                onChange={(event) => setFile(event.target.files?.[0] ?? null)}
                required
              />
            </label>
            <button disabled={submitting}>
              {submitting ? "登録中…" : "待ち行列へ追加"}
            </button>
          </form>
          {message && (
            <p className="message" role="status">
              {message}
            </p>
          )}

          <h2>自分のジョブ</h2>
          <div className="jobs" aria-live="polite">
            {jobs.length === 0 && (
              <p className="muted">まだジョブはありません。</p>
            )}
            {jobs.map((job) => (
              <button
                className={`job ${selectedId === job.id ? "selected" : ""}`}
                key={job.id}
                onClick={() => {
                  setSelectedId(job.id);
                  setLog("");
                  setMessage("");
                }}
              >
                <span>
                  <strong>{job.material_label}</strong>
                  <small>{formatTime(job.created_at)}</small>
                </span>
                <span className={`state ${job.state.toLowerCase()}`}>
                  {labels[job.state]}
                </span>
              </button>
            ))}
          </div>
        </div>

        <aside>
          <h2>ジョブ詳細</h2>
          {!selected && (
            <p className="muted">
              ジョブを選択すると、進捗と結果を表示します。
            </p>
          )}
          {selected && (
            <>
              <dl>
                <dt>物質名</dt>
                <dd>{selected.material_label}</dd>
                <dt>状態</dt>
                <dd>
                  {labels[selected.state]}
                  {selected.queue_position &&
                    `（${selected.queue_position}番目）`}
                </dd>
                <dt>更新</dt>
                <dd>{formatTime(selected.updated_at)}</dd>
              </dl>
              {selected.state_reason && (
                <p className="error">{selected.state_reason}</p>
              )}
              {activeStates.has(selected.state) && (
                <button
                  className="secondary"
                  onClick={() =>
                    void cancelJob(selected)
                      .then(refresh)
                      .catch((error) => setMessage(error.message))
                  }
                >
                  キャンセル
                </button>
              )}
              <div className="actions">
                <button className="secondary" onClick={() => void loadLog()}>
                  ログを表示
                </button>
                {log && <pre>{log}</pre>}
              </div>
              {selected.state === "COMPLETED" && (
                <div className="results">
                  <h3>結果</h3>
                  <a
                    href={artifactUrl(selected, "bands.png")}
                    target="_blank"
                    rel="noreferrer"
                  >
                    <img
                      src={artifactUrl(selected, "bands.png")}
                      alt="バンド図"
                    />
                  </a>
                  <a
                    href={artifactUrl(selected, "pdos.png")}
                    target="_blank"
                    rel="noreferrer"
                  >
                    <img src={artifactUrl(selected, "pdos.png")} alt="PDOS図" />
                  </a>
                </div>
              )}
            </>
          )}
        </aside>
      </section>
    </main>
  );
}
