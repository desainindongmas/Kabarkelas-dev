BEGIN;

-- ============ 1) JADWAL PELAJARAN ============
CREATE TABLE public.lesson_schedules(
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL, school_id uuid NOT NULL,
  class_id uuid NOT NULL, subject_id uuid NOT NULL,
  teacher_user_id uuid NOT NULL REFERENCES public.users(id),
  weekday smallint NOT NULL CHECK(weekday BETWEEN 1 AND 7),
  start_time time NOT NULL, end_time time NOT NULL,
  room text,
  academic_year text NOT NULL,
  status text NOT NULL DEFAULT 'active' CHECK(status IN('active','ended')),
  created_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY(tenant_id,school_id,class_id) REFERENCES public.school_classes(tenant_id,school_id,id),
  FOREIGN KEY(tenant_id,school_id,subject_id) REFERENCES public.subjects(tenant_id,school_id,id),
  UNIQUE(tenant_id,school_id,id),
  CHECK(end_time>start_time)
);
CREATE INDEX lesson_schedules_class_idx ON public.lesson_schedules(tenant_id,school_id,class_id,weekday);

-- ============ 2) PENGUMUMAN ============
CREATE TABLE public.announcements(
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL, school_id uuid,
  title text NOT NULL, body text NOT NULL,
  audience_role text,
  audience_class_id uuid,
  status text NOT NULL DEFAULT 'draft' CHECK(status IN('draft','published','archived')),
  published_at timestamptz,
  created_by uuid NOT NULL REFERENCES public.users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY(tenant_id,school_id) REFERENCES public.schools(tenant_id,id),
  FOREIGN KEY(tenant_id,school_id,audience_class_id) REFERENCES public.school_classes(tenant_id,school_id,id),
  UNIQUE(tenant_id,school_id,id),
  CHECK((status='published' AND published_at IS NOT NULL) OR (status<>'published' AND published_at IS NULL))
);
CREATE INDEX announcements_school_idx ON public.announcements(tenant_id,school_id,published_at DESC) WHERE status='published';

CREATE TABLE public.announcement_reads(
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL, school_id uuid, announcement_id uuid NOT NULL,
  user_id uuid NOT NULL REFERENCES public.users(id),
  read_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY(tenant_id,school_id,announcement_id) REFERENCES public.announcements(tenant_id,school_id,id),
  UNIQUE(tenant_id,school_id,announcement_id,user_id)
);

-- ============ 3) IZIN GURU ============
CREATE TABLE public.teacher_leave_requests(
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL, school_id uuid NOT NULL,
  teacher_user_id uuid NOT NULL REFERENCES public.users(id),
  leave_type text NOT NULL CHECK(leave_type IN('sick','personal','official','other')),
  starts_on date NOT NULL, ends_on date NOT NULL,
  reason text NOT NULL CHECK(length(trim(reason))>=5),
  status text NOT NULL DEFAULT 'pending' CHECK(status IN('pending','approved','rejected','cancelled')),
  decided_by uuid REFERENCES public.users(id), decided_at timestamptz, decision_note text,
  created_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY(tenant_id,school_id) REFERENCES public.schools(tenant_id,id),
  UNIQUE(tenant_id,school_id,id),
  CHECK(ends_on>=starts_on),
  CHECK((status IN('approved','rejected') AND decided_by IS NOT NULL AND decided_at IS NOT NULL) OR status NOT IN('approved','rejected'))
);
CREATE INDEX teacher_leave_teacher_idx ON public.teacher_leave_requests(tenant_id,school_id,teacher_user_id,starts_on);

-- ============ 4) TUGAS & KUIS ============
CREATE TABLE public.homework_assignments(
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL, school_id uuid NOT NULL,
  class_id uuid NOT NULL, subject_id uuid NOT NULL,
  teacher_user_id uuid NOT NULL REFERENCES public.users(id),
  title text NOT NULL, instructions text,
  assigned_on date NOT NULL, due_on date NOT NULL,
  max_score numeric(8,2) NOT NULL CHECK(max_score>0),
  status text NOT NULL DEFAULT 'draft' CHECK(status IN('draft','published','closed')),
  published_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY(tenant_id,school_id,class_id) REFERENCES public.school_classes(tenant_id,school_id,id),
  FOREIGN KEY(tenant_id,school_id,subject_id) REFERENCES public.subjects(tenant_id,school_id,id),
  UNIQUE(tenant_id,school_id,id),
  CHECK(due_on>=assigned_on),
  CHECK((status='published' AND published_at IS NOT NULL) OR (status<>'published' AND published_at IS NULL))
);
CREATE INDEX homework_class_idx ON public.homework_assignments(tenant_id,school_id,class_id,due_on);

CREATE TABLE public.quiz_schedules(
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL, school_id uuid NOT NULL,
  class_id uuid NOT NULL, subject_id uuid NOT NULL,
  teacher_user_id uuid NOT NULL REFERENCES public.users(id),
  title text NOT NULL,
  quiz_on date NOT NULL, start_time time, end_time time,
  max_score numeric(8,2) NOT NULL CHECK(max_score>0),
  status text NOT NULL DEFAULT 'scheduled' CHECK(status IN('scheduled','done','cancelled')),
  notes text,
  created_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY(tenant_id,school_id,class_id) REFERENCES public.school_classes(tenant_id,school_id,id),
  FOREIGN KEY(tenant_id,school_id,subject_id) REFERENCES public.subjects(tenant_id,school_id,id),
  UNIQUE(tenant_id,school_id,id),
  CHECK((end_time IS NULL AND start_time IS NULL) OR (start_time IS NOT NULL AND end_time IS NOT NULL AND end_time>start_time))
);
CREATE INDEX quiz_class_idx ON public.quiz_schedules(tenant_id,school_id,class_id,quiz_on);

CREATE TABLE public.assignment_scores(
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL, school_id uuid NOT NULL,
  student_id uuid NOT NULL,
  homework_id uuid, quiz_id uuid,
  score numeric(8,2) NOT NULL CHECK(score>=0),
  note text,
  entered_by uuid NOT NULL REFERENCES public.users(id),
  entered_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY(tenant_id,school_id,student_id) REFERENCES public.students(tenant_id,school_id,id),
  FOREIGN KEY(tenant_id,school_id,homework_id) REFERENCES public.homework_assignments(tenant_id,school_id,id),
  FOREIGN KEY(tenant_id,school_id,quiz_id) REFERENCES public.quiz_schedules(tenant_id,school_id,id),
  CHECK((homework_id IS NOT NULL)::int + (quiz_id IS NOT NULL)::int = 1),
  UNIQUE(tenant_id,school_id,student_id,homework_id),
  UNIQUE(tenant_id,school_id,student_id,quiz_id)
);
CREATE INDEX assignment_scores_student_idx ON public.assignment_scores(tenant_id,school_id,student_id);

-- ============ 5) P5 / TAHFIZH ============
CREATE TABLE public.p5_tahfizh_assessments(
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL, school_id uuid NOT NULL,
  student_id uuid NOT NULL,
  category text NOT NULL CHECK(category IN('p5','tahfizh')),
  indicator text NOT NULL,
  score numeric(8,2) NOT NULL CHECK(score>=0 AND score<=100),
  note text,
  assessed_by uuid NOT NULL REFERENCES public.users(id),
  assessed_on date NOT NULL DEFAULT CURRENT_DATE,
  created_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY(tenant_id,school_id,student_id) REFERENCES public.students(tenant_id,school_id,id),
  UNIQUE(tenant_id,school_id,id)
);
CREATE INDEX p5_student_idx ON public.p5_tahfizh_assessments(tenant_id,school_id,student_id,category);

-- ============ RLS ============
DO $$ DECLARE t text; BEGIN
  FOREACH t IN ARRAY ARRAY['lesson_schedules','announcements','announcement_reads','teacher_leave_requests','homework_assignments','quiz_schedules','assignment_scores','p5_tahfizh_assessments'] LOOP
    EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY',t);
    EXECUTE format('ALTER TABLE public.%I FORCE ROW LEVEL SECURITY',t);
  END LOOP;
END $$;

CREATE POLICY pilot_lesson_read ON public.lesson_schedules FOR SELECT USING(app.has_active_membership(tenant_id,school_id));
CREATE POLICY pilot_announce_read ON public.announcements FOR SELECT USING(app.has_active_membership(tenant_id,school_id));
CREATE POLICY pilot_announce_readmark ON public.announcement_reads FOR SELECT USING(app.has_active_membership(tenant_id,school_id));
CREATE POLICY pilot_leave_read ON public.teacher_leave_requests FOR SELECT USING(app.has_active_membership(tenant_id,school_id));
CREATE POLICY pilot_homework_read ON public.homework_assignments FOR SELECT USING(app.has_active_membership(tenant_id,school_id));
CREATE POLICY pilot_quiz_read ON public.quiz_schedules FOR SELECT USING(app.has_active_membership(tenant_id,school_id));
CREATE POLICY pilot_ascore_read ON public.assignment_scores FOR SELECT USING(app.has_active_membership(tenant_id,school_id));
CREATE POLICY pilot_p5_read ON public.p5_tahfizh_assessments FOR SELECT USING(app.has_active_membership(tenant_id,school_id));

COMMIT;
