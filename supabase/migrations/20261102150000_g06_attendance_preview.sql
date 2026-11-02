-- G0.6 attendance preview: only published sessions, only unexcused absence.
BEGIN;
CREATE FUNCTION app.g06_attendance_preview(p_school uuid,p_start date,p_end date,p_absent_threshold integer DEFAULT 3)
RETURNS TABLE(student_id uuid,student_name text,session_count integer,unexcused_absences integer,requires_review boolean)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE v_actor uuid:=app.g05_actor();
BEGIN
 IF p_start IS NULL OR p_end IS NULL OR p_start>p_end OR p_end-p_start>120 OR p_absent_threshold IS NULL OR p_absent_threshold<1 OR p_absent_threshold>120 THEN
 RAISE EXCEPTION 'Invalid EWS attendance window' USING ERRCODE='22023'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.memberships m JOIN public.schools sc ON sc.id=m.school_id AND sc.tenant_id=m.tenant_id AND sc.status='active'
 JOIN public.tenants t ON t.id=m.tenant_id AND t.status='active'
 WHERE m.school_id=p_school AND m.user_id=v_actor AND m.status='active' AND m.role_code IN ('teacher','principal')) THEN
 RAISE EXCEPTION 'School unavailable' USING ERRCODE='42501'; END IF;
 RETURN QUERY
 WITH visible AS (
 SELECT s.id sid,s.display_name sname,ar.attendance_code
 FROM public.attendance_records ar
 JOIN public.attendance_sessions sess ON sess.id=ar.session_id AND sess.school_id=ar.school_id AND sess.tenant_id=ar.tenant_id
 JOIN public.students s ON s.id=ar.student_id AND s.school_id=ar.school_id AND s.tenant_id=ar.tenant_id AND s.status='active'
 JOIN public.class_student_enrollments en ON en.student_id=s.id AND en.school_id=sess.school_id AND en.tenant_id=sess.tenant_id AND en.class_id=sess.class_id AND en.status='active'
 WHERE ar.school_id=p_school AND sess.state='published' AND sess.session_date BETWEEN p_start AND p_end
 AND (EXISTS(SELECT 1 FROM public.memberships m WHERE m.user_id=v_actor AND m.school_id=ar.school_id AND m.tenant_id=ar.tenant_id AND m.role_code='principal' AND m.status='active')
 OR EXISTS(SELECT 1 FROM public.memberships m JOIN public.teacher_class_assignments tc ON tc.teacher_user_id=m.user_id AND tc.tenant_id=m.tenant_id AND tc.school_id=m.school_id AND tc.class_id=sess.class_id AND tc.status='active'
 WHERE m.user_id=v_actor AND m.school_id=ar.school_id AND m.tenant_id=ar.tenant_id AND m.role_code='teacher' AND m.status='active'))
 )
 SELECT sid,sname,count(*)::integer,count(*) FILTER(WHERE attendance_code='absent')::integer,
 (count(*) FILTER(WHERE attendance_code='absent')>=p_absent_threshold)
 FROM visible GROUP BY sid,sname ORDER BY sname;
END $$;
CREATE FUNCTION public.kabarkelas_ews_attendance_preview(p_school uuid,p_start date,p_end date,p_absent_threshold integer DEFAULT 3)
RETURNS TABLE(student_id uuid,student_name text,session_count integer,unexcused_absences integer,requires_review boolean)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path='' AS $$ SELECT * FROM app.g06_attendance_preview(p_school,p_start,p_end,p_absent_threshold) $$;
REVOKE ALL ON FUNCTION app.g06_attendance_preview(uuid,date,date,integer),public.kabarkelas_ews_attendance_preview(uuid,date,date,integer) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION app.g06_attendance_preview(uuid,date,date,integer),public.kabarkelas_ews_attendance_preview(uuid,date,date,integer) TO authenticated;
COMMIT;
