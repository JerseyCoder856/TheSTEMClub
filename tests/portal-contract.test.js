#!/usr/bin/env node
const fs = require('node:fs');
const assert = require('node:assert/strict');
const schema = fs.readFileSync('supabase/schema.sql', 'utf8');
const migrations = fs.readdirSync('supabase/migrations').map(file => fs.readFileSync(`supabase/migrations/${file}`, 'utf8')).join('\n');
const databaseSql = `${schema}\n${migrations}`;
const portal = fs.readFileSync('portal.js', 'utf8');
assert.ok(portal.includes("['/my-passport','My Passport']"), 'teacher workspace must link to the signed-in user\'s own Passport');
const adminHome = fs.readFileSync('admin/index.html', 'utf8');
assert.ok(adminHome.includes('class="btn-pill-yellow open-student-account" href="/my-passport?view=student">Open Student Account</a>'), 'admin overview must expose the student account preview');
assert.ok(portal.includes("path==='/my-passport'&&new URLSearchParams(location.search).get('view')==='student'"), 'student preview must be scoped to the Passport route');
assert.ok(portal.includes("if(path==='/member'){location.replace('/my-passport');return}"), 'legacy member dashboard must route to the canonical Passport');
assert.ok(portal.includes("dashboard.href='/my-passport'"), 'member navigation must return to the canonical Passport');
for (const helper of ['function loadNotificationCount()', 'function notificationDialog()', 'function feedbackDialog()']) {
  assert.ok(portal.includes(helper), `${helper} must be implemented for the workspace toolbar`);
}
assert.ok(portal.includes("client.rpc('member_notifications')"), 'notification UI must use the member-scoped notification RPC');
assert.ok(portal.includes("client.rpc('mark_notifications_read',{notification_ids:unread})"), 'opening notifications must mark only returned unread rows as read');
for (const helper of ['function mountStudentWorkspace()', 'async function loadStudentHome()', 'async function memberExplore()', 'async function memberBuild()', 'async function memberTeams()', 'async function memberClub()', 'async function profilePortfolio()', 'async function memberSettings()']) {
  assert.ok(portal.includes(helper), `${helper} must be implemented`);
}
for (const rpc of ['complete_student_lesson','create_student_project','update_student_project','submit_student_project','delete_student_project','review_student_project','create_student_team','student_team_directory','join_student_team','leave_student_team']) {
  assert.ok(portal.includes(`client.rpc('${rpc}'`), `${rpc} must be called by the portal`);
}
assert.ok(portal.includes("client.rpc('update_communication_preference'"), 'member communication preference must be persisted through its RPC');
const tables = [
  'profiles','memberships','events','attendance','point_transactions','badges',
  'member_badges','audit_logs','event_registrations','courses','course_modules',
  'lessons','resources','lesson_progress','community_posts','post_reactions',
  'post_reports','recognitions','recognition_reactions','recognition_reports',
  'outreach_campaigns','member_certificates','student_projects','student_teams','student_team_members'
];
for (const table of tables) {
  const createPattern = new RegExp(`create table(?: if not exists)? public\\.${table} \\(`, 'g');
  assert.equal((databaseSql.match(createPattern) || []).length, 1, `${table} must be defined once`);
  assert.ok(databaseSql.includes(`alter table public.${table} enable row level security;`), `${table} must have RLS`);
}
const storageBuckets = ['project-media', 'badge-assets', 'profile-photos'];
for (const table of [...portal.matchAll(/\.from\('([^']+)'\)/g)].map(m => m[1]).filter(name => !storageBuckets.includes(name))) {
  assert.ok(tables.includes(table)||['feedback','feedback_requests'].includes(table), `portal table ${table} is missing`);
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
for (const bucket of storageBuckets) assert.ok(migrations.includes(`'${bucket}'`), `${bucket} storage setup is missing`);
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
assert.ok(portal.includes("access.role==='admin'?'/admin':'/my-passport'"), 'login must route database administrators to the teacher workspace');
assert.ok(portal.includes(".eq('id',userId).maybeSingle()"), 'profile lookup must tolerate a missing row and report it explicitly');
assert.ok(portal.includes('No STEM Club profile exists for this sign-in.'), 'a missing profile must produce an actionable error');
const passportPage = fs.readFileSync('my-passport/index.html', 'utf8');
assert.ok(passportPage.includes('data-admin-access'), 'Passport must expose teacher tools after the database confirms admin access');
assert.ok(passportPage.includes('data-passport-point-bank'), 'Passport must expose the teacher reward-bank balance');
for (const route of ['my-card', 'member/education', 'member/community', 'member/events', 'member/achievements', 'member/membership', 'member/profile', 'member/settings']) {
  assert.ok(passportPage.includes(`href="/${route}"`), `Passport must link to /${route}`);
  assert.ok(fs.existsSync(`${route}/index.html`), `/${route} must be a published student destination`);
}

const htmlFiles = fs.readdirSync('.', {recursive: true})
  .filter(name => name.endsWith('.html'));
for (const file of htmlFiles) {
  const html = fs.readFileSync(file, 'utf8');
  assert.ok((html.match(/<!doctype html>/gi) || []).length <= 1, `${file} contains concatenated documents`);
  assert.ok((html.match(/<main\b/gi) || []).length <= 1, `${file} contains duplicated main page content`);
  const configPosition = html.indexOf('/portal-config.js?v=20260829-admin-access-2');
  const portalPosition = html.indexOf('/portal.js?v=20260829-admin-access-2');
  if (portalPosition !== -1) assert.ok(configPosition !== -1 && configPosition < portalPosition, `${file} must load the versioned config before portal.js`);
}
const functionNames = [...portal.matchAll(/^\s*(?:async\s+)?function\s+([\w$]+)\s*\(/gm)].map(match => match[1]);
assert.equal(new Set(functionNames).size, functionNames.length, 'portal.js contains duplicate function declarations');

const requiredAdminRoutes = ['admin', 'admin/badges', 'admin/learning', 'admin/events', 'admin/points'];
for (const route of requiredAdminRoutes) assert.ok(fs.existsSync(`${route}/index.html`), `/${route} must be present in the static publish output`);
for (const route of ['member/explore','member/build','member/teams','member/club']) assert.ok(fs.existsSync(`${route}/index.html`), `/${route} student portal route must be present in the static publish output`);
const studentStyles = fs.readFileSync('student-portal.css','utf8');
for (const color of ['#29ABE2','#FFD20A','#FF3038','#7ED957']) assert.ok(studentStyles.includes(color), `student portal must preserve pathway color ${color}`);
assert.ok(migrations.includes("where role = 'admin' and account_status = 'active'"), 'point banks must be seeded from active database administrators');
assert.match(migrations, /values\s*\(\s*'project-media',\s*'project-media',\s*false/, 'project-media must remain private');
const workspaceMigration = fs.readFileSync('supabase/migrations/202608290005_feedback_notifications.sql', 'utf8');
for (const table of ['notifications', 'feedback']) {
  assert.ok(workspaceMigration.includes(`create table if not exists public.${table}`), `${table} migration is missing`);
  assert.ok(workspaceMigration.includes(`alter table public.${table} enable row level security`), `${table} must have RLS`);
}
assert.ok(workspaceMigration.includes('profile_id = auth.uid()'), 'workspace messages must remain scoped to the signed-in profile');
assert.ok(workspaceMigration.includes("set search_path = ''"), 'security-definer notification writes must pin the search path');
assert.ok(portal.includes("localStorage.getItem('stem-language')"), 'workspace must persist the English/Spanish preference');
assert.ok(portal.includes("client.rpc('submit_feedback'"), 'feedback must use the RLS-backed RPC');
assert.ok(portal.includes("client.rpc('member_notifications'"), 'notifications must use the member-scoped RPC');
const studentLearningMigration = fs.readFileSync('supabase/migrations/202609270001_student_learning_progress.sql', 'utf8');
const studentProjectsMigration = fs.readFileSync('supabase/migrations/202609270002_student_projects_teams.sql', 'utf8');
assert.ok(studentLearningMigration.includes("'stem-path-electronics'") && studentLearningMigration.includes("'stem-path-programming'") && studentLearningMigration.includes("'stem-path-3d-design'") && studentLearningMigration.includes("'stem-path-environmentals'"), 'all four designed learning paths must be seeded');
assert.ok(studentLearningMigration.includes('revoke insert, update, delete on public.lesson_progress from authenticated'), 'students must not directly forge lesson completion rows');
assert.ok(studentLearningMigration.includes("'lesson:'||member_key::text||':'||target_lesson::text"), 'lesson XP must use an idempotent source key');
assert.ok(studentLearningMigration.includes('member_certificates'), 'path completion must persist certificates');
for (const table of ['student_projects','student_teams','student_team_members']) {
  assert.ok(studentProjectsMigration.includes(`alter table public.${table} enable row level security`), `${table} must enforce RLS`);
}
for (const rpc of ['create_student_project','update_student_project','submit_student_project','delete_student_project','review_student_project','create_student_team','student_team_directory','join_student_team','leave_student_team']) {
  assert.ok(studentProjectsMigration.includes(`function public.${rpc}(`), `${rpc} migration is missing`);
}
assert.ok(studentProjectsMigration.includes('admin_award_points_from_bank'), 'student project awards must debit the administrator reward bank');
const workflowsMigration = fs.readFileSync('supabase/migrations/202608290006_workspace_workflows.sql', 'utf8');
for (const rpc of ['admin_review_recognition','admin_request_feedback','respond_to_feedback_request']) assert.ok(workflowsMigration.includes(`function public.${rpc}(`), `${rpc} workflow RPC is missing`);
for (const activity of ['notify_attendance','notify_points','notify_badges','notify_feedback_request','notify_admin_feedback','notify_admin_recognition']) assert.ok(workflowsMigration.includes(`trigger ${activity}`), `${activity} notification trigger is missing`);
assert.ok(portal.includes("facingMode:{ideal:'environment'}"), 'scanner must prefer the rear camera');
assert.ok(portal.includes("window.addEventListener('pagehide',stop"), 'scanner must clean up camera access');
assert.ok(portal.includes("data-manual-scan"), 'scanner must provide manual fallback');
assert.ok(portal.includes("data-tour-back"), 'guided tour must provide Back navigation');
assert.ok(fs.existsSync('admin/notifications/index.html'), 'unified teacher notification route must exist');
