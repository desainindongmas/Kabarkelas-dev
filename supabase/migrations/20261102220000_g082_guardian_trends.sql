BEGIN;
CREATE FUNCTION app.g082_guardian_trends(p_school uuid)
RETURNS TABLE(student_id uuid,student_name text,subject_name text,assessment_title text,score_percent numeric,released_at timestamptz)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE v_actor uuid:=app.g05_actor();
BEGIN
 IF NOT EXISTS(SELECT 1 FROM public.memberships m JOIN public.schools sc ON sc.id=m.school_id AND sc.tenant_id=m.tenant_id AND sc.status='active' JOIN public.tenants t ON t.id=m.tenant_id AND t.status='active' WHERE m.user_id=v_actor AND m.school_id=p_school AND m.role_code='guardian' AND m.status='active') THEN RAISE EXCEPTION 'School unavailable' USING ERRCODE='42501'; END IF;
 RETURN QUERY
 SELECT st.id,st.display_name,sub.name,a.title,
 round(100*coalesce(r.effective_score,CASE WHEN g.status='published' THEN g.score END)/a.max_score,2),
 coalesce(r.released_at,g.published_at)
 FROM public.student_grades g
 JOIN public.assessments a ON a.id=g.assessment_id AND a.tenant_id=g.tenant_id AND a.school_id=g.school_id AND a.max_score>0
 JOIN public.subjects sub ON sub.id=a.subject_id AND sub.tenant_id=a.tenant_id AND sub.school_id=a.school_id
 JOIN public.students st ON st.id=g.student_id AND st.tenant_id=g.tenant_id AND st.school_id=g.school_id AND st.status='active'
 JOIN public.guardian_student_links l ON l.student_id=st.id AND l.tenant_id=st.tenant_id AND l.school_id=st.school_id AND l.guardian_user_id=v_actor AND l.verification_status='verified'
 LEFT JOIN LATERAL (SELECT rel.effective_score,rel.status,rel.released_at FROM public.assessment_releases rel WHERE rel.grade_id=g.id ORDER BY rel.version DESC LIMIT 1) r ON true
 WHERE g.school_id=p_school AND (r.status='released' OR (r.status IS NULL AND g.status='published'))
 AND coalesce(r.released_at,g.published_at) IS NOT NULL
 ORDER BY st.display_name,sub.name,coalesce(r.released_at,g.published_at),a.title;
END $$;
CREATE FUNCTION public.kabarkelas_guardian_academic_trends(p_school uuid)
RETURNS TABLE(student_id uuid,student_name text,subject_name text,assessment_title text,score_percent numeric,released_at timestamptz)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path='' AS $$ SELECT * FROM app.g082_guardian_trends(p_school) $$;
REVOKE ALL ON FUNCTION app.g082_guardian_trends(uuid),public.kabarkelas_guardian_academic_trends(uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION app.g082_guardian_trends(uuid),public.kabarkelas_guardian_academic_trends(uuid) TO authenticated;
COMMIT;