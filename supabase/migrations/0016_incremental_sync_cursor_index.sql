-- Supports stable keyset pagination for incremental business-record pulls.
-- The cursor must order by both updated_at and record_id so records sharing
-- the same timestamp are not skipped between pages.
create index if not exists idx_business_records_incremental_pull
  on public.business_records (business_id, entity_type, updated_at, record_id);
