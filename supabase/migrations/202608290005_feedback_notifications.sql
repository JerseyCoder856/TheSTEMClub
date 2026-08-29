begin;

create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references public.profiles(id) on delete cascade,
  title text not null check (char_length(title) between 1 and 120),
  body text not null check (char_length(body) between 1 and 500),
  link text check (link is null or link ~ '^/'),
  read_at timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists public.feedback (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references public.profiles(id) on delete cascade,
  category text not null default 'general' check (category in ('general','accessibility','translation','bug','idea')),
  message text not null check (char_length(message) between 5 and 2000),
  page_path text not null check (page_path ~ '^/'),
  status text not null default 'new' check (status in ('new','reviewing','resolved')),
  reviewed_by uuid references public.profiles(id) on delete set null,
  reviewed_at timestamptz,
  created_at timestamptz not null default now()
);

alter table public.notifications enable row level security;
alter table public.feedback enable row level security;

create policy "members read own notifications" on public.notifications
  for select to authenticated using (profile_id = auth.uid());
create policy "admins manage notifications" on public.notifications
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

create policy "members submit feedback" on public.feedback
  for insert to authenticated with check (profile_id = auth.uid() and status = 'new' and reviewed_by is null and reviewed_at is null);
create policy "members read own feedback" on public.feedback
  for select to authenticated using (profile_id = auth.uid());
create policy "admins manage feedback" on public.feedback
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

create or replace function public.submit_feedback(feedback_category text, feedback_message text, feedback_page_path text)
returns uuid
language plpgsql
security invoker
set search_path = ''
as $$
declare new_id uuid;
begin
  insert into public.feedback(profile_id, category, message, page_path)
  values (auth.uid(), feedback_category, feedback_message, feedback_page_path)
  returning id into new_id;
  return new_id;
end;
$$;

create or replace function public.member_notifications()
returns table(id uuid, title text, body text, link text, read_at timestamptz, created_at timestamptz)
language sql
security invoker
set search_path = ''
as $$
  select n.id, n.title, n.body, n.link, n.read_at, n.created_at
  from public.notifications n
  where n.profile_id = auth.uid()
  order by n.created_at desc
  limit 30;
$$;

create or replace function public.mark_notifications_read(notification_ids uuid[])
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare changed integer;
begin
  update public.notifications
  set read_at = coalesce(read_at, now())
  where profile_id = auth.uid() and id = any(notification_ids) and read_at is null;
  get diagnostics changed = row_count;
  return changed;
end;
$$;

revoke all on function public.mark_notifications_read(uuid[]) from public;
grant execute on function public.submit_feedback(text, text, text) to authenticated;
grant execute on function public.member_notifications() to authenticated;
grant execute on function public.mark_notifications_read(uuid[]) to authenticated;

create index if not exists notifications_profile_created_idx on public.notifications(profile_id, created_at desc);
create index if not exists feedback_status_created_idx on public.feedback(status, created_at desc);

commit;
