#!/usr/bin/env node
const fs = require('node:fs');
const assert = require('node:assert/strict');
const schema = fs.readFileSync('supabase/schema.sql', 'utf8');
const migrations = fs.readdirSync('supabase/migrations').map(file => fs.readFileSync(`supabase/migrations/${file}`, 'utf8')).join('\n');
const databaseSql = `${schema}\n${migrations}`;
const portal = fs.readFileSync('portal.js', 'utf8');
const tables = [
  'profiles','memberships','events','attendance','point_transactions','badges',
  'member_badges','audit_logs','event_registrations','courses','course_modules',
  'lessons','resources','lesson_progress','community_posts','post_reactions',
  'post_reports','recognitions','recognition_reactions','recognition_reports',
  'outreach_campaigns'
];
for (const table of tables) {
  assert.equal((schema.match(new RegExp(`create table public\\.${table} \\(`, 'g')) || []).length, 1, `${table} must be defined once`);
  assert.ok(schema.includes(`alter table public.${table} enable row level security;`), `${table} must have RLS`);
}
const storageBuckets = ['project-media', 'badge-assets'];
for (const table of [...portal.matchAll(/\.from\('([^']+)'\)/g)].map(m => m[1]).filter(name => !storageBuckets.includes(name))) {
  assert.ok(tables.includes(table), `portal table ${table} is missing`);
}
for (const rpc of [...portal.matchAll(/\.rpc\('([^']+)'/g)].map(m => m[1])) {
  assert.ok(databaseSql.includes(`function public.${rpc}(`), `portal RPC ${rpc} is missing`);
}
assert.ok(schema.includes("default ('TSC-' || lpad(nextval('public.membership_number_seq')::text, 4, '0'))"));
assert.ok(schema.includes("notify pgrst, 'reload schema';"));
assert.ok(!schema.includes('drop table if exists auth.users'));
assert.ok(!schema.split('\n').some(line => line.startsWith('|')), 'schema must be raw SQL');
assert.ok(!/\b[a-z]+\\_[a-z]+\b/.test(schema), 'schema contains escaped Markdown underscores');
assert.equal((schema.match(/^begin;$/gm) || []).length, 1);
assert.equal((schema.match(/^commit;$/gm) || []).length, 1);
console.log(`Portal contract OK: ${tables.length} RLS tables and all frontend RPCs are defined.`);

const resetPage = fs.readFileSync('reset-password/index.html', 'utf8');
const mediaMigration = fs.readFileSync('supabase/migrations/202608290001_portal_media_storage.sql', 'utf8');
for (const bucket of storageBuckets) assert.ok(mediaMigration.includes(`'${bucket}'`), `${bucket} storage setup is missing`);
assert.ok(mediaMigration.includes("public.is_admin()"), 'badge uploads must remain administrator-authorized');
assert.equal(
  (portal.match(/resetPasswordForEmail\(email,\{redirectTo:'https:\/\/thestemclub\.net\/reset-password'\}\)/g) || []).length,
  1,
  'password recovery must use the production reset page'
);
assert.ok(!/resetPasswordForEmail[^\n]*localhost/.test(portal), 'password recovery must not use localhost');
assert.ok(resetPage.includes('data-auth="reset-password"'), 'reset page must provide the password form');
assert.ok(portal.includes('client.auth.updateUser({password})'), 'reset form must update the Supabase user');
assert.ok(portal.includes("client.auth.exchangeCodeForSession(query.get('code'))"), 'PKCE recovery codes must be exchanged');
assert.ok(portal.includes("client.auth.setSession({access_token:hash.get('access_token'),refresh_token:hash.get('refresh_token')})"), 'hash recovery tokens must establish a session');
assert.ok(portal.includes("event==='PASSWORD_RECOVERY'"), 'recovery must wait for the PASSWORD_RECOVERY event');
assert.ok(portal.includes("location.assign('/login?password-reset=success')"), 'successful password reset must return to login with confirmation state');
assert.ok(resetPage.includes('disabled data-recovery-submit'), 'reset submit must start disabled');

const htmlFiles = fs.readdirSync('.', {recursive: true})
  .filter(name => name.endsWith('.html'));
for (const file of htmlFiles) {
  const html = fs.readFileSync(file, 'utf8');
  assert.ok((html.match(/<!doctype html>/gi) || []).length <= 1, `${file} contains concatenated documents`);
}
const functionNames = [...portal.matchAll(/^\s*(?:async\s+)?function\s+([\w$]+)\s*\(/gm)].map(match => match[1]);
assert.equal(new Set(functionNames).size, functionNames.length, 'portal.js contains duplicate function declarations');
