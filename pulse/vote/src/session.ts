const STORAGE_KEY = "pulse_anon_session";

const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function createSessionId(): string {
  if (typeof crypto !== "undefined" && "randomUUID" in crypto) {
    return crypto.randomUUID();
  }
  return "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace(/[xy]/g, (c) => {
    const r = (Math.random() * 16) | 0;
    const v = c === "x" ? r : (r & 0x3) | 0x8;
    return v.toString(16);
  });
}

function isValidSessionId(value: string): boolean {
  return UUID_RE.test(value);
}

/** Identifiant navigateur opaque — survit au refresh via localStorage. */
export function getOrCreateSessionId(): string {
  try {
    const existing = localStorage.getItem(STORAGE_KEY);
    if (existing && isValidSessionId(existing)) {
      return existing;
    }
  } catch {
    // ignore
  }

  const sessionId = createSessionId();
  try {
    localStorage.setItem(STORAGE_KEY, sessionId);
  } catch {
    // ignore
  }
  return sessionId;
}
