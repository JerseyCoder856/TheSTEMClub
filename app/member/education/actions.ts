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
  const { error } = await supabase.rpc("complete_student_lesson", { target_lesson: lessonId });
  if (error) redirect("/member/education?status=error");
  revalidatePath("/member/education");
  redirect("/member/education?status=completed");
}
