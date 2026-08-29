-- Ensure every currently active administrator has the private 10,000-point bank.
-- This is additive and intentionally derives administrators from database roles, not email.
begin;
insert into public.admin_point_banks (administrator_id)
select id
from public.profiles
where role = 'admin' and account_status = 'active'
on conflict (administrator_id) do nothing;
commit;
