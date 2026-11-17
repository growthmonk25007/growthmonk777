-- GrowthMonk phase 2: every other module stored as JSON documents per workspace.
-- Run after schema.sql. Flexible on purpose while the app's shapes settle; split into typed columns later.
do $$
declare t text;
begin
  foreach t in array array['tickets','forms','landing_pages','campaigns','segments','automations','surveys','kb_articles'] loop
    execute format($f$
      create table if not exists public.%1$I (
        id text primary key,
        workspace_id uuid not null references public.workspaces(id) on delete cascade,
        data jsonb not null default '{}'::jsonb,
        created_at timestamptz not null default now(),
        updated_at timestamptz not null default now()
      );
      create index if not exists %1$s_ws on public.%1$I(workspace_id);
      alter table public.%1$I enable row level security;
      drop policy if exists %1$s_all on public.%1$I;
      create policy %1$s_all on public.%1$I for all using (is_member(workspace_id)) with check (is_member(workspace_id));
    $f$, t);
  end loop;
end $$;

-- Form and landing-page submissions from the public (not signed in)
create table if not exists public.form_submissions (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  form_id text not null,
  source text,                -- 'form' or 'landing_page:<slug>'
  data jsonb not null,
  contact_id uuid references public.contacts(id) on delete set null,
  created_at timestamptz not null default now()
);
create index if not exists form_submissions_ws on public.form_submissions(workspace_id);
alter table public.form_submissions enable row level security;
drop policy if exists fs_read on public.form_submissions;
create policy fs_read on public.form_submissions for select using (is_member(workspace_id));

-- Public entry point: only accepts submissions for a form that exists; creates a Lead contact.
create or replace function public.submit_form(p_form_id text, p_source text, p_data jsonb)
returns uuid language plpgsql security definer set search_path = public as $$
declare ws uuid; cid uuid;
begin
  select workspace_id into ws from forms where id = p_form_id;
  if ws is null then raise exception 'unknown form'; end if;
  if coalesce(p_data->>'email','') !~* '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'invalid email'; end if;
  select id into cid from contacts where workspace_id = ws and lower(email) = lower(p_data->>'email') limit 1;
  if cid is null then
    insert into contacts(workspace_id, first_name, last_name, email, phone, lifecycle_stage, last_activity_at)
    values (ws, left(p_data->>'first_name',100), left(p_data->>'last_name',100), left(p_data->>'email',200), left(p_data->>'phone',40), 'Lead', now())
    returning id into cid;
  else
    update contacts set last_activity_at = now() where id = cid;
  end if;
  insert into form_submissions(workspace_id, form_id, source, data, contact_id) values (ws, p_form_id, left(p_source,120), p_data, cid);
  -- Count the submission here, once, so the app never adds its own +1 in Supabase mode (a submission also counts as a view)
  update forms set data = data || jsonb_build_object(
      'subs', (case when data->>'subs' ~ '^\d+$' then (data->>'subs')::int else 0 end) + 1,
      'views', (case when data->>'views' ~ '^\d+$' then (data->>'views')::int else 0 end) + 1),
    updated_at = now()
  where id = p_form_id;
  return cid;
end; $$;
grant execute on function public.submit_form(text, text, jsonb) to anon, authenticated;
