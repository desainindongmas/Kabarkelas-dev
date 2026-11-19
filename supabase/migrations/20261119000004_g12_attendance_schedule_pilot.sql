-- G12: write paths untuk kehadiran & jadwal, plus penyelesaian gap pilot.
BEGIN;

-- ============ 1) KEHADIRAN: list sessions + record + publish ============
CREATE FUNCTION app.g12_attendance_list(p_school uuid,p_class uuid DEFAULT NULL)
RETURNS TABLE(id uuid,class_id uuid,class_name text,session_date date,state text,published_at timestamptz,record_count bigint,absent_count bigint)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
BEGIN
 IF NOT app.pilot_can(p_school,ARRAY['teacher','principal','school_admin','guardian']) THEN
  RAISE EXCEPTION 'School unavailable' USING ERRCODE='42501'; END IF;
 RETURN QUERY
 SELECT s.id,s.class_id,c.name,s.session_date,s.state,s.published_at,
        (SELECT count(*) FROM public.attendance_records r WHERE r.session_id=s.id),
        (SELECT count(*) FROM public.attendance_records r WHERE r.session_id=s.id AND r.attendance_code='absent')
 FROM public.attendance_sessions s
 JOIN public.school_classes c ON c.id=s.class_id AND c.school_id=s.school_id AND c.tenant_id=s.tenant_id
 WHERE s.school_id=p_school AND s.state IN('confirmed','published')
   AND (p_class IS NULL OR s.class_id=p_class)
   AND (app.pilot_can(p_school,ARRAY['teacher','principal','school_admin'])
        OR EXISTS(SELECT 1 FROM public.guardian_student_links g JOIN public.class_student_enrollments e ON e.student_id=g.student_id AND e.class_id=s.class_id AND e.status='active' WHERE g.school_id=p_school AND g.guardian_user_id=app.current_user_id() AND g.verification_status='verified'))
 ORDER BY s.session_date DESC LIMIT 100;
END $$;
CREATE FUNCTION public.kabarkelas_attendance_list(p_school uuid,p_class uuid DEFAULT NULL)
RETURNS TABLE(id uuid,class_id uuid,class_name text,session_date date,state text,published_at timestamptz,record_count bigint,absent_count bigint)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path='' AS $$ SELECT * FROM app.g12_attendance_list(p_school,p_class) $$;

-- detail records satu sesi (staf)
CREATE FUNCTION public.kabarkelas_attendance_records(p_session uuid)
RETURNS TABLE(student_id uuid,display_name text,local_student_no text,attendance_code text,internal_note text)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE v_s record; v_actor uuid:=app.current_user_id();
BEGIN
 SELECT * INTO v_s FROM public.attendance_sessions WHERE id=p_session;
 IF NOT FOUND THEN RAISE EXCEPTION 'Session not found' USING ERRCODE='22023'; END IF;
 IF NOT app.pilot_can(v_s.school_id,ARRAY['teacher','principal','school_admin']) THEN
  RAISE EXCEPTION 'Not authorized' USING ERRCODE='42501'; END IF;
 RETURN QUERY
 SELECT s.id,s.display_name,s.local_student_no,r.attendance_code,r.internal_note
 FROM public.class_student_enrollments e
 JOIN public.students s ON s.id=e.student_id AND s.school_id=e.school_id AND s.tenant_id=e.tenant_id
 LEFT JOIN public.attendance_records r ON r.session_id=p_session AND r.student_id=s.id AND r.school_id=v_s.school_id AND r.tenant_id=v_s.tenant_id
 WHERE e.class_id=v_s.class_id AND e.status='active' AND s.status='active'
 ORDER BY s.display_name;
END $$;

-- buat sesi kehadiran (draft) untuk kelas — guru yang ditugaskan / staf
CREATE FUNCTION public.kabarkelas_attendance_create(p_school uuid,p_class uuid,p_date date,p_period uuid)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v_tenant uuid; v_id uuid;
BEGIN
 IF NOT app.pilot_can(p_school,ARRAY['teacher','principal','school_admin']) THEN
  RAISE EXCEPTION 'Not authorized' USING ERRCODE='42501'; END IF;
 IF p_date IS NULL THEN RAISE EXCEPTION 'Date required' USING ERRCODE='22023'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.school_classes c WHERE c.id=p_class AND c.school_id=p_school)
    OR NOT EXISTS(SELECT 1 FROM public.academic_periods ap WHERE ap.id=p_period AND ap.school_id=p_school AND ap.status='active') THEN
  RAISE EXCEPTION 'Class or period invalid' USING ERRCODE='22023'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.teacher_class_assignments tc WHERE tc.school_id=p_school AND tc.class_id=p_class AND tc.teacher_user_id=app.current_user_id() AND tc.status='active')
    AND NOT app.pilot_can(p_school,ARRAY['principal','school_admin']) THEN
  RAISE EXCEPTION 'Not assigned to this class' USING ERRCODE='42501'; END IF;
 SELECT tenant_id INTO v_tenant FROM public.schools WHERE id=p_school;
 INSERT INTO public.attendance_sessions(tenant_id,school_id,class_id,period_id,session_date,state)
 VALUES(v_tenant,p_school,p_class,p_period,p_date,'draft')
 ON CONFLICT(tenant_id,school_id,class_id,session_date) DO NOTHING
 RETURNING id INTO v_id;
 IF v_id IS NULL THEN
  SELECT id INTO v_id FROM public.attendance_sessions WHERE tenant_id=v_tenant AND school_id=p_school AND class_id=p_class AND session_date=p_date;
 END IF;
 RETURN v_id;
END $$;

-- upsert satu record kehadiran (hanya saat draft)
CREATE FUNCTION public.kabarkelas_attendance_mark(p_session uuid,p_student uuid,p_code text,p_note text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v_s record;
BEGIN
 SELECT * INTO v_s FROM public.attendance_sessions WHERE id=p_session;
 IF NOT FOUND THEN RAISE EXCEPTION 'Session not found' USING ERRCODE='22023'; END IF;
 IF v_s.state<>'draft' THEN RAISE EXCEPTION 'Session already confirmed' USING ERRCODE='22023'; END IF;
 IF NOT app.pilot_can(v_s.school_id,ARRAY['teacher','principal','school_admin']) THEN
  RAISE EXCEPTION 'Not authorized' USING ERRCODE='42501'; END IF;
 IF p_code NOT IN('present','sick','excused','absent','late') THEN RAISE EXCEPTION 'Invalid code' USING ERRCODE='22023'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.class_student_enrollments e WHERE e.school_id=v_s.school_id AND e.class_id=v_s.class_id AND e.student_id=p_student AND e.status='active') THEN
  RAISE EXCEPTION 'Student not enrolled' USING ERRCODE='22023'; END IF;
 INSERT INTO public.attendance_records(tenant_id,school_id,session_id,student_id,attendance_code,internal_note)
 VALUES(v_s.tenant_id,v_s.school_id,p_session,p_student,p_code,NULLIF(trim(p_note),''))
 ON CONFLICT(tenant_id,school_id,session_id,student_id) DO UPDATE SET attendance_code=EXCLUDED.attendance_code,internal_note=EXCLUDED.internal_note;
END $$;

-- konfirmasi (draft -> confirmed) lalu publish (confirmed -> published)
CREATE FUNCTION public.kabarkelas_attendance_transition(p_session uuid,p_action text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v_s record;
BEGIN
 SELECT * INTO v_s FROM public.attendance_sessions WHERE id=p_session;
 IF NOT FOUND THEN RAISE EXCEPTION 'Session not found' USING ERRCODE='22023'; END IF;
 IF NOT app.pilot_can(v_s.school_id,ARRAY['teacher','principal','school_admin']) THEN
  RAISE EXCEPTION 'Not authorized' USING ERRCODE='42501'; END IF;
 IF p_action='confirm' AND v_s.state='draft' THEN
  IF NOT EXISTS(SELECT 1 FROM public.attendance_records r WHERE r.session_id=p_session) THEN
   RAISE EXCEPTION 'No records yet' USING ERRCODE='23514'; END IF;
  UPDATE public.attendance_sessions SET state='confirmed' WHERE id=p_session;
 ELSIF p_action='publish' AND v_s.state='confirmed' THEN
  UPDATE public.attendance_sessions SET state='published',published_at=now() WHERE id=p_session;
 ELSIF p_action='reopen' AND v_s.state='confirmed' THEN
  UPDATE public.attendance_sessions SET state='draft' WHERE id=p_session;
 ELSE
  RAISE EXCEPTION 'Invalid transition' USING ERRCODE='22023';
 END IF;
END $$;

-- ============ 2) JADWAL: create + end ============
CREATE FUNCTION public.kabarkelas_schedule_create(p_school uuid,p_class uuid,p_subject uuid,p_weekday smallint,p_start time,p_end time,p_room text DEFAULT NULL,p_year text DEFAULT '2026/2027')
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v_tenant uuid; v_id uuid;
BEGIN
 IF NOT app.pilot_can(p_school,ARRAY['teacher','principal','school_admin']) THEN
  RAISE EXCEPTION 'Not authorized' USING ERRCODE='42501'; END IF;
 IF p_weekday<1 OR p_weekday>7 OR p_end<=p_start THEN RAISE EXCEPTION 'Invalid schedule' USING ERRCODE='22023'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.school_classes c WHERE c.id=p_class AND c.school_id=p_school)
    OR NOT EXISTS(SELECT 1 FROM public.subjects sj WHERE sj.id=p_subject AND sj.school_id=p_school) THEN
  RAISE EXCEPTION 'Class or subject invalid' USING ERRCODE='22023'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.teacher_class_assignments tc JOIN public.teacher_subject_assignments tsa
   ON tsa.class_id=tc.class_id AND tsa.subject_id=p_subject AND tsa.teacher_user_id=tc.teacher_user_id AND tsa.status='active' AND tsa.school_id=tc.school_id AND tsa.tenant_id=tc.tenant_id
   WHERE tc.school_id=p_school AND tc.class_id=p_class AND tc.teacher_user_id=app.current_user_id() AND tc.status='active')
    AND NOT app.pilot_can(p_school,ARRAY['principal','school_admin']) THEN
  RAISE EXCEPTION 'Not assigned to this class/subject' USING ERRCODE='42501'; END IF;
 SELECT tenant_id INTO v_tenant FROM public.schools WHERE id=p_school;
 INSERT INTO public.lesson_schedules(tenant_id,school_id,class_id,subject_id,teacher_user_id,weekday,start_time,end_time,room,academic_year,status)
 VALUES(v_tenant,p_school,p_class,p_subject,app.current_user_id(),p_weekday,p_start,p_end,NULLIF(trim(p_room),''),p_year,'active')
 RETURNING id INTO v_id;
 RETURN v_id;
END $$;

CREATE FUNCTION public.kabarkelas_schedule_end(p_schedule uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v_s record;
BEGIN
 SELECT * INTO v_s FROM public.lesson_schedules WHERE id=p_schedule;
 IF NOT FOUND THEN RAISE EXCEPTION 'Schedule not found' USING ERRCODE='22023'; END IF;
 IF v_s.teacher_user_id<>app.current_user_id()
    AND NOT app.pilot_can(v_s.school_id,ARRAY['principal','school_admin']) THEN
  RAISE EXCEPTION 'Not authorized' USING ERRCODE='42501'; END IF;
 UPDATE public.lesson_schedules SET status='ended' WHERE id=p_schedule;
END $$;

-- ============ 3) P5 untuk guardian: filter siswa ter-link ============
-- kabarkelas_p5_list sudah mendukung guardian via guardian_student_links —
-- cukup tambah 'p5' ke allowed modules guardian di UI.

-- ============ Grants ============
DO $$
DECLARE fn text;
BEGIN
 FOREACH fn IN ARRAY ARRAY[
  'app.g12_attendance_list(uuid,uuid)','public.kabarkelas_attendance_list(uuid,uuid)',
  'public.kabarkelas_attendance_records(uuid)','public.kabarkelas_attendance_create(uuid,uuid,date,uuid)',
  'public.kabarkelas_attendance_mark(uuid,uuid,text,text)','public.kabarkelas_attendance_transition(uuid,text)',
  'public.kabarkelas_schedule_create(uuid,uuid,uuid,smallint,time,time,text,text)','public.kabarkelas_schedule_end(uuid)'
 ] LOOP
  EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC,anon,authenticated',fn);
  EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated',fn);
 END LOOP;
END $$;

COMMIT;
