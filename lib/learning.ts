import type { LearningCourse } from "../types/learning";

export const courseSelection = "id,title,summary,access_level,position,course_modules(id,title,position,published,lessons(id,title,content,project_instructions,video_url,position,published,resources(title,resource_url,resource_type)))";

export function publishedModules(course: LearningCourse) {
  return course.course_modules.filter((module) => module.published)
    .sort((left, right) => left.position - right.position)
    .map((module) => ({ ...module, lessons: module.lessons.filter((lesson) => lesson.published)
      .sort((left, right) => left.position - right.position) }));
}
