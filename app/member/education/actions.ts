"use server";

import { redirect } from "next/navigation";
import { revalidatePath } from "next/cache";
import { createSupabaseServerClient } from "@/lib/supabase/server";

export async function completeLesson(formData: FormData) {
  const lessonId = String(formData.get("lessonId") ?? "");
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(lessonId)) redirect("/member/education?status=error");
  const supabase = await createSupabaseServerClient();
  if (!supabase) redirect("/login?next=%2Fmember%2Feducation");
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/login?next=%2Fmember%2Feducation");
  const { data: profile } = await supabase.from("profiles").select("account_status").eq("id", user.id).maybeSingle();
  if (profile?.account_status !== "active") redirect("/login?error=inactive");
  const { data: membership } = await supabase.from("memberships").select("id,status,expires_at").eq("profile_id", user.id).maybeSingle();
  if (!membership) redirect("/member/education?status=error");
  const { data: lesson } = await supabase.from("lessons").select("id,course_modules!inner(published,courses!inner(published,access_level))").eq("id", lessonId).eq("published", true).maybeSingle();
  // These foreign keys are many-to-one; the untyped client assumes arrays.
  const module = (lesson as unknown as { course_modules: { published: boolean; courses: { published: boolean; access_level: string } } } | null)?.course_modules;
  const course = module?.courses;
  if (!module?.published || !course?.published) redirect("/member/education?status=error");
  if (course.access_level === "active_members" && (membership.status !== "active" || (membership.expires_at && membership.expires_at < new Date().toISOString().slice(0, 10)))) redirect("/member/education?status=error");
  const { error } = await supabase.from("lesson_progress").upsert({ member_id: membership.id, lesson_id: lessonId }, { onConflict: "member_id,lesson_id", ignoreDuplicates: true });
  if (error) redirect("/member/education?status=error");
  revalidatePath("/member/education");
  redirect("/member/education?status=completed");
}
