-- P0 security hardening: additive migration after G0.8.5; do not rewrite applied history.
-- Source: G0.8.5 PR #10, follow-up audit. Apply only after explicit database approval.
BEGIN;
CREATE OR REPLACE FUNCTION app.g085_manage_observation(p_observation uuid,p_revision integer,p_action text,p_score integer,p_evidence text,p_reason text)
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid:=app.g05_actor(); oldrow public.student_development_observations%ROWTYPE; nextscore integer; nextevidence text; nextstate text;
BEGIN
 SELECT * INTO oldrow FROM public.student_development_observations WHERE id=p_observation FOR UPDATE;
 IF NOT FOUND OR NOT EXISTS(SELECT 1 FROM public.memberships m JOIN public.teacher_class_assignments a ON a.teacher_user_id=m.user_id AND a.tenant_id=m.tenant_id AND a.school_id=m.school_id AND a.class_id=oldrow.class_id AND a.status='active' JOIN public.class_student_enrollments e ON e.class_id=a.class_id AND e.student_id=oldrow.student_id AND e.tenant_id=a.tenant_id AND e.school_id=a.school_id AND e.status='active' WHERE m.user_id=actor AND m.tenant_id=oldrow.tenant_id AND m.school_id=oldrow.school_id AND m.role_code='teacher' AND m.status='active' AND oldrow.teacher_user_id=actor AND e.status='active' AND EXISTS (SELECT 1 FROM public.students s JOIN public.schools sc ON sc.id=s.school_id AND sc.tenant_id=s.tenant_id JOIN public.tenants t ON t.id=sc.tenant_id WHERE s.id=oldrow.student_id AND s.school_id=oldrow.school_id AND s.tenant_id=oldrow.tenant_id AND s.status='active' AND sc.status='active' AND t.status='active'))
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
CREATE OR REPLACE FUNCTION app.g085_teacher_observations(p_school uuid)
RETURNS TABLE(observation_id uuid,student_name text,indicator_label text,domain text,score integer,evidence text,state text,revision integer)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid:=app.g05_actor();
BEGIN
 RETURN QUERY SELECT o.id,s.display_name,o.indicator_label,o.domain,o.score,o.evidence,o.state,o.revision FROM public.student_development_observations o JOIN public.students s ON s.id=o.student_id AND s.tenant_id=o.tenant_id AND s.school_id=o.school_id
 JOIN public.memberships m ON m.tenant_id=o.tenant_id AND m.school_id=o.school_id AND m.user_id=actor AND m.role_code='teacher' AND m.status='active'
 JOIN public.teacher_class_assignments a ON a.tenant_id=o.tenant_id AND a.school_id=o.school_id AND a.class_id=o.class_id AND a.teacher_user_id=actor AND a.status='active'
 JOIN public.class_student_enrollments e ON e.tenant_id=o.tenant_id AND e.school_id=o.school_id AND e.class_id=o.class_id AND e.student_id=o.student_id AND e.status='active' JOIN public.schools sc ON sc.id=o.school_id AND sc.tenant_id=o.tenant_id AND sc.status='active' JOIN public.tenants t ON t.id=o.tenant_id AND t.status='active' WHERE o.school_id=p_school AND o.teacher_user_id=actor AND s.status='active' ORDER BY o.created_at DESC LIMIT 100;
END $$;
-- Protect correction/withdrawal history from later modification, including accidental owner writes.
CREATE FUNCTION app.g085_reject_audit_mutation()
RETURNS trigger LANGUAGE plpgsql SET search_path='' AS $$
BEGIN
 RAISE EXCEPTION 'Observation audit is append-only' USING ERRCODE='42501';
END $$;
CREATE TRIGGER g085_audit_append_only
 BEFORE UPDATE OR DELETE OR TRUNCATE ON public.development_observation_audit
 FOR EACH STATEMENT EXECUTE FUNCTION app.g085_reject_audit_mutation();
REVOKE ALL ON FUNCTION app.g085_reject_audit_mutation() FROM PUBLIC,anon,authenticated;
COMMIT;
