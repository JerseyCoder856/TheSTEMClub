begin;

create table if not exists public.student_projects (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles(id) on delete cascade,
  title text not null check (char_length(title) between 3 and 120),
  category text not null check (category in ('Electronics','Programming','3D Design','Environmentals')),
  description text not null check (char_length(description) between 10 and 5000),
  media_paths text[] not null default '{}',
  status text not null default 'draft' check (status in ('draft','pending','approved','hidden','removed')),
  reviewed_by uuid references public.profiles(id) on delete set null,
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint student_projects_media_count check (cardinality(media_paths) <= 8)
);
create index if not exists student_projects_owner_created_idx on public.student_projects(owner_id,created_at desc);
create index if not exists student_projects_public_idx on public.student_projects(category,created_at desc) where status='approved';
alter table public.student_projects enable row level security;
drop policy if exists student_projects_read_visible on public.student_projects;
create policy student_projects_read_visible on public.student_projects for select to authenticated
  using (public.is_admin() or (exists(select 1 from public.profiles p join public.memberships m on m.profile_id=p.id where p.id=auth.uid() and p.account_status='active' and m.status='active') and (owner_id=auth.uid() or status='approved')));
grant select on public.student_projects to authenticated;
revoke insert,update,delete on public.student_projects from authenticated;

create table if not exists public.student_teams (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles(id) on delete restrict,
  name text not null check (char_length(name) between 3 and 80),
  description text not null check (char_length(description) between 10 and 1000),
  pathway text not null check (pathway in ('Electronics','Programming','3D Design','Environmentals','All STEM')),
  status text not null default 'open' check (status in ('open','closed','archived')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table if not exists public.student_team_members (
  team_id uuid not null references public.student_teams(id) on delete cascade,
  profile_id uuid not null references public.profiles(id) on delete cascade,
  member_role text not null default 'member' check (member_role in ('leader','member')),
  joined_at timestamptz not null default now(),
  primary key(team_id,profile_id)
);
create index if not exists student_teams_status_pathway_idx on public.student_teams(status,pathway,created_at desc);
create index if not exists student_team_members_profile_idx on public.student_team_members(profile_id,joined_at desc);
alter table public.student_teams enable row level security;
alter table public.student_team_members enable row level security;
drop policy if exists student_teams_read_visible on public.student_teams;
create policy student_teams_read_visible on public.student_teams for select to authenticated
  using (public.is_admin() or (exists(select 1 from public.profiles p join public.memberships m on m.profile_id=p.id where p.id=auth.uid() and p.account_status='active' and m.status='active') and (status='open' or owner_id=auth.uid() or exists (
    select 1 from public.student_team_members tm where tm.team_id=id and tm.profile_id=auth.uid()
  )));
drop policy if exists student_team_members_read_visible on public.student_team_members;
create policy student_team_members_read_visible on public.student_team_members for select to authenticated
  using (public.is_admin() or (profile_id=auth.uid() and exists(select 1 from public.profiles p join public.memberships m on m.profile_id=p.id where p.id=auth.uid() and p.account_status='active' and m.status='active')));
grant select on public.student_teams,public.student_team_members to authenticated;
revoke insert,update,delete on public.student_teams,public.student_team_members from authenticated;

create or replace function public.create_student_project(
  project_title text, project_category text, project_description text, project_media_paths text[] default '{}'
)
returns uuid language plpgsql security definer set search_path='' as $$
declare new_project uuid;
begin
  if not exists(select 1 from public.profiles p join public.memberships m on m.profile_id=p.id where p.id=auth.uid() and p.account_status='active' and m.status='active') then raise exception 'An active membership is required'; end if;
  if char_length(trim(project_title)) not between 3 and 120 then raise exception 'Title must be 3–120 characters'; end if;
  if char_length(trim(project_description)) not between 10 and 5000 then raise exception 'Description must be 10–5,000 characters'; end if;
  if project_category not in ('Electronics','Programming','3D Design','Environmentals') then raise exception 'Choose a valid pathway'; end if;
  if coalesce(cardinality(project_media_paths),0)>8 or exists(select 1 from unnest(coalesce(project_media_paths,'{}')) as uploaded(path) where uploaded.path not like auth.uid()::text||'/%') then raise exception 'Project files must belong to your account and be limited to eight'; end if;
  insert into public.student_projects(owner_id,title,category,description,media_paths)
  values(auth.uid(),trim(project_title),project_category,trim(project_description),coalesce(project_media_paths,'{}'))
  returning id into new_project;
  return new_project;
end $$;

create or replace function public.update_student_project(
  target_project uuid, project_title text, project_category text, project_description text, project_media_paths text[]
)
returns void language plpgsql security definer set search_path='' as $$
begin
  if not exists(select 1 from public.profiles p join public.memberships m on m.profile_id=p.id where p.id=auth.uid() and p.account_status='active' and m.status='active') then raise exception 'An active membership is required'; end if;
  if char_length(trim(project_title)) not between 3 and 120 or char_length(trim(project_description)) not between 10 and 5000 then raise exception 'Check the title and description lengths'; end if;
  if project_category not in ('Electronics','Programming','3D Design','Environmentals') then raise exception 'Choose a valid pathway'; end if;
  if coalesce(cardinality(project_media_paths),0)>8 or exists(select 1 from unnest(coalesce(project_media_paths,'{}')) as uploaded(path) where uploaded.path not like auth.uid()::text||'/%') then raise exception 'Project files must belong to your account and be limited to eight'; end if;
  update public.student_projects set title=trim(project_title),category=project_category,description=trim(project_description),media_paths=coalesce(project_media_paths,'{}'),updated_at=now()
  where id=target_project and owner_id=auth.uid() and status='draft';
  if not found then raise exception 'Editable project not found'; end if;
end $$;

create or replace function public.submit_student_project(target_project uuid)
returns void language plpgsql security definer set search_path='' as $$
begin
  update public.student_projects set status='pending',updated_at=now()
  where id=target_project and owner_id=auth.uid() and status='draft'
    and exists(select 1 from public.profiles p join public.memberships m on m.profile_id=p.id where p.id=auth.uid() and p.account_status='active' and m.status='active');
  if not found then raise exception 'Draft project not found'; end if;
end $$;

create or replace function public.delete_student_project(target_project uuid)
returns void language plpgsql security definer set search_path='' as $$
begin
  delete from public.student_projects where id=target_project and owner_id=auth.uid() and status='draft'
    and exists(select 1 from public.profiles p join public.memberships m on m.profile_id=p.id where p.id=auth.uid() and p.account_status='active' and m.status='active');
  if not found then raise exception 'Only your own draft projects can be deleted'; end if;
end $$;

create or replace function public.review_student_project(target_project uuid, approved boolean)
returns void language plpgsql security definer set search_path='' as $$
declare project_owner uuid; project_title text; project_status text;
begin
  if not public.is_admin() then raise exception 'Administrator access required'; end if;
  select owner_id,title,status into project_owner,project_title,project_status from public.student_projects where id=target_project for update;
  if not found or project_status<>'pending' then raise exception 'Pending project not found'; end if;
  update public.student_projects set status=case when approved then 'approved' else 'hidden' end,reviewed_by=auth.uid(),reviewed_at=now(),updated_at=now() where id=target_project;
  if approved then
    perform public.admin_award_points_from_bank(
      (select id from public.memberships where profile_id=project_owner),
      50,
      'Approved project: '||project_title
    );
  end if;
end $$;

create or replace function public.create_student_team(team_name text,team_description text,team_pathway text)
returns uuid language plpgsql security definer set search_path='' as $$
declare new_team uuid;
begin
  if not exists(select 1 from public.profiles p join public.memberships m on m.profile_id=p.id where p.id=auth.uid() and p.account_status='active' and m.status='active') then raise exception 'An active membership is required'; end if;
  if char_length(trim(team_name)) not between 3 and 80 or char_length(trim(team_description)) not between 10 and 1000 then raise exception 'Check team name and description'; end if;
  if team_pathway not in ('Electronics','Programming','3D Design','Environmentals','All STEM') then raise exception 'Choose a valid pathway'; end if;
  insert into public.student_teams(owner_id,name,description,pathway) values(auth.uid(),trim(team_name),trim(team_description),team_pathway) returning id into new_team;
  insert into public.student_team_members(team_id,profile_id,member_role) values(new_team,auth.uid(),'leader');
  return new_team;
end $$;

create or replace function public.join_student_team(target_team uuid)
returns boolean language plpgsql security definer set search_path='' as $$
begin
  if not exists(select 1 from public.profiles p join public.memberships m on m.profile_id=p.id where p.id=auth.uid() and p.account_status='active' and m.status='active') then raise exception 'An active membership is required'; end if;
  if not exists(select 1 from public.student_teams where id=target_team and status='open') then raise exception 'Open team not found'; end if;
  insert into public.student_team_members(team_id,profile_id) values(target_team,auth.uid()) on conflict(team_id,profile_id) do nothing;
  return found;
end $$;

create or replace function public.leave_student_team(target_team uuid)
returns void language plpgsql security definer set search_path='' as $$
begin
  if not exists(select 1 from public.profiles p join public.memberships m on m.profile_id=p.id where p.id=auth.uid() and p.account_status='active' and m.status='active') then raise exception 'An active membership is required'; end if;
  delete from public.student_team_members where team_id=target_team and profile_id=auth.uid() and member_role='member';
  if not found then raise exception 'You are not a removable member of this team'; end if;
end $$;

create or replace function public.student_team_directory()
returns table(team_id uuid,name text,description text,pathway text,member_count bigint,joined_by_me boolean,is_leader boolean)
language sql stable security definer set search_path='' as $$
  select t.id,t.name,t.description,t.pathway,
    (select count(*) from public.student_team_members count_members join public.profiles p on p.id=count_members.profile_id where count_members.team_id=t.id and p.account_status='active'),
    exists(select 1 from public.student_team_members own where own.team_id=t.id and own.profile_id=auth.uid()),
    exists(select 1 from public.student_team_members lead where lead.team_id=t.id and lead.profile_id=auth.uid() and lead.member_role='leader')
  from public.student_teams t
  where exists(select 1 from public.profiles p join public.memberships m on m.profile_id=p.id where p.id=auth.uid() and p.account_status='active' and m.status='active')
    and (t.status='open' or exists(select 1 from public.student_team_members own where own.team_id=t.id and own.profile_id=auth.uid()))
  order by t.created_at desc;
$$;

revoke all on function public.create_student_project(text,text,text,text[]) from public;
revoke all on function public.update_student_project(uuid,text,text,text,text[]) from public;
revoke all on function public.submit_student_project(uuid) from public;
revoke all on function public.delete_student_project(uuid) from public;
revoke all on function public.review_student_project(uuid,boolean) from public;
revoke all on function public.create_student_team(text,text,text) from public;
revoke all on function public.join_student_team(uuid) from public;
revoke all on function public.leave_student_team(uuid) from public;
grant execute on function public.create_student_project(text,text,text,text[]) to authenticated;
grant execute on function public.update_student_project(uuid,text,text,text,text[]) to authenticated;
grant execute on function public.submit_student_project(uuid) to authenticated;
grant execute on function public.delete_student_project(uuid) to authenticated;
grant execute on function public.review_student_project(uuid,boolean) to authenticated;
grant execute on function public.create_student_team(text,text,text) to authenticated;
grant execute on function public.join_student_team(uuid) to authenticated;
grant execute on function public.leave_student_team(uuid) to authenticated;
revoke all on function public.student_team_directory() from public;
grant execute on function public.student_team_directory() to authenticated;

drop policy if exists "project_media_authenticated_read" on storage.objects;
create policy "project_media_authenticated_read" on storage.objects for select to authenticated
  using (bucket_id='project-media' and (public.is_admin() or exists(select 1 from public.profiles p where p.id=auth.uid() and p.account_status='active') and (
    (storage.foldername(name))[1]=auth.uid()::text or exists(
      select 1 from public.student_projects p where p.status='approved' and name=any(p.media_paths)
    ) or exists(
      select 1 from public.community_posts p where p.status='approved' and (p.image_url=name or p.image_url like '%/'||name)
    )
  )));

notify pgrst,'reload schema';
commit;