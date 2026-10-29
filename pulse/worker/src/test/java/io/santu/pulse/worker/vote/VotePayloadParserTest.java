package io.santu.pulse.worker.vote;

import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

class VotePayloadParserTest {

    private final VotePayloadParser parser = new VotePayloadParser(new ObjectMapper());

    @Test
    void parsesAndNormalizesValidVote() {
        assertThat(parser.parse("""
                {"tool":" Jenkins ","sessionId":" SID-1 "}
                """))
                .contains(new Vote("jenkins", "sid-1"));
    }

    @Test
    void acceptsSnakeCaseSessionId() {
        assertThat(parser.parse("""
                {"tool":"docker","session_id":"ABC"}
                """))
                .contains(new Vote("docker", "abc"));
    }

    @Test
    void fallsBackToSnakeCaseWhenCamelCaseIsEmpty() {
        assertThat(parser.parse("""
                {"tool":"docker","sessionId":" ","session_id":"ABC"}
                """))
                .contains(new Vote("docker", "abc"));
    }

    @Test
    void allowsMissingSessionId() {
        assertThat(parser.parse("""
                {"tool":"git"}
                """))
                .contains(new Vote("git", null));
    }

    @Test
    void acceptsEveryAllowedToolAndRejectsNullPayload() {
        VoteTools.ALLOWED.forEach(tool ->
                assertThat(parser.parse("{\"tool\":\"" + tool + "\"}"))
                        .contains(new Vote(tool, null))
        );
        assertThat(parser.parse(null)).isEmpty();
    }

    @Test
    void rejectsEmptyJsonAndJsonNull() {
        assertThat(parser.parse("")).isEmpty();
        assertThat(parser.parse("null")).isEmpty();
    }

    @Test
    void rejectsMissingNullAndNonTextToolValues() {
        assertThat(parser.parse("{}")).isEmpty();
        assertThat(parser.parse("{\"tool\":null}")).isEmpty();
        assertThat(parser.parse("{\"tool\":12}")).isEmpty();
    }

    @Test
    void acceptsMissingAndNullSessionIdsAsNull() {
        assertThat(parser.parse("{\"tool\":\"git\",\"sessionId\":null}"))
                .contains(new Vote("git", null));
        assertThat(parser.parse("{\"tool\":\"git\",\"session_id\":null}"))
                .contains(new Vote("git", null));
    }

    @Test
    void prefersANonEmptyCamelCaseSessionId() {
        assertThat(parser.parse("""
                {"tool":"aws","sessionId":"Camel","session_id":"snake"}
                """))
                .contains(new Vote("aws", "camel"));
    }

    @Test
    void usesNullForAnEmptySnakeCaseSessionId() {
        assertThat(parser.parse("""
                {"tool":"aws","sessionId":" ","session_id":" "}
                """))
                .contains(new Vote("aws", null));
    }

    @Test
    void rejectsMalformedJsonNonObjectsAndUnknownTools() {
        assertThat(parser.parse("{not-json")).isEmpty();
        assertThat(parser.parse("[\"docker\"]")).isEmpty();
        assertThat(parser.parse("{\"tool\":\"nginx\"}")).isEmpty();
    }
}
