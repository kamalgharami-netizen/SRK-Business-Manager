-- SRK Business Manager: initial multi-tenant foundation.
-- Run only in the new Supabase project. Review before production use.

create extension if not exists pgcrypto;

create table if not exists public.businesses (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  legal_name text,
  gstin text,
  state_code char(2),
  currency_code char(3) not null default 'INR',
  financial_year_start_month smallint not null default 4
    check (financial_year_start_month between 1 and 12),
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.business_members (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null default 'owner'
    check (role in ('owner', 'admin', 'accountant', 'sales', 'viewer')),
  created_at timestamptz not null default now(),
  unique (business_id, user_id)
);

create index if not exists idx_business_members_user on public.business_members(user_id);
create index if not exists idx_business_members_business on public.business_members(business_id);

create or replace function public.is_business_member(target_business_id uuid)
returns boolean
language sql stable security definer
set search_path = public
as $$
  select exists (
    select 1 from public.business_members bm
    where bm.business_id = target_business_id and bm.user_id = auth.uid()
  );
$$;

alter table public.businesses enable row level security;
alter table public.business_members enable row level security;

create policy "members can read their businesses"
on public.businesses for select to authenticated
using (public.is_business_member(id));

create policy "authenticated users can create businesses"
on public.businesses for insert to authenticated
with check (created_by = auth.uid());

create policy "business creators can add themselves as owner"
on public.business_members for insert to authenticated
with check (
  user_id = auth.uid() and role = 'owner'
  and exists (
    select 1 from public.businesses b
    where b.id = business_id and b.created_by = auth.uid()
  )
);

create policy "members can read business membership"
on public.business_members for select to authenticated
using (public.is_business_member(business_id));

grant select, insert on public.businesses to authenticated;
grant select, insert on public.business_members to authenticated;
grant execute on function public.is_business_member(uuid) to authenticated;
