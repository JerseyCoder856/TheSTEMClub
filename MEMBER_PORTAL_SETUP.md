# Member portal setup

## What is included

This static website now includes branded member routes and a Supabase-backed authentication/data foundation. Authentication is performed by Supabase Auth; browser code never handles password hashing or payment/role decisions. The SQL schema creates member IDs, membership records, course hierarchy, moderated community data, events/attendance, achievements, and restrictive Row Level Security policies.

## Required external setup

1. Create a Supabase project and run `supabase/schema.sql` in its SQL Editor.
2. In **Authentication → URL Configuration**, add the production domain and the local development URL to the allowed redirect URLs, including `/login` for confirmation and password reset links.
3. Add the Supabase project URL and **anon/publishable** key to `portal-config.js`. Do not put a service-role key in this website.
4. Configure email confirmation and password-reset email templates in Supabase Auth. A production SMTP provider is recommended before launch.
5. Create the initial user, then promote that specific user using the commented `update public.profiles` statement at the bottom of the schema. Do not grant admin from the browser.
6. Ensure static hosting serves directory indexes for `/login`, `/member`, and the other portal routes. If the host requires rewrite rules for extensionless paths, add them in its hosting configuration.

## Security notes

* Membership status, member roles, achievements, attendance, and premium access are database-owned fields; there are no client-side controls that can update them.
* RLS limits profiles and memberships to their owner (or an administrator), limits published premium material to active STEM Club members, and keeps community content in a pending/approved moderation flow.
* No direct messages, public member directory, payment integration, QR scanner, or unmoderated publishing is included.
