import type { Metadata } from "next";
import Link from "next/link";
import { redirect } from "next/navigation";
import { SignOutButton } from "@/app/components/SignOutButton";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import type { LearningCourse, MemberCertificate } from "@/types/learning";
import { completeLesson } from "./actions";

export const metadata: Metadata = { title: "Learning paths" };

export default async function MemberEducationPage({ searchParams }: { searchParams: Promise<{ status?: string; pathway?: string }> }) {
  const { status, pathway } = await searchParams;
  const supabase = await createSupabaseServerClient();
  if (!supabase) return <ConnectionMessage />;
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/login?next=%2Fmember%2Feducation");
  const { data: profile } = await supabase.from("profiles").select("account_status").eq("id", user.id).maybeSingle();
  if (!profile || profile.account_status !== "active") redirect("/login?error=inactive");

  const { data: membershipRows, error: membershipError } = await supabase.rpc("member_summary");
  const membership = (membershipRows as unknown as Array<{ membership_id: string }> | null)?.[0];
  if (membershipError || !membership?.membership_id) return <ConnectionMessage message="An active STEM Club membership is required to view learning paths." />;

  const [courseResponse, progressResponse, certificateResponse] = await Promise.all([
    supabase.from("courses").select("id,title,summary,pathway,position,course_modules(id,title,position,published,lessons(id,title,content,project_instructions,video_url,position,xp_reward,published,resources(title,resource_url,resource_type)))").eq("published", true).order("position"),
    supabase.from("lesson_progress").select("lesson_id,completed_at").eq("member_id", membership.membership_id),
    supabase.from("member_certificates").select("id,course_id,certificate_code,awarded_at").eq("member_id", membership.membership_id),
  ]);
  if (courseResponse.error || progressResponse.error || certificateResponse.error) return <ConnectionMessage message="Learning content could not be loaded. Please try again." />;

  const courses = (courseResponse.data ?? []) as unknown as LearningCourse[];
  const progress = new Map((progressResponse.data ?? []).map((item) => [item.lesson_id, item.completed_at]));
  const certificates = new Map((certificateResponse.data ?? []).map((item) => [item.course_id, item as MemberCertificate]));
  const visibleCourses = courses.filter((course) => !pathway || course.pathway === pathway);

  return (
    <main className="min-h-screen bg-surface-soft">
      <header className="flex min-h-20 items-center justify-between border-b border-line bg-white px-5 md:px-10">
        <Link href="/" className="font-extrabold text-navy-950">The STEM Club</Link>
        <nav aria-label="Member navigation" className="flex items-center gap-5 text-sm font-semibold text-navy-800"><Link href="/">Home</Link><Link href="/member/education" aria-current="page">Learn</Link><SignOutButton /></nav>
      </header>
      <div className="mx-auto max-w-6xl px-5 py-10 md:px-8 md:py-14">
        <p className="text-sm font-extrabold text-navy-800">LEARN</p>
        <h1 className="mt-2 text-4xl font-extrabold text-navy-950">Choose a learning path</h1>
        <p className="mt-3 max-w-2xl leading-7 text-muted">Build practical skills through hands-on lessons and track your completed work.</p>
        {status === "completed" && <p role="status" className="mt-6 border-l-4 border-brand-green bg-white p-4">Lesson completion saved.</p>}
        {status === "error" && <p role="alert" className="mt-6 border-l-4 border-brand-red bg-white p-4">The lesson could not be completed. Refresh the page and try again.</p>}
        <nav aria-label="Filter learning paths" className="mt-8 flex flex-wrap gap-2">
          {(["All", "Electronics", "Programming", "3D Design", "Environmentals"] as const).map((item) => {
            const href = item === "All" ? "/member/education" : `/member/education?pathway=${encodeURIComponent(item)}`;
            const selected = (pathway ?? "All") === item;
            return <Link key={item} href={href} aria-current={selected ? "page" : undefined} className={`rounded-full border px-4 py-2 text-sm font-bold ${selected ? "border-navy-900 bg-navy-900 text-white" : "border-line bg-white text-navy-900 hover:border-brand-blue"}`}>{item === "All" ? "All paths" : item}</Link>;
          })}
        </nav>
        <section aria-label="Published learning paths" className="mt-7 grid gap-6">
          {visibleCourses.map((course) => {
            const modules = course.course_modules.filter((module) => module.published).map((module) => ({
              ...module,
              lessons: module.lessons.filter((lesson) => lesson.published).sort((left, right) => left.position - right.position),
            }));
            const lessons = modules.flatMap((module) => module.lessons);
            const completedCount = lessons.filter((lesson) => progress.has(lesson.id)).length;
            const percentage = lessons.length ? Math.round((completedCount / lessons.length) * 100) : 0;
            const certificate = certificates.get(course.id);
            return <article key={course.id} className="border border-line bg-white p-5 shadow-sm md:p-7">
              <div className="flex flex-wrap items-start justify-between gap-4"><div><p className="text-xs font-extrabold uppercase text-navy-800">{course.pathway}</p><h2 className="mt-1 text-2xl font-extrabold text-navy-950">{course.title}</h2><p className="mt-2 max-w-3xl leading-7 text-muted">{course.summary}</p></div><span className="rounded-full bg-surface-soft px-3 py-2 text-sm font-bold text-navy-900">{completedCount}/{lessons.length} lessons</span></div>
              <div className="mt-5" role="progressbar" aria-label={`${course.title} completion`} aria-valuemin={0} aria-valuemax={100} aria-valuenow={percentage}><div className="h-2 overflow-hidden bg-line"><div className="h-full bg-brand-green transition-[width]" style={{ width: `${percentage}%` }} /></div><p className="mt-2 text-sm font-semibold text-muted">{percentage}% complete</p></div>
              <div className="mt-6 grid gap-5 md:grid-cols-2">
                {modules.map((module) => <section key={module.id} className="border-l-2 border-brand-blue pl-4"><h3 className="font-extrabold text-navy-950">{module.title}</h3><ul className="mt-3 grid gap-3">
                  {module.lessons.map((lesson) => {
                    const isComplete = progress.has(lesson.id);
                    return <li key={lesson.id} className="flex items-start justify-between gap-4 border-b border-line pb-3">
                      <details className="min-w-0 flex-1"><summary className="cursor-pointer font-semibold text-navy-900">{lesson.title}</summary>
                        {lesson.content && <p className="mt-3 whitespace-pre-wrap text-sm leading-6 text-muted">{lesson.content}</p>}
                        {lesson.project_instructions && <p className="mt-3 border-l-2 border-brand-yellow pl-3 text-sm leading-6 text-muted"><strong className="text-navy-900">Try it:</strong> {lesson.project_instructions}</p>}
                        {isHttpsUrl(lesson.video_url) && <a className="mt-3 inline-flex text-sm font-bold text-navy-800 underline" href={lesson.video_url} target="_blank" rel="noopener noreferrer">Watch lesson video</a>}
                        {lesson.resources.filter((resource) => isHttpsUrl(resource.resource_url)).map((resource) => <a key={resource.resource_url} className="mt-2 block text-sm font-bold text-navy-800 underline" href={resource.resource_url} target="_blank" rel="noopener noreferrer">{resource.title}</a>)}
                        <p className="mt-3 text-sm text-muted">{isComplete ? "Completed" : `Earn ${lesson.xp_reward} points`}</p>
                      </details>
                      {isComplete ? <span aria-label="Completed" className="text-sm font-extrabold text-brand-green">Done</span> : <form action={completeLesson}><input type="hidden" name="lessonId" value={lesson.id} /><button className="shrink-0 rounded-full bg-brand-yellow px-4 py-2 text-sm font-bold text-navy-950 hover:bg-yellow-300">Complete</button></form>}
                    </li>;
                  })}
                </ul></section>)}
              </div>
              {certificate && <p className="mt-5 border-t border-line pt-4 text-sm font-bold text-navy-900">Certificate {certificate.certificate_code}</p>}
            </article>;
          })}
          {visibleCourses.length === 0 && <p className="border border-line bg-white p-6 text-muted">No published learning paths match this filter.</p>}
        </section>
      </div>
    </main>
  );
}

function isHttpsUrl(value: string | null): value is string {
  if (!value) return false;
  try { return new URL(value).protocol === "https:"; } catch { return false; }
}

function ConnectionMessage({ message = "Connect Supabase to access the STEM Club Passport." }: { message?: string }) {
  return <main className="grid min-h-screen place-items-center bg-surface-soft px-5"><section className="max-w-lg border border-line bg-white p-8 text-center shadow-sm"><h1 className="text-2xl font-extrabold text-navy-950">Learning paths</h1><p className="mt-3 leading-7 text-muted">{message}</p><Link className="mt-6 inline-flex rounded-full bg-navy-900 px-5 py-3 font-bold text-white" href="/">Return home</Link></section></main>;
}
