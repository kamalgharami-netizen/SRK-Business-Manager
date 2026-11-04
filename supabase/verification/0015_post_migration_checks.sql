-- Run after applying supabase/migrations/0015_extended_business_onboarding.sql.
-- This script is read-only and raises an error if required schema objects are missing.
do $$
declare
  required_column text;
  required_columns text[] := array[
    'business_type', 'phone', 'email', 'address', 'city',
    'district', 'postal_code', 'state_name', 'pan',
    'gst_registration_type'
  ];
begin
  foreach required_column in array required_columns loop
    if not exists (
      select 1
      from information_schema.columns
      where table_schema = 'public'
        and table_name = 'businesses'
        and column_name = required_column
    ) then
      raise exception 'Migration 0015 check failed: missing public.businesses.%', required_column;
    end if;
  end loop;

  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.businesses'::regclass
      and conname = 'businesses_business_type_check'
  ) then
    raise exception 'Migration 0015 check failed: business type constraint is missing';
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.businesses'::regclass
      and conname = 'businesses_gst_registration_type_check'
  ) then
    raise exception 'Migration 0015 check failed: GST registration type constraint is missing';
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'businesses'
      and policyname = 'owners and admins can update business profile'
      and cmd = 'UPDATE'
  ) then
    raise exception 'Migration 0015 check failed: owner/admin update policy is missing';
  end if;
end
$$;

select
  column_name,
  data_type,
  is_nullable
from information_schema.columns
where table_schema = 'public'
  and table_name = 'businesses'
  and column_name in (
    'business_type', 'phone', 'email', 'address', 'city',
    'district', 'postal_code', 'state_name', 'pan',
    'gst_registration_type'
  )
order by column_name;
