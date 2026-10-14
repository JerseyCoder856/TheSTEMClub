import { NextResponse, type NextRequest } from "next/server";
import { createSupabaseServerClient } from "@/lib/supabase/server";

function json(body: object, status = 200) {
  return NextResponse.json(body, {
    status,
    headers: { "Cache-Control": "private, no-store, max-age=0", Vary: "Cookie" },
  });
}

function sameOrigin(request: NextRequest) {
  const origin = request.headers.get("origin");
  if (!origin) return true;
  try { return new URL(origin).origin === request.nextUrl.origin; } catch { return false; }
}

async function activeProfile(supabase: NonNullable<Awaited<ReturnType<typeof createSupabaseServerClient>>>, userId: string) {
  const { data, error } = await supabase.from("profiles").select("account_status").eq("id", userId).maybeSingle();
  return !error && data?.account_status === "active";
}

export async function GET() {
  const supabase = await createSupabaseServerClient();
  if (!supabase) return json({ error: "not_configured" }, 503);
  const { data: { user }, error } = await supabase.auth.getUser();
  if (error || !user) return json({ error: "unauthorized" }, 401);
  if (!(await activeProfile(supabase, user.id))) {
    await supabase.auth.signOut();
    return json({ error: "inactive" }, 403);
  }
  const { data: { session } } = await supabase.auth.getSession();
  if (!session) return json({ error: "unauthorized" }, 401);
  return json({ access_token: session.access_token, refresh_token: session.refresh_token });
}

export async function POST(request: NextRequest) {
  if (!sameOrigin(request)) return json({ error: "forbidden" }, 403);
  const supabase = await createSupabaseServerClient();
  if (!supabase) return json({ error: "not_configured" }, 503);
  let body: { access_token?: unknown; refresh_token?: unknown } | null;
  try { body = await request.json(); } catch { return json({ error: "invalid_request" }, 400); }
  if (!body || typeof body.access_token !== "string" || typeof body.refresh_token !== "string" || !body.access_token || !body.refresh_token || body.access_token.length > 10000 || body.refresh_token.length > 10000) {
    return json({ error: "invalid_request" }, 400);
  }
  const { data, error } = await supabase.auth.setSession({ access_token: body.access_token, refresh_token: body.refresh_token });
  if (error || !data.user) return json({ error: "unauthorized" }, 401);
  if (!(await activeProfile(supabase, data.user.id))) {
    await supabase.auth.signOut();
    return json({ error: "inactive" }, 403);
  }
  return json({ ok: true });
}

export async function DELETE(request: NextRequest) {
  if (!sameOrigin(request)) return json({ error: "forbidden" }, 403);
  const supabase = await createSupabaseServerClient();
  if (!supabase) return json({ error: "not_configured" }, 503);
  const { error } = await supabase.auth.signOut();
  if (error) return json({ error: "sign_out_failed" }, 500);
  return json({ ok: true });
}
