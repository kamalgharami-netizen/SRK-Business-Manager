-- Enable owner/admin-only bidirectional sync for the business profile.
-- Apply after migrations 0001 through 0010.

alter table public.business_records
  drop constraint if exists business_records_entity_type_check;

alter table public.business_records
  add constraint business_records_entity_type_check
  check (entity_type in (
    'business_profile',
    'parties',
    'products',
    'expenses',
    'invoices',
    'payments',
    'stock_movements',
    'payment_allocations'
  ));

create index if not exists idx_business_records_business_profile
  on public.business_records(business_id, record_id)
  where entity_type = 'business_profile';

create or replace function public.can_write_business_entity(
  target_business_id uuid,
  target_entity_type text
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select case public.current_business_role(target_business_id)
    when 'owner' then true
    when 'admin' then true
    when 'accountant' then target_entity_type in (
      'parties', 'products', 'expenses', 'invoices', 'payments',
      'payment_allocations', 'stock_movements'
    )
    when 'sales' then target_entity_type in (
      'parties', 'products', 'invoices', 'payments', 'payment_allocations'
    )
    else false
  end;
$$;

revoke all on function public.can_write_business_entity(uuid, text) from public;
grant execute on function public.can_write_business_entity(uuid, text) to authenticated;
