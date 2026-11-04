-- Read-only verification for migration 0016_incremental_sync_cursor_index.sql.
-- Run after migration 0016. Raises an error if the expected index is absent
-- or its key column order differs from the stable incremental-pull cursor.
do $$
declare
  actual_columns text[];
begin
  select array_agg(a.attname order by k.ordinality)
    into actual_columns
  from pg_index i
  cross join lateral unnest(i.indkey) with ordinality as k(attnum, ordinality)
  join pg_attribute a
    on a.attrelid = i.indrelid and a.attnum = k.attnum
  where i.indrelid = 'public.business_records'::regclass
    and i.indexrelid = to_regclass('public.idx_business_records_incremental_pull')
    and k.ordinality <= i.indnkeyatts;

  if actual_columns is distinct from
    array['business_id', 'entity_type', 'updated_at', 'record_id']::text[] then
    raise exception
      'Migration 0016 check failed: expected index columns [business_id, entity_type, updated_at, record_id], got %',
      actual_columns;
  end if;
end
$$;

select indexname, indexdef
from pg_indexes
where schemaname = 'public'
  and tablename = 'business_records'
  and indexname = 'idx_business_records_incremental_pull';
