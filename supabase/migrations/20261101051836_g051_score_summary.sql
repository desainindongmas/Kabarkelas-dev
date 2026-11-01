-- G0.5.1 policy-aware assessment calculation.
-- Calculated results are separate from the existing immutable published grade.
BEGIN;
CREATE FUNCTION app.g051_attempt_summary(p_grade uuid)
RETURNS TABLE(initial_score numeric, latest_remedial_score numeric, effective_score numeric, attempt_count integer, policy_mode text)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE
 v_user uuid := app.g05_actor();
 v_g public.student_grades%ROWTYPE;
 v_max numeric;
 v_first numeric;
 v_latest numeric;
 v_best numeric;
 v_count integer;
 v_mode text;
 v_cap numeric;
BEGIN
 SELECT * INTO v_g FROM public.student_grades WHERE id=p_grade;
 IF NOT FOUND THEN RAISE EXCEPTION 'Grade unavailable' USING ERRCODE='42501'; END IF;
 IF NOT EXISTS(SELECT 1 FROM app.g05_access(p_grade,v_user) a WHERE a.teacher OR a.principal) THEN
   RAISE EXCEPTION 'Grade unavailable' USING ERRCODE='42501';
 END IF;
 SELECT max_score INTO v_max FROM public.assessments WHERE id=v_g.assessment_id AND school_id=v_g.school_id AND tenant_id=v_g.tenant_id;
 SELECT a.score INTO v_first FROM public.assessment_attempts a
 WHERE a.grade_id=p_grade AND a.attempt_kind='initial' ORDER BY a.recorded_at,a.id LIMIT 1;
 SELECT a.score INTO v_latest FROM public.assessment_attempts a
 WHERE a.grade_id=p_grade AND a.attempt_kind='remedial' ORDER BY a.recorded_at DESC,a.id DESC LIMIT 1;
 SELECT max(a.score),count(*)::integer INTO v_best,v_count FROM public.assessment_attempts a WHERE a.grade_id=p_grade;
 SELECT p.mode,p.cap_percent INTO v_mode,v_cap FROM public.assessment_policies p
 WHERE p.tenant_id=v_g.tenant_id AND p.school_id=v_g.school_id AND p.is_active
 ORDER BY p.version DESC LIMIT 1;
 v_mode:=COALESCE(v_mode,'best_score');
 IF v_count=0 THEN
   RETURN QUERY SELECT NULL::numeric,NULL::numeric,NULL::numeric,0::integer,v_mode; RETURN;
 END IF;
 IF v_first IS NULL THEN RAISE EXCEPTION 'Missing initial score' USING ERRCODE='23514'; END IF;
 IF v_mode='latest_score' THEN
   RETURN QUERY SELECT v_first,v_latest,COALESCE(v_latest,v_first),v_count,v_mode;
 ELSIF v_mode='best_capped' AND v_latest IS NOT NULL THEN
   RETURN QUERY SELECT v_first,v_latest,greatest(v_first,least(v_best,v_max*v_cap/100)),v_count,v_mode;
 ELSE
   RETURN QUERY SELECT v_first,v_latest,v_best,v_count,v_mode;
 END IF;
END $$;
CREATE FUNCTION public.kabarkelas_attempt_summary(p_grade uuid)
RETURNS TABLE(initial_score numeric, latest_remedial_score numeric, effective_score numeric, attempt_count integer, policy_mode text)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path='' AS $$
 SELECT * FROM app.g051_attempt_summary(p_grade);
$$;
REVOKE ALL ON FUNCTION app.g051_attempt_summary(uuid),public.kabarkelas_attempt_summary(uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION app.g051_attempt_summary(uuid),public.kabarkelas_attempt_summary(uuid) TO authenticated;
COMMIT;
