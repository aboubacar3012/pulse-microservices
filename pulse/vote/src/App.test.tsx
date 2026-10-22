import { cleanup, fireEvent, render, screen, waitFor } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import App from "./App";

const SESSION = "550e8400-e29b-41d4-a716-446655440000";

vi.mock("./session", () => ({
  getOrCreateSessionId: () => SESSION,
}));

describe("Vote App", () => {
  beforeEach(() => {
    vi.stubGlobal(
      "fetch",
      vi.fn(async (input: RequestInfo | URL, init?: RequestInit) => {
        const url = String(input);
        if (url.includes(`/session/${SESSION}`)) {
          return {
            ok: true,
            json: async () => ({
              sessionId: SESSION,
              votes: { docker: 1 },
              total: 1,
            }),
          } as Response;
        }
        if (url.includes("/vote") && init?.method === "POST") {
          return {
            ok: true,
            json: async () => ({
              accepted: true,
              tool: "jenkins",
              sessionId: SESSION,
              sessionVotes: { docker: 1, jenkins: 1 },
              sessionTotal: 2,
            }),
          } as Response;
        }
        return { ok: false, status: 404, json: async () => ({}) } as Response;
      })
    );
  });

  afterEach(() => {
    cleanup();
    vi.unstubAllGlobals();
  });

  it("affiche la marque et les outils", async () => {
    render(<App />);
    expect(screen.getByText("Pulse")).toBeTruthy();
    expect(screen.getByRole("heading", { name: /vote pour tes outils/i })).toBeTruthy();
    expect(await screen.findByLabelText(/voter pour jenkins/i)).toBeTruthy();
    expect(screen.getByText("×1")).toBeTruthy();
  });

  it("envoie un vote au clic", async () => {
    render(<App />);
    const button = await screen.findByLabelText(/voter pour jenkins/i);
    fireEvent.click(button);

    await waitFor(() => {
      expect(fetch).toHaveBeenCalledWith(
        "/api/vote",
        expect.objectContaining({
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ tool: "jenkins", sessionId: SESSION }),
        })
      );
    });

    expect(await screen.findByText(/jenkins · \+1/i)).toBeTruthy();
  });
});
