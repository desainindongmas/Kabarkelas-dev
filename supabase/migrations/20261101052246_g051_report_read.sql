BEGIN;
CREATE FUNCTION app.g051_report_setup_options(p_school uuid)
RETURNS TABLE(class_id uuid,class_name text,period_id uuid,period_code text,homeroom_user_id uuid,homeroom_label text)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE v_actor uuid:=app.g05_actor();
BEGIN
 IF NOT EXISTS(SELECT 1 FROM public.memberships m JOIN public.schools s ON s.id=m.school_id AND s.status='active' JOIN public.tenants t ON t.id=m.tenant_id AND t.status='active' WHERE m.user_id=v_actor AND m.school_id=p_school AND m.role_code='principal' AND m.status='active') THEN RAISE EXCEPTION 'Principal required' USING ERRCODE='42501'; END IF;
 RETURN QUERY
 SELECT c.id,c.name,p.id,p.code,u.id,coalesce(u.email,'Guru')
 FROM public.school_classes c
 JOIN public.academic_periods p ON p.tenant_id=c.tenant_id AND p.school_id=c.school_id
 JOIN public.teacher_class_assignments a ON a.class_id=c.id AND a.tenant_id=c.tenant_id AND a.school_id=c.school_id AND a.status='active'
 JOIN public.users u ON u.id=a.teacher_user_id
 JOIN public.memberships m ON m.user_id=u.id AND m.tenant_id=c.tenant_id AND m.school_id=c.school_id AND m.role_code='teacher' AND m.status='active'
 WHERE c.school_id=p_school
 ORDER BY c.name,p.code,u.email;
END $$;
CREATE FUNCTION app.g051_my_class_reports(p_school uuid)
RETURNS TABLE(report_id uuid,class_name text,period_code text,report_status text,report_version integer,report_revision integer,allowed_actions text[])
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE v_actor uuid:=app.g05_actor();
BEGIN
 RETURN QUERY
 SELECT r.id,c.name,p.code,r.status,r.version,r.revision,
 CASE
 WHEN r.status='draft' AND EXISTS(SELECT 1 FROM public.memberships m JOIN public.teacher_class_assignments a ON a.teacher_user_id=m.user_id AND a.tenant_id=m.tenant_id AND a.school_id=m.school_id AND a.class_id=r.class_id AND a.status='active' WHERE m.user_id=v_actor AND m.school_id=r.school_id AND m.tenant_id=r.tenant_id AND m.role_code='teacher' AND m.status='active') THEN ARRAY['teacher_finalize']::text[]
 WHEN r.status='teacher_finalized' AND r.homeroom_user_id=v_actor AND EXISTS(SELECT 1 FROM public.memberships m WHERE m.user_id=v_actor AND m.school_id=r.school_id AND m.tenant_id=r.tenant_id AND m.role_code='teacher' AND m.status='active') THEN ARRAY['homeroom_review']::text[]
 WHEN r.status='homeroom_reviewed' AND EXISTS(SELECT 1 FROM public.memberships m WHERE m.user_id=v_actor AND m.school_id=r.school_id AND m.tenant_id=r.tenant_id AND m.role_code='principal' AND m.status='active') AND r.homeroom_user_id<>v_actor THEN ARRAY['principal_sign']::text[]
 WHEN r.status='principal_signed' AND (r.homeroom_user_id=v_actor OR EXISTS(SELECT 1 FROM public.memberships m WHERE m.user_id=v_actor AND m.school_id=r.school_id AND m.tenant_id=r.tenant_id AND m.role_code='principal' AND m.status='active')) THEN ARRAY['release']::text[]
 ELSE ARRAY[]::text[] END
 FROM public.school_report_reviews r
 JOIN public.school_classes c ON c.id=r.class_id AND c.school_id=r.school_id AND c.tenant_id=r.tenant_id
 JOIN public.academic_periods p ON p.id=r.period_id AND p.school_id=r.school_id AND p.tenant_id=r.tenant_id
 JOIN public.schools s ON s.id=r.school_id AND s.status='active'
 JOIN public.tenants t ON t.id=r.tenant_id AND t.status='active'
 WHERE r.school_id=p_school
 AND (
   EXISTS(SELECT 1 FROM public.memberships m WHERE m.user_id=v_actor AND m.school_id=r.school_id AND m.tenant_id=r.tenant_id AND m.role_code='principal' AND m.status='active')
   OR EXISTS(SELECT 1 FROM public.memberships m JOIN public.teacher_class_assignments a ON a.teacher_user_id=m.user_id AND a.class_id=r.class_id AND a.tenant_id=r.tenant_id AND a.school_id=r.school_id AND a.status='active' WHERE m.user_id=v_actor AND m.school_id=r.school_id AND m.tenant_id=r.tenant_id AND m.role_code='teacher' AND m.status='active')
 )
 ORDER BY c.name,p.code,r.version;
END $$;
CREATE FUNCTION app.g051_my_released_reports(p_school uuid)
RETURNS TABLE(student_name text,class_name text,period_code text,report_version integer,grades jsonb)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE v_actor uuid:=app.g05_actor();
BEGIN
 RETURN QUERY
 SELECT s.display_name,c.name,p.code,r.version,snap.payload->'grades'
 FROM public.school_report_reviews r
 JOIN public.school_report_snapshots snap ON snap.report_id=r.id AND snap.tenant_id=r.tenant_id AND snap.school_id=r.school_id AND snap.version=r.version
 JOIN public.students s ON s.id=snap.student_id AND s.school_id=r.school_id AND s.tenant_id=r.tenant_id AND s.status='active'
 JOIN public.school_classes c ON c.id=r.class_id AND c.school_id=r.school_id AND c.tenant_id=r.tenant_id
 JOIN public.academic_periods p ON p.id=r.period_id AND p.school_id=r.school_id AND p.tenant_id=r.tenant_id
 JOIN public.schools sch ON sch.id=r.school_id AND sch.status='active'
 JOIN public.tenants t ON t.id=r.tenant_id AND t.status='active'
 JOIN public.memberships m ON m.user_id=v_actor AND m.tenant_id=r.tenant_id AND m.school_id=r.school_id AND m.role_code='guardian' AND m.status='active'
 JOIN public.guardian_student_links l ON l.guardian_user_id=v_actor AND l.tenant_id=r.tenant_id AND l.school_id=r.school_id AND l.student_id=s.id AND l.verification_status='verified'
 WHERE r.school_id=p_school AND r.status='released'
 AND r.version=(SELECT max(other.version) FROM public.school_report_reviews other WHERE other.class_id=r.class_id AND other.period_id=r.period_id AND other.status='released')
 ORDER BY s.display_name,p.code;
END $$;
CREATE FUNCTION public.kabarkelas_report_setup_options(p_school uuid)
RETURNS TABLE(class_id uuid,class_name text,period_id uuid,period_code text,homeroom_user_id uuid,homeroom_label text)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path='' AS $$ SELECT * FROM app.g051_report_setup_options(p_school) $$;
CREATE FUNCTION public.kabarkelas_my_class_reports(p_school uuid)
RETURNS TABLE(report_id uuid,class_name text,period_code text,report_status text,report_version integer,report_revision integer,allowed_actions text[])
LANGUAGE sql STABLE SECURITY INVOKER SET search_path='' AS $$ SELECT * FROM app.g051_my_class_reports(p_school) $$;
CREATE FUNCTION public.kabarkelas_my_released_reports(p_school uuid)
RETURNS TABLE(student_name text,class_name text,period_code text,report_version integer,grades jsonb)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path='' AS $$ SELECT * FROM app.g051_my_released_reports(p_school) $$;
REVOKE ALL ON FUNCTION app.g051_report_setup_options(uuid),app.g051_my_class_reports(uuid),app.g051_my_released_reports(uuid),public.kabarkelas_report_setup_options(uuid),public.kabarkelas_my_class_reports(uuid),public.kabarkelas_my_released_reports(uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION app.g051_report_setup_options(uuid),app.g051_my_class_reports(uuid),app.g051_my_released_reports(uuid),public.kabarkelas_report_setup_options(uuid),public.kabarkelas_my_class_reports(uuid),public.kabarkelas_my_released_reports(uuid) TO authenticated;
COMMIT;
