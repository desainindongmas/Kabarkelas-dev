CREATE OR REPLACE FUNCTION public.kabarkelas_my_grades(p_school_id uuid)
RETURNS TABLE(student_name text,subject_name text,assessment_title text,score numeric,grade_status text)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public,auth AS $$
DECLARE v_user uuid;
BEGIN
 IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required' USING ERRCODE='28000'; END IF;
 SELECT id INTO v_user FROM public.users WHERE auth_subject=auth.uid()::text;
 IF v_user IS NULL THEN RETURN; END IF;
 RETURN QUERY
 SELECT s.display_name,sub.name,a.title,g.score,g.status
 FROM public.student_grades g
 JOIN public.students s ON s.id=g.student_id AND s.tenant_id=g.tenant_id AND s.school_id=g.school_id
 JOIN public.assessments a ON a.id=g.assessment_id AND a.tenant_id=g.tenant_id AND a.school_id=g.school_id
 JOIN public.subjects sub ON sub.id=a.subject_id AND sub.tenant_id=a.tenant_id AND sub.school_id=a.school_id
 JOIN public.schools sch ON sch.id=g.school_id AND sch.tenant_id=g.tenant_id AND sch.status='active'
 JOIN public.tenants t ON t.id=g.tenant_id AND t.status='active'
 WHERE g.school_id=p_school_id AND
 (
   EXISTS(SELECT 1 FROM public.memberships m WHERE m.user_id=v_user AND m.tenant_id=g.tenant_id AND m.school_id=g.school_id AND m.role_code='principal' AND m.status='active')
   OR
   (EXISTS(SELECT 1 FROM public.memberships m WHERE m.user_id=v_user AND m.tenant_id=g.tenant_id AND m.school_id=g.school_id AND m.role_code='teacher' AND m.status='active')
    AND EXISTS(SELECT 1 FROM public.teacher_class_assignments tc JOIN public.class_student_enrollments en ON en.tenant_id=tc.tenant_id AND en.school_id=tc.school_id AND en.class_id=tc.class_id WHERE tc.tenant_id=g.tenant_id AND tc.school_id=g.school_id AND tc.class_id=a.class_id AND tc.teacher_user_id=v_user AND tc.status='active' AND en.student_id=g.student_id AND en.status='active'))
   OR
   (g.status='published' AND g.published_at IS NOT NULL
    AND EXISTS(SELECT 1 FROM public.memberships m WHERE m.user_id=v_user AND m.tenant_id=g.tenant_id AND m.school_id=g.school_id AND m.role_code='guardian' AND m.status='active')
    AND EXISTS(SELECT 1 FROM public.guardian_student_links l WHERE l.student_id=g.student_id AND l.school_id=g.school_id AND l.tenant_id=g.tenant_id AND l.guardian_user_id=v_user AND l.verification_status='verified'))
 )
 ORDER BY s.display_name,sub.name,a.title;
END $$;
REVOKE ALL ON FUNCTION public.kabarkelas_my_grades(uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.kabarkelas_my_grades(uuid) TO authenticated;
