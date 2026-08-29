-- Additive media storage for moderated projects and administrator badge art.
-- Run after supabase/schema.sql. This does not alter or delete existing records.
begin;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values
  ('project-media','project-media',false,20971520,array['image/jpeg','image/png','image/webp','video/mp4','video/webm']),
  ('badge-assets','badge-assets',true,5242880,array['image/jpeg','image/png','image/webp','image/svg+xml'])
on conflict (id) do update set
  file_size_limit=excluded.file_size_limit,
  allowed_mime_types=excluded.allowed_mime_types;

-- A member owns only objects inside their UUID folder.
drop policy if exists "project_media_member_insert" on storage.objects;
create policy "project_media_member_insert" on storage.objects for insert to authenticated
with check (bucket_id='project-media' and (storage.foldername(name))[1]=auth.uid()::text);
drop policy if exists "project_media_owner_delete" on storage.objects;
create policy "project_media_owner_delete" on storage.objects for delete to authenticated
using (bucket_id='project-media' and ((storage.foldername(name))[1]=auth.uid()::text or public.is_admin()));
-- Signed reads work for the owner/admin. Approved project media is exposed through
-- the signed URL created by the authenticated portal, never as a public bucket URL.
drop policy if exists "project_media_authenticated_read" on storage.objects;
create policy "project_media_authenticated_read" on storage.objects for select to authenticated
using (bucket_id='project-media' and ((storage.foldername(name))[1]=auth.uid()::text or public.is_admin()
  or exists (select 1 from public.community_posts p where p.status='approved' and p.image_url like '%/' || name)));

-- Badge artwork is publicly readable, but only active database administrators write it.
drop policy if exists "badge_assets_admin_insert" on storage.objects;
create policy "badge_assets_admin_insert" on storage.objects for insert to authenticated
with check (bucket_id='badge-assets' and public.is_admin());
drop policy if exists "badge_assets_admin_update" on storage.objects;
create policy "badge_assets_admin_update" on storage.objects for update to authenticated
using (bucket_id='badge-assets' and public.is_admin()) with check (bucket_id='badge-assets' and public.is_admin());
drop policy if exists "badge_assets_admin_delete" on storage.objects;
create policy "badge_assets_admin_delete" on storage.objects for delete to authenticated
using (bucket_id='badge-assets' and public.is_admin());
drop policy if exists "badge_assets_public_read" on storage.objects;
create policy "badge_assets_public_read" on storage.objects for select to public
using (bucket_id='badge-assets');

commit;
