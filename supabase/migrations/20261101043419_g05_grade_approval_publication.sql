-- G0.5: Auth identity + live assignments; no caller-supplied actor or tenant.
BEGIN;
ALTER TABLE public.student_grades
  ADD COLUMN submitted_by uuid REFERENCES public.users(id),
  ADD COLUMN submitted_at timestamptz,
  ADD COLUMN approved_by uuid REFERENCES public.users(id),
  ADD COLUMN approved_at timestamptz,
  ADD COLUMN published_by uuid REFERENCES public.users(id),
  ADD CONSTRAINT grade_distinct_approver CHECK (approved_by IS NULL OR approved_by <> submitted_by),
  ADD CONSTRAINT grade_workflow_provenance CHECK (
    (status = 'draft' AND submitted_by IS NULL AND submitted_at IS NULL AND approved_by IS NULL AND approved_at IS NULL AND published_by IS NULL)
    OR (status = 'submitted' AND submitted_by IS NOT NULL AND submitted_at IS NOT NULL AND approved_by IS NULL AND approved_at IS NULL AND published_by IS NULL)
    OR (status = 'approved' AND submitted_by IS NOT NULL AND submitted_at IS NOT NULL AND approved_by IS NOT NULL AND approved_at IS NOT NULL AND published_by IS NULL)
    OR (status = 'published' AND submitted_by IS NOT NULL AND submitted_at IS NOT NULL AND approved_by IS NOT NULL AND approved_at IS NOT NULL AND published_by IS NOT NULL)
  );
ALTER TABLE public.academic_workflow_events ADD COLUMN actor_auth_subject uuid;
CREATE INDEX g05_grade_submitter_idx ON public.student_grades(submitted_by);
CREATE INDEX g05_grade_approver_idx ON public.student_grades(approved_by);
CREATE INDEX g05_grade_publisher_idx ON public.student_grades(published_by);
CREATE INDEX g05_grade_student_idx ON public.student_grades(tenant_id,school_id,student_id);
CREATE INDEX g05_event_actor_idx ON public.academic_workflow_events(actor_user_id);
CREATE INDEX g05_snapshot_publisher_idx ON public.academic_publication_snapshots(published_by);

-- Internal helpers are not exposed by PostgREST and are not callable by clients.
CREATE FUNCTION app.g05_actor() RETURNS uuid LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = '' AS $$
DECLARE v_user uuid;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required' USING ERRCODE='28000'; END IF;
  SELECT id INTO v_user FROM public.users WHERE auth_subject=auth.uid()::text;
  IF v_user IS NULL THEN RAISE EXCEPTION 'Active identity required' USING ERRCODE='42501'; END IF;
  RETURN v_user;
END $$;

CREATE FUNCTION app.g05_access(p_grade uuid, p_user uuid)
RETURNS TABLE(teacher boolean, principal boolean, guardian boolean)
LANGUAGE sql STABLE SET search_path = '' AS $$
SELECT
  EXISTS(SELECT 1 FROM public.memberships m WHERE m.user_id=p_user AND m.tenant_id=g.tenant_id AND m.school_id=g.school_id AND m.role_code='teacher' AND m.status='active')
  AND EXISTS(SELECT 1 FROM public.teacher_class_assignments tc
    JOIN public.class_student_enrollments en ON en.tenant_id=tc.tenant_id AND en.school_id=tc.school_id AND en.class_id=tc.class_id
    WHERE tc.tenant_id=g.tenant_id AND tc.school_id=g.school_id AND tc.class_id=a.class_id
      AND tc.teacher_user_id=p_user AND tc.status='active' AND en.student_id=g.student_id AND en.status='active'
      AND en.started_at<=statement_timestamp() AND (en.ended_at IS NULL OR en.ended_at>statement_timestamp())),
  EXISTS(SELECT 1 FROM public.memberships m WHERE m.user_id=p_user AND m.tenant_id=g.tenant_id AND m.school_id=g.school_id AND m.role_code='principal' AND m.status='active'),
  EXISTS(SELECT 1 FROM public.memberships m WHERE m.user_id=p_user AND m.tenant_id=g.tenant_id AND m.school_id=g.school_id AND m.role_code='guardian' AND m.status='active')
  AND EXISTS(SELECT 1 FROM public.guardian_student_links l WHERE l.tenant_id=g.tenant_id AND l.school_id=g.school_id AND l.student_id=g.student_id AND l.guardian_user_id=p_user AND l.verification_status='verified')
FROM public.student_grades g
JOIN public.assessments a ON (a.tenant_id,a.school_id,a.id)=(g.tenant_id,g.school_id,g.assessment_id)
JOIN public.students s ON (s.tenant_id,s.school_id,s.id)=(g.tenant_id,g.school_id,g.student_id) AND s.status='active'
JOIN public.schools sch ON (sch.tenant_id,sch.id)=(g.tenant_id,g.school_id) AND sch.status='active'
JOIN public.tenants t ON t.id=g.tenant_id AND t.status='active'
WHERE g.id=p_grade;
$$;

CREATE FUNCTION app.g05_freeze_grade() RETURNS trigger LANGUAGE plpgsql SET search_path = '' AS $$
BEGIN
  IF OLD.status='published' THEN RAISE EXCEPTION 'Published grades are immutable' USING ERRCODE='55000'; END IF;
  IF OLD.status<>'draft' AND (TG_OP='DELETE' OR
    (NEW.tenant_id,NEW.school_id,NEW.student_id,NEW.assessment_id,NEW.score,NEW.submitted_by,NEW.submitted_at)
      IS DISTINCT FROM (OLD.tenant_id,OLD.school_id,OLD.student_id,OLD.assessment_id,OLD.score,OLD.submitted_by,OLD.submitted_at)) THEN
    RAISE EXCEPTION 'Submitted grade content is frozen' USING ERRCODE='55000';
  END IF;
  IF TG_OP='DELETE' THEN RETURN OLD; END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER g05_freeze_grade BEFORE UPDATE OR DELETE ON public.student_grades
FOR EACH ROW EXECUTE FUNCTION app.g05_freeze_grade();
CREATE TRIGGER g05_snapshot_no_truncate BEFORE TRUNCATE ON public.academic_publication_snapshots
FOR EACH STATEMENT EXECUTE FUNCTION app.g03e_block_snapshot_mutation();
CREATE TRIGGER g05_events_no_truncate BEFORE TRUNCATE ON public.academic_workflow_events
FOR EACH STATEMENT EXECUTE FUNCTION app.g03e_block_snapshot_mutation();
CREATE TRIGGER g05_grades_no_truncate BEFORE TRUNCATE ON public.student_grades
FOR EACH STATEMENT EXECUTE FUNCTION app.g03e_block_snapshot_mutation();

CREATE FUNCTION app.g05_transition(p_grade_id uuid,p_action text,p_expected_revision integer)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_user uuid := app.g05_actor();
  g public.student_grades%ROWTYPE;
  a public.assessments%ROWTYPE;
  rights record;
  v_next text;
  v_at timestamptz := clock_timestamp();
  v_payload jsonb;
  v_snapshot uuid;
  v_request uuid := gen_random_uuid();
BEGIN
  IF p_action IS NULL OR p_action NOT IN ('submit','approve','publish') OR p_expected_revision IS NULL THEN
    RAISE EXCEPTION 'Invalid transition request' USING ERRCODE='22023';
  END IF;
  SELECT * INTO g FROM public.student_grades WHERE id=p_grade_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Grade unavailable' USING ERRCODE='42501'; END IF;
  -- Hold authorization records until commit: revocation and transitions serialize.
  PERFORM 1 FROM public.tenants WHERE id=g.tenant_id FOR SHARE;
  PERFORM 1 FROM public.schools WHERE id=g.school_id AND tenant_id=g.tenant_id FOR SHARE;
  PERFORM 1 FROM public.users WHERE id=v_user FOR SHARE;
  PERFORM 1 FROM public.memberships WHERE user_id=v_user AND tenant_id=g.tenant_id AND school_id=g.school_id FOR SHARE;
  SELECT * INTO a FROM public.assessments WHERE id=g.assessment_id AND tenant_id=g.tenant_id AND school_id=g.school_id FOR SHARE;
  PERFORM 1 FROM public.students WHERE id=g.student_id AND tenant_id=g.tenant_id AND school_id=g.school_id FOR SHARE;
  PERFORM 1 FROM public.teacher_class_assignments WHERE teacher_user_id=v_user AND tenant_id=g.tenant_id AND school_id=g.school_id AND class_id=a.class_id FOR SHARE;
  PERFORM 1 FROM public.class_student_enrollments WHERE student_id=g.student_id AND tenant_id=g.tenant_id AND school_id=g.school_id AND class_id=a.class_id FOR SHARE;
  IF app.g05_actor()<>v_user THEN RAISE EXCEPTION 'Identity changed' USING ERRCODE='42501'; END IF;
  SELECT * INTO rights FROM app.g05_access(g.id,v_user);
  IF NOT FOUND OR (p_action='submit' AND NOT rights.teacher) OR (p_action IN ('approve','publish') AND NOT rights.principal) THEN
    RAISE EXCEPTION 'Grade unavailable' USING ERRCODE='42501';
  END IF;
  IF p_action IN ('approve','publish') AND g.submitted_by=v_user THEN
    RAISE EXCEPTION 'Self approval or publication forbidden' USING ERRCODE='42501';
  END IF;
  IF g.revision<>p_expected_revision THEN RAISE EXCEPTION 'Stale grade; reload' USING ERRCODE='40001'; END IF;
  v_next := CASE WHEN p_action='submit' AND g.status='draft' THEN 'submitted'
                 WHEN p_action='approve' AND g.status='submitted' THEN 'approved'
                 WHEN p_action='publish' AND g.status='approved' THEN 'published' END;
  IF v_next IS NULL THEN RAISE EXCEPTION 'Invalid grade state' USING ERRCODE='55000'; END IF;
  IF g.score IS NULL OR g.score::text='NaN' OR g.score<0 OR g.score>a.max_score THEN
    RAISE EXCEPTION 'Score must be within assessment range' USING ERRCODE='23514';
  END IF;
  UPDATE public.student_grades SET status=v_next,revision=revision+1,updated_at=v_at,
    submitted_by=CASE WHEN p_action='submit' THEN v_user ELSE submitted_by END,
    submitted_at=CASE WHEN p_action='submit' THEN v_at ELSE submitted_at END,
    approved_by=CASE WHEN p_action='approve' THEN v_user ELSE approved_by END,
    approved_at=CASE WHEN p_action='approve' THEN v_at ELSE approved_at END,
    published_by=CASE WHEN p_action='publish' THEN v_user ELSE published_by END,
    published_at=CASE WHEN p_action='publish' THEN v_at ELSE published_at END
  WHERE id=g.id;
  IF p_action='publish' THEN
    SELECT jsonb_build_object('grade_id',g.id,'student_id',g.student_id,'student_name',s.display_name,
      'subject_name',sub.name,'assessment_title',a.title,'score',g.score,'max_score',a.max_score,
      'grade_status','published','revision',g.revision+1,'submitted_by',g.submitted_by,
      'approved_by',g.approved_by,'published_by',v_user,'published_at',v_at)
    INTO v_payload FROM public.students s JOIN public.subjects sub ON sub.id=a.subject_id AND sub.tenant_id=g.tenant_id AND sub.school_id=g.school_id
    WHERE s.id=g.student_id AND s.tenant_id=g.tenant_id AND s.school_id=g.school_id;
    INSERT INTO public.academic_publication_snapshots(tenant_id,school_id,resource_type,resource_id,version,payload,payload_sha256,published_by,published_at)
    VALUES(g.tenant_id,g.school_id,'grade',g.id,g.revision+1,v_payload,encode(sha256(convert_to(v_payload::text,'UTF8')),'hex'),v_user,v_at)
    RETURNING id INTO v_snapshot;
  END IF;
  INSERT INTO public.academic_workflow_events(tenant_id,school_id,resource_type,resource_id,actor_user_id,actor_auth_subject,from_state,to_state,action,request_id,occurred_at)
  VALUES(g.tenant_id,g.school_id,'grade',g.id,v_user,auth.uid(),g.status,v_next,p_action,v_request,v_at);
  RETURN jsonb_build_object('grade_id',g.id,'status',v_next,'revision',g.revision+1,'snapshot_id',v_snapshot,'request_id',v_request);
END $$;

CREATE FUNCTION app.g05_grades(p_school_id uuid)
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
    CASE WHEN g.status='draft' AND rights.teacher THEN ARRAY['submit']
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

-- Public API wrappers use invoker privileges. Only these private entrypoints are granted.
CREATE FUNCTION public.kabarkelas_transition_grade(p_grade_id uuid,p_action text,p_expected_revision integer)
RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path = '' AS $$
  SELECT app.g05_transition(p_grade_id,p_action,p_expected_revision);
$$;
CREATE FUNCTION public.kabarkelas_grade_workflow(p_school_id uuid)
RETURNS TABLE(grade_id uuid,student_name text,subject_name text,assessment_title text,score numeric,grade_status text,revision integer,allowed_actions text[])
LANGUAGE sql STABLE SECURITY INVOKER SET search_path = '' AS $$ SELECT * FROM app.g05_grades(p_school_id); $$;
-- Preserve the existing frontend response shape while making its published read immutable.
CREATE OR REPLACE FUNCTION public.kabarkelas_my_grades(p_school_id uuid)
RETURNS TABLE(student_name text,subject_name text,assessment_title text,score numeric,grade_status text)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path = '' AS $$
  SELECT student_name,subject_name,assessment_title,score,grade_status FROM app.g05_grades(p_school_id);
$$;
REVOKE ALL ON FUNCTION app.g05_actor(),app.g05_access(uuid,uuid),app.g05_freeze_grade(),app.g05_transition(uuid,text,integer),app.g05_grades(uuid) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.kabarkelas_transition_grade(uuid,text,integer),public.kabarkelas_grade_workflow(uuid),public.kabarkelas_my_grades(uuid) FROM PUBLIC,anon,authenticated;
GRANT USAGE ON SCHEMA app TO authenticated;
GRANT EXECUTE ON FUNCTION app.g05_transition(uuid,text,integer),app.g05_grades(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.kabarkelas_transition_grade(uuid,text,integer),public.kabarkelas_grade_workflow(uuid),public.kabarkelas_my_grades(uuid) TO authenticated;
REVOKE ALL ON public.student_grades,public.academic_workflow_events,public.academic_publication_snapshots FROM PUBLIC,anon,authenticated;
COMMIT;
