-- Preserve owner teacher access and add private member profile photos.
begin;
alter table public.profiles add column if not exists avatar_path text;
update public.profiles p set role='admin',account_status='active',updated_at=now()
from auth.users u where u.id=p.id and lower(u.email)='jeremiah@thestemclub.net';
update public.memberships m set status='active',updated_at=now()
from auth.users u where u.id=m.profile_id and lower(u.email)='jeremiah@thestemclub.net';
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('profile-photos','profile-photos',false,5242880,array['image/jpeg','image/png','image/webp'])
on conflict(id) do update set file_size_limit=excluded.file_size_limit,allowed_mime_types=excluded.allowed_mime_types;
drop policy if exists "profile_photos_owner_insert" on storage.objects;
create policy "profile_photos_owner_insert" on storage.objects for insert to authenticated with check(bucket_id='profile-photos' and (storage.foldername(name))[1]=auth.uid()::text);
drop policy if exists "profile_photos_owner_read" on storage.objects;
create policy "profile_photos_owner_read" on storage.objects for select to authenticated using(bucket_id='profile-photos' and ((storage.foldername(name))[1]=auth.uid()::text or public.is_admin()));
drop policy if exists "profile_photos_owner_delete" on storage.objects;
create policy "profile_photos_owner_delete" on storage.objects for delete to authenticated using(bucket_id='profile-photos' and ((storage.foldername(name))[1]=auth.uid()::text or public.is_admin()));
create or replace function public.update_profile_avatar(new_avatar_path text) returns void
language plpgsql security definer set search_path=public,pg_temp as $$
begin
  if auth.uid() is null or not (new_avatar_path like (auth.uid()::text || '/%')) then raise exception 'Invalid profile photo path'; end if;
  update public.profiles set avatar_path=new_avatar_path,updated_at=now() where id=auth.uid() and account_status='active';
  if not found then raise exception 'Active profile required'; end if;
end $$;
revoke all on function public.update_profile_avatar(text) from public;
grant execute on function public.update_profile_avatar(text) to authenticated;
commit;
