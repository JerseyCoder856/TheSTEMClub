-- The STEM Club Passport — production schema for Supabase PostgreSQL.
-- Run this file in a NEW Supabase project. Authentication passwords remain in Supabase Auth.
create extension if not exists pgcrypto;
create type public.member_role as enum ('member','admin');
create type public.account_status as enum ('active','suspended');
create type public.membership_status as enum ('active','inactive','expired');
create type public.event_status as enum ('draft','open','closed','cancelled');
create type public.check_in_status as enum ('checked_in','override');

create sequence public.membership_number_seq start 1;
create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  first_name text not null check (char_length(first_name) between 1 and 80),
  last_name text not null check (char_length(last_name) between 1 and 80),
  role public.member_role not null default 'member', account_status public.account_status not null default 'active',
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table public.memberships (
  id uuid primary key default gen_random_uuid(), profile_id uuid unique not null references public.profiles(id) on delete cascade,
  membership_number text unique not null default ('TSC-' || lpad(nextval('public.membership_number_seq')::text,4,'0')),
  qr_token uuid unique not null default gen_random_uuid(), status public.membership_status not null default 'active',
  issued_at date not null default current_date, expires_at date, created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table public.events (
  id uuid primary key default gen_random_uuid(), title text not null check(char_length(title) between 1 and 160), description text,
  starts_at timestamptz not null, ends_at timestamptz, location text, status public.event_status not null default 'draft',
  created_by uuid references public.profiles(id), created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table public.attendance (
  id uuid primary key default gen_random_uuid(), event_id uuid not null references public.events(id) on delete cascade,
  member_id uuid not null references public.memberships(id) on delete cascade, checked_in_at timestamptz not null default now(),
  status public.check_in_status not null default 'checked_in', checked_in_by uuid not null references public.profiles(id), notes text,
  created_at timestamptz not null default now(), unique(event_id,member_id)
);
create table public.point_transactions (
  id uuid primary key default gen_random_uuid(), member_id uuid not null references public.memberships(id) on delete cascade,
  event_id uuid references public.events(id) on delete set null, amount integer not null check(amount <> 0), reason text not null check(char_length(reason) between 1 and 240),
  awarded_by uuid not null references public.profiles(id), created_at timestamptz not null default now()
);
create table public.badges (
  id uuid primary key default gen_random_uuid(), name text unique not null, description text not null, icon_url text, icon_emoji text,
  category text, rarity text, criteria text, manual_award boolean not null default true, created_by uuid references public.profiles(id), created_at timestamptz not null default now()
);
create table public.member_badges (
  id uuid primary key default gen_random_uuid(), member_id uuid not null references public.memberships(id) on delete cascade,
  badge_id uuid not null references public.badges(id) on delete cascade, reason text, awarded_by uuid not null references public.profiles(id),
  awarded_at timestamptz not null default now(), unique(member_id,badge_id)
);
create table public.audit_logs (
  id bigint generated always as identity primary key, action text not null, member_id uuid references public.memberships(id) on delete set null,
  event_id uuid references public.events(id) on delete set null, administrator_id uuid references public.profiles(id) on delete set null,
  metadata jsonb not null default '{}'::jsonb, created_at timestamptz not null default now()
);

create or replace function public.is_admin() returns boolean language sql stable security definer set search_path=public as $$
 select exists(select 1 from public.profiles where id=auth.uid() and role='admin' and account_status='active') $$;
create or replace function public.handle_new_user() returns trigger language plpgsql security definer set search_path=public as $$
declare p_id uuid; begin
 insert into public.profiles(id,first_name,last_name) values(new.id,coalesce(nullif(trim(new.raw_user_meta_data->>'first_name'),''),'Member'),coalesce(nullif(trim(new.raw_user_meta_data->>'last_name'),''),'Member'));
 insert into public.memberships(profile_id) values(new.id) returning id into p_id;
 insert into public.audit_logs(action,member_id,metadata) values('membership.created',p_id,jsonb_build_object('source','registration'));
 return new; end $$;
create trigger on_auth_user_created after insert on auth.users for each row execute function public.handle_new_user();

create or replace function public.public_membership_verification(token uuid)
returns table(membership_number text,status public.membership_status,issued_at date,expires_at date)
language sql stable security definer set search_path=public as $$ select m.membership_number,m.status,m.issued_at,m.expires_at from memberships m where m.qr_token=token $$;
grant execute on function public.public_membership_verification(uuid) to anon,authenticated;

create or replace function public.member_summary()
returns table(membership_id uuid,membership_number text,qr_token uuid,status public.membership_status,issued_at date,expires_at date,stem_points bigint)
language sql stable security definer set search_path=public as $$
 select m.id,m.membership_number,m.qr_token,m.status,m.issued_at,m.expires_at,coalesce(sum(pt.amount),0)::bigint from memberships m left join point_transactions pt on pt.member_id=m.id where m.profile_id=auth.uid() group by m.id $$;

create or replace function public.admin_check_in(token uuid,target_event uuid,override_inactive boolean default false,checkin_notes text default null)
returns table(membership_number text,first_name text,last_name text,membership_status public.membership_status,duplicate boolean)
language plpgsql security definer set search_path=public as $$
declare m memberships%rowtype; p profiles%rowtype; affected integer; was_duplicate boolean; begin
 if not is_admin() then raise exception 'Administrator access required'; end if;
 select * into m from memberships where qr_token=token; if not found then raise exception 'Membership not found'; end if;
 if m.status <> 'active' and not override_inactive then raise exception 'Membership is not active'; end if;
 select * into p from profiles where id=m.profile_id;
 insert into attendance(event_id,member_id,status,checked_in_by,notes) values(target_event,m.id,case when m.status='active' then 'checked_in' else 'override' end,auth.uid(),checkin_notes)
 on conflict(event_id,member_id) do nothing; get diagnostics affected = row_count; was_duplicate := affected = 0;
 if not was_duplicate then insert into audit_logs(action,member_id,event_id,administrator_id) values('attendance.checked_in',m.id,target_event,auth.uid()); end if;
 return query select m.membership_number,p.first_name,p.last_name,m.status,was_duplicate; end $$;

create or replace function public.admin_award_event_points(target_event uuid,points integer,award_reason text)
returns integer language plpgsql security definer set search_path=public as $$ declare n integer; begin
 if not is_admin() then raise exception 'Administrator access required'; end if; if points=0 then raise exception 'Points cannot be zero'; end if;
 insert into point_transactions(member_id,event_id,amount,reason,awarded_by) select a.member_id,target_event,points,award_reason,auth.uid() from attendance a where a.event_id=target_event;
 get diagnostics n=row_count; insert into audit_logs(action,event_id,administrator_id,metadata) values('points.event_award',target_event,auth.uid(),jsonb_build_object('amount',points,'recipients',n,'reason',award_reason)); return n; end $$;

create or replace function public.audit_membership_change() returns trigger language plpgsql security definer set search_path=public as $$ begin
 if old.status is distinct from new.status then insert into audit_logs(action,member_id,administrator_id,metadata) values('membership.status_changed',new.id,auth.uid(),jsonb_build_object('from',old.status,'to',new.status)); end if; return new; end $$;
create trigger audit_membership_update after update on memberships for each row execute function public.audit_membership_change();
create or replace function public.audit_points_or_badge() returns trigger language plpgsql security definer set search_path=public as $$ begin
 insert into audit_logs(action,member_id,administrator_id,metadata) values(case when tg_table_name='point_transactions' then case when new.amount>0 then 'points.awarded' else 'points.removed' end else 'badge.awarded' end,new.member_id,auth.uid(),case when tg_table_name='point_transactions' then jsonb_build_object('amount',new.amount,'reason',new.reason) else jsonb_build_object('badge_id',new.badge_id,'reason',new.reason) end); return new; end $$;
create trigger audit_point_insert after insert on point_transactions for each row execute function public.audit_points_or_badge();
create trigger audit_badge_insert after insert on member_badges for each row execute function public.audit_points_or_badge();

alter table profiles enable row level security; alter table memberships enable row level security; alter table events enable row level security;
alter table attendance enable row level security; alter table point_transactions enable row level security; alter table badges enable row level security;
alter table member_badges enable row level security; alter table audit_logs enable row level security;
create policy "own profile read" on profiles for select using(id=auth.uid() or is_admin());
create policy "admin profiles" on profiles for all using(is_admin()) with check(is_admin());
create policy "own membership read" on memberships for select using(profile_id=auth.uid() or is_admin());
create policy "admin memberships" on memberships for all using(is_admin()) with check(is_admin());
create policy "members read open events" on events for select using(status in ('open','closed') or is_admin());
create policy "admin events" on events for all using(is_admin()) with check(is_admin());
create policy "own attendance read" on attendance for select using(member_id in(select id from memberships where profile_id=auth.uid()) or is_admin());
create policy "admin attendance" on attendance for all using(is_admin()) with check(is_admin());
create policy "own points read" on point_transactions for select using(member_id in(select id from memberships where profile_id=auth.uid()) or is_admin());
create policy "admin points" on point_transactions for all using(is_admin()) with check(is_admin());
create policy "authenticated badges read" on badges for select to authenticated using(true); create policy "admin badges" on badges for all using(is_admin()) with check(is_admin());
create policy "own member badges read" on member_badges for select using(member_id in(select id from memberships where profile_id=auth.uid()) or is_admin());
create policy "admin member badges" on member_badges for all using(is_admin()) with check(is_admin()); create policy "admin audit" on audit_logs for select using(is_admin());

-- First development member: create a TEST user through Supabase Auth after installing this schema.
-- The first registered Auth user atomically receives TSC-0001. Promote only your chosen owner account server-side:
-- update public.profiles set role='admin' where id='YOUR_AUTH_USER_UUID';
