-- Enable cloud sync for receipts and payments.
-- Apply after migrations 0001 through 0005.

alter table public.business_records
  drop constraint if exists business_records_entity_type_check;

alter table public.business_records
  add constraint business_records_entity_type_check
  check (entity_type in ('parties', 'products', 'expenses', 'invoices', 'payments'));

create index if not exists idx_business_records_payments
  on public.business_records(business_id, record_id)
  where entity_type = 'payments';
