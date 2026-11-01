-- G0.5.1 teacher-scoped assessment attempt operations.
-- Designed for NEW draft grades only. Historical G0.5 published records remain immutable.
BEGIN;
CREATE FUNCTION app.g051_can_manage_draft(p_grade uuid,p_actor uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
 SELECT EXISTS(
 SELECT 1 FROM public.student_grades g
 JOIN public.assessments a ON (a.id,a.school_id,a.tenant_id)=(g.assessment_id,g.school_id,g.tenant_id)
 JOIN public.students s ON (s.id,s.school_id,s.tenant_id)=(g.student_id,g.school_id,g.tenant_id) AND s.status='active'
 JOIN public.schools sc ON sc.id=g.school_id AND sc.tenant_id=g.tenant_id AND sc.status='active'
 JOIN public.tenants t ON t.id=g.tenant_id AND t.status='active'
 JOIN public.memberships m ON m.user_id=p_actor AND m.tenant_id=g.tenant_id AND m.school_id=g.school_id AND m.role_code='teacher' AND m.status='active'
 JOIN public.teacher_class_assignments tc ON tc.tenant_id=g.tenant_id AND tc.school_id=g.school_id AND tc.class_id=a.class_id AND tc.teacher_user_id=p_actor AND tc.status='active'
 JOIN public.class_student_enrollments en ON en.tenant_id=g.tenant_id AND en.school_id=g.school_id AND en.class_id=a.class_id AND en.student_id=g.student_id AND en.status='active' AND en.started_at<=now() AND (en.ended_at IS NULL OR en.ended_at>now())
 WHERE g.id=p_grade AND g.status='draft');
$$;
CREATE FUNCTION app.g051_record_attempt(p_grade uuid,p_kind text,p_score numeric,p_note text DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v_actor uuid; v_g public.student_grades%ROWTYPE; v_max numeric; v_id uuid;
BEGIN
 v_actor:=app.g05_actor();
 IF p_kind NOT IN ('initial','remedial') OR p_kind IS NULL THEN RAISE EXCEPTION 'Invalid kind' USING ERRCODE='22023'; END IF;
 SELECT * INTO v_g FROM public.student_grades WHERE id=p_grade FOR UPDATE;
 IF NOT FOUND OR NOT app.g051_can_manage_draft(p_grade,v_actor) THEN RAISE EXCEPTION 'Grade unavailable' USING ERRCODE='42501'; END IF;
 SELECT max_score INTO v_max FROM public.assessments WHERE id=v_g.assessment_id AND tenant_id=v_g.tenant_id AND school_id=v_g.school_id;
 IF p_score IS NULL OR p_score::text='NaN' OR p_score<0 OR p_score>v_max THEN RAISE EXCEPTION 'Score out of range' USING ERRCODE='23514'; END IF;
 IF p_kind='initial' AND EXISTS(SELECT 1 FROM public.assessment_attempts WHERE grade_id=p_grade AND attempt_kind='initial') THEN RAISE EXCEPTION 'Initial attempt exists' USING ERRCODE='23505'; END IF;
 IF p_kind='remedial' AND NOT EXISTS(SELECT 1 FROM public.assessment_attempts WHERE grade_id=p_grade AND attempt_kind='initial') THEN RAISE EXCEPTION 'Initial attempt required' USING ERRCODE='23514'; END IF;
 INSERT INTO public.assessment_attempts(tenant_id,school_id,grade_id,attempt_kind,score,recorded_by,note)
 VALUES(v_g.tenant_id,v_g.school_id,p_grade,p_kind,p_score,v_actor,left(p_note,500)) RETURNING id INTO v_id;
 RETURN v_id;
END $$;
CREATE FUNCTION app.g051_correct_attempt(p_attempt uuid,p_new_score numeric,p_reason text)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v_actor uuid; v_attempt public.assessment_attempts%ROWTYPE; v_grade public.student_grades%ROWTYPE; v_max numeric; v_correction uuid;
BEGIN
 v_actor:=app.g05_actor();
 SELECT * INTO v_attempt FROM public.assessment_attempts WHERE id=p_attempt FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Attempt unavailable' USING ERRCODE='42501'; END IF;
 SELECT * INTO v_grade FROM public.student_grades WHERE id=v_attempt.grade_id FOR UPDATE;
 IF NOT app.g051_can_manage_draft(v_attempt.grade_id,v_actor) THEN RAISE EXCEPTION 'Attempt unavailable' USING ERRCODE='42501'; END IF;
 SELECT max_score INTO v_max FROM public.assessments WHERE id=v_grade.assessment_id AND school_id=v_grade.school_id AND tenant_id=v_grade.tenant_id;
 IF p_reason IS NULL OR length(btrim(p_reason))<3 THEN RAISE EXCEPTION 'Reason required' USING ERRCODE='22023'; END IF;
 IF p_new_score IS NULL OR p_new_score::text='NaN' OR p_new_score<0 OR p_new_score>v_max THEN RAISE EXCEPTION 'Score out of range' USING ERRCODE='23514'; END IF;
 IF v_attempt.score=p_new_score THEN RAISE EXCEPTION 'No change' USING ERRCODE='22023'; END IF;
 INSERT INTO public.assessment_corrections(tenant_id,school_id,attempt_id,previous_score,corrected_score,reason,corrected_by)
 VALUES(v_attempt.tenant_id,v_attempt.school_id,v_attempt.id,v_attempt.score,p_new_score,btrim(p_reason),v_actor) RETURNING id INTO v_correction;
 UPDATE public.assessment_attempts SET score=p_new_score WHERE id=v_attempt.id;
 RETURN v_correction;
END $$;
CREATE FUNCTION public.kabarkelas_record_attempt(p_grade uuid,p_kind text,p_score numeric,p_note text DEFAULT NULL)
RETURNS uuid LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT app.g051_record_attempt(p_grade,p_kind,p_score,p_note) $$;
CREATE FUNCTION public.kabarkelas_correct_attempt(p_attempt uuid,p_new_score numeric,p_reason text)
RETURNS uuid LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT app.g051_correct_attempt(p_attempt,p_new_score,p_reason) $$;
REVOKE ALL ON FUNCTION app.g051_can_manage_draft(uuid,uuid),app.g051_record_attempt(uuid,text,numeric,text),app.g051_correct_attempt(uuid,numeric,text),public.kabarkelas_record_attempt(uuid,text,numeric,text),public.kabarkelas_correct_attempt(uuid,numeric,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION app.g051_record_attempt(uuid,text,numeric,text),app.g051_correct_attempt(uuid,numeric,text),public.kabarkelas_record_attempt(uuid,text,numeric,text),public.kabarkelas_correct_attempt(uuid,numeric,text) TO authenticated;
COMMIT;
