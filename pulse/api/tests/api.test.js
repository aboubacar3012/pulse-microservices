const request = require("supertest");

const VALID_SESSION = "550e8400-e29b-41d4-a716-446655440000";

const mockRedis = {
  hgetall: jest.fn(),
  hincrby: jest.fn(),
  expire: jest.fn(),
  lpush: jest.fn(),
};

const mockQuery = jest.fn();

jest.mock("ioredis", () =>
  jest.fn().mockImplementation(() => mockRedis)
);

jest.mock("pg", () => ({
  Pool: jest.fn().mockImplementation(() => ({
    query: mockQuery,
  })),
}));

const {
  app,
  TOOLS,
  SESSION_ID_RE,
  sessionKey,
  emptySessionVotes,
  redisRetryStrategy,
  readSessionVotes,
  initDb,
  start,
  bootstrap,
} = require("../src/index");

describe("helpers", () => {
  test("sessionKey préfixe l'id", () => {
    expect(sessionKey("abc")).toBe("pulse:session:abc");
  });

  test("emptySessionVotes couvre tous les outils à 0", () => {
    const votes = emptySessionVotes();
    expect(Object.keys(votes)).toEqual(TOOLS);
    expect(Object.values(votes).every((n) => n === 0)).toBe(true);
  });

  test("SESSION_ID_RE accepte un UUID v4", () => {
    expect(SESSION_ID_RE.test(VALID_SESSION)).toBe(true);
    expect(SESSION_ID_RE.test("not-a-uuid")).toBe(false);
    expect(SESSION_ID_RE.test("550e8400-e29b-11d4-a716-446655440000")).toBe(
      false
    );
  });

  test("redisRetryStrategy borne le backoff", () => {
    expect(redisRetryStrategy(1)).toBe(200);
    expect(redisRetryStrategy(10)).toBe(2000);
    expect(redisRetryStrategy(100)).toBe(3000);
  });

  test("readSessionVotes ignore les valeurs non numériques", async () => {
    mockRedis.hgetall.mockResolvedValue({
      docker: "3",
      jenkins: "NaN",
      git: "oops",
    });

    const votes = await readSessionVotes(VALID_SESSION);
    expect(votes.docker).toBe(3);
    expect(votes.jenkins).toBe(0);
    expect(votes.git).toBe(0);
  });
});

describe("initDb / start / bootstrap", () => {
  beforeEach(() => {
    jest.clearAllMocks();
    jest.restoreAllMocks();
  });

  afterEach(() => {
    jest.useRealTimers();
  });

  test("initDb exécute le schéma SQL", async () => {
    mockQuery.mockResolvedValue({ rows: [] });
    await initDb();
    expect(mockQuery).toHaveBeenCalledTimes(4);
    expect(mockQuery.mock.calls[0][0]).toMatch(/CREATE TABLE IF NOT EXISTS votes/i);
    expect(mockQuery.mock.calls[1][0]).toMatch(/session_id/i);
    expect(mockQuery.mock.calls[2][0]).toMatch(/idx_votes_tool/i);
    expect(mockQuery.mock.calls[3][0]).toMatch(/idx_votes_session/i);
  });

  test("start initialise la DB puis écoute le port", async () => {
    mockQuery.mockResolvedValue({ rows: [] });
    const listenSpy = jest
      .spyOn(app, "listen")
      .mockImplementation((_port, cb) => {
        if (typeof cb === "function") cb();
        return { close: jest.fn() };
      });
    const logSpy = jest.spyOn(console, "log").mockImplementation(() => {});

    await start();

    expect(mockQuery).toHaveBeenCalled();
    expect(listenSpy).toHaveBeenCalledWith(
      expect.any(Number),
      expect.any(Function)
    );
    expect(logSpy).toHaveBeenCalledWith(
      expect.stringMatching(/santu-pulse-api écoute/)
    );
  });

  test("start réessaie si Postgres est indisponible puis démarre", async () => {
    jest.useFakeTimers();
    mockQuery
      .mockRejectedValueOnce(new Error("ECONNREFUSED"))
      .mockResolvedValue({ rows: [] });

    const listenSpy = jest
      .spyOn(app, "listen")
      .mockImplementation((_port, cb) => {
        if (typeof cb === "function") cb();
        return { close: jest.fn() };
      });
    jest.spyOn(console, "warn").mockImplementation(() => {});
    jest.spyOn(console, "log").mockImplementation(() => {});

    const pending = start();
    await jest.advanceTimersByTimeAsync(2000);
    await pending;

    expect(listenSpy).toHaveBeenCalled();
    expect(mockQuery.mock.calls.length).toBeGreaterThanOrEqual(5);
  });

  test("start échoue après 30 tentatives", async () => {
    jest.useFakeTimers();
    mockQuery.mockRejectedValue(new Error("toujours down"));
    jest.spyOn(console, "warn").mockImplementation(() => {});
    jest.spyOn(app, "listen").mockImplementation(() => ({ close: jest.fn() }));

    const pending = start();
    const expectation = expect(pending).rejects.toThrow("toujours down");
    await jest.advanceTimersByTimeAsync(30 * 2000);
    await expectation;
  });

  test("bootstrap quitte le process si start échoue", async () => {
    mockQuery.mockRejectedValue(new Error("fatal"));
    jest.spyOn(console, "warn").mockImplementation(() => {});
    jest.spyOn(console, "error").mockImplementation(() => {});
    const exitSpy = jest.spyOn(process, "exit").mockImplementation(() => {});

    // Forcer un échec immédiat (1ère tentative = dernière via mock de boucle trop long)
    // On mocke start via le chemin réel avec fake timers + 30 fails serait long ;
    // ici on appelle bootstrap après avoir fait échouer initDb 30 fois rapidement.
    jest.useFakeTimers();
    const pending = bootstrap();
    await jest.advanceTimersByTimeAsync(30 * 2000);
    await pending;

    expect(exitSpy).toHaveBeenCalledWith(1);
  });

  test("bootstrap démarre correctement", async () => {
    mockQuery.mockResolvedValue({ rows: [] });
    jest.spyOn(app, "listen").mockImplementation((_port, cb) => {
      if (typeof cb === "function") cb();
      return { close: jest.fn() };
    });
    jest.spyOn(console, "log").mockImplementation(() => {});
    const exitSpy = jest.spyOn(process, "exit").mockImplementation(() => {});

    await bootstrap();
    expect(exitSpy).not.toHaveBeenCalled();
  });
});

describe("GET /health", () => {
  test("retourne ok", async () => {
    const res = await request(app).get("/health");
    expect(res.status).toBe(200);
    expect(res.body).toEqual({
      status: "ok",
      service: "santu-pulse-api",
    });
  });
});

describe("GET /tools", () => {
  test("liste les outils autorisés", async () => {
    const res = await request(app).get("/tools");
    expect(res.status).toBe(200);
    expect(res.body.tools).toEqual(TOOLS);
    expect(res.body.tools).toContain("jenkins");
  });
});

describe("GET /session/:sessionId", () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  test("rejette un sessionId invalide", async () => {
    const res = await request(app).get("/session/invalid");
    expect(res.status).toBe(400);
    expect(res.body.error).toMatch(/sessionId/i);
  });

  test("retourne les compteurs de session", async () => {
    mockRedis.hgetall.mockResolvedValue({ docker: "2", jenkins: "1" });

    const res = await request(app).get(`/session/${VALID_SESSION}`);
    expect(res.status).toBe(200);
    expect(res.body.sessionId).toBe(VALID_SESSION);
    expect(res.body.votes.docker).toBe(2);
    expect(res.body.votes.jenkins).toBe(1);
    expect(res.body.votes.git).toBe(0);
    expect(res.body.total).toBe(3);
    expect(mockRedis.hgetall).toHaveBeenCalledWith(
      `pulse:session:${VALID_SESSION}`
    );
  });

  test("répond 503 si Redis échoue", async () => {
    mockRedis.hgetall.mockRejectedValue(new Error("down"));

    const res = await request(app).get(`/session/${VALID_SESSION}`);
    expect(res.status).toBe(503);
    expect(res.body.error).toMatch(/indisponibles/i);
  });
});

describe("POST /vote", () => {
  beforeEach(() => {
    jest.clearAllMocks();
    mockRedis.lpush.mockResolvedValue(1);
    mockRedis.hincrby.mockResolvedValue(1);
    mockRedis.expire.mockResolvedValue(1);
    mockRedis.hgetall.mockResolvedValue({ jenkins: "1" });
  });

  test("rejette un outil inconnu", async () => {
    const res = await request(app)
      .post("/vote")
      .send({ tool: "nginx", sessionId: VALID_SESSION });

    expect(res.status).toBe(400);
    expect(res.body.error).toBe("outil invalide");
    expect(res.body.allowed).toEqual(TOOLS);
    expect(mockRedis.lpush).not.toHaveBeenCalled();
  });

  test("rejette un body sans outil", async () => {
    const res = await request(app)
      .post("/vote")
      .send({ sessionId: VALID_SESSION });

    expect(res.status).toBe(400);
    expect(res.body.error).toBe("outil invalide");
  });

  test("exige un sessionId valide", async () => {
    const res = await request(app)
      .post("/vote")
      .send({ tool: "docker", sessionId: "bad" });

    expect(res.status).toBe(400);
    expect(res.body.error).toBe("sessionId requis");
  });

  test("accepte un vote et l'enqueue dans Redis", async () => {
    const res = await request(app)
      .post("/vote")
      .send({ tool: "Jenkins", sessionId: VALID_SESSION.toUpperCase() });

    expect(res.status).toBe(202);
    expect(res.body.accepted).toBe(true);
    expect(res.body.tool).toBe("jenkins");
    expect(res.body.sessionId).toBe(VALID_SESSION);
    expect(res.body.sessionVotes.jenkins).toBe(1);
    expect(res.body.sessionTotal).toBe(1);

    expect(mockRedis.lpush).toHaveBeenCalledTimes(1);
    const [queue, payload] = mockRedis.lpush.mock.calls[0];
    expect(queue).toBe("votes");
    const parsed = JSON.parse(payload);
    expect(parsed.tool).toBe("jenkins");
    expect(parsed.sessionId).toBe(VALID_SESSION);
    expect(typeof parsed.ts).toBe("number");

    expect(mockRedis.hincrby).toHaveBeenCalledWith(
      `pulse:session:${VALID_SESSION}`,
      "jenkins",
      1
    );
    expect(mockRedis.expire).toHaveBeenCalled();
  });

  test("répond 503 si la file Redis est indisponible", async () => {
    mockRedis.lpush.mockRejectedValue(new Error("queue down"));

    const res = await request(app)
      .post("/vote")
      .send({ tool: "docker", sessionId: VALID_SESSION });

    expect(res.status).toBe(503);
    expect(res.body.error).toMatch(/indisponible/i);
  });
});

describe("GET /results", () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  test("agrège les totaux et comble les outils à zéro", async () => {
    mockQuery
      .mockResolvedValueOnce({
        rows: [
          { tool: "docker", count: 5, voters: 2 },
          { tool: "jenkins", count: 3, voters: 1 },
        ],
      })
      .mockResolvedValueOnce({
        rows: [{ voters: 3 }],
      });

    const res = await request(app).get("/results");
    expect(res.status).toBe(200);
    expect(res.body.totalVotes).toBe(8);
    expect(res.body.totalVoters).toBe(3);
    expect(res.body.results).toHaveLength(TOOLS.length);

    const docker = res.body.results.find((r) => r.tool === "docker");
    const git = res.body.results.find((r) => r.tool === "git");
    expect(docker).toEqual({ tool: "docker", count: 5, voters: 2 });
    expect(git).toEqual({ tool: "git", count: 0, voters: 0 });
  });

  test("totalVoters vaut 0 si aucune ligne votants", async () => {
    mockQuery
      .mockResolvedValueOnce({ rows: [] })
      .mockResolvedValueOnce({ rows: [] });

    const res = await request(app).get("/results");
    expect(res.status).toBe(200);
    expect(res.body.totalVotes).toBe(0);
    expect(res.body.totalVoters).toBe(0);
  });

  test("répond 503 si Postgres échoue", async () => {
    mockQuery.mockRejectedValue(new Error("db down"));

    const res = await request(app).get("/results");
    expect(res.status).toBe(503);
    expect(res.body.error).toMatch(/indisponible/i);
  });
});
