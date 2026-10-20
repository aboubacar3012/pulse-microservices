import { useCallback, useEffect, useState } from "react";
import { ToolIcon } from "./ToolIcon";
import { getOrCreateSessionId } from "./session";
import { TOOLS, TOOL_META, type Tool } from "./tools";

const API_URL = import.meta.env.VITE_API_URL || "http://localhost:3000";

type Toast = { id: number; ok: boolean; message: string } | null;
type VoteAction = "add" | "remove";

function emptyCounts(): Record<string, number> {
  return Object.fromEntries(TOOLS.map((t) => [t, 0]));
}

export default function App() {
  const [sessionId, setSessionId] = useState<string | null>(null);
  const [ready, setReady] = useState(false);
  const [pending, setPending] = useState<Tool | null>(null);
  const [toast, setToast] = useState<Toast>(null);
  const [localCounts, setLocalCounts] =
    useState<Record<string, number>>(emptyCounts);
  const [justVoted, setJustVoted] = useState<Tool | null>(null);

  const hydrate = useCallback(async (id: string) => {
    try {
      const res = await fetch(`${API_URL}/session/${id}`);
      if (!res.ok) return;
      const data = (await res.json()) as { votes?: Record<string, number> };
      if (data.votes) {
        setLocalCounts({ ...emptyCounts(), ...data.votes });
      }
    } catch {
      // ignore
    }
  }, []);

  useEffect(() => {
    const id = getOrCreateSessionId();
    setSessionId(id);
    setReady(true);
    void hydrate(id);
  }, [hydrate]);

  useEffect(() => {
    if (!toast) return;
    const id = window.setTimeout(() => setToast(null), 2200);
    return () => window.clearTimeout(id);
  }, [toast]);

  useEffect(() => {
    if (!justVoted) return;
    const id = window.setTimeout(() => setJustVoted(null), 480);
    return () => window.clearTimeout(id);
  }, [justVoted]);

  const changeVote = useCallback(
    async (tool: Tool, action: VoteAction) => {
      if (pending || !sessionId) return;
      if (action === "remove" && (localCounts[tool] || 0) <= 0) return;

      setPending(tool);
      try {
        const res = await fetch(`${API_URL}/vote`, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ tool, sessionId, action }),
        });
        if (!res.ok) {
          const body = await res.json().catch(() => ({}));
          throw new Error(body.error || `HTTP ${res.status}`);
        }
        const body = (await res.json()) as {
          sessionVotes?: Record<string, number>;
        };
        const votes = body.sessionVotes
          ? { ...emptyCounts(), ...body.sessionVotes }
          : {
              ...localCounts,
              [tool]: Math.max(
                0,
                (localCounts[tool] || 0) + (action === "add" ? 1 : -1)
              ),
            };
        const next = votes[tool] || 0;
        setLocalCounts(votes);
        setJustVoted(tool);
        setToast({
          id: Date.now(),
          ok: true,
          message: `${TOOL_META[tool].label} · ${action === "add" ? "+1" : "−1"} (×${next})`,
        });
      } catch (err) {
        setToast({
          id: Date.now(),
          ok: false,
          message: err instanceof Error ? err.message : "Échec",
        });
      } finally {
        setPending(null);
      }
    },
    [pending, sessionId, localCounts]
  );

  const myTotal = Object.values(localCounts).reduce((a, b) => a + b, 0);

  return (
    <div className="shell">
      <header className="top">
        <div className="brand-block">
          <p className="brand">Pulse</p>
          <p className="byline">Santu</p>
        </div>
        {myTotal > 0 && (
          <p className="session" aria-live="polite">
            {myTotal} vote{myTotal > 1 ? "s" : ""}
          </p>
        )}
      </header>

      <main className="main">
        <section className="intro">
          <h1>Vote pour tes outils.</h1>
          <p className="lede">
            Ajoute ou retire des votes — autant de fois que tu veux, sur
            plusieurs outils.
          </p>
        </section>

        <ul className="grid">
          {TOOLS.map((tool) => {
            const meta = TOOL_META[tool];
            const mine = localCounts[tool] || 0;
            const isPending = pending === tool;
            const isFlash = justVoted === tool;

            return (
              <li key={tool}>
                <div
                  className={[
                    "tile",
                    isPending ? "is-pending" : "",
                    isFlash ? "is-flash" : "",
                    mine > 0 ? "has-votes" : "",
                  ]
                    .filter(Boolean)
                    .join(" ")}
                >
                  <div className="tile-head">
                    <span className="icon-wrap">
                      <ToolIcon tool={tool} />
                    </span>
                    {mine > 0 && <span className="count-chip">×{mine}</span>}
                  </div>

                  <div className="tile-text">
                    <span className="tile-name">{meta.label}</span>
                    <span className="tile-blurb">{meta.blurb}</span>
                  </div>

                  <div className="controls">
                    <button
                      type="button"
                      className="ctrl minus"
                      disabled={!ready || !!pending || mine <= 0}
                      onClick={() => changeVote(tool, "remove")}
                      aria-label={`Retirer un vote pour ${meta.label}`}
                    >
                      −
                    </button>
                    <span className="ctrl-count" aria-live="polite">
                      {mine}
                    </span>
                    <button
                      type="button"
                      className="ctrl plus"
                      disabled={!ready || !!pending}
                      onClick={() => changeVote(tool, "add")}
                      aria-label={`Ajouter un vote pour ${meta.label}`}
                    >
                      +
                    </button>
                  </div>
                </div>
              </li>
            );
          })}
        </ul>
      </main>

      {toast && (
        <div
          className={`toast ${toast.ok ? "ok" : "err"}`}
          role="status"
          key={toast.id}
        >
          {toast.message}
        </div>
      )}
    </div>
  );
}
