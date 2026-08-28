# The STEM Club Passport — Supabase launch guide

## Run exactly one migration

Use only **`supabase/schema.sql`**. Do not combine it with an older SQL file.

1. Open `supabase/schema.sql` and replace the single placeholder `[MY EMAIL ADDRESS]` with the exact email already shown for your owner in **Supabase → Authentication → Users**. Keep the single quotes.
2. In **Supabase → SQL Editor → New query**, paste the complete raw contents of `supabase/schema.sql` and select **Run**.
3. The migration preserves `auth.users`, creates the application tables, backfills every existing Auth user, gives the owner the first available number (`TSC-0001` in an empty application database), promotes the matching owner to `admin`, and asks PostgREST to reload its schema cache.
4. Confirm the final result with:
   ```sql
   select u.email, p.role, p.account_status, m.membership_number, m.status
   from auth.users u
   join public.profiles p on p.id = u.id
   join public.memberships m on m.profile_id = p.id
   where lower(u.email) = lower('YOUR REAL OWNER EMAIL');
   ```
   It should return exactly one row with `admin`, `active`, and `TSC-0001` when this is the first application membership.

The destructive reset section at the top of the migration is commented out. Leave it commented. It is only a recovery aid for a brand-new project with no real application data; it never deletes `auth.users`.

## Frontend connection

The supplied Project URL and publishable browser key are already present in `portal-config.js`. This static site does not use Next.js, so `NEXT_PUBLIC_*` variables are not read at runtime. A publishable key is appropriate in browser code because all access is constrained by RLS. Never add the database password or `service_role` key to the repository.

## Authentication dashboard

In **Authentication → URL Configuration** set:

- Site URL: `https://thestemclub.net`
- Redirect URLs:
  - `https://thestemclub.net/login`
  - `https://thestemclub.net/forgot-password`
  - `http://localhost:8080/login` for local testing only

Enable Email/Password authentication. For production, require email confirmation and configure a production SMTP provider so confirmation and reset messages are reliable.

## Storage

No Storage bucket is required for this release. Community images, badge icons, course covers, and learning resources currently accept validated HTTPS URLs. Before enabling uploads, create private/moderated buckets and add MIME type, size, ownership, and review policies; do not make a public youth-member upload bucket.

## Email and video providers

- The Outreach screen securely retrieves attendee emails through an admin-only database function and exports a BCC/CSV list. It does **not** pretend to send email.
- Direct bulk sending still requires a server-side Supabase Edge Function plus Resend, Postmark, or SendGrid credentials stored as Edge Function secrets. Never call a bulk email provider with a secret from `portal.js`.
- Lessons accept only HTTPS YouTube, youtu.be, or Vimeo URLs. No video API key is required.

## First test

1. Sign in with the existing owner account and open `/admin`.
2. Register a second email through `/signup`; it should receive the next membership number and remain a regular member.
3. Create an open event, scan the member card, and scan it again to confirm duplicate protection.
4. Create a badge with a point value and award it from the member detail page; award it again to confirm duplicate protection.
5. Bulk-award event points twice with the same amount and reason; the second operation should add zero duplicate transactions.
6. Sign in as the regular member and confirm `/admin` redirects away and direct admin RPC calls are rejected.
7. Publish a course/module/lesson, then confirm it appears in Learning.
8. Submit a community post and recognition as the member; approve them as admin and confirm they appear in the member feed.
9. Confirm the welcome tour appears once, then replay it from Settings.
10. Load Outreach for the event, verify only the admin can see emails, and export the CSV.

## Intentionally incomplete external work

- Direct bulk-email delivery is not enabled until an email provider and Edge Function are configured.
- Managed file uploads are not enabled; this avoids unsafe public uploads until storage moderation rules are approved.
- Production SMTP, backups, custom-domain verification, and physical iOS/Android QR tests must be completed in the Supabase/deployment environments.
