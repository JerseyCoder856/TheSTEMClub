import type { Metadata } from "next";
import Link from "next/link";
import { redirect } from "next/navigation";
import { SignOutButton } from "@/app/components/SignOutButton";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { createCourse, createLesson, createModule, createResource, toggleCourse, publishModule, publishLesson } from "./actions";

export const metadata: Metadata = { title: "Learning administration" };

interface AdminLesson { id: string; title: string; position: number; published: boolean }
interface AdminModule { id: string; title: string; position: number; published: boolean; lessons: AdminLesson[] }
interface AdminCourse { id: string; title: string; slug: string; summary: string; published: boolean; position: number; course_modules: AdminModule[] }

const fieldClass = "min-h-11 w-full border border-line bg-white px-3 text-sm font-normal";
const labelClass = "grid gap-2 text-sm font-bold text-navy-900";
const buttonClass = "min-h-11 w-fit rounded-full bg-brand-green px-5 text-sm font-bold text-navy-950 hover:bg-green-400";

export default async function AdminLearningPage({ searchParams }: { searchParams: Promise<{ status?: string }> }) {
  const { status } = await searchParams;
  const supabase = await createSupabaseServerClient();
  if (!supabase) return <Message>Connect Supabase to manage learning content.</Message>;
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/login?next=%2Fadmin%2Flearning");
  const { data: profile } = await supabase.from("profiles").select("role,account_status").eq("id", user.id).maybeSingle();
  if (!profile || profile.account_status !== "active") redirect("/login?error=inactive");
  if (profile.role !== "admin") redirect("/member/education");

  const { data, error } = await supabase.from("courses").select("id,title,slug,summary,published,position,course_modules(id,title,position,published,lessons(id,title,position,published))").order("position");
  if (error) return <Message>Learning content could not be loaded.</Message>;
  const courses = (data ?? []) as unknown as AdminCourse[];
  const modules = courses.flatMap((course) => course.course_modules.map((module) => ({ ...module, courseTitle: course.title })));
  const lessons = modules.flatMap((module) => module.lessons.map((lesson) => ({ ...lesson, moduleTitle: module.title, courseTitle: module.courseTitle })));

  return (
    <main className="min-h-screen bg-surface-soft">
      <header className="flex min-h-20 items-center justify-between border-b border-line bg-white px-5 md:px-10">
        <Link href="/" className="font-extrabold text-navy-950">The STEM Club</Link>
        <nav aria-label="Teacher navigation" className="flex items-center gap-5 text-sm font-semibold text-navy-800"><a href="/admin">Workspace</a><Link href="/admin/learning" aria-current="page">Learning</Link><SignOutButton /></nav>
      </header>
      <div className="mx-auto max-w-6xl px-5 py-10 md:px-8 md:py-14">
        <p className="text-sm font-extrabold text-navy-800">TEACHER WORKSPACE</p><h1 className="mt-2 text-4xl font-extrabold text-navy-950">Learning content</h1><p className="mt-3 leading-7 text-muted">Create courses, organize lessons, and publish learning paths.</p>
        {status && <p role={status === "saved" ? "status" : "alert"} className={`mt-6 border-l-4 bg-white p-4 ${status === "saved" ? "border-brand-green" : "border-brand-red"}`}>{status === "saved" ? "Learning changes saved." : status === "invalid" ? "Check the form values and try again." : "The change could not be saved."}</p>}
        <section className="mt-8 grid gap-6 lg:grid-cols-[1.1fr_.9fr]">
          <div className="grid content-start gap-4"><h2 className="text-xl font-extrabold text-navy-950">Courses</h2>
            {courses.map((course) => <article key={course.id} className="border border-line bg-white p-5 shadow-sm"><div className="flex flex-wrap items-start justify-between gap-4"><div><span className={`text-xs font-extrabold uppercase ${course.published ? "text-brand-green" : "text-muted"}`}>{course.published ? "Published" : "Draft"}</span><h3 className="mt-1 text-xl font-extrabold text-navy-950">{course.title}</h3><p className="mt-1 text-sm text-muted">{course.summary}</p><p className="mt-2 text-xs text-muted">{course.course_modules.length} modules · {course.slug}</p></div><form action={toggleCourse}><input type="hidden" name="course_id" value={course.id} /><input type="hidden" name="published" value={String(course.published)} /><button className="rounded-full border border-line px-4 py-2 text-sm font-bold text-navy-900 hover:border-brand-blue">{course.published ? "Unpublish" : "Publish"}</button></form></div>
              {course.course_modules.toSorted((a, b) => a.position - b.position).map((module) => <section key={module.id} className="mt-4 border-t border-line pt-4">
                <h4 className="font-bold">{module.title}</h4>
                <PublishForm id={module.id} title={module.title} published={module.published} action={publishModule} />
                <ul className="mt-3 grid gap-3 pl-4">{module.lessons.toSorted((a, b) => a.position - b.position).map((lesson) => <li key={lesson.id}><p>{lesson.title}</p><PublishForm id={lesson.id} title={lesson.title} published={lesson.published} action={publishLesson} /></li>)}</ul>
              </section>)}
            </article>)}
            {courses.length === 0 && <p className="border border-line bg-white p-5 text-muted">No courses yet.</p>}
          </div>
          <div className="grid content-start gap-6">
            <FormSection title="Create course" action={createCourse} button="Create course">
              <label className={labelClass}>Title<input className={fieldClass} name="title" required maxLength={160} /></label>
              <label className={labelClass}>URL slug<input className={fieldClass} name="slug" required pattern="[a-z0-9]+(?:-[a-z0-9]+)*" /></label>
              <label className={labelClass}>Summary<textarea className={fieldClass} name="summary" required rows={3} /></label>
              <label className={labelClass}>Access<select className={fieldClass} name="access_level"><option value="all_members">All members</option><option value="active_members">Active memberships only</option></select></label>
              <label className="flex items-center gap-3 text-sm font-semibold text-navy-900"><input name="published" type="checkbox" /> Publish now</label>
            </FormSection>
            <FormSection title="Add module" action={createModule} button="Add module">
              <label className={labelClass}>Course<select className={fieldClass} name="course_id" required>{courses.map((course) => <option key={course.id} value={course.id}>{course.title}</option>)}</select></label>
              <label className={labelClass}>Module title<input className={fieldClass} name="title" required maxLength={160} /></label>
              <label className={labelClass}>Position (leave blank to append)<input className={fieldClass} name="position" type="number" min="0" placeholder="Auto" /></label>
              <label className="flex items-center gap-3 text-sm font-semibold text-navy-900"><input name="published" type="checkbox" /> Published</label>
            </FormSection>
            <FormSection title="Add lesson" action={createLesson} button="Add lesson">
              <label className={labelClass}>Module<select className={fieldClass} name="module_id" required>{modules.map((module) => <option key={module.id} value={module.id}>{module.courseTitle} · {module.title}</option>)}</select></label>
              <label className={labelClass}>Lesson title<input className={fieldClass} name="title" required maxLength={160} /></label>
              <label className={labelClass}>Lesson content<textarea className={fieldClass} name="content" rows={4} maxLength={50000} /></label>
              <label className={labelClass}>Project instructions<textarea className={fieldClass} name="project_instructions" rows={3} maxLength={20000} /></label>
              <label className={labelClass}>YouTube or Vimeo URL<input className={fieldClass} name="video_url" type="url" /></label>
              <label className={labelClass}>Position (leave blank to append)<input className={fieldClass} name="position" type="number" min="0" placeholder="Auto" /></label>
              <label className="flex items-center gap-3 text-sm font-semibold text-navy-900"><input name="published" type="checkbox" /> Published</label>
            </FormSection>
            <FormSection title="Add resource" action={createResource} button="Add resource">
              <label className={labelClass}>Lesson<select className={fieldClass} name="lesson_id" required>{lessons.map((lesson) => <option key={lesson.id} value={lesson.id}>{lesson.courseTitle} · {lesson.moduleTitle} · {lesson.title}</option>)}</select></label>
              <label className={labelClass}>Resource title<input className={fieldClass} name="title" required maxLength={160} /></label>
              <label className={labelClass}>HTTPS URL<input className={fieldClass} name="resource_url" type="url" required /></label>
              <label className={labelClass}>Type<select className={fieldClass} name="resource_type"><option value="link">Link</option><option value="download">Download</option><option value="worksheet">Worksheet</option><option value="project">Project</option></select></label>
            </FormSection>
          </div>
        </section>
      </div>
    </main>
  );
}

function FormSection({ title, action, button, children }: { title: string; action: (formData: FormData) => Promise<void>; button: string; children: React.ReactNode }) {
  return <section className="border border-line bg-white p-5 shadow-sm"><h2 className="mb-4 text-lg font-extrabold text-navy-950">{title}</h2><form action={action} className="grid gap-4">{children}<button className={buttonClass}>{button}</button></form></section>;
}

function Message({ children }: { children: React.ReactNode }) {
  return <main className="grid min-h-screen place-items-center bg-surface-soft px-5"><p className="border border-line bg-white p-6 text-muted">{children}</p></main>;
}

function PublishForm({ id, title, published, action }: { id: string; title: string; published: boolean; action: (formData: FormData) => Promise<void> }) {
  return <form action={action} className="mt-2 flex items-center gap-3 text-sm"><span>{published ? "Published" : "Draft"}</span><input type="hidden" name="id" value={id} /><input type="hidden" name="published" value={String(!published)} /><button aria-label={`${published ? "Unpublish" : "Publish"} ${title}`} className="min-h-11 rounded-full border border-line px-4 font-bold">{published ? "Unpublish" : "Publish"}</button></form>;
}
