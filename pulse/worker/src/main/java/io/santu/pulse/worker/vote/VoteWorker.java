package io.santu.pulse.worker.vote;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.dao.DataAccessException;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Component;

import java.time.Duration;
import java.util.Optional;

@Component
public class VoteWorker implements ApplicationRunner {

    private static final Logger logger = LoggerFactory.getLogger(VoteWorker.class);
    private static final String VOTES_QUEUE = "votes";
    private static final Duration QUEUE_TIMEOUT = Duration.ofSeconds(5);
    private static final Duration RETRY_DELAY = Duration.ofSeconds(2);

    private final StringRedisTemplate redis;
    private final JdbcTemplate jdbcTemplate;
    private final VotePayloadParser payloadParser;
    private final Duration queueTimeout;
    private final Duration retryDelay;

    public VoteWorker(
            StringRedisTemplate redis,
            JdbcTemplate jdbcTemplate,
            VotePayloadParser payloadParser
    ) {
        this(redis, jdbcTemplate, payloadParser, QUEUE_TIMEOUT, RETRY_DELAY);
    }

    VoteWorker(
            StringRedisTemplate redis,
            JdbcTemplate jdbcTemplate,
            VotePayloadParser payloadParser,
            Duration queueTimeout,
            Duration retryDelay
    ) {
        this.redis = redis;
        this.jdbcTemplate = jdbcTemplate;
        this.payloadParser = payloadParser;
        this.queueTimeout = queueTimeout;
        this.retryDelay = retryDelay;
    }

    @Override
    public void run(ApplicationArguments args) {
        if (!ensureSchema()) {
            return;
        }

        logger.info("santu-pulse-worker prêt");
        while (!Thread.currentThread().isInterrupted()) {
            String payload;
            try {
                payload = redis.opsForList().rightPop(VOTES_QUEUE, queueTimeout);
            } catch (DataAccessException ex) {
                logger.error("erreur Redis; nouvelle tentative", ex);
                if (!pauseBeforeRetry()) {
                    return;
                }
                continue;
            }

            if (payload == null) {
                continue;
            }

            try {
                processPayload(payload);
            } catch (DataAccessException ex) {
                logger.error("erreur Postgres; nouvelle tentative", ex);
                if (!pauseBeforeRetry()) {
                    return;
                }
                if (!ensureSchema()) {
                    return;
                }
            }
        }
    }

    boolean processPayload(String payload) {
        Optional<Vote> vote = payloadParser.parse(payload);
        if (vote.isEmpty()) {
            logger.warn("vote ignoré: payload invalide ou outil non autorisé");
            return false;
        }

        Vote parsed = vote.get();
        jdbcTemplate.update(
                "INSERT INTO votes (tool, session_id) VALUES (?, ?)",
                parsed.tool(),
                parsed.sessionId()
        );
        logger.info("vote enregistré: {}", parsed.tool());
        return true;
    }

    private boolean ensureSchema() {
        while (!Thread.currentThread().isInterrupted()) {
            try {
                jdbcTemplate.execute("""
                        CREATE TABLE IF NOT EXISTS votes (
                          id BIGSERIAL PRIMARY KEY,
                          tool TEXT NOT NULL,
                          created_at TIMESTAMPTZ DEFAULT NOW()
                        )
                        """);
                jdbcTemplate.execute(
                        "ALTER TABLE votes ADD COLUMN IF NOT EXISTS session_id TEXT"
                );
                jdbcTemplate.execute(
                        "CREATE INDEX IF NOT EXISTS idx_votes_tool ON votes (tool)"
                );
                jdbcTemplate.execute(
                        "CREATE INDEX IF NOT EXISTS idx_votes_session ON votes (session_id)"
                );
                return true;
            } catch (DataAccessException ex) {
                logger.error("attente Postgres pendant l'initialisation du schéma", ex);
                if (!pauseBeforeRetry()) {
                    return false;
                }
            }
        }
        return false;
    }

    private boolean pauseBeforeRetry() {
        try {
            Thread.sleep(retryDelay);
            return true;
        } catch (InterruptedException ex) {
            Thread.currentThread().interrupt();
            return false;
        }
    }
}
