-- Keep server-side role permissions aligned with the local sync policy.
-- Advance allocations are required to sync receipts/payments applied to invoices.

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
