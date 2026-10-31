-- Enable cloud sync for independent expense records.
-- Apply after 0001, 0002 and 0003 migrations.

alter table public.business_records
  drop constraint if exists business_records_entity_type_check;

alter table public.business_records
  add constraint business_records_entity_type_check
  check (entity_type in ('parties', 'products', 'expenses'));

create index if not exists idx_business_records_expenses
  on public.business_records(business_id, record_id)
  where entity_type = 'expenses';
