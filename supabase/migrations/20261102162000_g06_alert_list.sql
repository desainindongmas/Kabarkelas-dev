BEGIN;
CREATE FUNCTION app.g06_my_alerts(p_school uuid)
RETURNS TABLE(alert_id uuid,student_name text,signal text,explanation text,alert_status text,severity text,detected_at timestamptz)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE v_actor uuid:=app.g05_actor();
BEGIN
 IF NOT EXISTS(SELECT 1 FROM public.memberships m JOIN public.schools sc ON sc.id=m.school_id AND sc.tenant_id=m.tenant_id AND sc.status='active' JOIN public.tenants t ON t.id=m.tenant_id AND t.status='active' WHERE m.user_id=v_actor AND m.school_id=p_school AND m.status='active' AND m.role_code IN ('teacher','principal')) THEN RAISE EXCEPTION 'School unavailable' USING ERRCODE='42501'; END IF;
 RETURN QUERY SELECT al.id,s.display_name,ru.rule_key,al.explanation,al.status,al.severity,al.detected_at
 FROM public.ews_alerts al
 JOIN public.ews_rules ru ON ru.id=al.rule_id AND ru.tenant_id=al.tenant_id AND ru.school_id=al.school_id
 JOIN public.students s ON s.id=al.student_id AND s.tenant_id=al.tenant_id AND s.school_id=al.school_id AND s.status='active'
 WHERE al.school_id=p_school AND
 (EXISTS(SELECT 1 FROM public.memberships m WHERE m.user_id=v_actor AND m.tenant_id=al.tenant_id AND m.school_id=al.school_id AND m.role_code='principal' AND m.status='active')
 OR EXISTS(SELECT 1 FROM public.memberships m JOIN public.teacher_class_assignments tc ON tc.teacher_user_id=m.user_id AND tc.tenant_id=m.tenant_id AND tc.school_id=m.school_id AND tc.status='active' JOIN public.class_student_enrollments en ON en.class_id=tc.class_id AND en.student_id=al.student_id AND en.tenant_id=tc.tenant_id AND en.school_id=tc.school_id AND en.status='active' WHERE m.user_id=v_actor AND m.tenant_id=al.tenant_id AND m.school_id=al.school_id AND m.role_code='teacher' AND m.status='active'))
 ORDER BY al.detected_at DESC,al.id;
END $$;
CREATE FUNCTION public.kabarkelas_ews_my_alerts(p_school uuid)
RETURNS TABLE(alert_id uuid,student_name text,signal text,explanation text,alert_status text,severity text,detected_at timestamptz)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path='' AS $$ SELECT * FROM app.g06_my_alerts(p_school) $$;
REVOKE ALL ON FUNCTION app.g06_my_alerts(uuid),public.kabarkelas_ews_my_alerts(uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION app.g06_my_alerts(uuid),public.kabarkelas_ews_my_alerts(uuid) TO authenticated;
COMMIT;