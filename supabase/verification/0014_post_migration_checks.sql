-- Read-only post-migration verification for SRK Business Manager.
-- Run in the Supabase SQL Editor after applying migrations 0001-0014.
-- This script does not alter data, policies, functions, or schema.

-- 1. Core sync table and Row Level Security status.
select
  to_regclass('public.business_records') as business_records_table,
  coalesce((
    select c.relrowsecurity
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relname = 'business_records'
  ), false) as rls_enabled,
  coalesce((
    select c.relforcerowsecurity
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relname = 'business_records'
  ), false) as rls_forced;

-- 2. Policies currently attached to the sync table.
select policyname, permissive, roles, cmd, qual, with_check
from pg_policies
where schemaname = 'public' and tablename = 'business_records'
order by policyname;

-- 3. Entity-type constraint: confirm warehouse_transfers is allowed.
select
  conname,
  pg_get_constraintdef(oid) as constraint_definition,
  (pg_get_constraintdef(oid) like '%warehouse_transfers%') as includes_warehouse_transfers
from pg_constraint
where conrelid = 'public.business_records'::regclass
  and conname = 'business_records_entity_type_check';

-- 4. Warehouse-transfer lookup index.
select indexname, indexdef
from pg_indexes
where schemaname = 'public'
  and tablename = 'business_records'
  and indexname = 'idx_business_records_warehouse_transfers';

-- 5. Required role functions and authenticated EXECUTE grants.
select
  p.proname,
  pg_get_function_identity_arguments(p.oid) as arguments,
  has_function_privilege(
    'authenticated',
    p.oid,
    'EXECUTE'
  ) as authenticated_can_execute
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in ('current_business_role', 'can_write_business_entity')
order by p.proname;

-- 6. Show the deployed server-side write-policy function definition.
select pg_get_functiondef(
  'public.can_write_business_entity(uuid,text)'::regprocedure
) as deployed_write_policy;

-- Expected checks:
-- * business_records_table is public.business_records.
-- * rls_enabled is true.
-- * The entity constraint includes warehouse_transfers.
-- * idx_business_records_warehouse_transfers is present.
-- * current_business_role and can_write_business_entity exist.
-- * authenticated_can_execute is true for both functions.
-- * The deployed function grants writes only to the intended roles/entities.
--
-- Important: SQL Editor sessions generally run with elevated privileges and
-- are not a valid substitute for testing RLS as each signed-in application
-- user. Verify RLS through authenticated client sessions for owner/admin/
-- accountant/sales/viewer accounts before production use.
