# lunchsync-working-skeleton

LunchSync is a capstone project monorepo that starts with a **working skeleton**: small but runnable end-to-end flows first, then incremental expansion. Milestone 1 intentionally covers only login/profile through restaurant confirmation so a 4-person team can align quickly across customer app, owner app, POS web, and backend API.

## Working Skeleton Philosophy
We build in strict order and keep each step executable before moving forward:
1. login/profile
2. invite/member join
3. lunch session creation
4. AI recommendation with reasons (stub in milestone 1)
5. voting
6. restaurant confirmation
7. later: menu/order/payment simulation
8. later: owner app/POS sync

## Repository Tree (Current)
```text
/
  README.md
  AGENTS.md
  .gitignore
  apps/
    customer-app/README.md
    owner-app/README.md
    pos-web/README.md
  backend/
    api/   (Spring Boot Java 17 service)
  docs/
    architecture.md
    repository-ownership.md
    working-skeleton.md
    milestone-1-scope.md
    api-milestone-1.md
    local-setup.md
  seed/
    README.md
    milestone-1-sample-data.md
  infra/
    README.md
```

## What Exists Now vs Deferred
### Exists now (Milestone 1)
- Spring Boot backend API with H2
- Mock login and mock current user resolution
- Profile read/update
- Invite creation
- Session creation + retrieval
- Stub recommendation generation (3 fake restaurants)
- Vote submission
- Restaurant confirmation

### Deferred
- Menu/order/payment simulation
- Owner workflow implementation
- POS sync behavior
- Real authentication/authorization
- Production infrastructure

## Run backend/api locally
From repo root:
```bash
cd backend/api
gradle bootRun
```

Then open:
- API base: `http://localhost:8080`
- H2 console: `http://localhost:8080/h2-console`

## Milestone 1 endpoint summary
- `GET /api/v1/health`
- `POST /api/v1/auth/mock-login`
- `GET /api/v1/profile/me`
- `PUT /api/v1/profile/me`
- `POST /api/v1/invites`
- `POST /api/v1/sessions`
- `GET /api/v1/sessions/{sessionId}`
- `POST /api/v1/recommendations`
- `POST /api/v1/votes`
- `POST /api/v1/restaurant-decisions`

See `docs/api-milestone-1.md` for examples and behavior limits.
