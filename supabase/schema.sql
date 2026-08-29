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
-- drop table if exists public.outreach_campaigns cascade;
-- drop table if exists public.recognition_reports cascade;
-- drop table if exists public.recognition_reactions cascade;
-- drop table if exists public.recognitions cascade;
-- drop table if exists public.post_reports cascade;
-- drop table if exists public.post_reactions cascade;
-- drop table if exists public.community_posts cascade;
-- drop table if exists public.lesson_progress cascade;
-- drop table if exists public.resources cascade;
-- drop table if exists public.lessons cascade;
-- drop table if exists public.course_modules cascade;
-- drop table if exists public.courses cascade;
-- drop table if exists public.event_registrations cascade;
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

begin;

create sequence if not exists public.membership_number_seq start with 1 increment by 1;

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  first_name text not null check (char_length(first_name) between 1 and 80),
  last_name text not null check (char_length(last_name) between 1 and 80),
  role public.member_role not null default 'member',
  account_status public.account_status not null default 'active',
  onboarding_completed_at timestamptz,
  admin_tour_completed_at timestamptz,
  communication_consent boolean not null default false,
  communication_opted_out_at timestamptz,
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
  source_key text unique,
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
  color text not null default '#FFD500' check (color ~ '^#[0-9A-Fa-f]{6}$'),
  point_value integer not null default 0,
  criteria text,
  manual_award boolean not null default true,
  archived_at timestamptz,
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

create table public.event_registrations (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.events(id) on delete cascade,
  member_id uuid not null references public.memberships(id) on delete cascade,
  registered_at timestamptz not null default now(),
  unique (event_id, member_id)
);

create table public.courses (
  id uuid primary key default gen_random_uuid(),
  title text not null check (char_length(title) between 1 and 160),
  slug text not null unique check (slug ~ '^[a-z0-9]+(?:-[a-z0-9]+)*$'),
  summary text not null default '',
  cover_image_url text,
  access_level text not null default 'all_members' check (access_level in ('all_members', 'active_members')),
  published boolean not null default false,
  position integer not null default 0,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.course_modules (
  id uuid primary key default gen_random_uuid(),
  course_id uuid not null references public.courses(id) on delete cascade,
  title text not null check (char_length(title) between 1 and 160),
  description text not null default '',
  position integer not null default 0,
  published boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (course_id, position)
);

create table public.lessons (
  id uuid primary key default gen_random_uuid(),
  module_id uuid not null references public.course_modules(id) on delete cascade,
  title text not null check (char_length(title) between 1 and 160),
  content text not null default '' check (char_length(content) <= 50000),
  project_instructions text not null default '' check (char_length(project_instructions) <= 20000),
  video_url text check (video_url is null or video_url ~ '^https://(www[.])?(youtube[.]com|youtu[.]be|vimeo[.]com)/'),
  position integer not null default 0,
  published boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (module_id, position)
);

create table public.resources (
  id uuid primary key default gen_random_uuid(),
  lesson_id uuid not null references public.lessons(id) on delete cascade,
  title text not null check (char_length(title) between 1 and 160),
  resource_url text not null check (resource_url ~ '^https://'),
  resource_type text not null default 'link' check (resource_type in ('link', 'download', 'worksheet', 'project')),
  position integer not null default 0,
  created_at timestamptz not null default now()
);

create table public.lesson_progress (
  member_id uuid not null references public.memberships(id) on delete cascade,
  lesson_id uuid not null references public.lessons(id) on delete cascade,
  completed_at timestamptz not null default now(),
  primary key (member_id, lesson_id)
);

create table public.community_posts (
  id uuid primary key default gen_random_uuid(),
  author_id uuid not null references public.profiles(id) on delete cascade,
  title text not null check (char_length(title) between 1 and 160),
  body text not null check (char_length(body) between 1 and 5000),
  category text not null check (category in ('project', 'accomplishment', 'question', 'idea')),
  image_url text check (image_url is null or image_url ~ '^https://'),
  course_id uuid references public.courses(id) on delete set null,
  event_id uuid references public.events(id) on delete set null,
  status text not null default 'pending' check (status in ('pending', 'approved', 'hidden', 'removed')),
  moderated_by uuid references public.profiles(id) on delete set null,
  moderated_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.post_reactions (
  post_id uuid not null references public.community_posts(id) on delete cascade,
  profile_id uuid not null references public.profiles(id) on delete cascade,
  reaction text not null check (reaction in ('celebrate', 'inspiring', 'creative', 'helpful', 'teamwork')),
  created_at timestamptz not null default now(),
  primary key (post_id, profile_id)
);

create table public.post_reports (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.community_posts(id) on delete cascade,
  reporter_id uuid not null references public.profiles(id) on delete cascade,
  reason text not null check (char_length(reason) between 5 and 500),
  status text not null default 'open' check (status in ('open', 'reviewed', 'dismissed')),
  reviewed_by uuid references public.profiles(id) on delete set null,
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  unique (post_id, reporter_id)
);

create table public.recognitions (
  id uuid primary key default gen_random_uuid(),
  sender_id uuid not null references public.profiles(id) on delete cascade,
  recipient_id uuid not null references public.profiles(id) on delete cascade,
  value text not null check (value in ('creativity', 'teamwork', 'courage', 'helpfulness', 'persistence', 'leadership')),
  message text not null check (char_length(message) between 5 and 280),
  status text not null default 'pending' check (status in ('pending', 'approved', 'hidden', 'removed')),
  moderated_by uuid references public.profiles(id) on delete set null,
  moderated_at timestamptz,
  created_at timestamptz not null default now(),
  check (sender_id <> recipient_id)
);

create table public.recognition_reactions (
  recognition_id uuid not null references public.recognitions(id) on delete cascade,
  profile_id uuid not null references public.profiles(id) on delete cascade,
  reaction text not null check (reaction in ('celebrate', 'inspiring', 'creative', 'helpful', 'teamwork')),
  created_at timestamptz not null default now(),
  primary key (recognition_id, profile_id)
);

create table public.recognition_reports (
  id uuid primary key default gen_random_uuid(),
  recognition_id uuid not null references public.recognitions(id) on delete cascade,
  reporter_id uuid not null references public.profiles(id) on delete cascade,
  reason text not null check (char_length(reason) between 5 and 500),
  status text not null default 'open' check (status in ('open', 'reviewed', 'dismissed')),
  created_at timestamptz not null default now(),
  unique (recognition_id, reporter_id)
);

create table public.outreach_campaigns (
  id uuid primary key default gen_random_uuid(),
  event_id uuid references public.events(id) on delete set null,
  subject text not null,
  message text not null,
  recipient_count integer not null default 0,
  provider_message_id text unique,
  status text not null default 'draft' check (status in ('draft', 'exported', 'sent', 'failed')),
  created_by uuid not null references public.profiles(id),
  created_at timestamptz not null default now(),
  sent_at timestamptz
);

create index attendance_member_idx on public.attendance (member_id, checked_in_at desc);
create index point_transactions_member_idx on public.point_transactions (member_id, created_at desc);
create index member_badges_member_idx on public.member_badges (member_id, awarded_at desc);
create index events_starts_at_idx on public.events (starts_at desc);
create index audit_logs_created_at_idx on public.audit_logs (created_at desc);
create index community_posts_status_idx on public.community_posts (status, created_at desc);
create index recognitions_status_idx on public.recognitions (status, created_at desc);
create index lessons_module_position_idx on public.lessons (module_id, position);
create index modules_course_position_idx on public.course_modules (course_id, position);

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

-- Backfill Auth accounts that existed before this application schema. This does
-- not modify or delete auth.users. Replace the owner email placeholder before
-- running: that account is processed first and receives TSC-0001 when there are
-- no existing memberships.
do $$
declare
  owner_email constant text := 'jeremiah@thestemclub.net';
  existing_memberships bigint;
  user_record record;
begin
  select count(*) into existing_memberships from public.memberships;
  if existing_memberships = 0 then
    perform setval('public.membership_number_seq', 1, false);
  end if;

  for user_record in
    select u.* from auth.users u
    order by case when lower(u.email) = lower(owner_email) then 0 else 1 end, u.created_at, u.id
  loop
    insert into public.profiles (id, first_name, last_name)
    values (
      user_record.id,
      coalesce(nullif(trim(user_record.raw_user_meta_data ->> 'first_name'), ''), 'Member'),
      coalesce(nullif(trim(user_record.raw_user_meta_data ->> 'last_name'), ''), 'Member')
    ) on conflict (id) do nothing;

    insert into public.memberships (profile_id)
    values (user_record.id)
    on conflict (profile_id) do nothing;
  end loop;

  if owner_email = '[MY EMAIL ADDRESS]' then
    raise notice 'Owner email placeholder not replaced; no account was promoted.';
  else
    update public.profiles p set role = 'admin', account_status = 'active', updated_at = now()
    from auth.users u where u.id = p.id and lower(u.email) = lower(owner_email);
    if not found then raise exception 'No Auth user found for owner email %', owner_email; end if;
  end if;
end $$;

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
    case
      when selected_membership.status = 'active' then 'checked_in'::public.check_in_status
      else 'override'::public.check_in_status
    end,
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
    member_id, event_id, amount, reason, awarded_by, source_key
  )
  select
    a.member_id,
    target_event,
    points,
    trim(award_reason),
    auth.uid(),
    'event:' || target_event::text || ':member:' || a.member_id::text || ':amount:' || points::text || ':reason:' || md5(trim(award_reason))
  from public.attendance a
  where a.event_id = target_event
  on conflict (source_key) do nothing;
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

-- Admin-only member directory. Email is read from auth.users only inside this
-- database-authorized function and is never available to regular members.
create or replace function public.admin_member_directory()
returns table (
  membership_id uuid,
  profile_id uuid,
  membership_number text,
  first_name text,
  last_name text,
  email text,
  membership_status public.membership_status,
  account_status public.account_status,
  issued_at date,
  stem_points bigint,
  badge_count bigint,
  last_check_in timestamptz
)
language plpgsql
stable
security definer
set search_path = public, auth, pg_temp
as $$
begin
  if not public.is_admin() then raise exception 'Administrator access required'; end if;
  return query
  select m.id, p.id, m.membership_number, p.first_name, p.last_name, u.email::text,
    m.status, p.account_status, m.issued_at,
    coalesce((select sum(pt.amount) from public.point_transactions pt where pt.member_id = m.id), 0)::bigint,
    (select count(*) from public.member_badges mb where mb.member_id = m.id),
    (select max(a.checked_in_at) from public.attendance a where a.member_id = m.id)
  from public.memberships m
  join public.profiles p on p.id = m.profile_id
  join auth.users u on u.id = p.id
  order by m.membership_number;
end;
$$;

create or replace function public.admin_dashboard_stats()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  if not public.is_admin() then raise exception 'Administrator access required'; end if;
  return jsonb_build_object(
    'total_members', (select count(*) from public.memberships),
    'active_members', (select count(*) from public.memberships where status = 'active'),
    'recent_signups', (select count(*) from public.memberships where created_at >= now() - interval '30 days'),
    'upcoming_events', (select count(*) from public.events where starts_at >= now() and status <> 'cancelled'),
    'recent_attendance', (select count(*) from public.attendance where checked_in_at >= now() - interval '30 days'),
    'points_awarded', (select coalesce(sum(amount), 0) from public.point_transactions where amount > 0),
    'badges_awarded', (select count(*) from public.member_badges),
    'awaiting_moderation',
      (select count(*) from public.community_posts where status = 'pending') +
      (select count(*) from public.recognitions where status = 'pending')
  );
end;
$$;

create or replace function public.admin_attendee_contacts(target_event uuid)
returns table (membership_number text, first_name text, last_name text, email text, communication_consent boolean)
language plpgsql
stable
security definer
set search_path = public, auth, pg_temp
as $$
begin
  if not public.is_admin() then raise exception 'Administrator access required'; end if;
  return query
  select m.membership_number, p.first_name, p.last_name, u.email::text, p.communication_consent
  from public.attendance a
  join public.memberships m on m.id = a.member_id
  join public.profiles p on p.id = m.profile_id
  join auth.users u on u.id = p.id
  where a.event_id = target_event and p.communication_opted_out_at is null
  order by p.last_name, p.first_name;
end;
$$;

create or replace function public.admin_award_badge(target_member uuid, target_badge uuid, award_reason text default null)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  award_id uuid;
  badge_points integer;
  badge_name text;
begin
  if not public.is_admin() then raise exception 'Administrator access required'; end if;
  select point_value, name into badge_points, badge_name from public.badges where id = target_badge and archived_at is null;
  if not found then raise exception 'Badge not found or archived'; end if;

  insert into public.member_badges (member_id, badge_id, reason, awarded_by)
  values (target_member, target_badge, nullif(trim(award_reason), ''), auth.uid())
  on conflict (member_id, badge_id) do nothing
  returning id into award_id;

  if award_id is null then raise exception 'Member already has this badge'; end if;
  if badge_points <> 0 then
    insert into public.point_transactions (member_id, amount, reason, awarded_by, source_key)
    values (target_member, badge_points, 'Badge: ' || badge_name, auth.uid(), 'badge:' || award_id::text);
  end if;
  return award_id;
end;
$$;

create or replace function public.member_directory()
returns table (profile_id uuid, display_name text)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select p.id, p.first_name || ' ' || left(p.last_name, 1) || '.'
  from public.profiles p
  join public.memberships m on m.profile_id = p.id
  where auth.uid() is not null and p.account_status = 'active' and m.status = 'active'
  order by p.first_name, p.last_name;
$$;

create or replace function public.community_feed()
returns table (
  id uuid, title text, body text, category text, image_url text,
  author_name text, created_at timestamptz
)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select cp.id, cp.title, cp.body, cp.category, cp.image_url,
    p.first_name || ' ' || left(p.last_name, 1) || '.', cp.created_at
  from public.community_posts cp
  join public.profiles p on p.id = cp.author_id
  where auth.uid() is not null and cp.status = 'approved'
  order by cp.created_at desc;
$$;

create or replace function public.recognition_feed()
returns table (
  id uuid, value text, message text, sender_name text,
  recipient_name text, created_at timestamptz
)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select r.id, r.value, r.message,
    sender.first_name || ' ' || left(sender.last_name, 1) || '.',
    recipient.first_name || ' ' || left(recipient.last_name, 1) || '.',
    r.created_at
  from public.recognitions r
  join public.profiles sender on sender.id = r.sender_id
  join public.profiles recipient on recipient.id = r.recipient_id
  where auth.uid() is not null and r.status = 'approved'
  order by r.created_at desc;
$$;

create or replace function public.create_community_post(
  post_title text, post_body text, post_category text, post_image_url text default null,
  related_course uuid default null, related_event uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare new_id uuid;
begin
  if not exists (select 1 from public.profiles where id = auth.uid() and account_status = 'active') then
    raise exception 'Active membership required';
  end if;
  if (select count(*) from public.community_posts where author_id = auth.uid() and created_at > now() - interval '1 hour') >= 5 then
    raise exception 'Posting limit reached. Please try again later.';
  end if;
  insert into public.community_posts (author_id, title, body, category, image_url, course_id, event_id)
  values (auth.uid(), trim(post_title), trim(post_body), post_category, nullif(trim(post_image_url), ''), related_course, related_event)
  returning id into new_id;
  return new_id;
end;
$$;

create or replace function public.create_recognition(recipient uuid, recognition_value text, recognition_message text)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare new_id uuid;
begin
  if not exists (select 1 from public.profiles where id = auth.uid() and account_status = 'active') then
    raise exception 'Active membership required';
  end if;
  if (select count(*) from public.recognitions where sender_id = auth.uid() and created_at > now() - interval '1 day') >= 10 then
    raise exception 'Recognition limit reached. Please try again tomorrow.';
  end if;
  insert into public.recognitions (sender_id, recipient_id, value, message)
  values (auth.uid(), recipient, recognition_value, trim(recognition_message))
  returning id into new_id;
  return new_id;
end;
$$;

create or replace function public.complete_onboarding(admin_tour boolean default false)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if admin_tour then
    update public.profiles set admin_tour_completed_at = now() where id = auth.uid() and public.is_admin();
  else
    update public.profiles set onboarding_completed_at = now() where id = auth.uid();
  end if;
end;
$$;

create or replace function public.update_communication_preference(consent boolean)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  update public.profiles
  set communication_consent = consent,
      communication_opted_out_at = case when consent then null else now() end,
      updated_at = now()
  where id = auth.uid();
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

create or replace function public.audit_moderation_change()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if old.status is distinct from new.status then
    insert into public.audit_logs (action, administrator_id, metadata)
    values (
      tg_argv[0] || '.status_changed',
      auth.uid(),
      jsonb_build_object('record_id', new.id, 'from', old.status, 'to', new.status)
    );
  end if;
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

create trigger courses_set_updated_at before update on public.courses
for each row execute function public.set_updated_at();
create trigger modules_set_updated_at before update on public.course_modules
for each row execute function public.set_updated_at();
create trigger lessons_set_updated_at before update on public.lessons
for each row execute function public.set_updated_at();
create trigger community_posts_set_updated_at before update on public.community_posts
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

create trigger audit_community_post_moderation after update on public.community_posts
for each row execute function public.audit_moderation_change('community_post');
create trigger audit_recognition_moderation after update on public.recognitions
for each row execute function public.audit_moderation_change('recognition');

-- Row Level Security
alter table public.profiles enable row level security;
alter table public.memberships enable row level security;
alter table public.events enable row level security;
alter table public.attendance enable row level security;
alter table public.point_transactions enable row level security;
alter table public.badges enable row level security;
alter table public.member_badges enable row level security;
alter table public.audit_logs enable row level security;
alter table public.event_registrations enable row level security;
alter table public.courses enable row level security;
alter table public.course_modules enable row level security;
alter table public.lessons enable row level security;
alter table public.resources enable row level security;
alter table public.lesson_progress enable row level security;
alter table public.community_posts enable row level security;
alter table public.post_reactions enable row level security;
alter table public.post_reports enable row level security;
alter table public.recognitions enable row level security;
alter table public.recognition_reactions enable row level security;
alter table public.recognition_reports enable row level security;
alter table public.outreach_campaigns enable row level security;

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

create policy "registrations_own_or_admin" on public.event_registrations for select to authenticated
using (member_id in (select id from public.memberships where profile_id = auth.uid()) or public.is_admin());
create policy "registrations_own_insert" on public.event_registrations for insert to authenticated
with check (member_id in (select id from public.memberships where profile_id = auth.uid()) or public.is_admin());
create policy "registrations_own_delete" on public.event_registrations for delete to authenticated
using (member_id in (select id from public.memberships where profile_id = auth.uid()) or public.is_admin());

create policy "courses_member_read" on public.courses for select to authenticated
using (published or public.is_admin());
create policy "courses_admin_all" on public.courses for all to authenticated
using (public.is_admin()) with check (public.is_admin());
create policy "modules_member_read" on public.course_modules for select to authenticated
using ((published and exists (select 1 from public.courses c where c.id = course_id and c.published)) or public.is_admin());
create policy "modules_admin_all" on public.course_modules for all to authenticated
using (public.is_admin()) with check (public.is_admin());
create policy "lessons_member_read" on public.lessons for select to authenticated
using ((published and exists (select 1 from public.course_modules cm join public.courses c on c.id = cm.course_id where cm.id = module_id and cm.published and c.published)) or public.is_admin());
create policy "lessons_admin_all" on public.lessons for all to authenticated
using (public.is_admin()) with check (public.is_admin());
create policy "resources_member_read" on public.resources for select to authenticated
using (exists (select 1 from public.lessons l where l.id = lesson_id and (l.published or public.is_admin())));
create policy "resources_admin_all" on public.resources for all to authenticated
using (public.is_admin()) with check (public.is_admin());
create policy "progress_own_all" on public.lesson_progress for all to authenticated
using (member_id in (select id from public.memberships where profile_id = auth.uid()) or public.is_admin())
with check (member_id in (select id from public.memberships where profile_id = auth.uid()) or public.is_admin());

create policy "posts_approved_or_own_or_admin" on public.community_posts for select to authenticated
using (status = 'approved' or author_id = auth.uid() or public.is_admin());
create policy "posts_admin_update" on public.community_posts for update to authenticated
using (public.is_admin()) with check (public.is_admin());
create policy "reactions_read" on public.post_reactions for select to authenticated using (true);
create policy "reactions_own_write" on public.post_reactions for insert to authenticated
with check (profile_id = auth.uid() and exists (select 1 from public.profiles where id = auth.uid() and account_status = 'active'));
create policy "reactions_own_update" on public.post_reactions for update to authenticated
using (profile_id = auth.uid()) with check (profile_id = auth.uid());
create policy "reactions_own_delete" on public.post_reactions for delete to authenticated using (profile_id = auth.uid());
create policy "post_reports_own_insert" on public.post_reports for insert to authenticated with check (reporter_id = auth.uid());
create policy "post_reports_admin_read" on public.post_reports for select to authenticated using (public.is_admin());
create policy "post_reports_admin_update" on public.post_reports for update to authenticated using (public.is_admin()) with check (public.is_admin());

create policy "recognitions_approved_or_involved" on public.recognitions for select to authenticated
using (status = 'approved' or sender_id = auth.uid() or recipient_id = auth.uid() or public.is_admin());
create policy "recognitions_admin_update" on public.recognitions for update to authenticated
using (public.is_admin()) with check (public.is_admin());
create policy "recognition_reactions_read" on public.recognition_reactions for select to authenticated using (true);
create policy "recognition_reactions_own_write" on public.recognition_reactions for insert to authenticated
with check (profile_id = auth.uid() and exists (select 1 from public.profiles where id = auth.uid() and account_status = 'active'));
create policy "recognition_reactions_own_update" on public.recognition_reactions for update to authenticated
using (profile_id = auth.uid()) with check (profile_id = auth.uid());
create policy "recognition_reactions_own_delete" on public.recognition_reactions for delete to authenticated using (profile_id = auth.uid());
create policy "recognition_reports_own_insert" on public.recognition_reports for insert to authenticated with check (reporter_id = auth.uid());
create policy "recognition_reports_admin_read" on public.recognition_reports for select to authenticated using (public.is_admin());
create policy "outreach_admin_all" on public.outreach_campaigns for all to authenticated
using (public.is_admin()) with check (public.is_admin());

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
grant select, insert, delete on public.event_registrations to authenticated;
grant select, insert, update, delete on public.courses, public.course_modules, public.lessons, public.resources to authenticated;
grant select, insert, update, delete on public.lesson_progress to authenticated;
grant select, update on public.community_posts to authenticated;
grant select, insert, update, delete on public.post_reactions to authenticated;
grant select, insert, update on public.post_reports to authenticated;
grant select, update on public.recognitions to authenticated;
grant select, insert, update, delete on public.recognition_reactions to authenticated;
grant select, insert on public.recognition_reports to authenticated;
grant select, insert, update, delete on public.outreach_campaigns to authenticated;


revoke all on function public.is_admin() from public;
revoke all on function public.member_summary() from public;
revoke all on function public.admin_check_in(uuid, uuid, boolean, text) from public;
revoke all on function public.admin_award_event_points(uuid, integer, text) from public;
revoke all on function public.public_membership_verification(uuid) from public;
revoke all on function public.admin_member_directory() from public;
revoke all on function public.admin_dashboard_stats() from public;
revoke all on function public.admin_attendee_contacts(uuid) from public;
revoke all on function public.admin_award_badge(uuid, uuid, text) from public;
revoke all on function public.member_directory() from public;
revoke all on function public.community_feed() from public;
revoke all on function public.recognition_feed() from public;
revoke all on function public.create_community_post(text, text, text, text, uuid, uuid) from public;
revoke all on function public.create_recognition(uuid, text, text) from public;
revoke all on function public.complete_onboarding(boolean) from public;
revoke all on function public.update_communication_preference(boolean) from public;

grant execute on function public.is_admin() to authenticated;
grant execute on function public.member_summary() to authenticated;
grant execute on function public.admin_check_in(uuid, uuid, boolean, text) to authenticated;
grant execute on function public.admin_award_event_points(uuid, integer, text) to authenticated;
grant execute on function public.public_membership_verification(uuid) to anon, authenticated;
grant execute on function public.admin_member_directory() to authenticated;
grant execute on function public.admin_dashboard_stats() to authenticated;
grant execute on function public.admin_attendee_contacts(uuid) to authenticated;
grant execute on function public.admin_award_badge(uuid, uuid, text) to authenticated;
grant execute on function public.member_directory() to authenticated;
grant execute on function public.community_feed() to authenticated;
grant execute on function public.recognition_feed() to authenticated;
grant execute on function public.create_community_post(text, text, text, text, uuid, uuid) to authenticated;
grant execute on function public.create_recognition(uuid, text, text) to authenticated;
grant execute on function public.complete_onboarding(boolean) to authenticated;
grant execute on function public.update_communication_preference(boolean) to authenticated;

commit;

-- Ask PostgREST to refresh immediately after this migration.
notify pgrst, 'reload schema';

-- After signup, promote only the intended owner from Supabase SQL Editor:
-- update public.profiles set role = 'admin' where id = 'AUTH_USER_UUID';
