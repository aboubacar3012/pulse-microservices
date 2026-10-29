package io.santu.pulse.worker.vote;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.springframework.dao.DataAccessResourceFailureException;
import org.springframework.data.redis.core.ListOperations;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.jdbc.core.JdbcTemplate;

import java.time.Duration;
import java.util.concurrent.atomic.AtomicInteger;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.doAnswer;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

class VoteWorkerTest {

    private final StringRedisTemplate redis = mock(StringRedisTemplate.class);
    private final ListOperations<String, String> queue = mock(ListOperations.class);
    private final JdbcTemplate jdbcTemplate = mock(JdbcTemplate.class);
    private final VoteWorker worker = new VoteWorker(
            redis,
            jdbcTemplate,
            new VotePayloadParser(new com.fasterxml.jackson.databind.ObjectMapper()),
            Duration.ZERO,
            Duration.ZERO
    );

    VoteWorkerTest() {
        when(redis.opsForList()).thenReturn(queue);
    }

    @AfterEach
    void clearInterruptFlag() {
        Thread.interrupted();
    }

    @Test
    void persistsAValidVote() {
        assertThat(worker.processPayload("""
                {"tool":"Terraform","sessionId":"S1"}
                """)).isTrue();

        verify(jdbcTemplate).update(
                "INSERT INTO votes (tool, session_id) VALUES (?, ?)",
                "terraform",
                "s1"
        );
    }

    @Test
    void supportsTheSpringInjectedConstructor() {
        VoteWorker injectedWorker = new VoteWorker(
                redis,
                jdbcTemplate,
                new VotePayloadParser(new com.fasterxml.jackson.databind.ObjectMapper())
        );

        assertThat(injectedWorker.processPayload("{\"tool\":\"git\"}")).isTrue();
        verify(jdbcTemplate).update(
                "INSERT INTO votes (tool, session_id) VALUES (?, ?)",
                "git",
                null
        );
    }

    @Test
    void ignoresInvalidVotesWithoutWritingToDatabase() {
        assertThat(worker.processPayload("""
                {"tool":"unknown"}
                """)).isFalse();

        verifyNoInteractions(jdbcTemplate);
    }

    @Test
    void initializesTheSchemaAndContinuesPollingUntilInterrupted() {
        when(queue.rightPop(eq("votes"), eq(Duration.ZERO))).thenAnswer(invocation -> {
            Thread.currentThread().interrupt();
            return null;
        });

        worker.run(null);

        verify(jdbcTemplate).execute(org.mockito.ArgumentMatchers.contains("CREATE TABLE"));
        verify(jdbcTemplate).execute(
                "ALTER TABLE votes ADD COLUMN IF NOT EXISTS session_id TEXT"
        );
        verify(jdbcTemplate).execute(
                "CREATE INDEX IF NOT EXISTS idx_votes_tool ON votes (tool)"
        );
        verify(jdbcTemplate).execute(
                "CREATE INDEX IF NOT EXISTS idx_votes_session ON votes (session_id)"
        );
        verify(queue).rightPop("votes", Duration.ZERO);
    }

    @Test
    void retriesSchemaInitializationAfterDatabaseFailure() {
        AtomicInteger schemaAttempts = new AtomicInteger();
        doAnswer(invocation -> {
            if (schemaAttempts.getAndIncrement() == 0) {
                throw new DataAccessResourceFailureException("database not ready");
            }
            return null;
        }).when(jdbcTemplate).execute(anyString());
        when(queue.rightPop(eq("votes"), eq(Duration.ZERO))).thenAnswer(invocation -> {
            Thread.currentThread().interrupt();
            return null;
        });

        worker.run(null);

        assertThat(schemaAttempts).hasValue(5);
        verify(queue).rightPop("votes", Duration.ZERO);
    }

    @Test
    void exitsWhenSchemaInitializationIsInterrupted() {
        doAnswer(invocation -> {
            Thread.currentThread().interrupt();
            throw new DataAccessResourceFailureException("database unavailable");
        }).when(jdbcTemplate).execute(anyString());

        worker.run(null);

        verifyNoInteractions(queue);
        assertThat(Thread.currentThread().isInterrupted()).isTrue();
    }

    @Test
    void exitsWithoutConnectingWhenAlreadyInterrupted() {
        Thread.currentThread().interrupt();

        worker.run(null);

        verifyNoInteractions(jdbcTemplate, queue);
        assertThat(Thread.currentThread().isInterrupted()).isTrue();
    }

    @Test
    void retriesRedisAfterAConnectionFailure() {
        AtomicInteger polls = new AtomicInteger();
        when(queue.rightPop(eq("votes"), eq(Duration.ZERO))).thenAnswer(invocation -> {
            if (polls.getAndIncrement() == 0) {
                throw new DataAccessResourceFailureException("redis unavailable");
            }
            Thread.currentThread().interrupt();
            return null;
        });

        worker.run(null);

        assertThat(polls).hasValue(2);
    }

    @Test
    void exitsWhenRedisFailureIsInterruptedDuringBackoff() {
        when(queue.rightPop(eq("votes"), eq(Duration.ZERO))).thenAnswer(invocation -> {
            Thread.currentThread().interrupt();
            throw new DataAccessResourceFailureException("redis unavailable");
        });

        worker.run(null);

        verify(queue).rightPop("votes", Duration.ZERO);
        assertThat(Thread.currentThread().isInterrupted()).isTrue();
    }

    @Test
    void recreatesSchemaAndResumesPollingAfterPersistenceFailure() {
        AtomicInteger polls = new AtomicInteger();
        when(queue.rightPop(eq("votes"), eq(Duration.ZERO))).thenAnswer(invocation -> {
            if (polls.getAndIncrement() == 0) {
                return "{\"tool\":\"docker\",\"sessionId\":\"sid\"}";
            }
            Thread.currentThread().interrupt();
            return null;
        });
        when(jdbcTemplate.update(
                "INSERT INTO votes (tool, session_id) VALUES (?, ?)",
                "docker",
                "sid"
        )).thenThrow(new DataAccessResourceFailureException("database disconnected"));

        worker.run(null);

        assertThat(polls).hasValue(2);
        verify(jdbcTemplate, org.mockito.Mockito.times(8)).execute(anyString());
        verify(jdbcTemplate).update(
                "INSERT INTO votes (tool, session_id) VALUES (?, ?)",
                "docker",
                "sid"
        );
    }

    @Test
    void exitsWhenSchemaRecoveryIsInterruptedAfterPersistenceFailure() {
        AtomicInteger schemaExecutions = new AtomicInteger();
        AtomicInteger polls = new AtomicInteger();
        when(queue.rightPop(eq("votes"), eq(Duration.ZERO))).thenAnswer(invocation -> {
            polls.incrementAndGet();
            return "{\"tool\":\"docker\"}";
        });
        when(jdbcTemplate.update(
                "INSERT INTO votes (tool, session_id) VALUES (?, ?)",
                "docker",
                null
        )).thenThrow(new DataAccessResourceFailureException("database disconnected"));
        doAnswer(invocation -> {
            if (schemaExecutions.incrementAndGet() == 5) {
                Thread.currentThread().interrupt();
                throw new DataAccessResourceFailureException("database unavailable");
            }
            return null;
        }).when(jdbcTemplate).execute(anyString());

        worker.run(null);

        assertThat(schemaExecutions).hasValue(5);
        assertThat(polls).hasValue(1);
        assertThat(Thread.currentThread().isInterrupted()).isTrue();
    }
}
