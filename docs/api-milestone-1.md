# API Milestone 1

Base URL: `http://localhost:8080`

Mock current user resolution for `/profile/me`:
- Uses `X-Mock-User-Id` header when provided.
- Falls back to default user ID `1` when header is omitted.
- If user `1` does not exist yet, it is auto-created as `guest-1`.

## 1) GET /api/v1/health
- Purpose: basic service health check.
- Request example: none.
- Response example:
```json
{ "status": "UP", "service": "lunchsync-api" }
```
- Mocked behavior: static success payload.
- Limitations: not a deep dependency check.

## 2) POST /api/v1/auth/mock-login
- Purpose: create/find a user profile and return mock token.
- Request example:
```json
{ "displayName": "hyeonho", "email": "hyeonho@example.com" }
```
- Response example:
```json
{ "userId": 1, "displayName": "hyeonho", "accessToken": "mock-token-user-1" }
```
- Mocked behavior: no password, no real token signing.
- Limitations: not secure; testing-only identity stub.

## 3) GET /api/v1/profile/me
- Purpose: read current user profile via mock identity.
- Request example: optional `X-Mock-User-Id` header.
- Response example:
```json
{
  "userId": 1,
  "displayName": "hyeonho",
  "email": "hyeonho@example.com",
  "affiliation": "Capstone Team",
  "defaultRadiusMeters": 1200,
  "defaultBudget": 15000,
  "lunchTime": "12:30",
  "preferences": ["korean", "japanese"],
  "allergies": ["peanut"]
}
```
- Mocked behavior: defaults to user ID 1.
- Limitations: no auth/authorization checks.

## 4) PUT /api/v1/profile/me
- Purpose: update current user profile fields.
- Request example:
```json
{
  "displayName": "hyeonho",
  "affiliation": "Capstone Team",
  "defaultRadiusMeters": 1200,
  "defaultBudget": 15000,
  "lunchTime": "12:30",
  "preferences": ["korean", "japanese"],
  "allergies": ["peanut"]
}
```
- Response example: same shape as GET profile response.
- Mocked behavior: upsert-like update on current user.
- Limitations: limited validation only.

## 5) POST /api/v1/invites
- Purpose: create an invite record.
- Request example:
```json
{ "hostUserId": 1, "targetName": "dayeon" }
```
- Response example:
```json
{ "inviteId": 1, "inviteCode": "INVITE-ABC123", "status": "CREATED" }
```
- Mocked behavior: random invite code generation.
- Limitations: no invite acceptance flow yet.

## 6) POST /api/v1/sessions
- Purpose: create lunch session with members.
- Request example:
```json
{
  "hostUserId": 1,
  "title": "today lunch",
  "radiusMeters": 1200,
  "budget": 15000,
  "targetTime": "12:30",
  "memberUserIds": [1, 2, 3]
}
```
- Response example:
```json
{ "sessionId": 1, "status": "CREATED" }
```
- Mocked behavior: creates missing users for listed members.
- Limitations: no invite-to-member validation.

## 7) GET /api/v1/sessions/{sessionId}
- Purpose: fetch session details.
- Request example: `GET /api/v1/sessions/1`
- Response includes basic info, members, current status, confirmed restaurant (optional).
- Mocked behavior: pulls related members and latest decision.
- Limitations: no pagination/history.

## 8) POST /api/v1/recommendations
- Purpose: return 3 coherent stub recommendations for a session.
- Request example:
```json
{ "sessionId": 1 }
```
- Response example: array of 3 recommendations with id/name/category/price/distance/reason.
- Mocked behavior: generated in-memory from static sample set.
- Limitations: no external data, no AI model call.

## 9) POST /api/v1/votes
- Purpose: record a member vote for a restaurant.
- Request example:
```json
{ "sessionId": 1, "userId": 2, "restaurantId": 101 }
```
- Response example:
```json
{ "voteId": 1, "status": "RECORDED" }
```
- Mocked behavior: one vote record insertion.
- Limitations: duplicate vote handling is minimal.

## 10) POST /api/v1/restaurant-decisions
- Purpose: confirm final restaurant for session.
- Request example:
```json
{ "sessionId": 1, "restaurantId": 101 }
```
- Response example:
```json
{
  "sessionId": 1,
  "restaurantId": 101,
  "restaurantName": "Seoul Kitchen",
  "status": "CONFIRMED"
}
```
- Mocked behavior: confirms from known recommendation names or fallback label.
- Limitations: no lock/finalization guard against re-confirmation races.
