# The STEM Club Passport — production setup

## Quick connection (4 steps)

1. In your Supabase project, open **SQL Editor → New query**, open the repository’s raw **`supabase/schema.sql`** file, copy its entire contents, paste it, and click **Run**.
2. Open **Project Settings → API**. Copy the **Project URL** and the **publishable** key (the legacy `anon` key also works) into `portal-config.js`:
   ```js
   window.STEM_CLUB_SUPABASE = {
     url: 'https://YOUR_PROJECT_REF.supabase.co',
     anonKey: 'YOUR_PUBLISHABLE_KEY'
   };
   ```
3. Open **Authentication → URL Configuration**. Set **Site URL** to `https://thestemclub.net` and add `https://thestemclub.net/login` as a redirect URL.
4. Deploy, create your account at `/signup`, then promote it with the SQL command in step 6 below.

Only the publishable/anon key belongs in `portal-config.js`. Never paste the database password or `service_role` key into a website file.

## Architecture

The public website remains static HTML/CSS/JavaScript. The Passport adds Supabase Auth and managed PostgreSQL without exposing a database password or service-role key in the browser. PostgreSQL Row Level Security owns access control; security-definer functions perform public verification, atomic check-in, and bulk points operations.

## One-time Supabase setup

1. Create a **new Supabase project** (the schema is intended for a fresh project) and save its database password securely.
2. Open **SQL Editor**, paste `supabase/schema.sql`, and run it once.
3. In **Authentication → Providers → Email**, enable email/password. Require email confirmation for production and configure a production SMTP service.
4. In **Authentication → URL Configuration**, set the Site URL to `https://thestemclub.net` and add `https://thestemclub.net/login`, plus local development URLs such as `http://localhost:8080/login`, to Redirect URLs.
5. Copy the project URL and **publishable/anon key** from **Project Settings → API** into `portal-config.js`. The anon key is intentionally public and constrained by RLS. Never put the service-role key in this repository.
6. Register the organization owner's account through `/signup`. The first registered account receives `TSC-0001`. In SQL Editor, promote only that account: `update public.profiles set role='admin' where id='AUTH_USER_UUID';` Obtain the UUID from Authentication → Users.
7. Test login, then open `/admin`. Create an open workshop before using `/admin/attendance`.

## Which login can I use?

There is deliberately no shared or hardcoded password in this repository. After completing steps 1–5, open `/signup` and register the email and password you want to use for testing. In a fresh database that first account receives `TSC-0001`. If you promote that account with step 6, the same credentials can test both the member Passport and `/admin` because authorization comes from its database role. To test member restrictions separately, register a second account and leave its role as `member`; it receives `TSC-0002` and must be denied access to `/admin`.

## Hosting requirements

The current deployment must serve each directory's `index.html` for extensionless routes. HTTPS is mandatory for phone camera access. If the host does not support directory indexes, add rewrites from `/my-card`, `/my-passport`, `/verify`, and `/admin/*` to their corresponding `index.html` files.

The QR contains only `https://thestemclub.net/verify/?token=<random UUID>`. Status is looked up live, so deactivation does not require a replacement card. The public RPC returns only membership number, status, and issue/expiration dates.

## Operational checks before launch

- Confirm email delivery and password reset templates.
- Confirm a member receives `TSC-0001` in a fresh database and later registrations increment without duplicates.
- Confirm logged-out and member accounts cannot read or write admin data.
- Scan a printed and on-screen card on iOS and Android over HTTPS.
- Configure Supabase database backups and review Auth/audit logs regularly.
- For minors, add the organization's approved guardian consent and privacy workflow before collecting additional personal data.
