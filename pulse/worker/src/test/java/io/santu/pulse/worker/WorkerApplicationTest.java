package io.santu.pulse.worker;

import org.junit.jupiter.api.Test;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.WebApplicationType;

import static org.mockito.Mockito.mockConstruction;
import static org.mockito.Mockito.verify;

class WorkerApplicationTest {

    @Test
    void startsAsANonWebApplication() {
        String[] args = {"--spring.main.banner-mode=off"};

        try (var applications = mockConstruction(SpringApplication.class)) {
            WorkerApplication.main(args);

            SpringApplication application = applications.constructed().getFirst();
            verify(application).setWebApplicationType(WebApplicationType.NONE);
            verify(application).run(args);
        }
    }
}
