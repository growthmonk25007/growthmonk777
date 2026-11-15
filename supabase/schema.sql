-- GrowthMonk phase 1 schema: workspaces, members, contacts, companies
create extension if not exists pgcrypto;

create table if not exists public.workspaces (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  created_by uuid references auth.users(id) default auth.uid(),
  created_at timestamptz not null default now()
);

create table if not exists public.workspace_members (
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null default 'member' check (role in ('owner','admin','member')),
  created_at timestamptz not null default now(),
  primary key (workspace_id, user_id)
);

create table if not exists public.companies (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  name text not null,
  domain text,
  industry text,
  city text,
  created_at timestamptz not null default now()
);

create table if not exists public.contacts (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  first_name text,
  last_name text,
  email text,
  phone text,
  company_id uuid references public.companies(id) on delete set null,
  lifecycle_stage text default 'Lead',
  owner_id uuid references auth.users(id),
  last_activity_at timestamptz,
  created_at timestamptz not null default now()
);

create index if not exists idx_members_user on public.workspace_members(user_id);
create index if not exists idx_companies_ws on public.companies(workspace_id);
create index if not exists idx_contacts_ws on public.contacts(workspace_id);
create index if not exists idx_contacts_company on public.contacts(company_id);

-- membership helpers (security definer avoids recursive RLS)
create or replace function public.is_member(ws uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from workspace_members where workspace_id = ws and user_id = auth.uid());
$$;
create or replace function public.is_admin(ws uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from workspace_members where workspace_id = ws and user_id = auth.uid() and role in ('owner','admin'));
$$;

-- create a workspace and make the caller its owner in one call
create or replace function public.create_workspace(ws_name text) returns uuid
language plpgsql security definer set search_path = public as $$
declare new_id uuid;
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  insert into workspaces(name, created_by) values (ws_name, auth.uid()) returning id into new_id;
  insert into workspace_members(workspace_id, user_id, role) values (new_id, auth.uid(), 'owner');
  return new_id;
end; $$;
grant execute on function public.create_workspace(text) to authenticated;

alter table public.workspaces enable row level security;
alter table public.workspace_members enable row level security;
alter table public.companies enable row level security;
alter table public.contacts enable row level security;

create policy ws_select on public.workspaces for select using (is_member(id));
create policy ws_update on public.workspaces for update using (is_admin(id));

create policy wm_select on public.workspace_members for select using (is_member(workspace_id));
create policy wm_admin_write on public.workspace_members for all using (is_admin(workspace_id)) with check (is_admin(workspace_id));

create policy co_all on public.companies for all using (is_member(workspace_id)) with check (is_member(workspace_id));
create policy ct_all on public.contacts for all using (is_member(workspace_id)) with check (is_member(workspace_id));
