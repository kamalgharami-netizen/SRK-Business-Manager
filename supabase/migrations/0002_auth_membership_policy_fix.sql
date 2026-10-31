-- SRK Business Manager: allow a verified creator to add their own owner membership.
-- Apply after 0001_initial_schema.sql in the Supabase SQL Editor.

create or replace function public.is_business_creator(target_business_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.businesses b
    where b.id = target_business_id
      and b.created_by = auth.uid()
  );
$$;

revoke all on function public.is_business_creator(uuid) from public;
grant execute on function public.is_business_creator(uuid) to authenticated;

drop policy if exists "business creators can add themselves as owner"
on public.business_members;

create policy "business creators can add themselves as owner"
on public.business_members
for insert
to authenticated
with check (
  user_id = auth.uid()
  and role = 'owner'
  and public.is_business_creator(business_id)
);
