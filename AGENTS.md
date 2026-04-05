# Agent Guidelines for LunchSync

## Scope Control Rules
- Preserve the working skeleton order at all times:
  1) login/profile
  2) invite/member join
  3) lunch session creation
  4) AI recommendation with reasons
  5) voting
  6) restaurant confirmation
  7) later milestones: menu/order/payment simulation
  8) later milestones: owner app/POS sync
- Do not implement later milestones before earlier flow is end-to-end.
- Keep scope minimal and student-friendly.
- Prefer boring/simple code over abstraction-heavy designs.

## Tech and Architecture Guardrails
- Do not introduce major infra/framework changes without strong written reason.
- Keep repository as a monorepo; only `backend/api` is a runnable Spring Boot project for now.
- Avoid advanced infrastructure additions (CI/CD, brokers, orchestration, cloud deployment) at this stage.

## Backend Feature Ownership Areas
- `auth`, `profile`: login/profile owner
- `invite`, `session`: collaboration flow owner
- `recommendation`, `vote`, `decision`: recommendation/voting owner
- `common`, docs consistency: integration owner

## Documentation Discipline
- Always update docs when endpoint contracts or behavior change.
- Keep `docs/api-milestone-1.md`, `docs/milestone-1-scope.md`, and root `README.md` in sync.
