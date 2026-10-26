-- Keep the storage contract reproducible even when the local Storage API is
-- still warming up after a database reset. This matches supabase/config.toml
-- and is safe to apply repeatedly to an existing project.

insert into storage.buckets (
  id,
  name,
  public,
  file_size_limit,
  allowed_mime_types
)
values (
  'order-photos',
  'order-photos',
  true,
  5242880,
  array['image/jpeg', 'image/jpg', 'image/png', 'image/webp']::text[]
)
on conflict (id) do update
set name = excluded.name,
    public = excluded.public,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types,
    updated_at = now();
