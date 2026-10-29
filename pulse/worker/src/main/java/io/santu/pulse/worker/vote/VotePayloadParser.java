package io.santu.pulse.worker.vote;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.stereotype.Component;

import java.util.Locale;
import java.util.Optional;

@Component
public class VotePayloadParser {

    private final ObjectMapper objectMapper;

    public VotePayloadParser(ObjectMapper objectMapper) {
        this.objectMapper = objectMapper;
    }

    public Optional<Vote> parse(String payload) {
        if (payload == null) {
            return Optional.empty();
        }

        JsonNode data;
        try {
            data = objectMapper.readTree(payload);
        } catch (JsonProcessingException ex) {
            return Optional.empty();
        }

        if (data == null || !data.isObject()) {
            return Optional.empty();
        }

        String tool = text(data, "tool").map(this::normalize).orElse("");
        if (!VoteTools.ALLOWED.contains(tool)) {
            return Optional.empty();
        }

        String sessionId = text(data, "sessionId")
                .map(this::normalize)
                .filter(value -> !value.isEmpty())
                .or(() -> text(data, "session_id")
                        .map(this::normalize)
                        .filter(value -> !value.isEmpty()))
                .orElse(null);

        return Optional.of(new Vote(tool, sessionId));
    }

    private Optional<String> text(JsonNode data, String field) {
        JsonNode node = data.get(field);
        if (node == null || node.isNull()) {
            return Optional.empty();
        }
        return Optional.of(node.asText());
    }

    private String normalize(String raw) {
        return raw.strip().toLowerCase(Locale.ROOT);
    }
}
