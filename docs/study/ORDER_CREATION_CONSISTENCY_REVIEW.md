# LunchSync Order Creation Consistency Review

Date: 2026-07-27
Branch: `agent/reliability-observability`
Draft PR: https://github.com/whh07151/LunchSync/pull/15

## Pain Point

`POST /api/orders` previously inserted the `orders` row and `order_items` rows with
separate Supabase requests. The service ignored an `order_items` insert error and
continued into simulated payment, so a failed item write could leave a paid order
with no line items.

## User Impact

The customer could receive a successful order response while the restaurant saw an
empty order. This also made totals, kitchen preparation, and later cancellation
hard to explain because the order header and its contents no longer agreed.

## Root Cause

The repository already contained a PostgreSQL `create_order_with_items` function,
but `OrdersService.createOrder` did not call it. That function also predated the
required `orders.restaurant_id` field, so its contract could not safely be enabled
as-is.

## Solution

- Route order-header and line-item creation through one PostgreSQL RPC.
- Pass the validated restaurant, normalized payment method, server-calculated total,
  and server-priced line items into that function.
- Let PostgreSQL roll back the whole function if any line-item insert fails.
- Return HTTP 500 without exposing a partial order when the RPC fails.
- Add a versioned migration that replaces the obsolete function signature and stores
  `restaurant_id`.

The acceptance test exercises the public HTTP sequence:

1. `POST /api/orders` while the database boundary rejects the line-item insert.
2. `GET /api/orders/today` as the same authenticated user.
3. Verify the create request fails and no partial order is visible.

Before the implementation, the test observed `201` and a visible `PAID` order.
After the implementation, it observes `500` and an empty order list.

## Key Files

- `backend/src/orders/orders.service.ts`
- `backend/src/orders/orders.consistency.spec.ts`
- `backend/scripts/migrations/2026-07-27-create-order-with-items-v2.sql`

## Technology Choice And Alternatives

PostgreSQL owns the transaction because Supabase requests made from the NestJS
service are separate database transactions.

- Chosen: one database function for the two related writes. It reuses the existing
  Supabase/PostgreSQL stack and gives real rollback semantics.
- Rejected for this slice: compensating deletion after a failed item insert. A
  process crash or failed cleanup could still leave the partial order.
- Deferred: a payment saga or reconciliation worker. That is needed for the separate
  case where Toss approval succeeds but the following database status update fails,
  but it is not necessary to fix atomic order creation.

## Validation

```powershell
cd backend
cmd /c npm test -- --runInBand
cmd /c npm run build
```

Result on 2026-07-27:

- 5 Jest suites passed.
- 21 tests passed.
- NestJS production build passed.

No live database migration was executed. Apply
`2026-07-27-create-order-with-items-v2.sql` in a reviewed non-production Supabase
environment before deploying the backend change.

## Security And Privacy Review

- User identity still comes from the authenticated server request.
- Menu prices and totals are still calculated from server-fetched menu records.
- The client cannot select `restaurant_id` or line-item prices passed to the RPC.
- The error response does not include order contents, credentials, or payment data.
- No secrets, real customer records, or payment keys were added to the test.

## Rollback

Revert the service call and the versioned migration together before deployment.
If the migration has already been applied, restore the prior function only during a
reviewed maintenance operation; do not leave the new backend calling an old
signature.

## AI Usage Scope

AI assisted with code inspection, the acceptance-test fixture, the minimal RPC
integration, and documentation. It did not execute a live payment, deploy the
backend, or apply a database migration.

## Human Verification Scope

- Review the SQL function permissions and ownership in the target Supabase project.
- Apply the migration to a non-production database before deploying the backend.
- Rehearse one forced line-item constraint failure and confirm no order row remains.
- Verify one normal `SIMULATE` order and one normal `TOSS` pending order end to end.
- Track Toss-approved/database-update-failed reconciliation as a separate reliability
  slice.
