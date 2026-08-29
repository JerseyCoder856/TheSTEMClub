#!/usr/bin/env node
const fs=require('node:fs');
const assert=require('node:assert/strict');
const ux=fs.readFileSync('portal-ux.js','utf8');
const css=fs.readFileSync('portal.css','utf8');
const sql=fs.readFileSync('supabase/migrations/202608290005_workspace_workflows.sql','utf8');
const portal=fs.readFileSync('portal.js','utf8');

for(const width of ['900px','640px']) assert.ok(css.includes(`max-width:${width}`),`responsive breakpoint ${width} missing`);
assert.ok(css.includes('.portal-table.responsive-table tr{padding:12px'), 'wide point ledger must become mobile cards');
assert.ok(css.includes('min-height:48px;font-size:16px'), 'mobile controls must be touch-friendly and avoid iOS zoom');
assert.ok(ux.includes("localStorage.getItem('stem-language')"));
assert.ok(ux.includes("localStorage.setItem('stem-language'"));
assert.ok(ux.includes("document.documentElement.lang=getLang()"));
for(const control of ['data-pause-scan','data-switch-camera','data-close-scan','data-manual-form']) assert.ok(ux.includes(control),`${control} missing`);
assert.ok(ux.includes("await window._scanner.stop()"), 'camera stream must stop');
assert.ok(sql.includes('unique (event_id, member_id)') || fs.readFileSync('supabase/schema.sql','utf8').includes('unique (event_id, member_id)'), 'attendance must reject duplicates');
assert.ok(sql.includes("if not public.is_admin() then raise exception 'Administrator access required'"));
assert.ok(sql.includes("for update"), 'point bank must be locked during an award');
assert.ok(sql.includes("if b < points") && sql.includes("if b < attendee_count*points"), 'individual and bulk awards must prevent overdrafts');
assert.ok(sql.includes("idempotency_key"), 'point workflows must be idempotent');
assert.ok(portal.includes("confirm(`Award ${Number(d.get('points'))} points to every checked-in attendee?`)"), 'bulk awards require confirmation');
for(const action of ['data-notification-count','data-mark-all','data-notification-id']) assert.ok(ux.includes(action),`${action} missing`);
for(const action of ['data-tour-back','data-tour-next','data-tour-skip','tour-progress']) assert.ok(ux.includes(action),`${action} missing`);
assert.ok(!fs.readFileSync('supabase/migrations/202608290001_portal_media_storage.sql','utf8').includes("('project-media','project-media',true"),'project-media must remain private');
console.log('Workspace workflow contract OK: responsive, bilingual, scanner, rewards, notifications, and tours verified.');
