CREATE OR REPLACE FUNCTION public.kabarkelas_my_role_students(p_school_id uuid)
RETURNS TABLE(student_id uuid, display_name text, local_student_no text, access_role text)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public,auth AS $$
DECLARE v_user uuid;
BEGIN
 IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required' USING ERRCODE='28000'; END IF;
 SELECT u.id INTO v_user FROM public.users u WHERE u.auth_subject=auth.uid()::text;
 IF v_user IS NULL THEN RETURN; END IF;
 RETURN QUERY
 SELECT s.id,s.display_name,s.local_student_no,
   CASE WHEN EXISTS(SELECT 1 FROM public.memberships m WHERE m.user_id=v_user AND m.tenant_id=s.tenant_id AND m.school_id=s.school_id AND m.role_code='principal' AND m.status='active') THEN 'principal' ELSE 'guardian' END
 FROM public.students s
 JOIN public.schools sch ON sch.id=s.school_id AND sch.tenant_id=s.tenant_id AND sch.status='active'
 JOIN public.tenants t ON t.id=s.tenant_id AND t.status='active'
 WHERE s.school_id=p_school_id AND s.status='active'
 AND (
 EXISTS(SELECT 1 FROM public.memberships m WHERE m.user_id=v_user AND m.tenant_id=s.tenant_id AND m.school_id=s.school_id AND m.role_code='principal' AND m.status='active')
 OR (EXISTS(SELECT 1 FROM public.memberships m WHERE m.user_id=v_user AND m.tenant_id=s.tenant_id AND m.school_id=s.school_id AND m.role_code='guardian' AND m.status='active')
 AND EXISTS(SELECT 1 FROM public.guardian_student_links l WHERE l.student_id=s.id AND l.school_id=s.school_id AND l.tenant_id=s.tenant_id AND l.guardian_user_id=v_user AND l.verification_status='verified'))
 )
 ORDER BY s.display_name,s.id;
END $$;
REVOKE ALL ON FUNCTION public.kabarkelas_my_role_students(uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.kabarkelas_my_role_students(uuid) TO authenticated;
