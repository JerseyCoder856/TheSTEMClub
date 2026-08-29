-- Additive teacher reward bank. Each active admin begins with 10,000 award points.
begin;
create table if not exists public.admin_point_banks (
  administrator_id uuid primary key references public.profiles(id) on delete cascade,
  balance integer not null default 10000 check (balance >= 0),
  updated_at timestamptz not null default now()
);
alter table public.admin_point_banks enable row level security;
create policy "admins_read_own_point_bank" on public.admin_point_banks for select to authenticated using (administrator_id=auth.uid() and public.is_admin());

create or replace function public.admin_point_bank_balance() returns integer language plpgsql security definer set search_path=public,pg_temp as $$
declare b integer;
begin
 if not public.is_admin() then raise exception 'Administrator access required'; end if;
 insert into public.admin_point_banks(administrator_id) values(auth.uid()) on conflict do nothing;
 select balance into b from public.admin_point_banks where administrator_id=auth.uid(); return b;
end $$;

create or replace function public.admin_award_points_from_bank(target_member uuid, points integer, award_reason text) returns integer language plpgsql security definer set search_path=public,pg_temp as $$
declare b integer;
begin
 if not public.is_admin() then raise exception 'Administrator access required'; end if;
 if points <= 0 or points > 10000 then raise exception 'Award must be between 1 and 10,000 points'; end if;
 if length(trim(award_reason)) < 3 then raise exception 'A clear reason is required'; end if;
 insert into public.admin_point_banks(administrator_id) values(auth.uid()) on conflict do nothing;
 select balance into b from public.admin_point_banks where administrator_id=auth.uid() for update;
 if b < points then raise exception 'Teacher point bank has insufficient points'; end if;
 update public.admin_point_banks set balance=balance-points,updated_at=now() where administrator_id=auth.uid();
 insert into public.point_transactions(member_id,amount,reason,awarded_by,source_key) values(target_member,points,trim(award_reason),auth.uid(),'teacher-bank:'||gen_random_uuid());
 return b-points;
end $$;
revoke all on function public.admin_point_bank_balance() from public;
revoke all on function public.admin_award_points_from_bank(uuid,integer,text) from public;
grant execute on function public.admin_point_bank_balance() to authenticated;
grant execute on function public.admin_award_points_from_bank(uuid,integer,text) to authenticated;
commit;
