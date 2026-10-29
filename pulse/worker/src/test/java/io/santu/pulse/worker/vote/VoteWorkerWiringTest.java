package io.santu.pulse.worker.vote;

import org.junit.jupiter.api.Test;
import org.springframework.context.annotation.AnnotationConfigApplicationContext;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.jdbc.core.JdbcTemplate;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;

class VoteWorkerWiringTest {

    @Test
    void springUsesTheAutowiredConstructorWhenMultipleConstructorsExist() {
        try (AnnotationConfigApplicationContext context =
                     new AnnotationConfigApplicationContext()) {
            context.registerBean(StringRedisTemplate.class, () -> mock(StringRedisTemplate.class));
            context.registerBean(JdbcTemplate.class, () -> mock(JdbcTemplate.class));
            context.registerBean(VotePayloadParser.class, () ->
                    new VotePayloadParser(new com.fasterxml.jackson.databind.ObjectMapper()));
            context.register(VoteWorker.class);

            context.refresh();

            assertThat(context.getBean(VoteWorker.class)).isNotNull();
        }
    }
}
