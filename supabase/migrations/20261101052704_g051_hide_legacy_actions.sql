-- Keep existing G0.5 read contract, but suppress legacy actions for remedial assessments.
BEGIN;
CREATE OR REPLACE FUNCTION app.g05_grades(p_school_id uuid)
RETURNS TABLE(grade_id uuid,student_name text,subject_name text,assessment_title text,score numeric,grade_status text,revision integer,allowed_actions text[])
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_user uuid := app.g05_actor();
BEGIN
  RETURN QUERY
  SELECT g.id,
    CASE WHEN g.status='published' THEN snap.payload->>'student_name' ELSE s.display_name END,
    CASE WHEN g.status='published' THEN snap.payload->>'subject_name' ELSE sub.name END,
    CASE WHEN g.status='published' THEN snap.payload->>'assessment_title' ELSE a.title END,
    CASE WHEN g.status='published' THEN (snap.payload->>'score')::numeric ELSE g.score END,
    g.status,g.revision,
    CASE WHEN EXISTS(SELECT 1 FROM public.assessment_attempts at WHERE at.grade_id=g.id) THEN ARRAY[]::text[]
    WHEN g.status='draft' AND rights.teacher THEN ARRAY['submit']
      WHEN g.status='submitted' AND rights.principal AND g.submitted_by<>v_user THEN ARRAY['approve']
      WHEN g.status='approved' AND rights.principal AND g.submitted_by<>v_user THEN ARRAY['publish']
      ELSE ARRAY[]::text[] END
  FROM public.student_grades g
  JOIN public.students s ON (s.tenant_id,s.school_id,s.id)=(g.tenant_id,g.school_id,g.student_id)
  JOIN public.assessments a ON (a.tenant_id,a.school_id,a.id)=(g.tenant_id,g.school_id,g.assessment_id)
  JOIN public.subjects sub ON (sub.tenant_id,sub.school_id,sub.id)=(g.tenant_id,g.school_id,a.subject_id)
  CROSS JOIN LATERAL app.g05_access(g.id,v_user) rights
  LEFT JOIN public.academic_publication_snapshots snap ON snap.tenant_id=g.tenant_id AND snap.school_id=g.school_id AND snap.resource_type='grade' AND snap.resource_id=g.id AND snap.version=g.revision
  WHERE g.school_id=p_school_id
    AND (g.status<>'published' OR snap.id IS NOT NULL)
    AND (rights.teacher OR rights.principal OR (rights.guardian AND g.status='published' AND snap.id IS NOT NULL))
  ORDER BY s.display_name,sub.name,a.title,g.id;
END $$;
COMMIT;
