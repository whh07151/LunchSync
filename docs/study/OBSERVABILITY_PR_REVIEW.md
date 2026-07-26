# LunchSync Observability PR Review

Date: 2026-07-26
Branch: `agent/reliability-observability`
Draft PR: https://github.com/whh07151/LunchSync/pull/15

## Pain Point

LunchSync already had core lunch-ordering flows, but incident diagnosis still depended on ad hoc console output and manual reproduction.
When a mobile payment, vote, or POS request failed, there was no stable request identifier or runtime snapshot to connect user reports with backend behavior.

## User Impact

The PR adds a small reliability layer so failures can be explained faster:

- Every HTTP response receives an `x-request-id`.
- Backend logs include method, path, status code, duration, and request ID.
- A runtime endpoint reports process health without exposing environment variables or secrets.

## Implementation Map

- `backend/src/observability/request-logging.middleware.ts`
  - Resolves an incoming `x-request-id` or generates a UUID.
  - Writes structured JSON logs after the response finishes.
  - Uses log level by status class: normal log for 2xx/3xx, warn for 4xx, error for 5xx.
- `backend/src/observability/observability.service.ts`
  - Builds a coarse runtime snapshot with uptime, Node version, memory, and event loop utilization.
  - Avoids database credentials, headers, request bodies, and user data.
- `backend/src/observability/observability.controller.ts`
  - Exposes `GET /api/observability/runtime`.
  - Skips throttling so a health poll does not consume user-facing API quota.
- `backend/src/app.module.ts`
  - Registers `ObservabilityModule`.
  - Applies `RequestLoggingMiddleware` to all routes.

## Technology Choice

This PR stays inside NestJS primitives instead of adding a full telemetry stack.
That is the correct first step for this repository because the immediate gap is correlation and runtime visibility, not long-term metrics storage.
OpenTelemetry, Prometheus, or log shipping can be added later after the request shape and health contract are stable.

## Validation

Previously run on this branch:

```powershell
cmd /c npm test -- --runInBand
cmd /c npm run build
```

Focused test files:

- `backend/src/observability/request-logging.middleware.spec.ts`
- `backend/src/observability/observability.service.spec.ts`

## Security And Privacy Review

- No secrets are logged.
- No request body, authorization header, cookie, or user profile field is logged.
- Runtime output is intentionally coarse and process-level.
- If this endpoint is exposed beyond a trusted environment, the next hardening step is to place it behind internal auth or infrastructure-level allowlisting.

## Rollback

Revert the observability module registration in `backend/src/app.module.ts` and remove the `backend/src/observability/` folder.
The change is isolated and does not alter business database schema or payment behavior.

## Interview Notes

The strongest explanation is operational:

> I added the smallest useful observability layer first: request correlation and runtime health. It gives maintainers enough evidence to debug payment, vote, and POS failures without committing the project to a large monitoring platform too early.

Follow-up topics to discuss:

- Why request IDs are more useful than raw logs during incident triage.
- Why response-finish logging captures the final status code accurately.
- How the endpoint could evolve into Prometheus metrics or OpenTelemetry traces.
- Why sensitive fields were deliberately excluded from logs.
