#!/usr/bin/env node
const fs = require('node:fs');
const assert = require('node:assert/strict');
const schema = fs.readFileSync('supabase/schema.sql', 'utf8');
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
for (const table of [...portal.matchAll(/\.from\('([^']+)'\)/g)].map(m => m[1])) {
  assert.ok(tables.includes(table), `portal table ${table} is missing`);
}
for (const rpc of [...portal.matchAll(/\.rpc\('([^']+)'/g)].map(m => m[1])) {
  assert.ok(schema.includes(`function public.${rpc}(`), `portal RPC ${rpc} is missing`);
}
assert.ok(schema.includes("default ('TSC-' || lpad(nextval('public.membership_number_seq')::text, 4, '0'))"));
assert.ok(schema.includes("notify pgrst, 'reload schema';"));
assert.ok(!schema.includes('drop table if exists auth.users'));
assert.ok(!schema.split('\n').some(line => line.startsWith('|')), 'schema must be raw SQL');
assert.ok(!/\b[a-z]+\\_[a-z]+\b/.test(schema), 'schema contains escaped Markdown underscores');
assert.equal((schema.match(/^begin;$/gm) || []).length, 1);
assert.equal((schema.match(/^commit;$/gm) || []).length, 1);
console.log(`Portal contract OK: ${tables.length} RLS tables and all frontend RPCs are defined.`);
