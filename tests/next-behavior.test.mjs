import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import ts from "typescript";

function load(file, dependencies = {}) {
  const source = readFileSync(new URL(`../${file}`, import.meta.url), "utf8");
  const { outputText } = ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 } });
  const exports = {};
  new Function("require", "exports", outputText)((name) => {
    if (!(name in dependencies)) throw new Error(`Unexpected dependency: ${name}`);
    return dependencies[name];
  }, exports);
  return exports;
}

const { safeNextPath } = load("lib/auth/redirect.ts");
for (const unsafe of ["https://evil.test", "//evil.test", "/\\evil.test", "/\n/evil.test", "javascript:alert(1)", ""]) assert.equal(safeNextPath(unsafe), "");
assert.equal(safeNextPath("/member/education?status=completed#lesson"), "/member/education?status=completed#lesson");

const { publishedModules, courseSelection } = load("lib/learning.ts");
const course = { course_modules: [
  { id: "later", published: true, position: 2, lessons: [{ id: "b", published: true, position: 2 }, { id: "a", published: true, position: 1 }, { id: "draft", published: false, position: 0 }] },
  { id: "first", published: true, position: 1, lessons: [] },
  { id: "draft", published: false, position: 0, lessons: [] },
] };
assert.deepEqual(publishedModules(course).map((m) => [m.id, m.lessons.map((l) => l.id)]), [["first", []], ["later", ["a", "b"]]]);
assert.equal(course.course_modules[0].id, "later");
// Validate every selected column against its actual table in the checked-in schema.
const schema = readFileSync(new URL("../supabase/schema.sql", import.meta.url), "utf8");
const tokens = courseSelection.match(/\w+|[(),]/g);
let offset = 0;
function checkSelection(table) {
  const definition = schema.match(new RegExp(`create table public\\.${table} \\(([\\s\\S]*?)\\n\\);`))?.[1];
  assert.ok(definition, `Missing table ${table}`);
  while (offset < tokens.length) {
    const field = tokens[offset++];
    if (field === ")") return;
    if (field === ",") continue;
    if (tokens[offset] === "(") { offset++; checkSelection(field); }
    else assert.match(definition, new RegExp(`\\n\\s+${field}\\s`), `${table}.${field} must exist`);
  }
}
checkSelection("courses");

const lessonId = "11111111-1111-4111-8111-111111111111";
async function completion({ active = true, published = true, access = "all_members", membershipStatus = "active", writeError = null } = {}) {
  const writes = [];
  const rows = {
    profiles: { account_status: active ? "active" : "suspended" },
    memberships: { id: "member-id", status: membershipStatus, expires_at: null },
    lessons: { course_modules: { published, courses: { published, access_level: access } } },
  };
  const client = {
    auth: { getUser: async () => ({ data: { user: { id: "user-id" } } }) },
    from(table) {
      return {
        select() { return this; }, eq() { return this; },
        maybeSingle: async () => ({ data: rows[table] }),
        upsert: async (...args) => { writes.push({ table, args }); return { error: writeError }; },
      };
    },
  };
  const { completeLesson } = load("app/member/education/actions.ts", {
    "next/navigation": { redirect: (url) => { throw new Error(url); } },
    "next/cache": { revalidatePath() {} },
    "@/lib/supabase/server": { createSupabaseServerClient: async () => client },
  });
  const form = new FormData(); form.set("lessonId", lessonId);
  let destination;
  try { await completeLesson(form); } catch (error) { destination = error.message; }
  return { destination, writes };
}
const completed = await completion();
assert.equal(completed.destination, "/member/education?status=completed");
assert.deepEqual(completed.writes, [{ table: "lesson_progress", args: [{ member_id: "member-id", lesson_id: lessonId }, { onConflict: "member_id,lesson_id", ignoreDuplicates: true }] }]);
for (const options of [{ active: false }, { published: false }, { access: "active_members", membershipStatus: "expired" }]) {
  const result = await completion(options);
  assert.equal(result.writes.length, 0);
  assert.notEqual(result.destination, "/member/education?status=completed");
}
assert.equal((await completion({ writeError: new Error("unavailable") })).destination, "/member/education?status=error");

const { POST } = load("app/api/session/route.ts", {
  "next/server": { NextResponse: { json: (body, options) => ({ body, ...options }) } },
  "@/lib/supabase/server": { createSupabaseServerClient: async () => ({}) },
});
for (const body of [null, [], {}, "text", { access_token: "", refresh_token: "" }]) {
  const response = await POST({ headers: new Headers({ origin: "https://club.test" }), nextUrl: new URL("https://club.test/api/session"), json: async () => body });
  assert.equal(response.status, 400);
  assert.match(response.headers["Cache-Control"], /no-store/);
}
console.log("Next behavior OK: local redirects, schema-compatible queries, ordered published content, authorized idempotent completion, and malformed sessions.");
