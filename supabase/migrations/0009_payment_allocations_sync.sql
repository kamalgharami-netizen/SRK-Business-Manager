-- Enable cloud synchronisation for advance-to-invoice payment allocations.
-- Apply after migrations 0001 through 0008.
--
-- 0010 aligns role permissions; this migration must also allow the entity type
-- at the database constraint level or all allocation writes are rejected.

alter table public.business_records
  drop constraint if exists business_records_entity_type_check;

alter table public.business_records
  add constraint business_records_entity_type_check
  check (entity_type in (
    'parties',
    'products',
    'expenses',
    'invoices',
    'payments',
    'stock_movements',
    'payment_allocations'
  ));

create index if not exists idx_business_records_payment_allocations
  on public.business_records(business_id, record_id)
  where entity_type = 'payment_allocations';

comment on table public.business_records is
  'Versioned business sync records; entity_type payment_allocations stores immutable advance-to-invoice allocation payloads.';
