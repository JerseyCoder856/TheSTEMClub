# Platform repair audit

## Routes

- Public: `/`, `/blog.html`, `/support.html`, `/checkout.html`
- Authentication: `/signup`, `/login`, `/forgot-password`, `/reset-password`
- Member: `/member`, `/member/education`, `/member/community`, `/member/events`,
  `/member/achievements`, `/member/membership`, `/member/profile`, `/member/settings`
- Administration: `/admin`, `/admin/members`, `/admin/member`, `/admin/attendance`,
  `/admin/events`, `/admin/event`, `/admin/points`, `/admin/badges`, `/admin/learning`,
  `/admin/community`, `/admin/recognitions`, `/admin/outreach`, `/admin/audit`, `/admin/settings`

## Confirmed root cause and repair

Fourteen route files contained two HTML documents concatenated into one file. `portal.js`
also contained an older implementation block appended after the current block, producing
duplicate declarations and duplicate listeners. These were source-file concatenation errors,
not CSS rendering errors. The extra documents and old JavaScript block were removed, and the
contract test now rejects either regression.

Password recovery now supports PKCE codes and legacy hash tokens, requires an authenticated
recovery signal before enabling the form, checks the result of `updateUser`, signs out the
recovery session, and returns an explicit success state to login. Invalid links remain disabled
and offer a new-link action.

## Production verification still required

This repository does not contain production credentials or test-user passwords. The following
cannot truthfully be certified from a static checkout and must be run against the deployed
Supabase project: email delivery, owner password reset and subsequent login, camera permission
on a physical phone, and two-account RLS tests. Do not mark those checks complete until the
manual checklist below passes.

1. In Supabase Auth URL Configuration set Site URL to `https://thestemclub.net` and add exactly
   `https://thestemclub.net/reset-password` to Redirect URLs. Remove localhost entries used by
   production email flows.
2. Run `supabase/schema.sql` only on a new project. For an existing production project, inspect
   applied migrations first; never use the commented reset section.
3. Confirm the owner with:
   `select u.email,p.role,p.account_status,m.status as membership_status from auth.users u join public.profiles p on p.id=u.id join public.memberships m on m.profile_id=p.id where lower(u.email)='jeremiah@thestemclub.net';`
4. Deploy the static files, clear the CDN cache, then request a fresh recovery email. Confirm the
   landing URL is production, set a password, see the login success message, and sign in with it.
5. With the owner, visit every administration route and perform a reversible test action. With a
   regular member in a separate private window, verify `/admin` redirects and direct admin RPCs
   return an authorization error. Repeat with a suspended member and verify portal access ends.

## Known unfinished scope

Interest-tag targeting, announcement delivery/read state, safe member-to-member point transfers,
and the full course authoring expansion requested in the redesign brief
are not implemented in this repair commit. Existing events, attendance, points, badges, learning,
community, recognition, outreach, and audit features remain in place; they require the production
two-account verification above. Google Sheets synchronization, outbound email, and web push are
not configured and must not be advertised as active.

## Media migration added

Run `supabase/migrations/202608290001_portal_media_storage.sql` once in the
Supabase SQL Editor after the base schema. It creates the private `project-media`
bucket and public-read `badge-assets` bucket with MIME limits, ownership rules,
administrator-only badge writes, and approved-project signed-read policies. Do
not manually make `project-media` public. The portal generates unique filenames;
no service-role key is used in the browser.

Run `supabase/migrations/202608290002_admin_point_bank.sql` next. It creates an
RLS-enabled 10,000-point teacher reward bank and a database-authorized atomic
award function. Only an active `admin` can read their bank or issue rewards;
the debit and member ledger entry succeed or fail together.

Run `supabase/migrations/202608290003_owner_avatar_access.sql` third. It
reasserts the configured owner as an active database administrator, keeps the
owner membership active, adds the private `profile-photos` bucket, and allows
members to manage only photos stored under their own authenticated UUID.
