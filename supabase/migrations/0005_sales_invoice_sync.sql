-- Enable cloud sync for sales invoices and their line items.
-- Apply after migrations 0001 through 0004.

alter table public.business_records
  drop constraint if exists business_records_entity_type_check;

alter table public.business_records
  add constraint business_records_entity_type_check
  check (entity_type in ('parties', 'products', 'expenses', 'invoices'));

create index if not exists idx_business_records_invoices
  on public.business_records(business_id, record_id)
  where entity_type = 'invoices';
