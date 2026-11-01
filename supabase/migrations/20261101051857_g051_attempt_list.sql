BEGIN;
CREATE FUNCTION app.g051_list_attempts(p_grade uuid)
RETURNS TABLE(attempt_id uuid, attempt_kind text, score numeric, recorded_at timestamptz, note text)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE v_user uuid := app.g05_actor();
BEGIN
 IF NOT EXISTS(SELECT 1 FROM app.g05_access(p_grade,v_user) a WHERE a.teacher OR a.principal) THEN
   RAISE EXCEPTION 'Grade unavailable' USING ERRCODE='42501';
 END IF;
 RETURN QUERY SELECT at.id,at.attempt_kind,at.score,at.recorded_at,at.note
 FROM public.assessment_attempts at JOIN public.student_grades g ON g.id=at.grade_id
 WHERE at.grade_id=p_grade AND at.tenant_id=g.tenant_id AND at.school_id=g.school_id
 ORDER BY at.recorded_at,at.id;
END $$;
CREATE FUNCTION public.kabarkelas_list_attempts(p_grade uuid)
RETURNS TABLE(attempt_id uuid,attempt_kind text,score numeric,recorded_at timestamptz,note text)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path='' AS $$ SELECT * FROM app.g051_list_attempts(p_grade) $$;
REVOKE ALL ON FUNCTION app.g051_list_attempts(uuid),public.kabarkelas_list_attempts(uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION app.g051_list_attempts(uuid),public.kabarkelas_list_attempts(uuid) TO authenticated;
COMMIT;
