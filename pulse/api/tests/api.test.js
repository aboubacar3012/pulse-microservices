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

const { app, TOOLS, SESSION_ID_RE, sessionKey, emptySessionVotes } = require("../src/index");

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

  test("répond 503 si Postgres échoue", async () => {
    mockQuery.mockRejectedValue(new Error("db down"));

    const res = await request(app).get("/results");
    expect(res.status).toBe(503);
    expect(res.body.error).toMatch(/indisponible/i);
  });
});
