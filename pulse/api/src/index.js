const express = require("express");
const cors = require("cors");
const Redis = require("ioredis");
const { Pool } = require("pg");
const swaggerUi = require("swagger-ui-express");
const swaggerJsdoc = require("swagger-jsdoc");

const swaggerSpec = swaggerJsdoc({
  definition: {
    openapi: "3.0.3",
    info: {
      title: "Santu Pulse API",
      version: "1.0.0",
    },
    servers: [{ url: "http://localhost:3000" }],
    paths: {
      "/health": {
        get: {
          tags: ["health"],
          summary: "Santé de l'API",
          responses: {
            200: { description: "OK" },
          },
        },
      },
      "/tools": {
        get: {
          tags: ["vote"],
          summary: "Liste des outils votables",
          responses: { 200: { description: "Liste des outils" } },
        },
      },
      "/session/{sessionId}": {
        get: {
          tags: ["vote"],
          summary: "Compteurs d'une session",
          parameters: [
            {
              name: "sessionId",
              in: "path",
              required: true,
              schema: { type: "string", format: "uuid" },
            },
          ],
          responses: {
            200: { description: "Compteurs session" },
            400: { description: "sessionId invalide" },
            503: { description: "Redis indisponible" },
          },
        },
      },
      "/vote": {
        post: {
          tags: ["vote"],
          summary: "Enregistrer un vote",
          requestBody: {
            required: true,
            content: {
              "application/json": {
                schema: {
                  type: "object",
                  required: ["tool", "sessionId"],
                  properties: {
                    tool: {
                      type: "string",
                      enum: ["docker","ansible","kubernetes","linux","git","terraform","jenkins","aws"],
                    },
                    sessionId: { type: "string", format: "uuid" },
                  },
                },
              },
            },
          },
          responses: {
            202: { description: "Vote accepté" },
            400: { description: "Entrée invalide" },
            503: { description: "Redis indisponible" },
          },
        },
      },
      "/results": {
        get: {
          tags: ["results"],
          summary: "Totaux globaux",
          responses: {
            200: { description: "Résultats agrégés" },
            503: { description: "Postgres indisponible" },
          },
        },
      },
    },
  },
  apis: ["./src/index.js"], // ou un fichier openapi.yaml
});

const TOOLS = [
  "docker",
  "ansible",
  "kubernetes",
  "linux",
  "git",
  "terraform",
  "jenkins",
  "aws",
];

const PORT = Number(process.env.PORT || 3000);
const REDIS_HOST = process.env.REDIS_HOST || "localhost";
const REDIS_PORT = Number(process.env.REDIS_PORT || 6379);
const DATABASE_URL =
  process.env.DATABASE_URL ||
  "postgres://pulse:pulse@localhost:5432/pulse";
const VOTES_QUEUE = "votes";
const SESSION_TTL_SEC = Number(process.env.SESSION_TTL_SEC || 60 * 60 * 24 * 7);
const SESSION_ID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

const app = express();
app.use(cors());
app.use(express.json());

function redisRetryStrategy(times) {
  return Math.min(times * 200, 3000);
}

// const redis = new Redis({
//   host: REDIS_HOST,
//   port: REDIS_PORT,
//   maxRetriesPerRequest: null,
//   enableReadyCheck: true,
//   retryStrategy: redisRetryStrategy,
// });

const pool = new Pool({ connectionString: DATABASE_URL });

function sessionKey(sessionId) {
  return `pulse:session:${sessionId}`;
}

function emptySessionVotes() {
  return Object.fromEntries(TOOLS.map((tool) => [tool, 0]));
}

async function readSessionVotes(sessionId) {
  const raw = await redis.hgetall(sessionKey(sessionId));
  const votes = emptySessionVotes();
  for (const tool of TOOLS) {
    const n = Number(raw[tool] || 0);
    votes[tool] = Number.isFinite(n) ? n : 0;
  }
  return votes;
}

async function bumpSessionVote(sessionId, tool) {
  const key = sessionKey(sessionId);
  const count = await redis.hincrby(key, tool, 1);
  await redis.expire(key, SESSION_TTL_SEC);
  return count;
}

async function initDb() {
  await pool.query(`
    CREATE TABLE IF NOT EXISTS votes (
      id BIGSERIAL PRIMARY KEY,
      tool TEXT NOT NULL,
      created_at TIMESTAMPTZ DEFAULT NOW()
    )
  `);
  await pool.query(`
    ALTER TABLE votes
    ADD COLUMN IF NOT EXISTS session_id TEXT
  `);
  await pool.query(`
    CREATE INDEX IF NOT EXISTS idx_votes_tool ON votes (tool)
  `);
  await pool.query(`
    CREATE INDEX IF NOT EXISTS idx_votes_session ON votes (session_id)
  `);
}

app.get("/health", (_req, res) => {
  res.json({ status: "ok", service: "santu-pulse-api" });
});

app.get("/tools", (_req, res) => {
  res.json({ tools: TOOLS });
});

app.get("/session/:sessionId", async (req, res) => {
  const sessionId = String(req.params.sessionId || "").trim().toLowerCase();
  if (!SESSION_ID_RE.test(sessionId)) {
    return res.status(400).json({ error: "sessionId invalide" });
  }

  try {
    const votes = await readSessionVotes(sessionId);
    const total = Object.values(votes).reduce((a, b) => a + b, 0);
    return res.json({ sessionId, votes, total });
  } catch (err) {
    console.error("session read failed:", err.message);
    return res.status(503).json({ error: "compteurs indisponibles !!!" });
  }
});

app.post("/vote", async (req, res) => {
  const tool = String(req.body?.tool || "")
    .trim()
    .toLowerCase();
  const sessionId = String(req.body?.sessionId || "")
    .trim()
    .toLowerCase();

  if (!TOOLS.includes(tool)) {
    return res.status(400).json({
      error: "outil invalide",
      allowed: TOOLS,
    });
  }

  if (!SESSION_ID_RE.test(sessionId)) {
    return res.status(400).json({ error: "sessionId requis" });
  }

  try {
    await redis.lpush(
      VOTES_QUEUE,
      JSON.stringify({ tool, sessionId, ts: Date.now() })
    );
    await bumpSessionVote(sessionId, tool);

    const votes = await readSessionVotes(sessionId);
    const total = Object.values(votes).reduce((a, b) => a + b, 0);

    return res.status(202).json({
      accepted: true,
      tool,
      sessionId,
      sessionVotes: votes,
      sessionTotal: total,
    });
  } catch (err) {
    console.error("vote enqueue failed:", err.message);
    return res.status(503).json({ error: "file de votes indisponible" });
  }
});

app.get("/results", async (_req, res) => {
  try {
    const { rows } = await pool.query(
      `SELECT tool,
              COUNT(*)::int AS count,
              COUNT(DISTINCT session_id)::int AS voters
       FROM votes
       GROUP BY tool`
    );

    const byTool = Object.fromEntries(
      rows.map((row) => [
        row.tool,
        { count: row.count, voters: row.voters },
      ])
    );

    const results = TOOLS.map((tool) => ({
      tool,
      count: byTool[tool]?.count || 0,
      voters: byTool[tool]?.voters || 0,
    }));

    const totalVotes = results.reduce((sum, row) => sum + row.count, 0);
    const { rows: voterRows } = await pool.query(
      `SELECT COUNT(DISTINCT session_id)::int AS voters
       FROM votes
       WHERE session_id IS NOT NULL`
    );
    const totalVoters = voterRows[0]?.voters || 0;

    return res.json({ results, totalVotes, totalVoters });
  } catch (err) {
    console.error("results query failed:", err.message);
    return res.status(503).json({ error: "base de données indisponible" });
  }
});

app.get("/v3/api-docs", (_req, res) => res.json(swaggerSpec));
app.use("/swagger-ui", swaggerUi.serve, swaggerUi.setup(swaggerSpec));

async function start() {
  // for (let attempt = 1; attempt <= 30; attempt += 1) {
  //   try {
  //     await initDb();
  //     break;
  //   } catch (err) {
  //     console.warn(
  //       `attente postgres (${attempt}/30): ${err.message}`
  //     );
  //     await new Promise((r) => setTimeout(r, 2000));
  //     if (attempt === 30) throw err;
  //   }
  // }

  app.listen(PORT, () => {
    console.log(`santu-pulse-api écoute sur :${PORT}`);
  });
}

async function bootstrap() {
  try {
    await start();
  } catch (err) {
    console.error("démarrage impossible:", err);
    process.exit(1);
  }
}

if (require.main === module) {
  bootstrap();
}

module.exports = {
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
};
