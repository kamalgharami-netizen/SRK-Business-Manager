-- Extended company onboarding profile. Existing businesses remain valid;
-- all new profile fields are nullable or have safe defaults.
alter table public.businesses
  add column if not exists business_type text,
  add column if not exists phone text,
  add column if not exists email text,
  add column if not exists address text,
  add column if not exists city text,
  add column if not exists district text,
  add column if not exists postal_code text,
  add column if not exists state_name text,
  add column if not exists pan text,
  add column if not exists gst_registration_type text;

alter table public.businesses
  add constraint businesses_business_type_check
  check (business_type is null or business_type in
    ('proprietorship','partnership','llp','private_limited','public_limited','trust','society','other'));

alter table public.businesses
  add constraint businesses_gst_registration_type_check
  check (gst_registration_type is null or gst_registration_type in
    ('regular','composition','casual','non_resident','unregistered'));

create policy "owners and admins can update business profile"
on public.businesses for update to authenticated
using (
  exists (
    select 1 from public.business_members bm
    where bm.business_id = businesses.id and bm.user_id = auth.uid()
      and bm.role in ('owner', 'admin')
  )
)
with check (
  exists (
    select 1 from public.business_members bm
    where bm.business_id = id and bm.user_id = auth.uid()
      and bm.role in ('owner', 'admin')
  )
);

grant update on public.businesses to authenticated;
