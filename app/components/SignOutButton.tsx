"use client";

import { createSupabaseBrowserClient } from "@/lib/supabase/browser";

export function SignOutButton() {
  async function signOut() {
    await createSupabaseBrowserClient()?.auth.signOut();
    await fetch("/api/session", { method: "DELETE", credentials: "same-origin" }).catch(() => undefined);
    window.location.assign("/");
  }
  return <button type="button" onClick={signOut} className="rounded-full border border-line px-4 py-2 text-sm font-bold text-navy-900 hover:border-brand-blue">Log out</button>;
}
