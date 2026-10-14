import assert from "node:assert/strict";
import { access, readFile } from "node:fs/promises";
import { spawnSync } from "node:child_process";
import path from "node:path";

const projectRoot = process.cwd();
const syncResult = spawnSync(process.execPath, ["scripts/sync-legacy-public.mjs"], { cwd: projectRoot, encoding: "utf8" });
assert.equal(syncResult.status, 0, syncResult.stderr || "Legacy asset sync failed.");

for (const file of [
  "public/index.html", "public/blog.html", "public/support.html", "public/portal.js",
  "public/admin/attendance/index.html", "public/member/events/index.html",
]) await access(path.join(projectRoot, file));

const nextConfig = await readFile(path.join(projectRoot, "next.config.ts"), "utf8");
assert.match(nextConfig, /afterFiles:\s*\[\{\s*source:\s*["']\/:path\*["']/);
const packageConfig = JSON.parse(await readFile(path.join(projectRoot, "package.json"), "utf8"));
assert.equal(packageConfig.scripts.prebuild, "node scripts/sync-legacy-public.mjs");
for (const file of ["app/login/page.tsx", "app/api/session/route.ts", "app/member/education/page.tsx", "app/admin/learning/page.tsx"]) {
  await access(path.join(projectRoot, file));
}
const sessionRoute = await readFile(path.join(projectRoot, "app/api/session/route.ts"), "utf8");
assert.match(sessionRoute, /Cache-Control.*no-store/);
assert.ok(sessionRoute.includes("auth.setSession"));
const legacyPortal = await readFile(path.join(projectRoot, "portal.js"), "utf8");
assert.ok(legacyPortal.includes("importServerSession()"));
assert.ok(legacyPortal.includes("syncServerSession(session)"));
console.log("Next migration contract OK: legacy routes sync and Supabase session bridge is present.");
