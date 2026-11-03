-- Remote migration version assigned by the project-scoped Supabase MCP.
-- pg-delta currently normalizes service-role grants and does not preserve every
-- explicit revoke from the declarative source. Keep this small reviewed
-- migration after the generated baseline so the effective privileges are
-- deterministic on every reset.

revoke all on all tables in schema public
from public, anon, authenticated, service_role;

grant select, insert, update, delete
on table
  public.users,
  public.restaurants,
  public.menu_items,
  public.sessions,
  public.session_members,
  public.invitations,
  public.votes,
  public.cart_items,
  public.orders,
  public.order_items,
  public.notifications,
  public.friends,
  public.pos_seats,
  public.pos_reservations,
  public.tournament_results
to service_role;

revoke all on function public.set_restaurants_updated_at()
from public, anon, authenticated;

revoke all on function public.set_orders_updated_at()
from public, anon, authenticated;

revoke all on function public.create_session_with_host_member(
  text,
  uuid,
  timestamptz,
  integer,
  integer,
  integer,
  text,
  numeric,
  numeric
) from public, anon, authenticated;

revoke all on function public.delete_session_cascade(uuid)
from public, anon, authenticated;

revoke all on function public.create_order_with_items(
  uuid,
  uuid,
  uuid,
  integer,
  text,
  json
) from public, anon, authenticated;

revoke all on function public.check_schema_resources()
from public, anon, authenticated;

grant execute on function public.create_session_with_host_member(
  text,
  uuid,
  timestamptz,
  integer,
  integer,
  integer,
  text,
  numeric,
  numeric
) to service_role;

grant execute on function public.delete_session_cascade(uuid)
to service_role;

grant execute on function public.create_order_with_items(
  uuid,
  uuid,
  uuid,
  integer,
  text,
  json
) to service_role;

grant execute on function public.check_schema_resources()
to service_role;

create policy order_photos_public_read
on storage.objects
for select
to anon, authenticated
using (bucket_id = 'order-photos');
