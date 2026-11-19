BEGIN;

CREATE OR REPLACE FUNCTION app.pilot_can(p_school uuid, p_roles text[]) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
 SELECT EXISTS(
   SELECT 1 FROM public.memberships m
   JOIN public.schools s ON s.id=m.school_id AND s.tenant_id=m.tenant_id AND s.status='active'
   JOIN public.tenants t ON t.id=m.tenant_id AND t.status='active'
   WHERE m.school_id=p_school AND m.user_id=app.current_user_id()
     AND m.status='active' AND m.role_code=ANY(p_roles)
 )
$$;

-- ============ JADWAL ============
CREATE OR REPLACE FUNCTION app.g10_schedule_list(p_school uuid,p_class uuid DEFAULT NULL)
RETURNS TABLE(id uuid,class_id uuid,class_name text,subject_id uuid,subject_name text,teacher_user_id uuid,teacher_name text,weekday smallint,start_time time,end_time time,room text,academic_year text)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
BEGIN
 IF NOT app.pilot_can(p_school,ARRAY['teacher','principal','school_admin','guardian','foundation_admin']) THEN
   RAISE EXCEPTION 'School unavailable' USING ERRCODE='42501'; END IF;
 RETURN QUERY
 SELECT ls.id,ls.class_id,c.name,ls.subject_id,s.name,u.display_name,ls.teacher_user_id,ls.weekday,ls.start_time,ls.end_time,ls.room,ls.academic_year
 FROM public.lesson_schedules ls
 JOIN public.school_classes c ON c.id=ls.class_id AND c.school_id=ls.school_id AND c.tenant_id=ls.tenant_id
 JOIN public.subjects s ON s.id=ls.subject_id AND s.school_id=ls.school_id AND s.tenant_id=ls.tenant_id
 JOIN public.users u ON u.id=ls.teacher_user_id
 WHERE ls.school_id=p_school AND ls.status='active' AND (p_class IS NULL OR ls.class_id=p_class)
 ORDER BY ls.weekday,ls.start_time;
END $$;

CREATE OR REPLACE FUNCTION public.kabarkelas_schedule_list(p_school uuid,p_class uuid DEFAULT NULL)
RETURNS TABLE(id uuid,class_id uuid,class_name text,subject_id uuid,subject_name text,teacher_user_id uuid,teacher_name text,weekday smallint,start_time time,end_time time,room text,academic_year text)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path='' AS $$ SELECT * FROM app.g10_schedule_list(p_school,p_class) $$;

-- ============ PENGUMUMAN ============
CREATE OR REPLACE FUNCTION app.g10_announce_list(p_school uuid)
RETURNS TABLE(id uuid,title text,body text,published_at timestamptz,created_by uuid,creator_name text)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE v_actor uuid:=app.current_user_id();
BEGIN
 IF NOT app.pilot_can(p_school,ARRAY['teacher','principal','school_admin','guardian']) THEN
   RAISE EXCEPTION 'School unavailable' USING ERRCODE='42501'; END IF;
 RETURN QUERY
 SELECT a.id,a.title,a.body,a.published_at,a.created_by,u.display_name
 FROM public.announcements a
 JOIN public.users u ON u.id=a.created_by
 WHERE a.school_id=p_school AND a.status='published' AND a.published_at<=now()
   AND (a.audience_role IS NULL OR EXISTS(
     SELECT 1 FROM public.memberships m WHERE m.user_id=v_actor AND m.school_id=p_school AND m.status='active' AND m.role_code=a.audience_role))
   AND (a.audience_class_id IS NULL OR EXISTS(
     SELECT 1 FROM public.memberships m JOIN public.class_student_enrollments e ON e.student_id=m.user_id AND e.school_id=p_school AND e.class_id=a.audience_class_id AND e.status='active'
     WHERE m.user_id=v_actor AND m.school_id=p_school AND m.status='active' AND m.role_code='guardian'))
 ORDER BY a.published_at DESC LIMIT 50;
END $$;

CREATE OR REPLACE FUNCTION public.kabarkelas_announce_list(p_school uuid)
RETURNS TABLE(id uuid,title text,body text,published_at timestamptz,created_by uuid,creator_name text)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path='' AS $$ SELECT * FROM app.g10_announce_list(p_school) $$;

CREATE OR REPLACE FUNCTION app.g10_announce_create(p_school uuid,p_title text,p_body text,p_audience_role text DEFAULT NULL,p_audience_class uuid DEFAULT NULL)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v_id uuid;
BEGIN
 IF NOT app.pilot_can(p_school,ARRAY['principal','school_admin']) THEN
   RAISE EXCEPTION 'Only school leadership can publish announcements' USING ERRCODE='42501'; END IF;
 IF length(trim(p_title))<3 OR length(trim(p_body))<10 THEN
   RAISE EXCEPTION 'Title/body too short' USING ERRCODE='22023'; END IF;
 INSERT INTO public.announcements(tenant_id,school_id,title,body,audience_role,audience_class_id,status,published_at,created_by)
 SELECT s.tenant_id,s.id,trim(p_title),trim(p_body),NULLIF(p_audience_role,''),p_audience_class,'published',now(),app.current_user_id()
 FROM public.schools s WHERE s.id=p_school
 RETURNING id INTO v_id;
 RETURN v_id;
END $$;

CREATE OR REPLACE FUNCTION public.kabarkelas_announce_create(p_school uuid,p_title text,p_body text,p_audience_role text DEFAULT NULL,p_audience_class uuid DEFAULT NULL)
RETURNS uuid
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT app.g10_announce_create(p_school,p_title,p_body,p_audience_role,p_audience_class) $$;

-- ============ IZIN GURU ============
CREATE OR REPLACE FUNCTION app.g10_leave_list(p_school uuid)
RETURNS TABLE(id uuid,teacher_user_id uuid,teacher_name text,leave_type text,starts_on date,ends_on date,reason text,status text,decided_by uuid,decided_at timestamptz,decision_note text)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
BEGIN
 IF NOT app.pilot_can(p_school,ARRAY['teacher','principal','school_admin']) THEN
   RAISE EXCEPTION 'School unavailable' USING ERRCODE='42501'; END IF;
 RETURN QUERY
 SELECT l.id,l.teacher_user_id,u.display_name,l.leave_type,l.starts_on,l.ends_on,l.reason,l.status,l.decided_by,l.decided_at,l.decision_note
 FROM public.teacher_leave_requests l
 JOIN public.users u ON u.id=l.teacher_user_id
 WHERE l.school_id=p_school
   AND (EXISTS(SELECT 1 FROM public.memberships m WHERE m.user_id=app.current_user_id() AND m.school_id=p_school AND m.role_code IN('principal','school_admin') AND m.status='active')
        OR l.teacher_user_id=app.current_user_id())
 ORDER BY l.created_at DESC LIMIT 100;
END $$;

CREATE OR REPLACE FUNCTION public.kabarkelas_leave_list(p_school uuid)
RETURNS TABLE(id uuid,teacher_user_id uuid,teacher_name text,leave_type text,starts_on date,ends_on date,reason text,status text,decided_by uuid,decided_at timestamptz,decision_note text)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path='' AS $$ SELECT * FROM app.g10_leave_list(p_school) $$;

CREATE OR REPLACE FUNCTION app.g10_leave_request(p_school uuid,p_type text,p_start date,p_end date,p_reason text)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v_id uuid; v_tenant uuid;
BEGIN
 IF NOT app.pilot_can(p_school,ARRAY['teacher']) THEN
   RAISE EXCEPTION 'Only teachers can request leave' USING ERRCODE='42501'; END IF;
 IF p_start IS NULL OR p_end IS NULL OR p_end<p_start OR p_end-p_start>60 THEN
   RAISE EXCEPTION 'Invalid leave dates' USING ERRCODE='22023'; END IF;
 IF length(trim(p_reason))<5 THEN RAISE EXCEPTION 'Reason too short' USING ERRCODE='22023'; END IF;
 SELECT tenant_id INTO v_tenant FROM public.schools WHERE id=p_school;
 INSERT INTO public.teacher_leave_requests(tenant_id,school_id,teacher_user_id,leave_type,starts_on,ends_on,reason)
 VALUES(v_tenant,p_school,app.current_user_id(),p_type,p_start,p_end,trim(p_reason)) RETURNING id INTO v_id;
 RETURN v_id;
END $$;

CREATE OR REPLACE FUNCTION public.kabarkelas_leave_request(p_school uuid,p_type text,p_start date,p_end date,p_reason text)
RETURNS uuid
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT app.g10_leave_request(p_school,p_type,p_start,p_end,p_reason) $$;

CREATE OR REPLACE FUNCTION app.g10_leave_decide(p_leave uuid,p_approve boolean,p_note text DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
 IF NOT EXISTS(SELECT 1 FROM public.teacher_leave_requests l WHERE l.id=p_leave AND l.status='pending') THEN
   RAISE EXCEPTION 'Leave request not pending' USING ERRCODE='55000'; END IF;
 IF NOT app.pilot_can((SELECT school_id FROM public.teacher_leave_requests WHERE id=p_leave),ARRAY['principal','school_admin']) THEN
   RAISE EXCEPTION 'Only leadership can decide' USING ERRCODE='42501'; END IF;
 UPDATE public.teacher_leave_requests
 SET status=CASE WHEN p_approve THEN 'approved' ELSE 'rejected' END,
     decided_by=app.current_user_id(), decided_at=now(), decision_note=NULLIF(trim(p_note),'')
 WHERE id=p_leave;
END $$;

CREATE OR REPLACE FUNCTION public.kabarkelas_leave_decide(p_leave uuid,p_approve boolean,p_note text DEFAULT NULL)
RETURNS void
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT app.g10_leave_decide(p_leave,p_approve,p_note) $$;

-- ============ TUGAS & KUIS ============
CREATE OR REPLACE FUNCTION app.g10_homework_list(p_school uuid,p_class uuid DEFAULT NULL)
RETURNS TABLE(id uuid,class_id uuid,class_name text,subject_id uuid,subject_name text,teacher_user_id uuid,teacher_name text,title text,instructions text,assigned_on date,due_on date,max_score numeric,status text)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
BEGIN
 IF NOT app.pilot_can(p_school,ARRAY['teacher','principal','school_admin','guardian']) THEN
   RAISE EXCEPTION 'School unavailable' USING ERRCODE='42501'; END IF;
 RETURN QUERY
 SELECT h.id,h.class_id,c.name,h.subject_id,s.name,u.display_name,h.teacher_user_id,h.title,h.instructions,h.assigned_on,h.due_on,h.max_score,h.status
 FROM public.homework_assignments h
 JOIN public.school_classes c ON c.id=h.class_id AND c.school_id=h.school_id AND c.tenant_id=h.tenant_id
 JOIN public.subjects s ON s.id=h.subject_id AND s.school_id=h.school_id AND s.tenant_id=h.tenant_id
 JOIN public.users u ON u.id=h.teacher_user_id
 WHERE h.school_id=p_school AND h.status IN('published','closed') AND (p_class IS NULL OR h.class_id=p_class)
 ORDER BY h.due_on DESC LIMIT 100;
END $$;

CREATE OR REPLACE FUNCTION public.kabarkelas_homework_list(p_school uuid,p_class uuid DEFAULT NULL)
RETURNS TABLE(id uuid,class_id uuid,class_name text,subject_id uuid,subject_name text,teacher_user_id uuid,teacher_name text,title text,instructions text,assigned_on date,due_on date,max_score numeric,status text)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path='' AS $$ SELECT * FROM app.g10_homework_list(p_school,p_class) $$;

CREATE OR REPLACE FUNCTION app.g10_homework_create(p_school uuid,p_class uuid,p_subject uuid,p_title text,p_instructions text,p_assigned date,p_due date,p_max numeric)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v_id uuid; v_tenant uuid;
BEGIN
 IF NOT app.pilot_can(p_school,ARRAY['teacher','principal','school_admin']) THEN
   RAISE EXCEPTION 'Only teaching staff can assign homework' USING ERRCODE='42501'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.teacher_class_assignments tc JOIN public.memberships m ON m.user_id=tc.teacher_user_id AND m.school_id=tc.school_id AND m.tenant_id=tc.tenant_id AND m.status='active' AND m.role_code='teacher'
   WHERE tc.school_id=p_school AND tc.class_id=p_class AND tc.teacher_user_id=app.current_user_id() AND tc.status='active')
   AND NOT app.pilot_can(p_school,ARRAY['principal','school_admin']) THEN
   RAISE EXCEPTION 'Not assigned to this class' USING ERRCODE='42501'; END IF;
 IF length(trim(p_title))<3 OR p_due<p_assigned OR p_max<=0 THEN RAISE EXCEPTION 'Invalid homework' USING ERRCODE='22023'; END IF;
 SELECT tenant_id INTO v_tenant FROM public.schools WHERE id=p_school;
 INSERT INTO public.homework_assignments(tenant_id,school_id,class_id,subject_id,teacher_user_id,title,instructions,assigned_on,due_on,max_score,status,published_at)
 VALUES(v_tenant,p_school,p_class,p_subject,app.current_user_id(),trim(p_title),NULLIF(trim(p_instructions),''),p_assigned,p_due,p_max,'published',now())
 RETURNING id INTO v_id;
 RETURN v_id;
END $$;

CREATE OR REPLACE FUNCTION public.kabarkelas_homework_create(p_school uuid,p_class uuid,p_subject uuid,p_title text,p_instructions text,p_assigned date,p_due date,p_max numeric)
RETURNS uuid
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT app.g10_homework_create(p_school,p_class,p_subject,p_title,p_instructions,p_assigned,p_due,p_max) $$;

CREATE OR REPLACE FUNCTION app.g10_homework_score(p_homework uuid,p_student uuid,p_score numeric,p_note text DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v_h record;
BEGIN
 SELECT * INTO v_h FROM public.homework_assignments WHERE id=p_homework;
 IF NOT FOUND THEN RAISE EXCEPTION 'Homework not found' USING ERRCODE='22023'; END IF;
 IF NOT app.pilot_can(v_h.school_id,ARRAY['teacher','principal','school_admin']) THEN
   RAISE EXCEPTION 'Not authorized' USING ERRCODE='42501'; END IF;
 IF p_score<0 OR p_score>v_h.max_score THEN RAISE EXCEPTION 'Score out of range' USING ERRCODE='22023'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.class_student_enrollments e WHERE e.school_id=v_h.school_id AND e.class_id=v_h.class_id AND e.student_id=p_student AND e.status='active') THEN
   RAISE EXCEPTION 'Student not enrolled' USING ERRCODE='22023'; END IF;
 INSERT INTO public.assignment_scores(tenant_id,school_id,student_id,homework_id,score,note,entered_by)
 VALUES(v_h.tenant_id,v_h.school_id,p_student,p_homework,p_score,NULLIF(trim(p_note),''),app.current_user_id())
 ON CONFLICT(tenant_id,school_id,student_id,homework_id) DO UPDATE SET score=EXCLUDED.score,note=EXCLUDED.note,entered_by=EXCLUDED.entered_by,entered_at=now();
END $$;

CREATE OR REPLACE FUNCTION public.kabarkelas_homework_score(p_homework uuid,p_student uuid,p_score numeric,p_note text DEFAULT NULL)
RETURNS void
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT app.g10_homework_score(p_homework,p_student,p_score,p_note) $$;

CREATE OR REPLACE FUNCTION app.g10_quiz_list(p_school uuid,p_class uuid DEFAULT NULL)
RETURNS TABLE(id uuid,class_id uuid,class_name text,subject_id uuid,subject_name text,teacher_user_id uuid,teacher_name text,title text,quiz_on date,start_time time,end_time time,max_score numeric,status text,notes text)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
BEGIN
 IF NOT app.pilot_can(p_school,ARRAY['teacher','principal','school_admin','guardian']) THEN
   RAISE EXCEPTION 'School unavailable' USING ERRCODE='42501'; END IF;
 RETURN QUERY
 SELECT q.id,q.class_id,c.name,q.subject_id,s.name,u.display_name,q.teacher_user_id,q.title,q.quiz_on,q.start_time,q.end_time,q.max_score,q.status,q.notes
 FROM public.quiz_schedules q
 JOIN public.school_classes c ON c.id=q.class_id AND c.school_id=q.school_id AND c.tenant_id=q.tenant_id
 JOIN public.subjects s ON s.id=q.subject_id AND s.school_id=q.school_id AND s.tenant_id=q.tenant_id
 JOIN public.users u ON u.id=q.teacher_user_id
 WHERE q.school_id=p_school AND q.status IN('scheduled','done') AND (p_class IS NULL OR q.class_id=p_class)
 ORDER BY q.quiz_on DESC LIMIT 100;
END $$;

CREATE OR REPLACE FUNCTION public.kabarkelas_quiz_list(p_school uuid,p_class uuid DEFAULT NULL)
RETURNS TABLE(id uuid,class_id uuid,class_name text,subject_id uuid,subject_name text,teacher_user_id uuid,teacher_name text,title text,quiz_on date,start_time time,end_time time,max_score numeric,status text,notes text)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path='' AS $$ SELECT * FROM app.g10_quiz_list(p_school,p_class) $$;

CREATE OR REPLACE FUNCTION app.g10_quiz_create(p_school uuid,p_class uuid,p_subject uuid,p_title text,p_quiz_on date,p_start time,p_end time,p_max numeric,p_notes text DEFAULT NULL)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v_id uuid; v_tenant uuid;
BEGIN
 IF NOT app.pilot_can(p_school,ARRAY['teacher','principal','school_admin']) THEN
   RAISE EXCEPTION 'Only teaching staff can schedule quiz' USING ERRCODE='42501'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.teacher_class_assignments tc WHERE tc.school_id=p_school AND tc.class_id=p_class AND tc.teacher_user_id=app.current_user_id() AND tc.status='active')
   AND NOT app.pilot_can(p_school,ARRAY['principal','school_admin']) THEN
   RAISE EXCEPTION 'Not assigned to this class' USING ERRCODE='42501'; END IF;
 IF length(trim(p_title))<3 OR p_quiz_on IS NULL OR p_max<=0 THEN RAISE EXCEPTION 'Invalid quiz' USING ERRCODE='22023'; END IF;
 SELECT tenant_id INTO v_tenant FROM public.schools WHERE id=p_school;
 INSERT INTO public.quiz_schedules(tenant_id,school_id,class_id,subject_id,teacher_user_id,title,quiz_on,start_time,end_time,max_score,status,notes)
 VALUES(v_tenant,p_school,p_class,p_subject,app.current_user_id(),trim(p_title),p_quiz_on,p_start,p_end,p_max,'scheduled',NULLIF(trim(p_notes),''))
 RETURNING id INTO v_id;
 RETURN v_id;
END $$;

CREATE OR REPLACE FUNCTION public.kabarkelas_quiz_create(p_school uuid,p_class uuid,p_subject uuid,p_title text,p_quiz_on date,p_start time,p_end time,p_max numeric,p_notes text DEFAULT NULL)
RETURNS uuid
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT app.g10_quiz_create(p_school,p_class,p_subject,p_title,p_quiz_on,p_start,p_end,p_max,p_notes) $$;

CREATE OR REPLACE FUNCTION app.g10_quiz_score(p_quiz uuid,p_student uuid,p_score numeric,p_note text DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v_q record;
BEGIN
 SELECT * INTO v_q FROM public.quiz_schedules WHERE id=p_quiz;
 IF NOT FOUND THEN RAISE EXCEPTION 'Quiz not found' USING ERRCODE='22023'; END IF;
 IF NOT app.pilot_can(v_q.school_id,ARRAY['teacher','principal','school_admin']) THEN
   RAISE EXCEPTION 'Not authorized' USING ERRCODE='42501'; END IF;
 IF p_score<0 OR p_score>v_q.max_score THEN RAISE EXCEPTION 'Score out of range' USING ERRCODE='22023'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.class_student_enrollments e WHERE e.school_id=v_q.school_id AND e.class_id=v_q.class_id AND e.student_id=p_student AND e.status='active') THEN
   RAISE EXCEPTION 'Student not enrolled' USING ERRCODE='22023'; END IF;
 INSERT INTO public.assignment_scores(tenant_id,school_id,student_id,quiz_id,score,note,entered_by)
 VALUES(v_q.tenant_id,v_q.school_id,p_student,p_quiz,p_score,NULLIF(trim(p_note),''),app.current_user_id())
 ON CONFLICT(tenant_id,school_id,student_id,quiz_id) DO UPDATE SET score=EXCLUDED.score,note=EXCLUDED.note,entered_by=EXCLUDED.entered_by,entered_at=now();
END $$;

CREATE OR REPLACE FUNCTION public.kabarkelas_quiz_score(p_quiz uuid,p_student uuid,p_score numeric,p_note text DEFAULT NULL)
RETURNS void
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT app.g10_quiz_score(p_quiz,p_student,p_score,p_note) $$;

-- ============ ORANG TUA: TUGAS/KUIS/NILAI ============
CREATE OR REPLACE FUNCTION app.g10_parent_assignments(p_school uuid)
RETURNS TABLE(kind text,ref_id uuid,title text,detail text,due_or_on date,max_score numeric,score numeric,note text)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE v_actor uuid:=app.current_user_id();
BEGIN
 IF NOT app.pilot_can(p_school,ARRAY['guardian']) THEN
   RAISE EXCEPTION 'Guardian access only' USING ERRCODE='42501'; END IF;
 RETURN QUERY
 SELECT 'homework'::text,h.id,h.title,
        c.name||' · '||s.name||' · oleh '||u.display_name,
        h.due_on,h.max_score,sc.score,sc.note
 FROM public.homework_assignments h
 JOIN public.school_classes c ON c.id=h.class_id AND c.school_id=h.school_id AND c.tenant_id=h.tenant_id
 JOIN public.subjects s ON s.id=h.subject_id AND s.school_id=h.school_id AND s.tenant_id=h.tenant_id
 JOIN public.users u ON u.id=h.teacher_user_id
 JOIN public.guardian_student_links g ON g.school_id=h.school_id AND g.tenant_id=h.tenant_id AND g.guardian_user_id=v_actor AND g.verification_status='verified'
 JOIN public.class_student_enrollments e ON e.school_id=h.school_id AND e.class_id=h.class_id AND e.student_id=g.student_id AND e.status='active'
 LEFT JOIN public.assignment_scores sc ON sc.homework_id=h.id AND sc.student_id=g.student_id AND sc.school_id=h.school_id AND sc.tenant_id=h.tenant_id
 WHERE h.school_id=p_school AND h.status IN('published','closed')
 UNION ALL
 SELECT 'quiz'::text,q.id,q.title,
        c.name||' · '||s.name||' · oleh '||u.display_name,
        q.quiz_on,q.max_score,sc.score,sc.note
 FROM public.quiz_schedules q
 JOIN public.school_classes c ON c.id=q.class_id AND c.school_id=q.school_id AND c.tenant_id=q.tenant_id
 JOIN public.subjects s ON s.id=q.subject_id AND s.school_id=q.school_id AND s.tenant_id=q.tenant_id
 JOIN public.users u ON u.id=q.teacher_user_id
 JOIN public.guardian_student_links g ON g.school_id=q.school_id AND g.tenant_id=q.tenant_id AND g.guardian_user_id=v_actor AND g.verification_status='verified'
 JOIN public.class_student_enrollments e ON e.school_id=q.school_id AND e.class_id=q.class_id AND e.student_id=g.student_id AND e.status='active'
 LEFT JOIN public.assignment_scores sc ON sc.quiz_id=q.id AND sc.student_id=g.student_id AND sc.school_id=q.school_id AND sc.tenant_id=q.tenant_id
 WHERE q.school_id=p_school AND q.status IN('scheduled','done')
 ORDER BY due_or_on DESC LIMIT 200;
END $$;

CREATE OR REPLACE FUNCTION public.kabarkelas_parent_assignments(p_school uuid)
RETURNS TABLE(kind text,ref_id uuid,title text,detail text,due_or_on date,max_score numeric,score numeric,note text)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path='' AS $$ SELECT * FROM app.g10_parent_assignments(p_school) $$;

-- ============ P5 / TAHFIZH ============
CREATE OR REPLACE FUNCTION app.g10_p5_list(p_school uuid,p_student uuid DEFAULT NULL)
RETURNS TABLE(id uuid,student_id uuid,student_name text,category text,indicator text,score numeric,note text,assessed_by uuid,assessor_name text,assessed_on date)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
BEGIN
 IF NOT app.pilot_can(p_school,ARRAY['teacher','principal','school_admin','guardian']) THEN
   RAISE EXCEPTION 'School unavailable' USING ERRCODE='42501'; END IF;
 RETURN QUERY
 SELECT p.id,p.student_id,s.display_name,p.category,p.indicator,p.score,p.note,p.assessed_by,u.display_name,p.assessed_on
 FROM public.p5_tahfizh_assessments p
 JOIN public.students s ON s.id=p.student_id AND s.school_id=p.school_id AND s.tenant_id=p.tenant_id
 JOIN public.users u ON u.id=p.assessed_by
 WHERE p.school_id=p_school AND (p_student IS NULL OR p.student_id=p_student)
   AND (app.pilot_can(p_school,ARRAY['teacher','principal','school_admin'])
        OR EXISTS(SELECT 1 FROM public.guardian_student_links g WHERE g.student_id=p.student_id AND g.school_id=p.school_id AND g.guardian_user_id=app.current_user_id() AND g.verification_status='verified'))
 ORDER BY p.assessed_on DESC LIMIT 200;
END $$;

CREATE OR REPLACE FUNCTION public.kabarkelas_p5_list(p_school uuid,p_student uuid DEFAULT NULL)
RETURNS TABLE(id uuid,student_id uuid,student_name text,category text,indicator text,score numeric,note text,assessed_by uuid,assessor_name text,assessed_on date)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path='' AS $$ SELECT * FROM app.g10_p5_list(p_school,p_student) $$;

CREATE OR REPLACE FUNCTION app.g10_p5_record(p_school uuid,p_student uuid,p_category text,p_indicator text,p_score numeric,p_note text DEFAULT NULL)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v_id uuid; v_tenant uuid;
BEGIN
 IF NOT app.pilot_can(p_school,ARRAY['teacher','principal','school_admin']) THEN
   RAISE EXCEPTION 'Only staff can record P5/Tahfizh' USING ERRCODE='42501'; END IF;
 IF p_category NOT IN('p5','tahfizh') OR p_score<0 OR p_score>100 OR length(trim(p_indicator))<3 THEN
   RAISE EXCEPTION 'Invalid assessment' USING ERRCODE='22023'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.students s WHERE s.id=p_student AND s.school_id=p_school AND s.status='active') THEN
   RAISE EXCEPTION 'Student not found' USING ERRCODE='22023'; END IF;
 SELECT tenant_id INTO v_tenant FROM public.schools WHERE id=p_school;
 INSERT INTO public.p5_tahfizh_assessments(tenant_id,school_id,student_id,category,indicator,score,note,assessed_by)
 VALUES(v_tenant,p_school,p_student,p_category,trim(p_indicator),p_score,NULLIF(trim(p_note),''),app.current_user_id())
 RETURNING id INTO v_id;
 RETURN v_id;
END $$;

CREATE OR REPLACE FUNCTION public.kabarkelas_p5_record(p_school uuid,p_student uuid,p_category text,p_indicator text,p_score numeric,p_note text DEFAULT NULL)
RETURNS uuid
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT app.g10_p5_record(p_school,p_student,p_category,p_indicator,p_score,p_note) $$;

-- Grants
DO $$
DECLARE fn text;
BEGIN
 FOREACH fn IN ARRAY ARRAY[
  'app.g10_schedule_list(uuid,uuid)','public.kabarkelas_schedule_list(uuid,uuid)',
  'app.g10_announce_list(uuid)','public.kabarkelas_announce_list(uuid)','app.g10_announce_create(uuid,text,text,text,uuid)','public.kabarkelas_announce_create(uuid,text,text,text,uuid)',
  'app.g10_leave_list(uuid)','public.kabarkelas_leave_list(uuid)','app.g10_leave_request(uuid,text,date,date,text)','public.kabarkelas_leave_request(uuid,text,date,date,text)','app.g10_leave_decide(uuid,boolean,text)','public.kabarkelas_leave_decide(uuid,boolean,text)',
  'app.g10_homework_list(uuid,uuid)','public.kabarkelas_homework_list(uuid,uuid)','app.g10_homework_create(uuid,uuid,uuid,text,text,date,date,numeric)','public.kabarkelas_homework_create(uuid,uuid,uuid,text,text,date,date,numeric)','app.g10_homework_score(uuid,uuid,numeric,text)','public.kabarkelas_homework_score(uuid,uuid,numeric,text)',
  'app.g10_quiz_list(uuid,uuid)','public.kabarkelas_quiz_list(uuid,uuid)','app.g10_quiz_create(uuid,uuid,uuid,text,date,time,time,numeric,text)','public.kabarkelas_quiz_create(uuid,uuid,uuid,text,date,time,time,numeric,text)','app.g10_quiz_score(uuid,uuid,numeric,text)','public.kabarkelas_quiz_score(uuid,uuid,numeric,text)',
  'app.g10_parent_assignments(uuid)','public.kabarkelas_parent_assignments(uuid)',
  'app.g10_p5_list(uuid,uuid)','public.kabarkelas_p5_list(uuid,uuid)','app.g10_p5_record(uuid,uuid,text,text,numeric,text)','public.kabarkelas_p5_record(uuid,uuid,text,text,numeric,text)'
 ] LOOP
  EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC,anon,authenticated',fn);
  EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated',fn);
 END LOOP;
END $$;

COMMIT;
