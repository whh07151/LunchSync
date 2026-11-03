# LunchSync release readiness

Updated: 2026-08-22

## What this repository now verifies without touching external systems

- `backend/Dockerfile` builds the NestJS API with the repository's locked Node
  24.11.1/npm 11 toolchain in a multi-stage image,
  executes it as UID/GID `10001`, and probes `/api/ready` rather than the
  liveness-only health endpoint.
- `.github/workflows/verify.yml` runs backend install/test/build and Flutter
  test, analysis, and unsigned debug APK build on pull requests and the
  portfolio branch.
- `.github/workflows/deploy-backend.yml` has no push trigger. It first verifies
  the selected revision, then changes EC2 only when a human manually dispatches
  the workflow with `confirm_production_deployment=DEPLOY`.
- The production bootstrap rejects a missing `TOSS_SECRET_KEY` before it can
  serve payment confirmation requests.

## Local release checks

```powershell
Set-Location backend
cmd /c npm test -- --runInBand
cmd /c npm run build
docker build --file Dockerfile --tag lunchsync-backend:local .
```

The image must be started with production-only configuration supplied outside
the repository. Its health endpoint is intentionally not healthy until the
Supabase schema readiness check succeeds.

## Explicitly out of scope for this change

- No Supabase migration, remote database mutation, EC2 change, image push, or
  Toss payment was performed.
- A release AAB requires the separately managed Android upload keystore; the
  CI workflow deliberately builds only an unsigned debug APK.
- A production deployment still needs an approved commit SHA, EC2 ownership,
  configured secrets, an allowed HTTPS origin, and a human dispatch of the
  manual workflow.
