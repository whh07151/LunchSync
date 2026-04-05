# Milestone 1 Scope

## Included
- Mock login
- Profile read/update
- Invite creation
- Session creation and read
- Recommendation generation (stub)
- Vote recording
- Restaurant confirmation
- Local H2-backed persistence for core entities

## Excluded
- Real auth/security
- Menu/order/payment domain
- Owner app implementation
- POS sync implementation
- External integrations and advanced infrastructure

## Deferred Risks
- Recommendation quality is stubbed and not personalized beyond simple reasons.
- No conflict/concurrency handling for concurrent voting/decision updates.
- No production-hardening concerns (security, migrations, scaling).

## Acceptance Criteria
- Backend starts locally with Java 17 and Gradle.
- All milestone 1 REST endpoints respond with documented request/response shapes.
- Session state transitions cover CREATED -> RECOMMENDING -> VOTING -> RESTAURANT_CONFIRMED.
- Documentation matches implementation behavior.
