BEGIN;
CREATE TABLE public.development_rubric_indicators(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),tenant_id uuid NOT NULL,school_id uuid NOT NULL,
 domain text NOT NULL CHECK(domain IN ('academic_competency','character')),
 indicator_code text NOT NULL CHECK(length(indicator_code) BETWEEN 2 AND 50),
 indicator_label text NOT NULL CHECK(length(indicator_label) BETWEEN 3 AND 120),
 status text NOT NULL DEFAULT 'approved' CHECK(status IN ('approved','retired')),
 approved_by uuid NOT NULL REFERENCES public.users(id),
 approved_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(tenant_id,school_id,domain,indicator_code)
);
ALTER TABLE public.development_rubric_indicators ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.development_rubric_indicators FORCE ROW LEVEL SECURITY;
REVOKE ALL ON public.development_rubric_indicators FROM PUBLIC,anon,authenticated;
CREATE FUNCTION app.g084_approve_indicator(p_school uuid,p_domain text,p_code text,p_label text)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid:=app.g05_actor();tenant uuid;rid uuid;
BEGIN
 SELECT s.tenant_id INTO tenant FROM public.schools s JOIN public.tenants t ON t.id=s.tenant_id AND t.status='active' WHERE s.id=p_school AND s.status='active';
 IF tenant IS NULL OR NOT EXISTS(SELECT 1 FROM public.memberships m WHERE m.user_id=actor AND m.school_id=p_school AND m.tenant_id=tenant AND m.role_code='principal' AND m.status='active') THEN RAISE EXCEPTION 'Principal required' USING ERRCODE='42501'; END IF;
 INSERT INTO public.development_rubric_indicators(tenant_id,school_id,domain,indicator_code,indicator_label,approved_by)
 VALUES(tenant,p_school,p_domain,btrim(p_code),btrim(p_label),actor)
 ON CONFLICT(tenant_id,school_id,domain,indicator_code) DO UPDATE SET indicator_label=EXCLUDED.indicator_label,status='approved',approved_by=actor,approved_at=now() RETURNING id INTO rid;
 RETURN rid;
END $$;
CREATE FUNCTION app.g084_indicators(p_school uuid)
RETURNS TABLE(domain text,indicator_code text,indicator_label text)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid:=app.g05_actor();
BEGIN
 IF NOT EXISTS(SELECT 1 FROM public.memberships m JOIN public.schools s ON s.id=m.school_id AND s.tenant_id=m.tenant_id AND s.status='active' JOIN public.tenants t ON t.id=s.tenant_id AND t.status='active' WHERE m.user_id=actor AND m.school_id=p_school AND m.role_code IN ('teacher','principal') AND m.status='active') THEN RAISE EXCEPTION 'Access denied' USING ERRCODE='42501'; END IF;
 RETURN QUERY SELECT r.domain,r.indicator_code,r.indicator_label FROM public.development_rubric_indicators r WHERE r.school_id=p_school AND r.status='approved' ORDER BY r.domain,r.indicator_code;
END $$;
CREATE FUNCTION public.kabarkelas_approve_development_indicator(p_school uuid,p_domain text,p_code text,p_label text)
RETURNS uuid LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT app.g084_approve_indicator(p_school,p_domain,p_code,p_label) $$;
CREATE FUNCTION public.kabarkelas_development_indicators(p_school uuid)
RETURNS TABLE(domain text,indicator_code text,indicator_label text)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path='' AS $$ SELECT * FROM app.g084_indicators(p_school) $$;
REVOKE ALL ON FUNCTION app.g084_approve_indicator(uuid,text,text,text),app.g084_indicators(uuid),public.kabarkelas_approve_development_indicator(uuid,text,text,text),public.kabarkelas_development_indicators(uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION app.g084_approve_indicator(uuid,text,text,text),app.g084_indicators(uuid),public.kabarkelas_approve_development_indicator(uuid,text,text,text),public.kabarkelas_development_indicators(uuid) TO authenticated;
COMMIT;