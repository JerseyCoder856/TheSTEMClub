export interface LearningResource {
  title: string;
  resource_url: string;
  resource_type: string;
}

export interface LearningLesson {
  id: string;
  title: string;
  content: string | null;
  project_instructions: string | null;
  video_url: string | null;
  position: number;
  published: boolean;
  resources: LearningResource[];
}

export interface LearningModule {
  id: string;
  title: string;
  position: number;
  published: boolean;
  lessons: LearningLesson[];
}

export interface LearningCourse {
  id: string;
  title: string;
  summary: string;
  access_level: "all_members" | "active_members";
  position: number;
  course_modules: LearningModule[];
}
