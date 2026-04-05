# lunchsync-api

Spring Boot backend API for LunchSync milestone 1.

## Run (without wrapper jar in this repo)
Use local Gradle installation:
```bash
gradle bootRun
```

## Optional: regenerate wrapper locally
If your team wants `./gradlew`, run once on a machine with Gradle installed:
```bash
gradle wrapper --gradle-version 8.10.2
```

## Test
```bash
gradle test
```

## Notes
- Mock user header: `X-Mock-User-Id`
- Default current user id: `1`
- H2 console: `/h2-console`
