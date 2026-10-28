package io.santu.pulse.worker.vote;

import java.util.Set;

public final class VoteTools {

    public static final Set<String> ALLOWED = Set.of(
            "docker",
            "ansible",
            "kubernetes",
            "linux",
            "git",
            "terraform",
            "jenkins",
            "aws"
    );

    private VoteTools() {
    }
}
