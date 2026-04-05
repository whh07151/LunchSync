# Local Setup

## Required runtime
- Java 17
- Gradle 8.x (local install)

## Run backend/api
From repository root:
```bash
cd backend/api
gradle bootRun
```

Or from `backend/api`:
```bash
gradle bootRun
```

## Optional wrapper regeneration
This repository intentionally does not track `gradle-wrapper.jar` to avoid binary upload issues in constrained PR tooling.
If needed, regenerate it locally:
```bash
gradle wrapper --gradle-version 8.10.2
```

## H2 configuration
- Location: `backend/api/src/main/resources/application.yml`
- JDBC URL: `jdbc:h2:mem:lunchsync;MODE=PostgreSQL;DB_CLOSE_DELAY=-1;DB_CLOSE_ON_EXIT=FALSE`
- H2 console: `http://localhost:8080/h2-console`

## Mock current user behavior
- Header `X-Mock-User-Id` sets current user for `/api/v1/profile/me` endpoints.
- If omitted, backend defaults to user ID `1`.
- If default user does not exist, it is auto-created with safe placeholder values.
