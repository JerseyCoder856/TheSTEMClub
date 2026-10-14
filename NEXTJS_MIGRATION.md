# Incremental Next.js migration

The Next.js App Router owns `/`, `/login`, `/member/education`,
`/admin/learning`, and `/api/session`. Other pages remain static and are copied
to generated `public/` assets before development and production builds.
This PR completes that first migration slice; it does not port every portal page.

## Run locally or deploy to Vercel

1. Use Node.js 22.13 or newer and run `npm ci`.
2. Copy `.env.example` to `.env.local`. Supply the Supabase project URL and its
   public publishable/anon key. Both variables must point to the same project.
3. Run `npm run dev`, or `npm run build` followed by `npm start`.
4. In Vercel, choose the Next.js framework preset and configure both variables
   for each relevant environment before rebuilding. Do not set a static output
   directory: the login bridge and learning routes need the Next.js server.
5. Configure Supabase Auth redirect URLs for the deployed origin and
   `http://localhost:3000`, including `/login` and `/reset-password`.

The sync script reads `.env.local` and generates `public/portal-config.js` from
the same public variables used by Next.js. The source `portal-config.js` remains
the fallback for static-only hosting. Never supply a service-role key.

## Database compatibility

Existing installations use the tables in `supabase/schema.sql`; this migration
requires no database reset or additional SQL. New projects should follow
`MEMBER_PORTAL_SETUP.md`. Do not rerun the fresh-install schema on a live database.

Student learning lists published courses, modules, lessons, and HTTPS resources
and records completion in `lesson_progress` using the signed-in membership.
Duplicate completion preserves the original timestamp. Teachers can create
content and publish/unpublish courses, modules, and lessons. Authorization still
uses the authenticated Supabase client and existing RLS policies.

Pathway categories, automatic lesson XP, and certificates are deferred: the
current schema does not define those columns, tables, or RPCs. The application
does not promise rewards it cannot record. The existing database policies should
be separately strengthened before treating course `access_level` as a database
security boundary; this UI checks it, but the legacy course policies only check
publication.

## Validation

Run `npm run typecheck`, `npm run lint`, `npm test`, `npm run build`, and
`npm audit`. The behavior tests verify login return URL safety, selected learning
columns against the real schema, publication ordering, completion authorization,
duplicate handling, and malformed session payloads.

`npm run test:integration` builds and starts a real production Next.js server
against a local Supabase HTTP fixture. It verifies session cookies, token refresh,
member/admin route access, suspension, database outages, cross-origin rejection,
logout, and legacy routes with the real Supabase SDK. It makes no production
database changes and requires no real accounts. Run `npm run build` afterward
before serving the app normally, because this test builds with fixture variables.

Before production rollout, verify with staging member and administrator accounts:

- Sign in, move between Next.js learning and legacy Passport/Workspace pages,
  refresh the page, and sign out from both interfaces.
- Confirm suspended accounts cannot enter learning or submit completion.
- Create a draft module and lesson, publish them, and verify their order as a member.
- Complete a lesson twice and confirm one progress record with its original date.
- Check password reset and signup callbacks on the actual deployment origin.

These account tests require staging credentials and cannot be replaced by a
successful unauthenticated build or preview deployment.
