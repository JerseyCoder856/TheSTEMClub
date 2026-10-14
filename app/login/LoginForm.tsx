"use client";

import { useEffect, useState, type FormEvent } from "react";
import type { Session } from "@supabase/supabase-js";
import { createSupabaseBrowserClient } from "@/lib/supabase/browser";
import { safeNextPath } from "@/lib/auth/redirect";

type BrowserClient = NonNullable<ReturnType<typeof createSupabaseBrowserClient>>;

async function syncServerSession(session: Session) {
  try {
    const response = await fetch("/api/session", {
      method: "POST", credentials: "same-origin", cache: "no-store",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ access_token: session.access_token, refresh_token: session.refresh_token }),
    });
    return response.ok;
  } catch { return false; }
}

async function activeRole(client: BrowserClient, session: Session) {
  const { data, error } = await client.from("profiles").select("role,account_status").eq("id", session.user.id).maybeSingle();
  if (error || !data || data.account_status !== "active") return null;
  return data.role as string;
}

function destination(nextPath: string, role: string) {
  return safeNextPath(nextPath) || (role === "admin" ? "/admin/learning" : "/member/education");
}

export function LoginForm({ next, initialError }: { next: string; initialError: string }) {
  const [client] = useState(createSupabaseBrowserClient);
  const [error, setError] = useState(initialError);
  const [busy, setBusy] = useState(false);
  const nextPath = safeNextPath(next);

  useEffect(() => {
    if (!client) return;
    let cancelled = false;
    async function resumeSession() {
      let session: Session | null = null;
      try {
        const response = await fetch("/api/session", { credentials: "same-origin", cache: "no-store" });
        if (response.ok) {
          const tokens = await response.json() as { access_token?: string; refresh_token?: string };
          if (tokens.access_token && tokens.refresh_token) {
            const result = await client!.auth.setSession({ access_token: tokens.access_token, refresh_token: tokens.refresh_token });
            if (!result.error) session = result.data.session;
          }
        }
      } catch { /* Fall back to an existing browser session. */ }
      if (!session) session = (await client!.auth.getSession()).data.session;
      if (!session || !(await syncServerSession(session))) return;
      const role = await activeRole(client!, session);
      if (!role) {
        await client!.auth.signOut();
        await fetch("/api/session", { method: "DELETE", credentials: "same-origin" }).catch(() => undefined);
        if (!cancelled) setError("This account is not active. Contact The STEM Club for help.");
        return;
      }
      if (!cancelled) window.location.replace(destination(nextPath, role));
    }
    void resumeSession();
    return () => { cancelled = true; };
  }, [client, nextPath]);

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!client) return setError("Sign-in is not configured yet.");
    setBusy(true);
    setError("");
    const form = new FormData(event.currentTarget);
    const { data, error: authError } = await client.auth.signInWithPassword({
      email: String(form.get("email") ?? "").trim(),
      password: String(form.get("password") ?? ""),
    });
    if (authError || !data.session) {
      setBusy(false);
      setError("Email or password was not accepted.");
      return;
    }
    const role = await activeRole(client, data.session);
    if (!role) {
      await client.auth.signOut();
      setBusy(false);
      setError("This account is not active. Contact The STEM Club for help.");
      return;
    }
    if (!(await syncServerSession(data.session))) {
      await client.auth.signOut();
      setBusy(false);
      setError("Your secure session could not be established. Please try again.");
      return;
    }
    window.location.assign(destination(nextPath, role));
  }

  return (
    <form onSubmit={submit} className="mt-6 grid gap-4">
      {error && <p role="alert" className="border-l-4 border-brand-red bg-red-50 p-3 text-sm text-navy-950">{error}</p>}
      <label className="grid gap-2 text-sm font-bold text-navy-900">Email<input className="min-h-12 border border-line px-3 font-normal" name="email" type="email" autoComplete="email" required disabled={busy} /></label>
      <label className="grid gap-2 text-sm font-bold text-navy-900">Password<input className="min-h-12 border border-line px-3 font-normal" name="password" type="password" autoComplete="current-password" required disabled={busy} /></label>
      <button className="mt-2 min-h-12 rounded-full bg-brand-red px-5 font-bold text-white hover:bg-red-700 disabled:opacity-60" disabled={busy}>{busy ? "Signing in…" : "Log in"}</button>
    </form>
  );
}
