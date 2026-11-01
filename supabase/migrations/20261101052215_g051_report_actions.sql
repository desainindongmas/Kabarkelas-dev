-- G0.5.1 class report approval; no per-grade principal approval.
BEGIN;
CREATE FUNCTION app.g051_create_class_report(p_class uuid,p_period uuid,p_homeroom uuid)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v_actor uuid:=app.g05_actor(); v_cls public.school_classes%ROWTYPE; v_version integer; v_id uuid;
BEGIN
 SELECT * INTO v_cls FROM public.school_classes WHERE id=p_class;
 IF NOT FOUND THEN RAISE EXCEPTION 'Class unavailable' USING ERRCODE='42501'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.schools s JOIN public.tenants t ON t.id=s.tenant_id AND t.status='active' WHERE s.id=v_cls.school_id AND s.status='active') THEN RAISE EXCEPTION 'School unavailable' USING ERRCODE='42501'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.academic_periods p WHERE p.id=p_period AND p.tenant_id=v_cls.tenant_id AND p.school_id=v_cls.school_id) THEN RAISE EXCEPTION 'Period unavailable' USING ERRCODE='42501'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.memberships m WHERE m.user_id=v_actor AND m.tenant_id=v_cls.tenant_id AND m.school_id=v_cls.school_id AND m.role_code='principal' AND m.status='active') THEN RAISE EXCEPTION 'Principal required' USING ERRCODE='42501'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.memberships m JOIN public.teacher_class_assignments a ON a.teacher_user_id=m.user_id AND a.tenant_id=m.tenant_id AND a.school_id=m.school_id AND a.class_id=p_class AND a.status='active' WHERE m.user_id=p_homeroom AND m.tenant_id=v_cls.tenant_id AND m.school_id=v_cls.school_id AND m.role_code='teacher' AND m.status='active') THEN RAISE EXCEPTION 'Homeroom teacher not assigned to class' USING ERRCODE='42501'; END IF;
 IF EXISTS(SELECT 1 FROM public.school_report_reviews r WHERE r.class_id=p_class AND r.period_id=p_period AND r.status<>'released') THEN RAISE EXCEPTION 'Existing report requires completion' USING ERRCODE='55000'; END IF;
 SELECT coalesce(max(version),0)+1 INTO v_version FROM public.school_report_reviews WHERE class_id=p_class AND period_id=p_period;
 INSERT INTO public.school_report_reviews(tenant_id,school_id,class_id,period_id,version,homeroom_user_id)
 VALUES(v_cls.tenant_id,v_cls.school_id,p_class,p_period,v_version,p_homeroom) RETURNING id INTO v_id;
 RETURN v_id;
END $$;
CREATE FUNCTION app.g051_transition_class_report(p_report uuid,p_action text,p_revision integer)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v_actor uuid:=app.g05_actor(); r public.school_report_reviews%ROWTYPE; v_next text; v_teacher boolean; v_principal boolean; v_homeroom boolean; v_time timestamptz:=clock_timestamp(); v_student record; v_payload jsonb; v_signed integer:=0;
BEGIN
 SELECT * INTO r FROM public.school_report_reviews WHERE id=p_report FOR UPDATE;
 IF NOT FOUND OR p_revision IS NULL THEN RAISE EXCEPTION 'Report unavailable' USING ERRCODE='42501'; END IF;
 IF p_revision<>r.revision THEN RAISE EXCEPTION 'Stale report; reload' USING ERRCODE='40001'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.schools s JOIN public.tenants t ON t.id=s.tenant_id WHERE s.id=r.school_id AND s.tenant_id=r.tenant_id AND s.status='active' AND t.status='active') THEN RAISE EXCEPTION 'School unavailable' USING ERRCODE='42501'; END IF;
 SELECT EXISTS(SELECT 1 FROM public.memberships m JOIN public.teacher_class_assignments a ON a.teacher_user_id=m.user_id AND a.tenant_id=m.tenant_id AND a.school_id=m.school_id AND a.class_id=r.class_id AND a.status='active' WHERE m.user_id=v_actor AND m.tenant_id=r.tenant_id AND m.school_id=r.school_id AND m.role_code='teacher' AND m.status='active') INTO v_teacher;
 SELECT EXISTS(SELECT 1 FROM public.memberships m WHERE m.user_id=v_actor AND m.tenant_id=r.tenant_id AND m.school_id=r.school_id AND m.role_code='principal' AND m.status='active') INTO v_principal;
 v_homeroom:=v_teacher AND v_actor=r.homeroom_user_id;
 IF p_action='teacher_finalize' AND r.status='draft' AND v_teacher THEN v_next:='teacher_finalized';
 ELSIF p_action='homeroom_review' AND r.status='teacher_finalized' AND v_homeroom THEN v_next:='homeroom_reviewed';
 ELSIF p_action='principal_sign' AND r.status='homeroom_reviewed' AND v_principal AND v_actor<>r.homeroom_user_id THEN v_next:='principal_signed';
 ELSIF p_action='release' AND r.status='principal_signed' AND (v_homeroom OR v_principal) THEN v_next:='released';
 ELSE RAISE EXCEPTION 'Invalid report transition or access' USING ERRCODE='42501'; END IF;
 IF p_action='teacher_finalize' THEN
   IF NOT EXISTS(SELECT 1 FROM public.student_grades g JOIN public.assessments a ON a.id=g.assessment_id AND a.tenant_id=g.tenant_id AND a.school_id=g.school_id WHERE a.class_id=r.class_id AND a.period_id=r.period_id AND g.school_id=r.school_id) THEN RAISE EXCEPTION 'No grades to review' USING ERRCODE='23514'; END IF;
   IF EXISTS(SELECT 1 FROM public.student_grades g JOIN public.assessments a ON a.id=g.assessment_id AND a.tenant_id=g.tenant_id AND a.school_id=g.school_id WHERE a.class_id=r.class_id AND a.period_id=r.period_id AND g.school_id=r.school_id AND g.status<>'published' AND NOT EXISTS(SELECT 1 FROM public.assessment_releases rel WHERE rel.grade_id=g.id)) THEN RAISE EXCEPTION 'Unfinalized grades remain' USING ERRCODE='23514'; END IF;
 END IF;
 IF p_action='principal_sign' THEN
   FOR v_student IN SELECT s.id,s.display_name FROM public.class_student_enrollments e JOIN public.students s ON s.id=e.student_id AND s.tenant_id=e.tenant_id AND s.school_id=e.school_id WHERE e.class_id=r.class_id AND e.tenant_id=r.tenant_id AND e.school_id=r.school_id AND e.status='active' AND s.status='active' LOOP
     SELECT jsonb_build_object('student_id',v_student.id,'student_name',v_student.display_name,'report_id',r.id,'report_version',r.version,'grades',
       COALESCE((SELECT jsonb_agg(jsonb_build_object('subject',sub.name,'assessment',a.title,'score',COALESCE(rel.effective_score,g.score)) ORDER BY sub.name,a.title)
       FROM public.student_grades g JOIN public.assessments a ON a.id=g.assessment_id AND a.tenant_id=g.tenant_id AND a.school_id=g.school_id
       JOIN public.subjects sub ON sub.id=a.subject_id AND sub.tenant_id=a.tenant_id AND sub.school_id=a.school_id
       LEFT JOIN LATERAL (SELECT x.effective_score FROM public.assessment_releases x WHERE x.grade_id=g.id ORDER BY x.version DESC LIMIT 1) rel ON true
       WHERE a.class_id=r.class_id AND a.period_id=r.period_id AND g.student_id=v_student.id AND (g.status='published' OR rel.effective_score IS NOT NULL)), '[]'::jsonb))
     INTO v_payload;
     INSERT INTO public.school_report_snapshots(tenant_id,school_id,report_id,student_id,version,payload,payload_sha256,signed_by,signed_at)
     VALUES(r.tenant_id,r.school_id,r.id,v_student.id,r.version,v_payload,encode(sha256(convert_to(v_payload::text,'UTF8')),'hex'),v_actor,v_time);
     v_signed:=v_signed+1;
   END LOOP;
   IF v_signed=0 THEN RAISE EXCEPTION 'No active pupils for report' USING ERRCODE='23514'; END IF;
 END IF;
 UPDATE public.school_report_reviews SET status=v_next,revision=revision+1,
 signed_by=CASE WHEN v_next='principal_signed' THEN v_actor ELSE signed_by END,
 signed_at=CASE WHEN v_next='principal_signed' THEN v_time ELSE signed_at END,
 released_at=CASE WHEN v_next='released' THEN v_time ELSE released_at END WHERE id=r.id;
 RETURN jsonb_build_object('report_id',r.id,'status',v_next,'revision',r.revision+1);
END $$;
CREATE FUNCTION public.kabarkelas_create_class_report(p_class uuid,p_period uuid,p_homeroom uuid)
RETURNS uuid LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT app.g051_create_class_report(p_class,p_period,p_homeroom) $$;
CREATE FUNCTION public.kabarkelas_transition_class_report(p_report uuid,p_action text,p_revision integer)
RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT app.g051_transition_class_report(p_report,p_action,p_revision) $$;
REVOKE ALL ON FUNCTION app.g051_create_class_report(uuid,uuid,uuid),app.g051_transition_class_report(uuid,text,integer),public.kabarkelas_create_class_report(uuid,uuid,uuid),public.kabarkelas_transition_class_report(uuid,text,integer) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION app.g051_create_class_report(uuid,uuid,uuid),app.g051_transition_class_report(uuid,text,integer),public.kabarkelas_create_class_report(uuid,uuid,uuid),public.kabarkelas_transition_class_report(uuid,text,integer) TO authenticated;
COMMIT;
