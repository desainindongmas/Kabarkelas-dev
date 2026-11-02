-- G0.6 preview: aggregate finalized academic indicators for assigned teachers/principals only.
-- No alerts written and no guardian/foundation access.
BEGIN;
CREATE FUNCTION app.g06_academic_preview(p_school uuid,p_threshold numeric DEFAULT 70,p_min_assessments integer DEFAULT 2)
RETURNS TABLE(student_id uuid,student_name text,assessment_count integer,average_percent numeric,requires_review boolean)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE v_actor uuid:=app.g05_actor();
BEGIN
 IF p_threshold IS NULL OR p_threshold<0 OR p_threshold>100 OR p_min_assessments IS NULL OR p_min_assessments<2 THEN
  RAISE EXCEPTION 'Invalid EWS preview parameters' USING ERRCODE='22023';
 END IF;
 IF NOT EXISTS(SELECT 1 FROM public.memberships m JOIN public.schools sc ON sc.id=m.school_id AND sc.tenant_id=m.tenant_id AND sc.status='active' JOIN public.tenants t ON t.id=m.tenant_id AND t.status='active' WHERE m.school_id=p_school AND m.user_id=v_actor AND m.status='active' AND m.role_code IN ('teacher','principal')) THEN
  RAISE EXCEPTION 'School unavailable' USING ERRCODE='42501';
 END IF;
 RETURN QUERY
 WITH accessible AS (
  SELECT s.id sid,s.display_name sname,g.id gid,g.tenant_id tid,g.school_id school,a.max_score,
   EXISTS(SELECT 1 FROM public.memberships m WHERE m.tenant_id=g.tenant_id AND m.school_id=g.school_id AND m.user_id=v_actor AND m.role_code='principal' AND m.status='active') is_principal
  FROM public.student_grades g JOIN public.assessments a ON a.id=g.assessment_id AND a.school_id=g.school_id AND a.tenant_id=g.tenant_id
  JOIN public.students s ON s.id=g.student_id AND s.school_id=g.school_id AND s.tenant_id=g.tenant_id AND s.status='active'
  JOIN public.class_student_enrollments en ON en.student_id=s.id AND en.class_id=a.class_id AND en.school_id=g.school_id AND en.tenant_id=g.tenant_id AND en.status='active'
  WHERE g.school_id=p_school AND a.max_score>0
  AND (EXISTS(SELECT 1 FROM public.memberships m WHERE m.tenant_id=g.tenant_id AND m.school_id=g.school_id AND m.user_id=v_actor AND m.role_code='principal' AND m.status='active')
   OR EXISTS(SELECT 1 FROM public.memberships m JOIN public.teacher_class_assignments tc ON tc.tenant_id=m.tenant_id AND tc.school_id=m.school_id AND tc.teacher_user_id=m.user_id AND tc.class_id=a.class_id AND tc.status='active' WHERE m.user_id=v_actor AND m.role_code='teacher' AND m.status='active' AND m.school_id=g.school_id AND m.tenant_id=g.tenant_id))
 ), scoring AS (
  SELECT x.sid,x.sname,x.gid,100*coalesce(rel.effective_score,CASE WHEN g.status='published' THEN g.score END)/x.max_score pct
  FROM accessible x JOIN public.student_grades g ON g.id=x.gid
  LEFT JOIN LATERAL (SELECT r.effective_score FROM public.assessment_releases r WHERE r.grade_id=g.id ORDER BY r.version DESC LIMIT 1) rel ON true
  WHERE rel.effective_score IS NOT NULL OR g.status='published'
 ), summary AS (
  SELECT sid,sname,count(DISTINCT gid)::integer n,round(avg(pct),2) average
  FROM scoring GROUP BY sid,sname
 )
 SELECT sid,sname,n,average,(n>=p_min_assessments AND average<p_threshold)
 FROM summary WHERE n>=p_min_assessments ORDER BY average,sname;
END $$;
CREATE FUNCTION public.kabarkelas_ews_academic_preview(p_school uuid,p_threshold numeric DEFAULT 70,p_min_assessments integer DEFAULT 2)
RETURNS TABLE(student_id uuid,student_name text,assessment_count integer,average_percent numeric,requires_review boolean)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path='' AS $$
 SELECT * FROM app.g06_academic_preview(p_school,p_threshold,p_min_assessments)
$$;
REVOKE ALL ON FUNCTION app.g06_academic_preview(uuid,numeric,integer),public.kabarkelas_ews_academic_preview(uuid,numeric,integer) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION app.g06_academic_preview(uuid,numeric,integer),public.kabarkelas_ews_academic_preview(uuid,numeric,integer) TO authenticated;
COMMIT;
