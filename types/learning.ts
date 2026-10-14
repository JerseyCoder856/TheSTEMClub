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
  xp_reward: number;
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
  pathway: string;
  position: number;
  course_modules: LearningModule[];
}

export interface MemberCertificate {
  id: string;
  course_id: string;
  certificate_code: string;
  awarded_at: string;
}
