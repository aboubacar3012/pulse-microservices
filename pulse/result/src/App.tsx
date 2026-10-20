import { useCallback, useEffect, useState } from "react";
import { ToolIcon } from "./ToolIcon";

// Chemin relatif : nginx (result) proxy /api → Service interne "api:3000"
const API_URL = import.meta.env.VITE_API_URL ?? "/api";
const POLL_MS = 2000;

type ResultRow = { tool: string; count: number; voters: number };

const LABELS: Record<string, string> = {
  docker: "Docker",
  ansible: "Ansible",
  kubernetes: "Kubernetes",
  linux: "Linux",
  git: "Git",
  terraform: "Terraform",
  jenkins: "Jenkins",
  aws: "AWS",
};

export default function App() {
  const [results, setResults] = useState<ResultRow[]>([]);
  const [totalVoters, setTotalVoters] = useState(0);
  const [error, setError] = useState<string | null>(null);
  const [updatedAt, setUpdatedAt] = useState<Date | null>(null);
  const [live, setLive] = useState(false);

  const load = useCallback(async () => {
    try {
      const res = await fetch(`${API_URL}/results`);
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      const data = (await res.json()) as {
        results: ResultRow[];
        totalVoters?: number;
      };
      setResults(data.results ?? []);
      setTotalVoters(data.totalVoters ?? 0);
      setError(null);
      setUpdatedAt(new Date());
      setLive(true);
    } catch (err) {
      setLive(false);
      setError(
        err instanceof Error ? err.message : "Impossible de charger les résultats"
      );
    }
  }, []);

  useEffect(() => {
    load();
    const id = window.setInterval(load, POLL_MS);
    return () => window.clearInterval(id);
  }, [load]);

  const total = results.reduce((sum, row) => sum + row.count, 0);
  const max = Math.max(1, ...results.map((row) => row.count));
  const sorted = [...results].sort((a, b) => b.count - a.count);
  const leader = sorted[0];

  return (
    <div className="shell">
      <header className="top">
        <div className="brand-block">
          <p className="brand">Pulse</p>
          <p className="byline">Santu</p>
        </div>
        <div className={`live ${live ? "on" : "off"}`}>
          <span className="dot" aria-hidden />
          {live ? "Live" : "Hors ligne"}
        </div>
      </header>

      <main className="main">
        <section className="hero">
          <div className="hero-row">
            <span className="eyebrow">Total des votes</span>
            <span className="total" aria-live="polite">
              {total.toLocaleString("fr-FR")}
            </span>
          </div>
          <p className="hero-row meta">
            <span>
              {totalVoters.toLocaleString("fr-FR")} votant
              {totalVoters > 1 ? "s" : ""}
            </span>
            <span className="sep" aria-hidden>
              ·
            </span>
            <span>
              {leader && leader.count > 0
                ? `${LABELS[leader.tool] || leader.tool} en tête`
                : "En attente"}
            </span>
          </p>
          <p className="hero-row clock">
            {updatedAt
              ? `Mis à jour ${updatedAt.toLocaleTimeString("fr-FR")}`
              : "—"}
          </p>
        </section>

        {error && (
          <p className="banner err" role="alert">
            {error}
          </p>
        )}

        <ol className="board">
          {sorted.map((row, index) => {
            const pct = Math.round((row.count / max) * 100);
            return (
              <li key={row.tool} style={{ animationDelay: `${index * 0.04}s` }}>
                <div
                  className={`row ${index === 0 && row.count > 0 ? "lead" : ""}`}
                >
                  <span className="rank">
                    {String(index + 1).padStart(2, "0")}
                  </span>
                  <span className="icon-wrap">
                    <ToolIcon tool={row.tool} />
                  </span>
                  <div className="body">
                    <div className="labels">
                      <span className="name">
                        {LABELS[row.tool] || row.tool}
                      </span>
                      <span className="stats">
                        <span className="count">
                          {row.count.toLocaleString("fr-FR")}
                          <span className="stat-label"> votes</span>
                        </span>
                        <span className="voters">
                          {row.voters.toLocaleString("fr-FR")}
                          <span className="stat-label">
                            {" "}
                            votant{row.voters > 1 ? "s" : ""}
                          </span>
                        </span>
                      </span>
                    </div>
                    <div className="track" aria-hidden>
                      <div className="fill" style={{ width: `${pct}%` }} />
                    </div>
                  </div>
                </div>
              </li>
            );
          })}
        </ol>
      </main>
    </div>
  );
}
