package io.santu.pulse.worker;

import com.zaxxer.hikari.HikariDataSource;
import org.junit.jupiter.api.Test;
import org.springframework.mock.env.MockEnvironment;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

class DatabaseConfigurationTest {

    @Test
    void convertsTheExistingPostgresUrlToJdbcConfiguration() {
        MockEnvironment environment = new MockEnvironment()
                .withProperty("DATABASE_URL", "postgresql://pulse:secret@db:5433/pulse?sslmode=disable");

        try (HikariDataSource dataSource = new DatabaseConfiguration().dataSource(environment)) {
            assertThat(dataSource.getJdbcUrl())
                    .isEqualTo("jdbc:postgresql://db:5433/pulse?sslmode=disable");
            assertThat(dataSource.getUsername()).isEqualTo("pulse");
            assertThat(dataSource.getPassword()).isEqualTo("secret");
        }
    }

    @Test
    void usesLocalDefaultsWhenNoDatabaseVariablesAreSet() {
        try (HikariDataSource dataSource =
                     new DatabaseConfiguration().dataSource(new MockEnvironment())) {
            assertThat(dataSource.getJdbcUrl())
                    .isEqualTo("jdbc:postgresql://localhost:5432/pulse");
            assertThat(dataSource.getUsername()).isEqualTo("pulse");
            assertThat(dataSource.getPassword()).isEqualTo("pulse");
        }
    }

    @Test
    void acceptsPostgresSchemeAndUsesTheDefaultPortAndCredentials() {
        MockEnvironment environment = new MockEnvironment()
                .withProperty("DATABASE_URL", "postgres://localhost/pulse");

        try (HikariDataSource dataSource = new DatabaseConfiguration().dataSource(environment)) {
            assertThat(dataSource.getJdbcUrl()).isEqualTo("jdbc:postgresql://localhost:5432/pulse");
            assertThat(dataSource.getUsername()).isEqualTo("pulse");
            assertThat(dataSource.getPassword()).isEqualTo("pulse");
        }
    }

    @Test
    void acceptsJdbcUrlAndAppliesDefaultCredentials() {
        MockEnvironment environment = new MockEnvironment()
                .withProperty("DATABASE_URL", "jdbc:postgresql://db:5432/pulse");

        try (HikariDataSource dataSource = new DatabaseConfiguration().dataSource(environment)) {
            assertThat(dataSource.getJdbcUrl()).isEqualTo("jdbc:postgresql://db:5432/pulse");
            assertThat(dataSource.getUsername()).isEqualTo("pulse");
            assertThat(dataSource.getPassword()).isEqualTo("pulse");
        }
    }

    @Test
    void prefersExplicitSpringDatasourceProperties() {
        MockEnvironment environment = new MockEnvironment()
                .withProperty("SPRING_DATASOURCE_URL", "jdbc:postgresql://db:5432/pulse")
                .withProperty("SPRING_DATASOURCE_USERNAME", "custom")
                .withProperty("SPRING_DATASOURCE_PASSWORD", "configured");

        try (HikariDataSource dataSource = new DatabaseConfiguration().dataSource(environment)) {
            assertThat(dataSource.getJdbcUrl()).isEqualTo("jdbc:postgresql://db:5432/pulse");
            assertThat(dataSource.getUsername()).isEqualTo("custom");
            assertThat(dataSource.getPassword()).isEqualTo("configured");
        }
    }

    @Test
    void explicitCredentialsOverrideCredentialsFromDatabaseUrl() {
        MockEnvironment environment = new MockEnvironment()
                .withProperty("DATABASE_URL", "postgres://url-user:url-password@db/pulse")
                .withProperty("SPRING_DATASOURCE_USERNAME", "explicit-user")
                .withProperty("SPRING_DATASOURCE_PASSWORD", "explicit-password");

        try (HikariDataSource dataSource = new DatabaseConfiguration().dataSource(environment)) {
            assertThat(dataSource.getUsername()).isEqualTo("explicit-user");
            assertThat(dataSource.getPassword()).isEqualTo("explicit-password");
        }
    }

    @Test
    void acceptsUserInfoWithoutPassword() {
        MockEnvironment environment = new MockEnvironment()
                .withProperty("DATABASE_URL", "postgres://url-user@db/pulse");

        try (HikariDataSource dataSource = new DatabaseConfiguration().dataSource(environment)) {
            assertThat(dataSource.getUsername()).isEqualTo("url-user");
            assertThat(dataSource.getPassword()).isEqualTo("pulse");
        }
    }

    @Test
    void rejectsUnsupportedDatabaseUrlSchemes() {
        MockEnvironment environment = new MockEnvironment()
                .withProperty("DATABASE_URL", "mysql://db/pulse");

        assertThatThrownBy(() -> new DatabaseConfiguration().dataSource(environment))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("DATABASE_URL must use postgres");
    }

    @Test
    void rejectsPostgresUrlsWithoutAHost() {
        MockEnvironment environment = new MockEnvironment()
                .withProperty("DATABASE_URL", "postgres:///pulse");

        assertThatThrownBy(() -> new DatabaseConfiguration().dataSource(environment))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessage("DATABASE_URL must include a host");
    }

    @Test
    void rejectsMalformedDatabaseUrls() {
        MockEnvironment environment = new MockEnvironment()
                .withProperty("DATABASE_URL", "postgres://db:invalid/pulse");

        assertThatThrownBy(() -> new DatabaseConfiguration().dataSource(environment))
                .isInstanceOf(IllegalArgumentException.class);
    }
}
