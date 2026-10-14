import type { Metadata } from "next";
import Link from "next/link";
import { LoginForm } from "./LoginForm";

export const metadata: Metadata = { title: "Log in" };

const errors: Record<string, string> = {
  configuration: "Sign-in is not configured yet.",
  invalid: "Email or password was not accepted.",
  inactive: "This account is not active. Contact The STEM Club for help.",
};

export default async function LoginPage({ searchParams }: { searchParams: Promise<{ error?: string; next?: string; "password-reset"?: string }> }) {
  const { error, next, "password-reset": passwordReset } = await searchParams;
  return (
    <main className="grid min-h-screen place-items-center bg-surface-soft px-5 py-12">
      <section className="w-full max-w-md border border-line bg-white p-7 shadow-sm sm:p-9">
        <Link href="/" className="text-sm font-bold text-navy-800">← The STEM Club</Link>
        <p className="mt-8 text-sm font-extrabold text-brand-blue">MEMBER PASSPORT</p>
        <h1 className="mt-2 text-3xl font-extrabold text-navy-950">Welcome back</h1>
        <p className="mt-2 leading-6 text-muted">Sign in to continue your learning and club activities.</p>
        {passwordReset === "success" && <p role="status" className="mt-5 border-l-4 border-brand-green bg-green-50 p-3 text-sm text-navy-950">Password updated. Log in with your new password.</p>}
        {error && <p role="alert" className="mt-5 border-l-4 border-brand-red bg-red-50 p-3 text-sm text-navy-950">{errors[error] ?? errors.invalid}</p>}
        <LoginForm next={next ?? ""} initialError="" />
        <div className="mt-5 flex justify-between gap-4 text-sm"><Link className="font-bold text-navy-800 underline" href="/forgot-password">Forgot password?</Link><Link className="font-bold text-navy-800 underline" href="/signup">Create an account</Link></div>
      </section>
    </main>
  );
}
