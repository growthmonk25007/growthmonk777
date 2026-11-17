-- GrowthMonk fix: add the contact fields the app uses (safe to run more than once)
alter table public.contacts
  add column if not exists name text,
  add column if not exists company text,
  add column if not exists stage text default 'Lead',
  add column if not exists score int default 0,
  add column if not exists owner text,
  add column if not exists m int default 0,
  add column if not exists acts jsonb default '[]'::jsonb;

-- Leads created by public forms only set first/last name and lifecycle stage; fill the app fields from them
create or replace function public.contacts_fill_app_fields() returns trigger language plpgsql as $$
begin
  if new.name is null or new.name = '' then
    new.name := nullif(trim(coalesce(new.first_name,'') || ' ' || coalesce(new.last_name,'')), '');
    if new.name is null then new.name := coalesce(new.email, 'New lead'); end if;
  end if;
  if new.stage is null then new.stage := coalesce(new.lifecycle_stage, 'Lead'); end if;
  if new.acts is null or new.acts = '[]'::jsonb then new.acts := '[["Contact created", 0]]'::jsonb; end if;
  return new;
end $$;
drop trigger if exists contacts_fill_app_fields on public.contacts;
create trigger contacts_fill_app_fields before insert on public.contacts
  for each row execute function public.contacts_fill_app_fields();

notify pgrst, 'reload schema';
