-- Public buckets already allow downloads through public object URLs. A broad
-- SELECT policy on storage.objects additionally permits clients to list every
-- object in the bucket, which is unnecessary for LunchSync.

drop policy if exists order_photos_public_read
on storage.objects;
