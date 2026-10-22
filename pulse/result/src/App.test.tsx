import { cleanup, render, screen, waitFor } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import App from "./App";

describe("Result App", () => {
  beforeEach(() => {
    vi.stubGlobal(
      "fetch",
      vi.fn(async () => ({
        ok: true,
        json: async () => ({
          results: [
            { tool: "docker", count: 10, voters: 3 },
            { tool: "jenkins", count: 4, voters: 2 },
            { tool: "ansible", count: 0, voters: 0 },
            { tool: "kubernetes", count: 0, voters: 0 },
            { tool: "linux", count: 0, voters: 0 },
            { tool: "git", count: 0, voters: 0 },
            { tool: "terraform", count: 0, voters: 0 },
            { tool: "aws", count: 0, voters: 0 },
          ],
          totalVotes: 14,
          totalVoters: 4,
        }),
      })) as unknown as typeof fetch
    );
  });

  afterEach(() => {
    cleanup();
    vi.unstubAllGlobals();
  });

  it("charge et affiche les totaux", async () => {
    render(<App />);

    await waitFor(() => {
      expect(screen.getByText("14")).toBeTruthy();
    });

    expect(screen.getByText(/4 votants/i)).toBeTruthy();
    expect(screen.getByText(/docker en tête/i)).toBeTruthy();
    expect(screen.getByText("Live")).toBeTruthy();
    expect(screen.getAllByText("Docker").length).toBeGreaterThan(0);
    expect(screen.getAllByText("Jenkins").length).toBeGreaterThan(0);
  });

  it("affiche une erreur si l'API échoue", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn(async () => {
        throw new Error("network down");
      })
    );

    render(<App />);

    const alert = await screen.findByRole("alert");
    expect(alert.textContent).toContain("network down");
    expect(screen.getByText("Hors ligne")).toBeTruthy();
  });
});
