-- The STEM Club Passport
-- Clean Supabase/PostgreSQL schema expected by portal.js.
-- Copy this raw SQL file into Supabase SQL Editor and run it once.

-- ============================================================================
-- OPTIONAL RESET FOR A BRAND-NEW, EMPTY PROJECT ONLY
-- ============================================================================
-- Do NOT run this reset after real members or events exist. It is intentionally
-- commented out so running the production schema never deletes data.
-- If a previous failed attempt left objects in an otherwise empty project,
-- uncomment this block, run it once, then comment it again before running the
-- remainder of this file.
--
-- drop table if exists public.audit_logs cascade;
-- drop table if exists public.member_badges cascade;
-- drop table if exists public.badges cascade;
-- drop table if exists public.point_transactions cascade;
-- drop table if exists public.attendance cascade;
-- drop table if exists public.events cascade;
-- drop table if exists public.memberships cascade;
-- drop table if exists public.profiles cascade;
-- drop sequence if exists public.membership_number_seq cascade;
-- drop type if exists public.check_in_status cascade;
-- drop type if exists public.event_status cascade;
-- drop type if exists public.membership_status cascade;
-- drop type if exists public.account_status cascade;
-- drop type if exists public.member_role cascade;
-- ============================================================================

create extension if not exists pgcrypto;

-- Create enum types safely when a failed attempt may already have created them.
do $$
begin
  create type public.member_role as enum ('member', 'admin');
exception when duplicate_object then null;
end $$;

do $$
begin
  create type public.account_status as enum ('active', 'suspended');
exception when duplicate_object then null;
end $$;

do $$
begin
  create type public.membership_status as enum ('active', 'inactive', 'expired');
exception when duplicate_object then null;
end $$;

-- Add required values when an old failed attempt left a differently shaped enum.
alter type public.membership_status add value if not exists 'active';
alter type public.membership_status add value if not exists 'inactive';
alter type public.membership_status add value if not exists 'expired';

do $$
begin
  create type public.event_status as enum ('draft', 'open', 'closed', 'cancelled');
exception when duplicate_object then null;
end $$;

do $$
begin
  create type public.check_in_status as enum ('checked_in', 'override');
exception when duplicate_object then null;
end $$;

create sequence if not exists public.membership_number_seq start with 1 increment by 1;

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  first_name text not null check (char_length(first_name) between 1 and 80),
  last_name text not null check (char_length(last_name) between 1 and 80),
  role public.member_role not null default 'member',
  account_status public.account_status not null default 'active',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.memberships (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null unique references public.profiles(id) on delete cascade,
  membership_number text not null unique
    default ('TSC-' || lpad(nextval('public.membership_number_seq')::text, 4, '0')),
  qr_token uuid not null unique default gen_random_uuid(),
  status public.membership_status not null default 'active',
  issued_at date not null default current_date,
  expires_at date,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint membership_number_format check (membership_number ~ '^TSC-[0-9]{4,}$'),
  constraint membership_dates_valid check (expires_at is null or expires_at >= issued_at)
);

create table public.events (
  id uuid primary key default gen_random_uuid(),
  title text not null check (char_length(title) between 1 and 160),
  description text,
  starts_at timestamptz not null,
  ends_at timestamptz,
  location text,
  status public.event_status not null default 'draft',
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint event_dates_valid check (ends_at is null or ends_at >= starts_at)
);

create table public.attendance (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.events(id) on delete cascade,
  member_id uuid not null references public.memberships(id) on delete cascade,
  checked_in_at timestamptz not null default now(),
  status public.check_in_status not null default 'checked_in',
  checked_in_by uuid not null references public.profiles(id),
  notes text,
  created_at timestamptz not null default now(),
  unique (event_id, member_id)
);

create table public.point_transactions (
  id uuid primary key default gen_random_uuid(),
  member_id uuid not null references public.memberships(id) on delete cascade,
  event_id uuid references public.events(id) on delete set null,
  amount integer not null check (amount <> 0),
  reason text not null check (char_length(reason) between 1 and 240),
  awarded_by uuid not null references public.profiles(id),
  created_at timestamptz not null default now()
);

create table public.badges (
  id uuid primary key default gen_random_uuid(),
  name text not null unique check (char_length(name) between 1 and 120),
  description text not null,
  icon_url text,
  icon_emoji text,
  category text,
  rarity text,
  criteria text,
  manual_award boolean not null default true,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now()
);

create table public.member_badges (
  id uuid primary key default gen_random_uuid(),
  member_id uuid not null references public.memberships(id) on delete cascade,
  badge_id uuid not null references public.badges(id) on delete cascade,
  reason text,
  awarded_by uuid not null references public.profiles(id),
  awarded_at timestamptz not null default now(),
  unique (member_id, badge_id)
);

create table public.audit_logs (
  id bigint generated always as identity primary key,
  action text not null,
  member_id uuid references public.memberships(id) on delete set null,
  event_id uuid references public.events(id) on delete set null,
  administrator_id uuid references public.profiles(id) on delete set null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index attendance_member_idx on public.attendance (member_id, checked_in_at desc);
create index point_transactions_member_idx on public.point_transactions (member_id, created_at desc);
create index member_badges_member_idx on public.member_badges (member_id, awarded_at desc);
create index events_starts_at_idx on public.events (starts_at desc);
create index audit_logs_created_at_idx on public.audit_logs (created_at desc);

-- True only for a signed-in, active administrator. SECURITY DEFINER avoids RLS
-- recursion when this function is used inside policies.
create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
    from public.profiles
    where id = auth.uid()
      and role = 'admin'
      and account_status = 'active'
  );
$$;

-- Supabase Auth signup creates the matching profile and membership atomically.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  created_membership_id uuid;
begin
  insert into public.profiles (id, first_name, last_name)
  values (
    new.id,
    coalesce(nullif(trim(new.raw_user_meta_data ->> 'first_name'), ''), 'Member'),
    coalesce(nullif(trim(new.raw_user_meta_data ->> 'last_name'), ''), 'Member')
  );

  insert into public.memberships (profile_id)
  values (new.id)
  returning id into created_membership_id;

  insert into public.audit_logs (action, member_id, metadata)
  values ('membership.created', created_membership_id, jsonb_build_object('source', 'registration'));

  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_user();

-- Public QR verification deliberately returns no name, email, profile ID, or QR token.
create or replace function public.public_membership_verification(token uuid)
returns table (
  membership_number text,
  status public.membership_status,
  issued_at date,
  expires_at date
)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select m.membership_number, m.status, m.issued_at, m.expires_at
  from public.memberships m
  where m.qr_token = token;
$$;

-- Private summary for the currently authenticated member only.
create or replace function public.member_summary()
returns table (
  membership_id uuid,
  membership_number text,
  qr_token uuid,
  status public.membership_status,
  issued_at date,
  expires_at date,
  stem_points bigint
)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select
    m.id,
    m.membership_number,
    m.qr_token,
    m.status,
    m.issued_at,
    m.expires_at,
    coalesce(sum(pt.amount), 0)::bigint
  from public.memberships m
  left join public.point_transactions pt on pt.member_id = m.id
  where m.profile_id = auth.uid()
  group by m.id;
$$;

-- Phone scanner RPC. The unique attendance constraint makes a repeated scan a
-- harmless duplicate. Inactive members require an explicit admin override.
create or replace function public.admin_check_in(
  token uuid,
  target_event uuid,
  override_inactive boolean default false,
  checkin_notes text default null
)
returns table (
  membership_number text,
  first_name text,
  last_name text,
  membership_status public.membership_status,
  duplicate boolean
)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  selected_membership public.memberships%rowtype;
  selected_profile public.profiles%rowtype;
  affected_rows integer;
begin
  if not public.is_admin() then
    raise exception 'Administrator access required';
  end if;

  select * into selected_membership
  from public.memberships
  where qr_token = token;

  if not found then
    raise exception 'Membership not found';
  end if;

  if selected_membership.status <> 'active' and not override_inactive then
    raise exception 'Membership is not active';
  end if;

  if not exists (select 1 from public.events where id = target_event and status = 'open') then
    raise exception 'Workshop is not open for check-in';
  end if;

  select * into selected_profile
  from public.profiles
  where id = selected_membership.profile_id;

  insert into public.attendance (
    event_id, member_id, status, checked_in_by, notes
  ) values (
    target_event,
    selected_membership.id,
    case when selected_membership.status = 'active' then 'checked_in' else 'override' end,
    auth.uid(),
    checkin_notes
  )
  on conflict (event_id, member_id) do nothing;

  get diagnostics affected_rows = row_count;

  if affected_rows = 1 then
    insert into public.audit_logs (action, member_id, event_id, administrator_id)
    values ('attendance.checked_in', selected_membership.id, target_event, auth.uid());
  end if;

  return query
  select
    selected_membership.membership_number,
    selected_profile.first_name,
    selected_profile.last_name,
    selected_membership.status,
    affected_rows = 0;
end;
$$;

-- Creates one point transaction per attendee so totals always have a history.
create or replace function public.admin_award_event_points(
  target_event uuid,
  points integer,
  award_reason text
)
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  recipient_count integer;
begin
  if not public.is_admin() then
    raise exception 'Administrator access required';
  end if;

  if points = 0 then
    raise exception 'Points cannot be zero';
  end if;

  if nullif(trim(award_reason), '') is null then
    raise exception 'A reason is required';
  end if;

  if not exists (select 1 from public.events where id = target_event) then
    raise exception 'Workshop not found';
  end if;

  insert into public.point_transactions (
    member_id, event_id, amount, reason, awarded_by
  )
  select a.member_id, target_event, points, trim(award_reason), auth.uid()
  from public.attendance a
  where a.event_id = target_event;

  get diagnostics recipient_count = row_count;

  insert into public.audit_logs (action, event_id, administrator_id, metadata)
  values (
    'points.event_award',
    target_event,
    auth.uid(),
    jsonb_build_object(
      'amount', points,
      'recipients', recipient_count,
      'reason', trim(award_reason)
    )
  );

  return recipient_count;
end;
$$;

create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create or replace function public.audit_membership_status_change()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if old.status is distinct from new.status then
    insert into public.audit_logs (action, member_id, administrator_id, metadata)
    values (
      'membership.status_changed',
      new.id,
      auth.uid(),
      jsonb_build_object('from', old.status, 'to', new.status)
    );
  end if;
  return new;
end;
$$;

create or replace function public.audit_point_transaction()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  insert into public.audit_logs (action, member_id, administrator_id, metadata)
  values (
    case when new.amount > 0 then 'points.awarded' else 'points.removed' end,
    new.member_id,
    new.awarded_by,
    jsonb_build_object('amount', new.amount, 'reason', new.reason)
  );
  return new;
end;
$$;

create or replace function public.audit_badge_award()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  insert into public.audit_logs (action, member_id, administrator_id, metadata)
  values (
    'badge.awarded',
    new.member_id,
    new.awarded_by,
    jsonb_build_object('badge_id', new.badge_id, 'reason', new.reason)
  );
  return new;
end;
$$;

drop trigger if exists profiles_set_updated_at on public.profiles;
create trigger profiles_set_updated_at before update on public.profiles
for each row execute function public.set_updated_at();

drop trigger if exists memberships_set_updated_at on public.memberships;
create trigger memberships_set_updated_at before update on public.memberships
for each row execute function public.set_updated_at();

drop trigger if exists events_set_updated_at on public.events;
create trigger events_set_updated_at before update on public.events
for each row execute function public.set_updated_at();

drop trigger if exists audit_membership_update on public.memberships;
create trigger audit_membership_update after update on public.memberships
for each row execute function public.audit_membership_status_change();

drop trigger if exists audit_point_insert on public.point_transactions;
create trigger audit_point_insert after insert on public.point_transactions
for each row execute function public.audit_point_transaction();

drop trigger if exists audit_badge_insert on public.member_badges;
create trigger audit_badge_insert after insert on public.member_badges
for each row execute function public.audit_badge_award();

-- Row Level Security
alter table public.profiles enable row level security;
alter table public.memberships enable row level security;
alter table public.events enable row level security;
alter table public.attendance enable row level security;
alter table public.point_transactions enable row level security;
alter table public.badges enable row level security;
alter table public.member_badges enable row level security;
alter table public.audit_logs enable row level security;

create policy "profiles_select_own_or_admin"
on public.profiles for select to authenticated
using (id = auth.uid() or public.is_admin());

create policy "profiles_admin_update"
on public.profiles for update to authenticated
using (public.is_admin()) with check (public.is_admin());

create policy "memberships_select_own_or_admin"
on public.memberships for select to authenticated
using (profile_id = auth.uid() or public.is_admin());

create policy "memberships_admin_update"
on public.memberships for update to authenticated
using (public.is_admin()) with check (public.is_admin());

create policy "events_select_member_or_admin"
on public.events for select to authenticated
using (status in ('open', 'closed') or public.is_admin());

create policy "events_admin_insert"
on public.events for insert to authenticated
with check (public.is_admin() and created_by = auth.uid());

create policy "events_admin_update"
on public.events for update to authenticated
using (public.is_admin()) with check (public.is_admin());

create policy "events_admin_delete"
on public.events for delete to authenticated
using (public.is_admin());

create policy "attendance_select_own_or_admin"
on public.attendance for select to authenticated
using (
  member_id in (select id from public.memberships where profile_id = auth.uid())
  or public.is_admin()
);

create policy "attendance_admin_all"
on public.attendance for all to authenticated
using (public.is_admin()) with check (public.is_admin());

create policy "points_select_own_or_admin"
on public.point_transactions for select to authenticated
using (
  member_id in (select id from public.memberships where profile_id = auth.uid())
  or public.is_admin()
);

create policy "points_admin_insert"
on public.point_transactions for insert to authenticated
with check (public.is_admin() and awarded_by = auth.uid());

create policy "badges_authenticated_select"
on public.badges for select to authenticated
using (true);

create policy "badges_admin_all"
on public.badges for all to authenticated
using (public.is_admin()) with check (public.is_admin());

create policy "member_badges_select_own_or_admin"
on public.member_badges for select to authenticated
using (
  member_id in (select id from public.memberships where profile_id = auth.uid())
  or public.is_admin()
);

create policy "member_badges_admin_insert"
on public.member_badges for insert to authenticated
with check (public.is_admin() and awarded_by = auth.uid());

create policy "audit_logs_admin_select"
on public.audit_logs for select to authenticated
using (public.is_admin());

-- Explicit API grants. RLS still decides which rows an authenticated user sees.
grant usage on schema public to anon, authenticated;
grant select on public.profiles, public.memberships, public.events,
  public.attendance, public.point_transactions, public.badges,
  public.member_badges to authenticated;
grant insert, update, delete on public.events, public.badges to authenticated;
grant update on public.profiles, public.memberships to authenticated;
grant insert, update, delete on public.attendance to authenticated;
grant insert on public.point_transactions, public.member_badges to authenticated;
grant select on public.audit_logs to authenticated;


revoke all on function public.is_admin() from public;
revoke all on function public.member_summary() from public;
revoke all on function public.admin_check_in(uuid, uuid, boolean, text) from public;
revoke all on function public.admin_award_event_points(uuid, integer, text) from public;
revoke all on function public.public_membership_verification(uuid) from public;

grant execute on function public.is_admin() to authenticated;
grant execute on function public.member_summary() to authenticated;
grant execute on function public.admin_check_in(uuid, uuid, boolean, text) to authenticated;
grant execute on function public.admin_award_event_points(uuid, integer, text) to authenticated;
grant execute on function public.public_membership_verification(uuid) to anon, authenticated;

-- After signup, promote only the intended owner from Supabase SQL Editor:
-- update public.profiles set role = 'admin' where id = 'AUTH_USER_UUID';
