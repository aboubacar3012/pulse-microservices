FROM maven:3.9-eclipse-temurin-21 AS builder
WORKDIR /build
COPY pom.xml .
COPY src ./src
RUN mvn -B verify

FROM eclipse-temurin:21-jre-alpine
WORKDIR /app
RUN addgroup -S app && adduser -S -G app -u 10001 app
COPY --from=builder /build/target/pulse-worker.jar ./pulse-worker.jar
USER 10001:10001
ENTRYPOINT ["java", "-jar", "/app/pulse-worker.jar"]
