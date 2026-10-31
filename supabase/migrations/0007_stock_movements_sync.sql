-- Enable cloud synchronisation for stock ledger movements.
-- Apply after migrations 0001 through 0006.

alter table public.business_records
  drop constraint if exists business_records_entity_type_check;

alter table public.business_records
  add constraint business_records_entity_type_check
  check (entity_type in ('parties', 'products', 'expenses', 'invoices', 'payments', 'stock_movements'));

create index if not exists idx_business_records_stock_movements
  on public.business_records(business_id, record_id)
  where entity_type = 'stock_movements';
