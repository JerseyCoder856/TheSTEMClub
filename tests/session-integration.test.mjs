import assert from "node:assert/strict";
import { createServer } from "node:http";
import { spawn } from "node:child_process";
import { once } from "node:events";

// Real Next.js + Supabase SDK over HTTP, with an isolated Auth/PostgREST fixture.
// No real users, emails, database writes, or production secrets are involved.
const user = { id: "11111111-1111-4111-8111-111111111111", aud: "authenticated", role: "authenticated", email: "fixture@example.test", app_metadata: {}, user_metadata: {}, created_at: new Date().toISOString() };
let profileStatus = "active";
let profileFailure = false;
let role = "member";
let logoutCount = 0;
let refreshCount = 0;
const jwt = (expiresIn = 3600) => [
  { alg: "HS256", typ: "JWT" },
  { sub: user.id, role: "authenticated", exp: Math.floor(Date.now() / 1000) + expiresIn },
].map((part) => Buffer.from(JSON.stringify(part)).toString("base64url")).concat(Buffer.from("fixture-signature").toString("base64url")).join(".");
const tokens = () => ({ access_token: jwt(), refresh_token: "fixture-refresh-token", token_type: "bearer", expires_in: 3600, user });
const fixture = createServer((req, res) => {
  const url = new URL(req.url, "http://fixture");
  res.setHeader("Content-Type", "application/json");
  if (url.pathname === "/auth/v1/user") return res.end(JSON.stringify(user));
  if (url.pathname === "/auth/v1/token") { refreshCount++; return res.end(JSON.stringify(tokens())); }
  if (url.pathname === "/auth/v1/logout") { logoutCount++; res.statusCode = 204; return res.end(); }
  if (url.pathname === "/rest/v1/profiles") {
    if (profileFailure) { res.statusCode = 503; return res.end(JSON.stringify({ message: "fixture database unavailable" })); }
    return res.end(JSON.stringify({ id: user.id, role, account_status: profileStatus }));
  }
  if (url.pathname === "/rest/v1/rpc/member_summary") return res.end(JSON.stringify([{ membership_id: user.id, status: "active", expires_at: null }]));
  if (["/rest/v1/courses", "/rest/v1/lesson_progress"].includes(url.pathname)) return res.end("[]");
  res.statusCode = 404; res.end(JSON.stringify({ message: `Unexpected fixture request ${url.pathname}` }));
});
fixture.listen(0, "127.0.0.1");
await once(fixture, "listening");
const supabaseUrl = `http://127.0.0.1:${fixture.address().port}`;
const env = { ...process.env, NEXT_PUBLIC_SUPABASE_URL: supabaseUrl, NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY: "sb_publishable_fixture", NEXT_TELEMETRY_DISABLED: "1" };
function child(args) { return spawn(process.execPath, args, { env, stdio: ["ignore", "pipe", "pipe"], windowsHide: true }); }
async function run(args) {
  const proc = child(args); let output = "";
  proc.stdout.on("data", (chunk) => { output += chunk; }); proc.stderr.on("data", (chunk) => { output += chunk; });
  const [code] = await once(proc, "exit"); assert.equal(code, 0, output);
}
let server;
try {
  await run(["scripts/sync-legacy-public.mjs"]);
  await run(["node_modules/next/dist/bin/next", "build"]);
  const portProbe = createServer(); portProbe.listen(0, "127.0.0.1"); await once(portProbe, "listening");
  const appPort = portProbe.address().port; await new Promise((resolve) => portProbe.close(resolve));
  server = child(["node_modules/next/dist/bin/next", "start", "--hostname", "127.0.0.1", "--port", String(appPort)]);
  let logs = "";
  server.stdout.on("data", (chunk) => { logs += chunk; }); server.stderr.on("data", (chunk) => { logs += chunk; });
  let origin;
  for (let tries = 0; tries < 100; tries++) {
    origin = logs.match(/http:\/\/127\.0\.0\.1:\d+/)?.[0];
    if (origin && logs.includes("Ready")) break;
    if (server.exitCode !== null) throw new Error(logs);
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
  assert.ok(origin, logs);
  const jar = new Map();
  async function request(path, options = {}) {
    const response = await fetch(origin + path, { redirect: "manual", ...options, headers: { cookie: [...jar].map(([k, v]) => `${k}=${v}`).join("; "), origin, ...options.headers } });
    for (const cookie of response.headers.getSetCookie()) {
      const pair = cookie.split(";")[0]; const split = pair.indexOf("=");
      if (pair.slice(split + 1)) jar.set(pair.slice(0, split), pair.slice(split + 1)); else jar.delete(pair.slice(0, split));
    }
    return response;
  }
  const post = (body) => request("/api/session", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify(body) });
  assert.equal((await request("/api/session")).status, 401);
  for (const path of ["/member/education", "/admin/learning"]) assert.equal((await request(path)).status, 307);
  assert.equal((await post(null)).status, 400);
  assert.equal((await post({ access_token: "not-a-jwt", refresh_token: "invalid" })).status, 401, "Malformed tokens must not crash the route");
  assert.equal((await post({ access_token: jwt(-60), refresh_token: "fixture-refresh-token" })).status, 200);
  assert.ok(refreshCount > 0, "Expired tokens should be refreshed by the SDK");
  assert.equal((await post(tokens())).status, 200);
  assert.ok(jar.size, "Session cookies should be written");
  let response = await request("/api/session");
  assert.equal(response.status, 200); assert.match(response.headers.get("cache-control"), /no-store/);
  assert.equal((await response.json()).refresh_token, "fixture-refresh-token");
  response = await request("/member/education"); assert.equal(response.status, 200); assert.match(await response.text(), /Choose a learning path/);
  response = await request("/admin/learning"); assert.equal(response.status, 307); assert.equal(response.headers.get("location"), "/member/education");
  role = "admin";
  response = await request("/admin/learning"); assert.equal(response.status, 200); assert.match(await response.text(), /Create course/);
  profileFailure = true;
  const previousLogouts = logoutCount;
  assert.equal((await request("/api/session")).status, 503, "A database outage is not a suspended account");
  assert.equal(logoutCount, previousLogouts, "A transient outage must not revoke the user's session");
  profileFailure = false;
  assert.equal((await request("/api/session")).status, 200);
  profileStatus = "suspended";
  assert.equal((await request("/api/session")).status, 403);
  assert.equal((await request("/api/session")).status, 401);
  profileStatus = "active";
  assert.equal((await post(tokens())).status, 200);
  assert.equal((await request("/api/session", { method: "DELETE", headers: { origin: "https://other.test" } })).status, 403);
  assert.equal((await request("/api/session", { method: "DELETE" })).status, 200);
  assert.equal((await request("/api/session")).status, 401);
  assert.equal((await request("/api/session", { method: "POST", headers: { origin: "https://other.test", "content-type": "application/json" }, body: JSON.stringify(tokens()) })).status, 403);
  for (const path of ["/admin/attendance", "/member/events", "/signup", "/reset-password"]) assert.equal((await request(path)).status, 200);
  response = await request("/portal-config.js"); assert.match(await response.text(), new RegExp(supabaseUrl));
  console.log("Session integration OK: production routes, real SDK cookie bridge and refresh, member/admin access, transient failures, suspension, logout, and legacy assets.");
} finally {
  if (server && server.exitCode === null) { server.kill(); await once(server, "exit"); }
  fixture.closeAllConnections(); await new Promise((resolve) => fixture.close(resolve));
}

