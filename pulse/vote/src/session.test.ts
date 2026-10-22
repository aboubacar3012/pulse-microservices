import { beforeEach, describe, expect, it, vi } from "vitest";
import { getOrCreateSessionId } from "./session";

const STORAGE_KEY = "pulse_anon_session";
const VALID =
  "550e8400-e29b-41d4-a716-446655440000";

describe("getOrCreateSessionId", () => {
  beforeEach(() => {
    localStorage.clear();
    vi.restoreAllMocks();
  });

  it("réutilise un UUID déjà stocké", () => {
    localStorage.setItem(STORAGE_KEY, VALID);
    expect(getOrCreateSessionId()).toBe(VALID);
  });

  it("crée et persiste un nouvel UUID si absent", () => {
    const id = getOrCreateSessionId();
    expect(id).toMatch(
      /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
    );
    expect(localStorage.getItem(STORAGE_KEY)).toBe(id);
  });

  it("remplace une valeur invalide en localStorage", () => {
    localStorage.setItem(STORAGE_KEY, "not-a-uuid");
    const id = getOrCreateSessionId();
    expect(id).not.toBe("not-a-uuid");
    expect(localStorage.getItem(STORAGE_KEY)).toBe(id);
  });
});
