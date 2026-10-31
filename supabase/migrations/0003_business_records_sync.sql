-- Cloud record storage for the first offline-sync entities.
-- Apply after 0001_initial_schema.sql and 0002_auth_membership_policy_fix.sql.

create table if not exists public.business_records (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  entity_type text not null check (entity_type in ('parties', 'products')),
  record_id uuid not null,
  payload jsonb not null default '{}'::jsonb,
  is_deleted boolean not null default false,
  updated_by uuid references auth.users(id) on delete set null,
  updated_at timestamptz not null default now(),
  unique (business_id, entity_type, record_id)
);

create index if not exists idx_business_records_business_updated
  on public.business_records(business_id, updated_at);

alter table public.business_records enable row level security;

create policy "business members can read records"
on public.business_records for select to authenticated
using (public.is_business_member(business_id));

create policy "business members can add records"
on public.business_records for insert to authenticated
with check (
  public.is_business_member(business_id)
  and (updated_by is null or updated_by = auth.uid())
);

create policy "business members can update records"
on public.business_records for update to authenticated
using (public.is_business_member(business_id))
with check (public.is_business_member(business_id));

grant select, insert, update on public.business_records to authenticated;
