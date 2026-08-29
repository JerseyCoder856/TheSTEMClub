-- Unified workspace workflows: private notifications, feedback, recognition responses,
-- and idempotent contextual point awards. Safe to run more than once.
begin;

create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  recipient_id uuid not null references public.profiles(id) on delete cascade,
  kind text not null,
  title_en text not null,
  title_es text not null,
  preview_en text,
  preview_es text,
  link text not null default '/my-passport',
  source_key text not null,
  read_at timestamptz,
  created_at timestamptz not null default now(),
  unique (recipient_id, source_key)
);
create index if not exists notifications_recipient_idx on public.notifications(recipient_id, created_at desc);
alter table public.notifications enable row level security;
drop policy if exists "notifications_own_read" on public.notifications;
create policy "notifications_own_read" on public.notifications for select to authenticated using (recipient_id=auth.uid());
drop policy if exists "notifications_own_update" on public.notifications;
create policy "notifications_own_update" on public.notifications for update to authenticated using (recipient_id=auth.uid()) with check (recipient_id=auth.uid());
revoke all on public.notifications from public, anon;
grant select, update on public.notifications to authenticated;

create table if not exists public.feedback_requests (
  id uuid primary key default gen_random_uuid(),
  requester_id uuid not null references public.profiles(id),
  recipient_id uuid not null references public.profiles(id),
  title text not null check (char_length(trim(title)) between 3 and 160),
  prompt text not null check (char_length(trim(prompt)) between 3 and 1000),
  response text check (response is null or char_length(trim(response)) between 1 and 4000),
  teacher_response text check (teacher_response is null or char_length(trim(teacher_response)) between 1 and 4000),
  visibility text not null default 'private' check (visibility in ('private','public')),
  responded_at timestamptz,
  teacher_responded_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists feedback_recipient_idx on public.feedback_requests(recipient_id, created_at desc);
alter table public.feedback_requests enable row level security;
drop policy if exists "feedback_involved_read" on public.feedback_requests;
create policy "feedback_involved_read" on public.feedback_requests for select to authenticated using (requester_id=auth.uid() or recipient_id=auth.uid() or public.is_admin());
drop policy if exists "feedback_admin_insert" on public.feedback_requests;
create policy "feedback_admin_insert" on public.feedback_requests for insert to authenticated with check (requester_id=auth.uid() and public.is_admin());
revoke all on public.feedback_requests from public, anon;
grant select on public.feedback_requests to authenticated;

alter table public.recognitions add column if not exists visibility text not null default 'private';
alter table public.recognitions add column if not exists response text;
alter table public.recognitions add column if not exists responded_at timestamptz;
alter table public.recognitions drop constraint if exists recognitions_visibility_check;
alter table public.recognitions add constraint recognitions_visibility_check check (visibility in ('private','public'));

create or replace function public.create_notification(target_profile uuid, notification_kind text, en_title text, es_title text, en_preview text, es_preview text, target_link text, dedupe_key text)
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare notification_id uuid;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if target_profile <> auth.uid() and not public.is_admin() then raise exception 'Administrator access required'; end if;
  insert into public.notifications(recipient_id,kind,title_en,title_es,preview_en,preview_es,link,source_key)
  values(target_profile,notification_kind,en_title,es_title,en_preview,es_preview,coalesce(target_link,'/my-passport'),dedupe_key)
  on conflict(recipient_id,source_key) do update set created_at=excluded.created_at
  returning id into notification_id;
  return notification_id;
end $$;

create or replace function public.request_feedback(target_profile uuid, request_title text, request_prompt text)
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare request_id uuid;
begin
  if not public.is_admin() then raise exception 'Administrator access required'; end if;
  if not exists(select 1 from public.profiles where id=target_profile and account_status='active') then raise exception 'Active recipient required'; end if;
  insert into public.feedback_requests(requester_id,recipient_id,title,prompt)
  values(auth.uid(),target_profile,trim(request_title),trim(request_prompt)) returning id into request_id;
  perform public.create_notification(target_profile,'feedback_requested','Feedback requested','Solicitud de comentarios',trim(request_title),trim(request_title),'/member/community','feedback-request:'||request_id);
  return request_id;
end $$;

create or replace function public.respond_to_feedback(request_id uuid, response_text text)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare owner_id uuid;
begin
  update public.feedback_requests set response=trim(response_text),responded_at=now(),updated_at=now()
  where id=request_id and recipient_id=auth.uid() and response is null returning requester_id into owner_id;
  if owner_id is null then raise exception 'Feedback request unavailable or already answered'; end if;
  insert into public.notifications(recipient_id,kind,title_en,title_es,preview_en,preview_es,link,source_key)
  values(owner_id,'feedback_received','Feedback received','Comentarios recibidos','A member answered your request.','Un miembro respondió a tu solicitud.','/admin/recognitions','feedback-response:'||request_id) on conflict do nothing;
end $$;

create or replace function public.admin_update_feedback(request_id uuid, teacher_reply text, new_visibility text)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare recipient uuid;
begin
  if not public.is_admin() then raise exception 'Administrator access required'; end if;
  if new_visibility not in ('private','public') then raise exception 'Invalid visibility'; end if;
  update public.feedback_requests set teacher_response=nullif(trim(teacher_reply),''),teacher_responded_at=case when nullif(trim(teacher_reply),'') is null then teacher_responded_at else now() end,visibility=new_visibility,updated_at=now()
  where id=request_id returning recipient_id into recipient;
  if recipient is null then raise exception 'Feedback request not found'; end if;
  if nullif(trim(teacher_reply),'') is not null then perform public.create_notification(recipient,'feedback_response','Teacher responded','El docente respondió','Open your feedback to read the response.','Abre tus comentarios para leer la respuesta.','/member/community','teacher-feedback-response:'||request_id); end if;
end $$;

create or replace function public.admin_update_recognition(recognition_id uuid, teacher_reply text, new_visibility text)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare recipient uuid;
begin
  if not public.is_admin() then raise exception 'Administrator access required'; end if;
  if new_visibility not in ('private','public') then raise exception 'Invalid visibility'; end if;
  update public.recognitions set response=nullif(trim(teacher_reply),''),responded_at=case when nullif(trim(teacher_reply),'') is null then responded_at else now() end,visibility=new_visibility,status=case when new_visibility='public' then 'approved' else 'pending' end
  where id=recognition_id returning recipient_id into recipient;
  if recipient is null then raise exception 'Recognition not found'; end if;
  if nullif(trim(teacher_reply),'') is not null then perform public.create_notification(recipient,'recognition_response','Recognition response','Respuesta al reconocimiento','A teacher responded to your recognition.','Un docente respondió a tu reconocimiento.','/member/community','recognition-response:'||recognition_id); end if;
end $$;

create or replace function public.admin_award_points_contextual(target_member uuid, points integer, award_reason text, related_type text, related_id uuid, idempotency_key uuid)
returns integer language plpgsql security definer set search_path=public,pg_temp as $$
declare b integer; recipient uuid;
begin
  if not public.is_admin() then raise exception 'Administrator access required'; end if;
  if points <= 0 or points > 10000 then raise exception 'Award must be between 1 and 10,000 points'; end if;
  if length(trim(award_reason)) < 3 then raise exception 'A clear reason is required'; end if;
  select profile_id into recipient from public.memberships where id=target_member and status='active';
  if recipient is null then raise exception 'Active membership required'; end if;
  insert into public.admin_point_banks(administrator_id) values(auth.uid()) on conflict do nothing;
  select balance into b from public.admin_point_banks where administrator_id=auth.uid() for update;
  if exists(select 1 from public.point_transactions where source_key='teacher-award:'||idempotency_key) then return b; end if;
  if b < points then raise exception 'Teacher point bank has insufficient points'; end if;
  update public.admin_point_banks set balance=balance-points,updated_at=now() where administrator_id=auth.uid();
  insert into public.point_transactions(member_id,amount,reason,awarded_by,source_key)
  values(target_member,points,trim(award_reason)||case when related_type is null then '' else ' ['||related_type||']' end,auth.uid(),'teacher-award:'||idempotency_key);
  return b-points;
end $$;

create or replace function public.notify_member_activity() returns trigger
language plpgsql security definer set search_path=public,pg_temp as $$
declare recipient uuid; label text;
begin
  if tg_table_name='point_transactions' then
    select profile_id into recipient from public.memberships where id=new.member_id;
    insert into public.notifications(recipient_id,kind,title_en,title_es,preview_en,preview_es,link,source_key)
    values(recipient,'points_awarded','STEM Points awarded','Puntos STEM otorgados',new.amount||' points: '||new.reason,new.amount||' puntos: '||new.reason,'/my-passport','point-transaction:'||new.id) on conflict do nothing;
  elsif tg_table_name='member_badges' then
    select m.profile_id,b.name into recipient,label from public.memberships m join public.badges b on b.id=new.badge_id where m.id=new.member_id;
    insert into public.notifications(recipient_id,kind,title_en,title_es,preview_en,preview_es,link,source_key)
    values(recipient,'badge_awarded','Badge earned','Insignia obtenida',label,label,'/member/achievements','badge-award:'||new.id) on conflict do nothing;
  elsif tg_table_name='attendance' then
    select profile_id into recipient from public.memberships where id=new.member_id;
    insert into public.notifications(recipient_id,kind,title_en,title_es,preview_en,preview_es,link,source_key)
    values(recipient,'attendance','Attendance checked in','Asistencia registrada','Your event check-in was successful.','Tu registro al evento fue exitoso.','/my-passport','attendance:'||new.id) on conflict do nothing;
  elsif tg_table_name='event_registrations' then
    select profile_id into recipient from public.memberships where id=new.member_id;
    insert into public.notifications(recipient_id,kind,title_en,title_es,preview_en,preview_es,link,source_key)
    values(recipient,'event_signup','Event signup confirmed','Inscripción al evento confirmada','You are registered.','Tu inscripción está confirmada.','/member/events','event-registration:'||new.id) on conflict do nothing;
  elsif tg_table_name='recognitions' then
    recipient:=new.recipient_id;
    insert into public.notifications(recipient_id,kind,title_en,title_es,preview_en,preview_es,link,source_key)
    values(recipient,'recognition_received','Recognition received','Reconocimiento recibido','Someone recognized your STEM Club contribution.','Alguien reconoció tu aporte a The STEM Club.','/member/community','recognition:'||new.id) on conflict do nothing;
  end if;
  return new;
end $$;
drop trigger if exists notify_point_award on public.point_transactions;
create trigger notify_point_award after insert on public.point_transactions for each row execute function public.notify_member_activity();
drop trigger if exists notify_badge_award on public.member_badges;
create trigger notify_badge_award after insert on public.member_badges for each row execute function public.notify_member_activity();
drop trigger if exists notify_attendance on public.attendance;
create trigger notify_attendance after insert on public.attendance for each row execute function public.notify_member_activity();
drop trigger if exists notify_event_registration on public.event_registrations;
create trigger notify_event_registration after insert on public.event_registrations for each row execute function public.notify_member_activity();
drop trigger if exists notify_recognition on public.recognitions;
create trigger notify_recognition after insert on public.recognitions for each row execute function public.notify_member_activity();

create or replace function public.admin_manual_check_in(target_member uuid, target_event uuid, checkin_notes text default null)
returns table(membership_number text,first_name text,last_name text,duplicate boolean)
language plpgsql security definer set search_path=public,pg_temp as $$
declare affected integer;
begin
  if not public.is_admin() then raise exception 'Administrator access required'; end if;
  if not exists(select 1 from public.events where id=target_event and status='open') then raise exception 'Event is not open for check-in'; end if;
  if not exists(select 1 from public.memberships where id=target_member and status='active') then raise exception 'Active membership required'; end if;
  insert into public.attendance(event_id,member_id,status,checked_in_by,notes)
  values(target_event,target_member,'checked_in',auth.uid(),nullif(trim(checkin_notes),'')) on conflict(event_id,member_id) do nothing;
  get diagnostics affected=row_count;
  if affected=1 then insert into public.audit_logs(action,member_id,event_id,administrator_id) values('attendance.checked_in',target_member,target_event,auth.uid()); end if;
  return query select m.membership_number,p.first_name,p.last_name,affected=0 from public.memberships m join public.profiles p on p.id=m.profile_id where m.id=target_member;
end $$;

create or replace function public.admin_award_event_points_from_bank(target_event uuid, points integer, award_reason text, idempotency_key uuid)
returns table(awarded_count integer, remaining_balance integer)
language plpgsql security definer set search_path=public,pg_temp as $$
declare attendee_count integer; b integer; inserted_count integer;
begin
  if not public.is_admin() then raise exception 'Administrator access required'; end if;
  if points <= 0 or points > 10000 then raise exception 'Award must be between 1 and 10,000 points'; end if;
  if length(trim(award_reason)) < 3 then raise exception 'A clear reason is required'; end if;
  select count(*) into attendee_count from public.attendance where event_id=target_event;
  if attendee_count=0 then raise exception 'This event has no checked-in attendees'; end if;
  insert into public.admin_point_banks(administrator_id) values(auth.uid()) on conflict do nothing;
  select balance into b from public.admin_point_banks where administrator_id=auth.uid() for update;
  if exists(select 1 from public.point_transactions where source_key like 'event-bank:'||idempotency_key||':%') then return query select 0,b; return; end if;
  if b < attendee_count*points then raise exception 'Teacher point bank has insufficient points'; end if;
  insert into public.point_transactions(member_id,event_id,amount,reason,awarded_by,source_key)
  select a.member_id,target_event,points,trim(award_reason),auth.uid(),'event-bank:'||idempotency_key||':'||a.member_id from public.attendance a where a.event_id=target_event
  on conflict(source_key) do nothing;
  get diagnostics inserted_count=row_count;
  update public.admin_point_banks set balance=balance-(inserted_count*points),updated_at=now() where administrator_id=auth.uid();
  return query select inserted_count,b-(inserted_count*points);
end $$;

revoke all on function public.create_notification(uuid,text,text,text,text,text,text,text) from public;
revoke all on function public.request_feedback(uuid,text,text) from public;
revoke all on function public.respond_to_feedback(uuid,text) from public;
revoke all on function public.admin_update_feedback(uuid,text,text) from public;
revoke all on function public.admin_update_recognition(uuid,text,text) from public;
revoke all on function public.admin_award_points_contextual(uuid,integer,text,text,uuid,uuid) from public;
revoke all on function public.admin_manual_check_in(uuid,uuid,text) from public;
revoke all on function public.admin_award_event_points_from_bank(uuid,integer,text,uuid) from public;
grant execute on function public.create_notification(uuid,text,text,text,text,text,text,text) to authenticated;
grant execute on function public.request_feedback(uuid,text,text) to authenticated;
grant execute on function public.respond_to_feedback(uuid,text) to authenticated;
grant execute on function public.admin_update_feedback(uuid,text,text) to authenticated;
grant execute on function public.admin_update_recognition(uuid,text,text) to authenticated;
grant execute on function public.admin_award_points_contextual(uuid,integer,text,text,uuid,uuid) to authenticated;
grant execute on function public.admin_manual_check_in(uuid,uuid,text) to authenticated;
grant execute on function public.admin_award_event_points_from_bank(uuid,integer,text,uuid) to authenticated;
commit;
