BEGIN;
ALTER TABLE public.student_development_observations ADD COLUMN revision integer NOT NULL DEFAULT 1;
ALTER TABLE public.student_development_observations DROP CONSTRAINT IF EXISTS student_development_observations_state_check;
ALTER TABLE public.student_development_observations ADD CONSTRAINT student_development_observations_state_check CHECK(state IN ('draft','published','withdrawn'));
ALTER TABLE public.student_development_observations DROP CONSTRAINT IF EXISTS student_development_observations_check;
ALTER TABLE public.student_development_observations ADD CONSTRAINT student_development_observations_publication_check CHECK ((state='draft' AND published_at IS NULL) OR (state IN ('published','withdrawn') AND published_at IS NOT NULL));
CREATE TABLE public.development_observation_audit(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),observation_id uuid NOT NULL REFERENCES public.student_development_observations(id),tenant_id uuid NOT NULL,school_id uuid NOT NULL,actor_user_id uuid NOT NULL,action text NOT NULL CHECK(action IN ('correct','withdraw')),previous_revision integer NOT NULL,new_revision integer NOT NULL,previous_score integer NOT NULL,new_score integer NOT NULL,previous_evidence text NOT NULL,new_evidence text NOT NULL,reason text NOT NULL CHECK(length(btrim(reason))>=8),created_at timestamptz NOT NULL DEFAULT now());
ALTER TABLE public.development_observation_audit ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.development_observation_audit FORCE ROW LEVEL SECURITY;
REVOKE ALL ON public.development_observation_audit FROM PUBLIC,anon,authenticated;
CREATE FUNCTION app.g085_manage_observation(p_observation uuid,p_revision integer,p_action text,p_score integer,p_evidence text,p_reason text)
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid:=app.g05_actor(); oldrow public.student_development_observations%ROWTYPE; nextscore integer; nextevidence text; nextstate text;
BEGIN
 SELECT * INTO oldrow FROM public.student_development_observations WHERE id=p_observation FOR UPDATE;
 IF NOT FOUND OR NOT EXISTS(SELECT 1 FROM public.memberships m JOIN public.teacher_class_assignments a ON a.teacher_user_id=m.user_id AND a.tenant_id=m.tenant_id AND a.school_id=m.school_id AND a.class_id=oldrow.class_id AND a.status='active' JOIN public.class_student_enrollments e ON e.class_id=a.class_id AND e.student_id=oldrow.student_id AND e.tenant_id=a.tenant_id AND e.school_id=a.school_id AND e.status='active' WHERE m.user_id=actor AND m.tenant_id=oldrow.tenant_id AND m.school_id=oldrow.school_id AND m.role_code='teacher' AND m.status='active' AND oldrow.teacher_user_id=actor)
 THEN RAISE EXCEPTION 'Observation unavailable' USING ERRCODE='42501'; END IF;
 IF oldrow.revision<>p_revision THEN RAISE EXCEPTION 'Stale observation' USING ERRCODE='40001'; END IF;
 IF p_action NOT IN ('correct','withdraw') OR oldrow.state='withdrawn' THEN RAISE EXCEPTION 'Invalid transition' USING ERRCODE='22023'; END IF;
 IF length(btrim(coalesce(p_reason,'')))<8 THEN RAISE EXCEPTION 'Reason required' USING ERRCODE='22023'; END IF;
 nextscore:=CASE WHEN p_action='correct' THEN p_score ELSE oldrow.score END;
 nextevidence:=CASE WHEN p_action='correct' THEN btrim(coalesce(p_evidence,'')) ELSE oldrow.evidence END;
 nextstate:=CASE WHEN p_action='withdraw' THEN 'withdrawn' ELSE oldrow.state END;
 IF nextscore NOT BETWEEN 1 AND 4 OR length(nextevidence)<8 THEN RAISE EXCEPTION 'Invalid observation data' USING ERRCODE='22023'; END IF;
 UPDATE public.student_development_observations SET score=nextscore,evidence=nextevidence,state=nextstate,revision=revision+1 WHERE id=p_observation;
 INSERT INTO public.development_observation_audit(observation_id,tenant_id,school_id,actor_user_id,action,previous_revision,new_revision,previous_score,new_score,previous_evidence,new_evidence,reason)
 VALUES(p_observation,oldrow.tenant_id,oldrow.school_id,actor,p_action,oldrow.revision,oldrow.revision+1,oldrow.score,nextscore,oldrow.evidence,nextevidence,btrim(p_reason));
 RETURN oldrow.revision+1;
END $$;
CREATE FUNCTION app.g085_teacher_observations(p_school uuid)
RETURNS TABLE(observation_id uuid,student_name text,indicator_label text,domain text,score integer,evidence text,state text,revision integer)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid:=app.g05_actor();
BEGIN
 RETURN QUERY SELECT o.id,s.display_name,o.indicator_label,o.domain,o.score,o.evidence,o.state,o.revision FROM public.student_development_observations o JOIN public.students s ON s.id=o.student_id AND s.tenant_id=o.tenant_id AND s.school_id=o.school_id
 JOIN public.memberships m ON m.tenant_id=o.tenant_id AND m.school_id=o.school_id AND m.user_id=actor AND m.role_code='teacher' AND m.status='active'
 JOIN public.teacher_class_assignments a ON a.tenant_id=o.tenant_id AND a.school_id=o.school_id AND a.class_id=o.class_id AND a.teacher_user_id=actor AND a.status='active'
 WHERE o.school_id=p_school AND o.teacher_user_id=actor ORDER BY o.created_at DESC LIMIT 100;
END $$;
CREATE FUNCTION public.kabarkelas_teacher_observations(p_school uuid)
RETURNS TABLE(observation_id uuid,student_name text,indicator_label text,domain text,score integer,evidence text,state text,revision integer) LANGUAGE sql STABLE SECURITY INVOKER SET search_path='' AS $$ SELECT * FROM app.g085_teacher_observations(p_school) $$;
CREATE FUNCTION public.kabarkelas_update_development_observation(p_observation uuid,p_revision integer,p_action text,p_score integer,p_evidence text,p_reason text)
RETURNS integer LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT app.g085_manage_observation(p_observation,p_revision,p_action,p_score,p_evidence,p_reason) $$;
REVOKE ALL ON FUNCTION app.g085_manage_observation(uuid,integer,text,integer,text,text),app.g085_teacher_observations(uuid),public.kabarkelas_teacher_observations(uuid),public.kabarkelas_update_development_observation(uuid,integer,text,integer,text,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION app.g085_manage_observation(uuid,integer,text,integer,text,text),app.g085_teacher_observations(uuid),public.kabarkelas_teacher_observations(uuid),public.kabarkelas_update_development_observation(uuid,integer,text,integer,text,text) TO authenticated;
COMMIT;