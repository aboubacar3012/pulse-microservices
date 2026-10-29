package io.santu.pulse.worker;

import com.zaxxer.hikari.HikariDataSource;
import org.springframework.boot.jdbc.DataSourceBuilder;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.core.env.Environment;

import java.net.URI;

@Configuration
public class DatabaseConfiguration {

    @Bean
    HikariDataSource dataSource(Environment environment) {
        String url = environment.getProperty("SPRING_DATASOURCE_URL");
        String username = environment.getProperty("SPRING_DATASOURCE_USERNAME");
        String password = environment.getProperty("SPRING_DATASOURCE_PASSWORD");

        if (url == null) {
            String databaseUrl = environment.getProperty("DATABASE_URL");
            if (databaseUrl == null || databaseUrl.isBlank()) {
                url = "jdbc:postgresql://localhost:5432/pulse";
            } else if (databaseUrl.startsWith("jdbc:")) {
                url = databaseUrl;
            } else {
                URI databaseUri = URI.create(databaseUrl);
                if (!"postgres".equals(databaseUri.getScheme())
                        && !"postgresql".equals(databaseUri.getScheme())) {
                    throw new IllegalArgumentException(
                            "DATABASE_URL must use postgres, postgresql, or jdbc:postgresql"
                    );
                }

                String host = databaseUri.getHost();
                if (host == null) {
                    throw new IllegalArgumentException("DATABASE_URL must include a host");
                }
                int port = databaseUri.getPort() == -1 ? 5432 : databaseUri.getPort();
                String path = databaseUri.getRawPath() == null ? "" : databaseUri.getRawPath();
                String query = databaseUri.getRawQuery() == null
                        ? ""
                        : "?" + databaseUri.getRawQuery();
                url = "jdbc:postgresql://" + host + ":" + port + path + query;

                String userInfo = databaseUri.getUserInfo();
                if (userInfo != null) {
                    int separator = userInfo.indexOf(':');
                    if (username == null) {
                        username = separator == -1 ? userInfo : userInfo.substring(0, separator);
                    }
                    if (password == null && separator != -1) {
                        password = userInfo.substring(separator + 1);
                    }
                }
            }
        }

        return DataSourceBuilder.create()
                .type(HikariDataSource.class)
                .url(url)
                .username(username == null ? "pulse" : username)
                .password(password == null ? "pulse" : password)
                .build();
    }
}
