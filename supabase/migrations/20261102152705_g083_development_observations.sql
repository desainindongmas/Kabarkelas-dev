BEGIN;
CREATE TABLE public.student_development_observations(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), tenant_id uuid NOT NULL, school_id uuid NOT NULL,
 student_id uuid NOT NULL, class_id uuid NOT NULL, teacher_user_id uuid NOT NULL,
 domain text NOT NULL CHECK(domain IN ('academic_competency','character')),
 indicator_code text NOT NULL CHECK(length(indicator_code) BETWEEN 2 AND 50),
 indicator_label text NOT NULL CHECK(length(indicator_label) BETWEEN 3 AND 120),
 score integer NOT NULL CHECK(score BETWEEN 1 AND 4),
 evidence text NOT NULL CHECK(length(btrim(evidence)) BETWEEN 8 AND 1000),
 observed_on date NOT NULL DEFAULT CURRENT_DATE,
 state text NOT NULL DEFAULT 'draft' CHECK(state IN ('draft','published')),
 published_at timestamptz,
 created_at timestamptz NOT NULL DEFAULT now(),
 FOREIGN KEY(tenant_id,school_id,student_id) REFERENCES public.students(tenant_id,school_id,id),
 FOREIGN KEY(tenant_id,school_id,class_id) REFERENCES public.school_classes(tenant_id,school_id,id),
 CHECK((state='draft' AND published_at IS NULL) OR (state='published' AND published_at IS NOT NULL))
);
ALTER TABLE public.student_development_observations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.student_development_observations FORCE ROW LEVEL SECURITY;
REVOKE ALL ON public.student_development_observations FROM PUBLIC,anon,authenticated;
CREATE FUNCTION app.g083_observe(p_school uuid,p_student uuid,p_class uuid,p_domain text,p_code text,p_label text,p_score int,p_evidence text,p_publish boolean DEFAULT false)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid:=app.g05_actor(); tenant uuid; result uuid;
BEGIN
 SELECT s.tenant_id INTO tenant FROM public.students s JOIN public.schools sc ON sc.id=s.school_id AND sc.tenant_id=s.tenant_id AND sc.status='active'
 JOIN public.tenants t ON t.id=sc.tenant_id AND t.status='active'
 WHERE s.id=p_student AND s.school_id=p_school AND s.status='active';
 IF tenant IS NULL OR NOT EXISTS(SELECT 1 FROM public.memberships m JOIN public.teacher_class_assignments a ON a.teacher_user_id=m.user_id AND a.tenant_id=m.tenant_id AND a.school_id=m.school_id AND a.status='active' AND a.class_id=p_class
 JOIN public.class_student_enrollments e ON e.class_id=a.class_id AND e.student_id=p_student AND e.tenant_id=a.tenant_id AND e.school_id=a.school_id AND e.status='active'
 WHERE m.user_id=actor AND m.tenant_id=tenant AND m.school_id=p_school AND m.role_code='teacher' AND m.status='active')
 THEN RAISE EXCEPTION 'Student unavailable' USING ERRCODE='42501'; END IF;
 INSERT INTO public.student_development_observations(tenant_id,school_id,student_id,class_id,teacher_user_id,domain,indicator_code,indicator_label,score,evidence,state,published_at)
 VALUES(tenant,p_school,p_student,p_class,actor,p_domain,btrim(p_code),btrim(p_label),p_score,btrim(p_evidence),CASE WHEN p_publish THEN 'published' ELSE 'draft' END,CASE WHEN p_publish THEN now() ELSE NULL END)
 RETURNING id INTO result;RETURN result;
END $$;
CREATE FUNCTION app.g083_guardian_radar(p_school uuid)
RETURNS TABLE(student_name text,domain text,indicator_code text,indicator_label text,average_score numeric,observation_count integer)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid:=app.g05_actor();
BEGIN
 IF NOT EXISTS(SELECT 1 FROM public.memberships m JOIN public.schools s ON s.id=m.school_id AND s.tenant_id=m.tenant_id AND s.status='active' JOIN public.tenants t ON t.id=m.tenant_id AND t.status='active' WHERE m.user_id=actor AND m.school_id=p_school AND m.role_code='guardian' AND m.status='active') THEN RAISE EXCEPTION 'School unavailable' USING ERRCODE='42501'; END IF;
 RETURN QUERY SELECT s.display_name,o.domain,o.indicator_code,o.indicator_label,round(avg(o.score)::numeric,2),count(*)::integer
 FROM public.student_development_observations o JOIN public.students s ON s.id=o.student_id AND s.tenant_id=o.tenant_id AND s.school_id=o.school_id AND s.status='active'
 JOIN public.guardian_student_links l ON l.student_id=s.id AND l.tenant_id=s.tenant_id AND l.school_id=s.school_id AND l.guardian_user_id=actor AND l.verification_status='verified'
 WHERE o.school_id=p_school AND o.state='published' GROUP BY s.id,s.display_name,o.domain,o.indicator_code,o.indicator_label ORDER BY s.display_name,o.domain,o.indicator_code;
END $$;
CREATE FUNCTION public.kabarkelas_teacher_development_observe(p_school uuid,p_student uuid,p_class uuid,p_domain text,p_code text,p_label text,p_score int,p_evidence text,p_publish boolean DEFAULT false)
RETURNS uuid LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT app.g083_observe(p_school,p_student,p_class,p_domain,p_code,p_label,p_score,p_evidence,p_publish) $$;
CREATE FUNCTION public.kabarkelas_guardian_development_radar(p_school uuid)
RETURNS TABLE(student_name text,domain text,indicator_code text,indicator_label text,average_score numeric,observation_count integer)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path='' AS $$ SELECT * FROM app.g083_guardian_radar(p_school) $$;
REVOKE ALL ON FUNCTION app.g083_observe(uuid,uuid,uuid,text,text,text,int,text,boolean),app.g083_guardian_radar(uuid),public.kabarkelas_teacher_development_observe(uuid,uuid,uuid,text,text,text,int,text,boolean),public.kabarkelas_guardian_development_radar(uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION app.g083_observe(uuid,uuid,uuid,text,text,text,int,text,boolean),app.g083_guardian_radar(uuid),public.kabarkelas_teacher_development_observe(uuid,uuid,uuid,text,text,text,int,text,boolean),public.kabarkelas_guardian_development_radar(uuid) TO authenticated;
COMMIT;