BEGIN;
CREATE FUNCTION app.g083_teacher_options(p_school uuid)
RETURNS TABLE(student_id uuid,student_name text,class_id uuid,class_name text)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid:=app.g05_actor();
BEGIN
 RETURN QUERY SELECT DISTINCT s.id,s.display_name,c.id,c.name FROM public.students s
 JOIN public.class_student_enrollments e ON e.student_id=s.id AND e.tenant_id=s.tenant_id AND e.school_id=s.school_id AND e.status='active'
 JOIN public.school_classes c ON c.id=e.class_id AND c.tenant_id=e.tenant_id AND c.school_id=e.school_id
 JOIN public.teacher_class_assignments a ON a.class_id=c.id AND a.tenant_id=c.tenant_id AND a.school_id=c.school_id AND a.teacher_user_id=actor AND a.status='active'
 JOIN public.memberships m ON m.user_id=actor AND m.tenant_id=s.tenant_id AND m.school_id=s.school_id AND m.role_code='teacher' AND m.status='active'
 JOIN public.schools sc ON sc.id=s.school_id AND sc.tenant_id=s.tenant_id AND sc.status='active'
 JOIN public.tenants t ON t.id=s.tenant_id AND t.status='active'
 WHERE s.school_id=p_school AND s.status='active' ORDER BY s.display_name,c.name;
END $$;
CREATE FUNCTION public.kabarkelas_teacher_development_options(p_school uuid)
RETURNS TABLE(student_id uuid,student_name text,class_id uuid,class_name text)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path='' AS $$ SELECT * FROM app.g083_teacher_options(p_school) $$;
REVOKE ALL ON FUNCTION app.g083_teacher_options(uuid), public.kabarkelas_teacher_development_options(uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION app.g083_teacher_options(uuid), public.kabarkelas_teacher_development_options(uuid) TO authenticated;
COMMIT;