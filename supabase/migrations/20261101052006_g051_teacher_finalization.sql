-- G0.5.1: teacher finalizes assessment attempts without principal approval.
-- New append-only releases are deliberately independent of legacy G0.5 published grades.
BEGIN;
CREATE TABLE public.assessment_releases (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 tenant_id uuid NOT NULL REFERENCES public.tenants(id),
 school_id uuid NOT NULL REFERENCES public.schools(id),
 grade_id uuid NOT NULL REFERENCES public.student_grades(id),
 version integer NOT NULL CHECK(version>0),
 status text NOT NULL CHECK(status IN ('finalized','released')),
 policy_mode text NOT NULL,
 effective_score numeric NOT NULL CHECK(effective_score>=0 AND effective_score::text<>'NaN'),
 snapshot jsonb NOT NULL,
 payload_sha256 text NOT NULL,
 finalized_by uuid NOT NULL REFERENCES public.users(id),
 finalized_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 released_at timestamptz,
 UNIQUE(grade_id,version),
 CHECK((status='released' AND released_at IS NOT NULL) OR (status='finalized' AND released_at IS NULL))
);
ALTER TABLE public.assessment_releases ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.assessment_releases FORCE ROW LEVEL SECURITY;
REVOKE ALL ON public.assessment_releases FROM PUBLIC,anon,authenticated;
CREATE FUNCTION app.g051_block_release_changes()
RETURNS trigger LANGUAGE plpgsql SET search_path='' AS $$
BEGIN
 RAISE EXCEPTION 'Assessment release history is immutable' USING ERRCODE='55000';
END $$;
CREATE TRIGGER g051_release_no_update BEFORE UPDATE OR DELETE ON public.assessment_releases
 FOR EACH ROW EXECUTE FUNCTION app.g051_block_release_changes();
CREATE TRIGGER g051_release_no_truncate BEFORE TRUNCATE ON public.assessment_releases
 FOR EACH STATEMENT EXECUTE FUNCTION app.g051_block_release_changes();
CREATE FUNCTION app.g051_finalize_assessment(p_grade uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE
 v_actor uuid:=app.g05_actor();
 g public.student_grades%ROWTYPE;
 a public.assessments%ROWTYPE;
 sc record;
 v_visibility text;
 v_score numeric;
 v_mode text;
 v_version integer;
 v_state text;
 v_payload jsonb;
 v_release_id uuid;
 v_time timestamptz:=clock_timestamp();
BEGIN
 SELECT * INTO g FROM public.student_grades WHERE id=p_grade FOR UPDATE;
 IF NOT FOUND OR NOT app.g051_can_manage_draft(p_grade,v_actor) THEN
   RAISE EXCEPTION 'Assessment unavailable' USING ERRCODE='42501';
 END IF;
 SELECT * INTO a FROM public.assessments WHERE id=g.assessment_id AND school_id=g.school_id AND tenant_id=g.tenant_id FOR SHARE;
 SELECT * INTO sc FROM app.g051_attempt_summary(p_grade);
 IF NOT FOUND OR sc.attempt_count<1 OR sc.initial_score IS NULL THEN
   RAISE EXCEPTION 'Initial score required' USING ERRCODE='23514';
 END IF;
 v_score:=sc.effective_score;
 v_mode:=sc.policy_mode;
 SELECT parent_visibility INTO v_visibility FROM public.assessment_policies
 WHERE school_id=g.school_id AND tenant_id=g.tenant_id AND is_active
 ORDER BY version DESC LIMIT 1;
 v_visibility:=COALESCE(v_visibility,'after_release');
 SELECT COALESCE(max(version),0)+1 INTO v_version FROM public.assessment_releases WHERE grade_id=p_grade;
 v_state:=CASE WHEN v_visibility='after_release' THEN 'released' ELSE 'finalized' END;
 v_payload:=jsonb_build_object('student_id',g.student_id,'assessment_id',g.assessment_id,
 'effective_score',v_score,'max_score',a.max_score,'attempt_count',sc.attempt_count,
 'policy_mode',v_mode,'parent_visibility',v_visibility,'version',v_version);
 INSERT INTO public.assessment_releases(tenant_id,school_id,grade_id,version,status,policy_mode,effective_score,snapshot,payload_sha256,finalized_by,finalized_at,released_at)
 VALUES(g.tenant_id,g.school_id,g.id,v_version,v_state,v_mode,v_score,v_payload,
 encode(sha256(convert_to(v_payload::text,'UTF8')),'hex'),v_actor,v_time,
 CASE WHEN v_state='released' THEN v_time ELSE NULL END)
 RETURNING id INTO v_release_id;
 RETURN jsonb_build_object('release_id',v_release_id,'version',v_version,'status',v_state,'effective_score',v_score);
END $$;
CREATE FUNCTION app.g051_parent_releases(p_school uuid)
RETURNS TABLE(student_name text,subject_name text,assessment_title text,score numeric,release_version integer)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
 SELECT s.display_name,sub.name,a.title,r.effective_score,r.version
 FROM public.assessment_releases r
 JOIN public.student_grades g ON g.id=r.grade_id AND g.tenant_id=r.tenant_id AND g.school_id=r.school_id
 JOIN public.students s ON s.id=g.student_id AND s.tenant_id=g.tenant_id AND s.school_id=g.school_id AND s.status='active'
 JOIN public.assessments a ON a.id=g.assessment_id AND a.tenant_id=g.tenant_id AND a.school_id=g.school_id
 JOIN public.subjects sub ON sub.id=a.subject_id AND sub.tenant_id=a.tenant_id AND sub.school_id=a.school_id
 JOIN public.schools school ON school.id=g.school_id AND school.status='active'
 JOIN public.tenants t ON t.id=g.tenant_id AND t.status='active'
 JOIN public.users u ON u.auth_subject=auth.uid()::text
 JOIN public.memberships m ON m.user_id=u.id AND m.tenant_id=g.tenant_id AND m.school_id=g.school_id AND m.role_code='guardian' AND m.status='active'
 JOIN public.guardian_student_links l ON l.guardian_user_id=u.id AND l.tenant_id=g.tenant_id AND l.school_id=g.school_id AND l.student_id=g.student_id AND l.verification_status='verified'
 WHERE r.school_id=p_school AND r.status='released'
 AND r.version=(SELECT max(other.version) FROM public.assessment_releases other WHERE other.grade_id=r.grade_id)
 ORDER BY s.display_name,sub.name,a.title;
$$;
CREATE FUNCTION public.kabarkelas_finalize_assessment(p_grade uuid)
RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$
 SELECT app.g051_finalize_assessment(p_grade);
$$;
CREATE FUNCTION public.kabarkelas_parent_assessments(p_school uuid)
RETURNS TABLE(student_name text,subject_name text,assessment_title text,score numeric,release_version integer)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path='' AS $$
 SELECT * FROM app.g051_parent_releases(p_school);
$$;
REVOKE ALL ON FUNCTION app.g051_block_release_changes(),app.g051_finalize_assessment(uuid),app.g051_parent_releases(uuid),public.kabarkelas_finalize_assessment(uuid),public.kabarkelas_parent_assessments(uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION app.g051_finalize_assessment(uuid),app.g051_parent_releases(uuid),public.kabarkelas_finalize_assessment(uuid),public.kabarkelas_parent_assessments(uuid) TO authenticated;
COMMIT;
