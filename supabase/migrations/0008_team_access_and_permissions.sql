-- Enforce a maximum of ten business accounts and role-based cloud writes.
-- Apply after migrations 0001 through 0007.

create or replace function public.current_business_role(target_business_id uuid)
returns text language sql stable security definer set search_path=public as $$
 select role from public.business_members
 where business_id=target_business_id and user_id=auth.uid() limit 1;
$$;

create or replace function public.can_write_business_entity(target_business_id uuid,target_entity_type text)
returns boolean language sql stable security definer set search_path=public as $$
 select case public.current_business_role(target_business_id)
  when 'owner' then true
  when 'admin' then true
  when 'accountant' then target_entity_type in ('parties','products','expenses','invoices','payments','stock_movements')
  when 'sales' then target_entity_type in ('parties','products','invoices','payments')
  else false end;
$$;

create or replace function public.enforce_business_member_limit()
returns trigger language plpgsql security definer set search_path=public as $$
declare member_count integer;
begin
 perform pg_advisory_xact_lock(hashtextextended(new.business_id::text,0));
 select count(*) into member_count from public.business_members where business_id=new.business_id;
 if member_count>=10 then
  raise exception 'BUSINESS_MEMBER_LIMIT: A business can have at most 10 user accounts.';
 end if;
 return new;
end;
$$;
drop trigger if exists trg_business_member_limit on public.business_members;
create trigger trg_business_member_limit before insert on public.business_members
for each row execute function public.enforce_business_member_limit();

create or replace function public.list_business_members(target_business_id uuid)
returns table(user_id uuid,email text,role text,created_at timestamptz)
language plpgsql stable security definer set search_path=public as $$
begin
 if not public.is_business_member(target_business_id) then raise exception 'Not authorised.'; end if;
 return query select bm.user_id,coalesce(u.email,''),bm.role,bm.created_at
 from public.business_members bm left join auth.users u on u.id=bm.user_id
 where bm.business_id=target_business_id
 order by case bm.role when 'owner' then 0 when 'admin' then 1 else 2 end,bm.created_at;
end;
$$;

create or replace function public.add_business_member(target_business_id uuid,member_email text,member_role text default 'viewer')
returns uuid language plpgsql security definer set search_path=public as $$
declare caller_role text; target_user_id uuid;
begin
 caller_role:=public.current_business_role(target_business_id);
 if caller_role not in ('owner','admin') then raise exception 'Only owner or admin can add users.'; end if;
 if member_role not in ('admin','accountant','sales','viewer') then raise exception 'Invalid role.'; end if;
 if caller_role<>'owner' and member_role='admin' then raise exception 'Only owner can grant admin.'; end if;
 select id into target_user_id from auth.users where lower(email)=lower(trim(member_email)) limit 1;
 if target_user_id is null then raise exception 'No registered account found. The person must register first.'; end if;
 insert into public.business_members(business_id,user_id,role) values(target_business_id,target_user_id,member_role);
 return target_user_id;
end;
$$;

create or replace function public.update_business_member_role(target_business_id uuid,target_user_id uuid,new_role text)
returns void language plpgsql security definer set search_path=public as $$
declare caller_role text; old_role text;
begin
 caller_role:=public.current_business_role(target_business_id);
 if caller_role not in ('owner','admin') then raise exception 'Only owner or admin can change roles.'; end if;
 if new_role not in ('admin','accountant','sales','viewer') then raise exception 'Invalid role.'; end if;
 select role into old_role from public.business_members where business_id=target_business_id and user_id=target_user_id;
 if old_role is null then raise exception 'Member not found.'; end if;
 if old_role='owner' then raise exception 'Owner role cannot be changed.'; end if;
 if caller_role<>'owner' and (old_role='admin' or new_role='admin') then raise exception 'Only owner can change admin access.'; end if;
 update public.business_members set role=new_role where business_id=target_business_id and user_id=target_user_id;
end;
$$;

create or replace function public.remove_business_member(target_business_id uuid,target_user_id uuid)
returns void language plpgsql security definer set search_path=public as $$
declare caller_role text; target_role text;
begin
 caller_role:=public.current_business_role(target_business_id);
 if caller_role not in ('owner','admin') then raise exception 'Only owner or admin can remove users.'; end if;
 if target_user_id=auth.uid() then raise exception 'You cannot remove your own account.'; end if;
 select role into target_role from public.business_members where business_id=target_business_id and user_id=target_user_id;
 if target_role is null then raise exception 'Member not found.'; end if;
 if target_role='owner' then raise exception 'Owner cannot be removed.'; end if;
 if caller_role<>'owner' and target_role='admin' then raise exception 'Only owner can remove an admin.'; end if;
 delete from public.business_members where business_id=target_business_id and user_id=target_user_id;
end;
$$;

revoke all on function public.current_business_role(uuid) from public;
revoke all on function public.can_write_business_entity(uuid,text) from public;
revoke all on function public.enforce_business_member_limit() from public;
revoke all on function public.list_business_members(uuid) from public;
revoke all on function public.add_business_member(uuid,text,text) from public;
revoke all on function public.update_business_member_role(uuid,uuid,text) from public;
revoke all on function public.remove_business_member(uuid,uuid) from public;
grant execute on function public.current_business_role(uuid) to authenticated;
grant execute on function public.can_write_business_entity(uuid,text) to authenticated;
grant execute on function public.list_business_members(uuid) to authenticated;
grant execute on function public.add_business_member(uuid,text,text) to authenticated;
grant execute on function public.update_business_member_role(uuid,uuid,text) to authenticated;
grant execute on function public.remove_business_member(uuid,uuid) to authenticated;

drop policy if exists "business members can add records" on public.business_records;
create policy "permitted roles can add business records" on public.business_records
for insert to authenticated with check (
 public.can_write_business_entity(business_id,entity_type) and (updated_by is null or updated_by=auth.uid())
);
drop policy if exists "business members can update records" on public.business_records;
create policy "permitted roles can update business records" on public.business_records
for update to authenticated
using (public.can_write_business_entity(business_id,entity_type))
with check (public.can_write_business_entity(business_id,entity_type) and (updated_by is null or updated_by=auth.uid()));
