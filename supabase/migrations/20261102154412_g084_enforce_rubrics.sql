BEGIN;
CREATE OR REPLACE FUNCTION app.g083_observe(p_school uuid,p_student uuid,p_class uuid,p_domain text,p_code text,p_label text,p_score int,p_evidence text,p_publish boolean DEFAULT false)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid:=app.g05_actor(); tenant uuid; result uuid; approved_label text;
BEGIN
 SELECT s.tenant_id INTO tenant FROM public.students s JOIN public.schools sc ON sc.id=s.school_id AND sc.tenant_id=s.tenant_id AND sc.status='active'
 JOIN public.tenants t ON t.id=sc.tenant_id AND t.status='active'
 WHERE s.id=p_student AND s.school_id=p_school AND s.status='active';
 IF tenant IS NULL OR NOT EXISTS(SELECT 1 FROM public.memberships m JOIN public.teacher_class_assignments a ON a.teacher_user_id=m.user_id AND a.tenant_id=m.tenant_id AND a.school_id=m.school_id AND a.status='active' AND a.class_id=p_class
 JOIN public.class_student_enrollments e ON e.class_id=a.class_id AND e.student_id=p_student AND e.tenant_id=a.tenant_id AND e.school_id=a.school_id AND e.status='active'
 WHERE m.user_id=actor AND m.tenant_id=tenant AND m.school_id=p_school AND m.role_code='teacher' AND m.status='active')
 THEN RAISE EXCEPTION 'Student unavailable' USING ERRCODE='42501'; END IF;
 SELECT r.indicator_label INTO approved_label FROM public.development_rubric_indicators r
 WHERE r.tenant_id=tenant AND r.school_id=p_school AND r.domain=p_domain AND r.indicator_code=btrim(p_code) AND r.status='approved';
 IF approved_label IS NULL OR approved_label<>btrim(coalesce(p_label,'')) THEN RAISE EXCEPTION 'Approved school rubric required' USING ERRCODE='22023'; END IF;
 INSERT INTO public.student_development_observations(tenant_id,school_id,student_id,class_id,teacher_user_id,domain,indicator_code,indicator_label,score,evidence,state,published_at)
 VALUES(tenant,p_school,p_student,p_class,actor,p_domain,btrim(p_code),approved_label,p_score,btrim(p_evidence),CASE WHEN p_publish THEN 'published' ELSE 'draft' END,CASE WHEN p_publish THEN now() ELSE NULL END)
 RETURNING id INTO result;RETURN result;
END $$;
COMMIT;