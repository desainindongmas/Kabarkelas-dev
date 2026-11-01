CREATE OR REPLACE FUNCTION public.kabarkelas_my_students(p_school_id uuid)
RETURNS TABLE(student_id uuid, display_name text, local_student_no text, class_name text)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public,app,auth AS $$
DECLARE v_user uuid;
BEGIN
 IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required' USING ERRCODE='28000'; END IF;
 SELECT u.id INTO v_user FROM public.users u WHERE u.auth_subject=auth.uid()::text;
 IF v_user IS NULL THEN RETURN; END IF;
 RETURN QUERY
 SELECT DISTINCT s.id,s.display_name,s.local_student_no,c.name
 FROM public.students s
 JOIN public.class_student_enrollments e ON e.tenant_id=s.tenant_id AND e.school_id=s.school_id AND e.student_id=s.id AND e.status='active'
 JOIN public.school_classes c ON c.id=e.class_id AND c.tenant_id=e.tenant_id AND c.school_id=e.school_id
 JOIN public.teacher_class_assignments a ON a.tenant_id=c.tenant_id AND a.school_id=c.school_id AND a.class_id=c.id AND a.status='active' AND a.teacher_user_id=v_user
 JOIN public.memberships m ON m.tenant_id=s.tenant_id AND m.school_id=s.school_id AND m.user_id=v_user AND m.role_code='teacher' AND m.status='active'
 JOIN public.schools sch ON sch.id=s.school_id AND sch.status='active'
 JOIN public.tenants t ON t.id=s.tenant_id AND t.status='active'
 WHERE s.school_id=p_school_id AND s.status='active'
 ORDER BY s.display_name,s.id,c.name;
END $$;
REVOKE ALL ON FUNCTION public.kabarkelas_my_students(uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.kabarkelas_my_students(uuid) TO authenticated;
