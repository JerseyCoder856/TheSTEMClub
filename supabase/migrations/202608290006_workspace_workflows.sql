begin;

alter table public.recognitions add column if not exists visibility text not null default 'public' check (visibility in ('public','private'));
alter table public.recognitions add column if not exists response text check (response is null or char_length(response) between 1 and 500);
alter table public.recognitions add column if not exists responded_at timestamptz;

create table if not exists public.feedback_requests (
  id uuid primary key default gen_random_uuid(),
  member_id uuid not null references public.profiles(id) on delete cascade,
  requested_by uuid not null references public.profiles(id) on delete cascade,
  prompt text not null check (char_length(prompt) between 5 and 500),
  response text check (response is null or char_length(response) between 5 and 2000),
  status text not null default 'requested' check (status in ('requested','responded','closed')),
  responded_at timestamptz,
  created_at timestamptz not null default now()
);
alter table public.feedback_requests enable row level security;
create policy "members read own feedback requests" on public.feedback_requests for select to authenticated using (member_id=auth.uid());
create policy "admins manage feedback requests" on public.feedback_requests for all to authenticated using (public.is_admin()) with check (public.is_admin());

create or replace function public.respond_to_feedback_request(target_request uuid, response_message text)
returns void language plpgsql security definer set search_path='' as $$
begin
  if char_length(trim(response_message)) not between 5 and 2000 then raise exception 'Response must be 5–2,000 characters'; end if;
  update public.feedback_requests set response=trim(response_message),status='responded',responded_at=now()
  where id=target_request and member_id=auth.uid() and status='requested';
  if not found then raise exception 'Open feedback request not found'; end if;
  insert into public.notifications(profile_id,title,body,link) select requested_by,'Feedback response received','A member responded to your feedback request.','/admin/notifications' from public.feedback_requests where id=target_request;
end $$;

create or replace function public.admin_review_recognition(target_recognition uuid, new_visibility text, response_message text default null)
returns void language plpgsql security definer set search_path='' as $$
begin
  if not public.is_admin() then raise exception 'Administrator access required'; end if;
  if new_visibility not in ('public','private') then raise exception 'Visibility must be public or private'; end if;
  update public.recognitions set status='approved', visibility=new_visibility,
    response=nullif(trim(response_message),''), responded_at=case when nullif(trim(response_message),'') is null then responded_at else now() end,
    moderated_by=auth.uid(), moderated_at=now() where id=target_recognition;
  if not found then raise exception 'Recognition not found'; end if;
  insert into public.notifications(profile_id,title,body,link) select recipient_id,'Recognition update',case when new_visibility='private' then 'A private recognition is ready for you.' else 'A recognition was published.' end,'/member/community' from public.recognitions where id=target_recognition;
end $$;

create or replace function public.admin_request_feedback(target_member uuid, feedback_prompt text)
returns uuid language plpgsql security definer set search_path='' as $$
declare new_id uuid;
begin
  if not public.is_admin() then raise exception 'Administrator access required'; end if;
  if char_length(trim(feedback_prompt)) not between 5 and 500 then raise exception 'Prompt must be 5–500 characters'; end if;
  if not exists(select 1 from public.profiles where id=target_member and account_status='active') then raise exception 'Active member not found'; end if;
  insert into public.feedback_requests(member_id,requested_by,prompt) values(target_member,auth.uid(),trim(feedback_prompt)) returning id into new_id;
  return new_id;
end $$;

create or replace function public.notify_member_activity() returns trigger language plpgsql security definer set search_path='' as $$
declare recipient uuid; heading text; detail text; destination text;
begin
  if tg_table_name='attendance' then select profile_id into recipient from public.memberships where id=new.member_id; heading='Workshop check-in'; detail='Your workshop attendance was recorded.'; destination='/member/events';
  elsif tg_table_name='point_transactions' then select profile_id into recipient from public.memberships where id=new.member_id; heading='STEM Points awarded'; detail=new.amount::text||' points: '||new.reason; destination='/member/achievements';
  elsif tg_table_name='member_badges' then select profile_id into recipient from public.memberships where id=new.member_id; heading='New badge'; detail='A teacher awarded you a new badge.'; destination='/member/achievements';
  elsif tg_table_name='feedback_requests' then recipient=new.member_id; heading='Feedback requested'; detail=new.prompt; destination='/member/settings';
  end if;
  if recipient is not null then insert into public.notifications(profile_id,title,body,link) values(recipient,heading,left(detail,500),destination); end if;
  return new;
end $$;

create trigger notify_attendance after insert on public.attendance for each row execute function public.notify_member_activity();
create trigger notify_points after insert on public.point_transactions for each row execute function public.notify_member_activity();
create trigger notify_badges after insert on public.member_badges for each row execute function public.notify_member_activity();
create trigger notify_feedback_request after insert on public.feedback_requests for each row execute function public.notify_member_activity();

create or replace function public.notify_administrators() returns trigger language plpgsql security definer set search_path='' as $$
begin
  insert into public.notifications(profile_id,title,body,link)
  select id,
    case when tg_table_name='feedback' then 'New member feedback' else 'Recognition awaiting review' end,
    case when tg_table_name='feedback' then left(new.message,500) else left(new.message,500) end,
    case when tg_table_name='feedback' then '/admin/notifications' else '/admin/recognitions' end
  from public.profiles where role='admin' and account_status='active';
  return new;
end $$;
create trigger notify_admin_feedback after insert on public.feedback for each row execute function public.notify_administrators();
create trigger notify_admin_recognition after insert on public.recognitions for each row execute function public.notify_administrators();

create or replace function public.recognition_feed()
returns table(id uuid, value text, message text, sender_name text, recipient_name text, created_at timestamptz)
language sql security definer set search_path='' as $$
  select r.id,r.value,r.message,s.first_name||' '||left(s.last_name,1)||'.',d.first_name||' '||left(d.last_name,1)||'.',r.created_at
  from public.recognitions r join public.profiles s on s.id=r.sender_id join public.profiles d on d.id=r.recipient_id
  where auth.uid() is not null and r.status='approved' and (r.visibility='public' or auth.uid() in (r.sender_id,r.recipient_id))
  order by r.created_at desc;
$$;

create or replace function public.admin_award_event_points(target_event uuid, points integer, award_reason text)
returns integer language plpgsql security definer set search_path='' as $$
declare recipient_count integer; required_points integer; bank_balance integer;
begin
  if not public.is_admin() then raise exception 'Administrator access required'; end if;
  if points <= 0 or points > 10000 then raise exception 'Award must be between 1 and 10,000 points'; end if;
  if char_length(trim(award_reason)) < 3 then raise exception 'A clear reason is required'; end if;
  if not exists(select 1 from public.events where id=target_event) then raise exception 'Workshop not found'; end if;
  select count(*) into recipient_count from public.attendance a where a.event_id=target_event and not exists(select 1 from public.point_transactions p where p.source_key='event:'||target_event::text||':member:'||a.member_id::text||':amount:'||points::text||':reason:'||md5(trim(award_reason)));
  required_points=recipient_count*points;
  insert into public.admin_point_banks(administrator_id) values(auth.uid()) on conflict do nothing;
  select balance into bank_balance from public.admin_point_banks where administrator_id=auth.uid() for update;
  if bank_balance < required_points then raise exception 'Teacher point bank has insufficient points'; end if;
  insert into public.point_transactions(member_id,event_id,amount,reason,awarded_by,source_key)
  select a.member_id,target_event,points,trim(award_reason),auth.uid(),'event:'||target_event::text||':member:'||a.member_id::text||':amount:'||points::text||':reason:'||md5(trim(award_reason)) from public.attendance a where a.event_id=target_event on conflict(source_key) do nothing;
  update public.admin_point_banks set balance=balance-required_points,updated_at=now() where administrator_id=auth.uid();
  return recipient_count;
end $$;
revoke all on function public.admin_award_event_points(uuid,integer,text) from public;
grant execute on function public.admin_award_event_points(uuid,integer,text) to authenticated;

revoke all on function public.respond_to_feedback_request(uuid,text) from public;
grant execute on function public.respond_to_feedback_request(uuid,text) to authenticated;
revoke all on function public.admin_review_recognition(uuid,text,text) from public;
revoke all on function public.admin_request_feedback(uuid,text) from public;
grant execute on function public.admin_review_recognition(uuid,text,text) to authenticated;
grant execute on function public.admin_request_feedback(uuid,text) to authenticated;
create index if not exists feedback_requests_member_created_idx on public.feedback_requests(member_id,created_at desc);
commit;
