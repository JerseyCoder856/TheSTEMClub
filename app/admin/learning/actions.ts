"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { createSupabaseServerClient } from "@/lib/supabase/server";

const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

async function requireAdmin() {
  const supabase = await createSupabaseServerClient();
  if (!supabase) redirect("/login?error=configuration");
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/login?next=%2Fadmin%2Flearning");
  const { data: profile } = await supabase.from("profiles").select("role,account_status").eq("id", user.id).maybeSingle();
  if (!profile || profile.account_status !== "active") {
    await supabase.auth.signOut();
    redirect("/login?error=inactive");
  }
  if (profile.role !== "admin") redirect("/member/education");
  return { supabase, user };
}

function textValue(formData: FormData, key: string) { return String(formData.get(key) ?? "").trim(); }

function requestedPosition(formData: FormData): number | null | undefined {
  const rawPosition = textValue(formData, "position");
  if (!rawPosition) return undefined;
  const position = Number(rawPosition);
  return Number.isInteger(position) && position >= 0 ? position : null;
}

export async function createCourse(formData: FormData) {
  const { supabase, user } = await requireAdmin();
  const title = textValue(formData, "title");
  const slug = textValue(formData, "slug");
  const summary = textValue(formData, "summary");
  const accessLevel = textValue(formData, "access_level");
  if (!title || !summary || !/^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(slug) || !["all_members", "active_members"].includes(accessLevel)) redirect("/admin/learning?status=invalid");
  const { error } = await supabase.from("courses").insert({ title, slug, summary, access_level: accessLevel, published: formData.get("published") === "on", created_by: user.id });
  if (error) redirect("/admin/learning?status=error");
  revalidatePath("/admin/learning");
  revalidatePath("/member/education");
  redirect("/admin/learning?status=saved");
}

export async function createModule(formData: FormData) {
  const { supabase } = await requireAdmin();
  const courseId = textValue(formData, "course_id");
  const title = textValue(formData, "title");
  let position = requestedPosition(formData);
  if (!uuidPattern.test(courseId) || !title || position === null) redirect("/admin/learning?status=invalid");
  if (position === undefined) {
    const { data: lastModule, error } = await supabase.from("course_modules").select("position").eq("course_id", courseId).order("position", { ascending: false }).limit(1).maybeSingle();
    if (error) redirect("/admin/learning?status=error");
    position = (lastModule?.position ?? -1) + 1;
  }
  const { error } = await supabase.from("course_modules").insert({ course_id: courseId, title, position, published: formData.get("published") === "on" });
  if (error) redirect("/admin/learning?status=error");
  revalidatePath("/admin/learning");
  revalidatePath("/member/education");
  redirect("/admin/learning?status=saved");
}

export async function createLesson(formData: FormData) {
  const { supabase } = await requireAdmin();
  const moduleId = textValue(formData, "module_id");
  const title = textValue(formData, "title");
  let position = requestedPosition(formData);
  const rawVideoUrl = textValue(formData, "video_url");
  if (!uuidPattern.test(moduleId) || !title || position === null) redirect("/admin/learning?status=invalid");
  if (position === undefined) {
    const { data: lastLesson, error } = await supabase.from("lessons").select("position").eq("module_id", moduleId).order("position", { ascending: false }).limit(1).maybeSingle();
    if (error) redirect("/admin/learning?status=error");
    position = (lastLesson?.position ?? -1) + 1;
  }
  let videoUrl: string | null = null;
  if (rawVideoUrl) {
    try {
      const parsedUrl = new URL(rawVideoUrl);
      if (parsedUrl.protocol !== "https:" || !["youtube.com", "www.youtube.com", "youtu.be", "vimeo.com", "www.vimeo.com"].includes(parsedUrl.hostname)) redirect("/admin/learning?status=invalid");
      videoUrl = parsedUrl.toString();
    } catch { redirect("/admin/learning?status=invalid"); }
  }
  const { error } = await supabase.from("lessons").insert({
    module_id: moduleId, title, content: textValue(formData, "content"),
    project_instructions: textValue(formData, "project_instructions"), video_url: videoUrl,
    position, published: formData.get("published") === "on",
  });
  if (error) redirect("/admin/learning?status=error");
  revalidatePath("/admin/learning");
  revalidatePath("/member/education");
  redirect("/admin/learning?status=saved");
}

export async function createResource(formData: FormData) {
  const { supabase } = await requireAdmin();
  const lessonId = textValue(formData, "lesson_id");
  const title = textValue(formData, "title");
  const resourceUrl = textValue(formData, "resource_url");
  const resourceType = textValue(formData, "resource_type");
  if (!uuidPattern.test(lessonId) || !title || !["link", "download", "worksheet", "project"].includes(resourceType)) redirect("/admin/learning?status=invalid");
  try { if (new URL(resourceUrl).protocol !== "https:") redirect("/admin/learning?status=invalid"); } catch { redirect("/admin/learning?status=invalid"); }
  const { error } = await supabase.from("resources").insert({ lesson_id: lessonId, title, resource_url: resourceUrl, resource_type: resourceType });
  if (error) redirect("/admin/learning?status=error");
  revalidatePath("/admin/learning");
  revalidatePath("/member/education");
  redirect("/admin/learning?status=saved");
}

export async function toggleCourse(formData: FormData) {
  const { supabase } = await requireAdmin();
  const courseId = textValue(formData, "course_id");
  const published = formData.get("published") === "true";
  if (!uuidPattern.test(courseId)) redirect("/admin/learning?status=invalid");
  const { error } = await supabase.from("courses").update({ published: !published }).eq("id", courseId);
  if (error) redirect("/admin/learning?status=error");
  revalidatePath("/admin/learning");
  revalidatePath("/member/education");
  redirect("/admin/learning?status=saved");
}

async function setPublished(formData: FormData, table: "course_modules" | "lessons") {
  const { supabase } = await requireAdmin();
  const id = textValue(formData, "id");
  const published = textValue(formData, "published");
  if (!uuidPattern.test(id) || !["true", "false"].includes(published)) redirect("/admin/learning?status=invalid");
  const { error } = await supabase.from(table).update({ published: published === "true" }).eq("id", id);
  if (error) redirect("/admin/learning?status=error");
  revalidatePath("/admin/learning");
  revalidatePath("/member/education");
  redirect("/admin/learning?status=saved");
}

export async function publishModule(formData: FormData) { await setPublished(formData, "course_modules"); }
export async function publishLesson(formData: FormData) { await setPublished(formData, "lessons"); }
