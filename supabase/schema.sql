-- The STEM Club member portal foundation. Run in the Supabase SQL editor.
-- All membership, role, and moderation decisions remain database-enforced.
create extension if not exists pgcrypto;
create type public.member_role as enum ('member', 'admin');
create type public.account_status as enum ('active', 'suspended');
create type public.membership_level as enum ('community', 'stem_club');
create type public.membership_status as enum ('active', 'inactive', 'past_due', 'cancelled');
create type public.content_access as enum ('community', 'stem_club');
create type public.post_status as enum ('pending', 'approved', 'hidden', 'removed');

create table public.profiles (id uuid primary key references auth.users(id) on delete cascade, first_name text not null check (char_length(first_name) between 1 and 80), last_name text not null check (char_length(last_name) between 1 and 80), member_id text unique not null, role public.member_role not null default 'member', account_status public.account_status not null default 'active', guardian_required boolean not null default false, guardian_consent_at timestamptz, created_at timestamptz not null default now(), updated_at timestamptz not null default now());
create table public.memberships (id uuid primary key default gen_random_uuid(), profile_id uuid unique not null references public.profiles(id) on delete cascade, level public.membership_level not null default 'community', status public.membership_status not null default 'active', starts_at timestamptz not null default now(), ends_at timestamptz, payment_provider_customer_id text, payment_provider_subscription_id text unique, created_at timestamptz not null default now(), updated_at timestamptz not null default now());
create table public.courses (id uuid primary key default gen_random_uuid(), title text not null, description text, access public.content_access not null default 'community', published boolean not null default false, created_at timestamptz not null default now());
create table public.course_modules (id uuid primary key default gen_random_uuid(), course_id uuid not null references public.courses(id) on delete cascade, title text not null, position integer not null default 0);
create table public.lessons (id uuid primary key default gen_random_uuid(), module_id uuid not null references public.course_modules(id) on delete cascade, title text not null, content text, video_url text, project_instructions text, access public.content_access not null default 'community', published boolean not null default false, position integer not null default 0);
create table public.resources (id uuid primary key default gen_random_uuid(), lesson_id uuid references public.lessons(id) on delete cascade, title text not null, url text, access public.content_access not null default 'community', published boolean not null default false);
create table public.course_progress (profile_id uuid not null references public.profiles(id) on delete cascade, lesson_id uuid not null references public.lessons(id) on delete cascade, completed_at timestamptz not null default now(), primary key(profile_id, lesson_id));
create table public.community_posts (id uuid primary key default gen_random_uuid(), author_id uuid not null references public.profiles(id) on delete cascade, category text not null check (category in ('general','showcase','questions','challenges','announcements')), title text not null check(char_length(title) <= 160), body text not null check(char_length(body) <= 5000), status public.post_status not null default 'pending', created_at timestamptz not null default now(), moderated_at timestamptz, moderated_by uuid references public.profiles(id));
create table public.community_comments (id uuid primary key default gen_random_uuid(), post_id uuid not null references public.community_posts(id) on delete cascade, author_id uuid not null references public.profiles(id) on delete cascade, body text not null check(char_length(body) <= 2000), status public.post_status not null default 'pending', created_at timestamptz not null default now());
create table public.community_reports (id uuid primary key default gen_random_uuid(), post_id uuid references public.community_posts(id) on delete cascade, comment_id uuid references public.community_comments(id) on delete cascade, reporter_id uuid not null references public.profiles(id) on delete cascade, reason text not null check(char_length(reason) <= 1000), created_at timestamptz not null default now(), check (num_nonnulls(post_id, comment_id) = 1));
create table public.events (id uuid primary key default gen_random_uuid(), title text not null, description text, starts_at timestamptz not null, ends_at timestamptz, location text, registration_info text, access public.content_access not null default 'community', published boolean not null default false, created_at timestamptz not null default now());
create table public.event_registrations (id uuid primary key default gen_random_uuid(), event_id uuid not null references public.events(id) on delete cascade, profile_id uuid not null references public.profiles(id) on delete cascade, registered_at timestamptz not null default now(), unique(event_id, profile_id));
create table public.event_attendance (id uuid primary key default gen_random_uuid(), event_id uuid not null references public.events(id) on delete cascade, profile_id uuid not null references public.profiles(id) on delete cascade, checked_in_at timestamptz, created_at timestamptz not null default now(), unique(event_id, profile_id));
create table public.achievements (id uuid primary key default gen_random_uuid(), name text unique not null, description text not null, icon_url text, criteria text, created_at timestamptz not null default now());
create table public.member_achievements (profile_id uuid not null references public.profiles(id) on delete cascade, achievement_id uuid not null references public.achievements(id) on delete cascade, earned_at timestamptz not null default now(), primary key(profile_id, achievement_id));

create or replace function public.is_admin() returns boolean language sql stable security definer set search_path = public as $$ select exists(select 1 from public.profiles where id = auth.uid() and role = 'admin' and account_status = 'active') $$;
create or replace function public.has_stem_access() returns boolean language sql stable security definer set search_path = public as $$ select exists(select 1 from public.memberships where profile_id = auth.uid() and level = 'stem_club' and status = 'active' and (ends_at is null or ends_at > now())) $$;
create sequence public.member_id_seq start 1;
create or replace function public.handle_new_user() returns trigger language plpgsql security definer set search_path = public as $$ begin insert into public.profiles(id,first_name,last_name,member_id) values(new.id, coalesce(new.raw_user_meta_data->>'first_name','Member'), coalesce(new.raw_user_meta_data->>'last_name',''), 'STC-' || lpad(nextval('public.member_id_seq')::text, 6, '0')); insert into public.memberships(profile_id) values(new.id); return new; end; $$;
create trigger on_auth_user_created after insert on auth.users for each row execute procedure public.handle_new_user();

-- Row Level Security: enable every application table, then grant the smallest required access.
alter table public.profiles enable row level security; alter table public.memberships enable row level security; alter table public.courses enable row level security; alter table public.course_modules enable row level security; alter table public.lessons enable row level security; alter table public.resources enable row level security; alter table public.course_progress enable row level security; alter table public.community_posts enable row level security; alter table public.community_comments enable row level security; alter table public.community_reports enable row level security; alter table public.events enable row level security; alter table public.event_registrations enable row level security; alter table public.event_attendance enable row level security; alter table public.achievements enable row level security; alter table public.member_achievements enable row level security;
create policy "profile owner or admin reads" on public.profiles for select using (id = auth.uid() or public.is_admin());
create policy "admin manages profiles" on public.profiles for all using (public.is_admin()) with check (public.is_admin());
create policy "member reads own membership" on public.memberships for select using (profile_id = auth.uid() or public.is_admin());
create policy "admin manages memberships" on public.memberships for all using (public.is_admin()) with check (public.is_admin());
create policy "members view allowed courses" on public.courses for select using (published and (access = 'community' or public.has_stem_access()) or public.is_admin());
create policy "admin manages courses" on public.courses for all using (public.is_admin()) with check (public.is_admin());
create policy "members view modules for allowed courses" on public.course_modules for select using (exists(select 1 from public.courses c where c.id=course_id and c.published and (c.access='community' or public.has_stem_access())) or public.is_admin());
create policy "admin manages modules" on public.course_modules for all using (public.is_admin()) with check (public.is_admin());
create policy "members view allowed lessons" on public.lessons for select using (published and (access='community' or public.has_stem_access()) or public.is_admin());
create policy "admin manages lessons" on public.lessons for all using (public.is_admin()) with check (public.is_admin());
create policy "members view allowed resources" on public.resources for select using (published and (access='community' or public.has_stem_access()) or public.is_admin());
create policy "admin manages resources" on public.resources for all using (public.is_admin()) with check (public.is_admin());
create policy "members manage own progress" on public.course_progress for all using (profile_id=auth.uid()) with check (profile_id=auth.uid());
create policy "admins view progress" on public.course_progress for select using (public.is_admin());
create policy "members view approved posts" on public.community_posts for select using (status='approved' or author_id=auth.uid() or public.is_admin());
create policy "members create own pending posts" on public.community_posts for insert with check (author_id=auth.uid() and status='pending');
create policy "admins manage posts" on public.community_posts for all using (public.is_admin()) with check (public.is_admin());
create policy "members view approved comments" on public.community_comments for select using (status='approved' or author_id=auth.uid() or public.is_admin());
create policy "members create own pending comments" on public.community_comments for insert with check (author_id=auth.uid() and status='pending');
create policy "admins manage comments" on public.community_comments for all using (public.is_admin()) with check (public.is_admin());
create policy "members create their reports" on public.community_reports for insert with check (reporter_id=auth.uid());
create policy "admins view reports" on public.community_reports for select using (public.is_admin());
create policy "members view allowed events" on public.events for select using (published and (access='community' or public.has_stem_access()) or public.is_admin());
create policy "admin manages events" on public.events for all using (public.is_admin()) with check (public.is_admin());
create policy "members manage own registrations" on public.event_registrations for all using (profile_id=auth.uid()) with check (profile_id=auth.uid());
create policy "admins view registrations" on public.event_registrations for select using (public.is_admin());
create policy "admins manage attendance" on public.event_attendance for all using (public.is_admin()) with check (public.is_admin());
create policy "members view achievements" on public.achievements for select using (true);
create policy "admins manage achievements" on public.achievements for all using (public.is_admin()) with check (public.is_admin());
create policy "members view their earned achievements" on public.member_achievements for select using (profile_id=auth.uid() or public.is_admin());
create policy "admins award achievements" on public.member_achievements for all using (public.is_admin()) with check (public.is_admin());

-- After creating the first account, promote it intentionally in the SQL editor:
-- update public.profiles set role = 'admin' where id = 'AUTH_USER_UUID';
