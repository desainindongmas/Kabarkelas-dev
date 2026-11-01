BEGIN;
ALTER TABLE public.assessment_policies ADD COLUMN created_by uuid REFERENCES public.users(id);
CREATE FUNCTION app.g051_policy_for_school(p_school uuid)
RETURNS TABLE(policy_version integer, mode text, cap_percent numeric, parent_visibility text)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE v_actor uuid:=app.g05_actor();
BEGIN
 IF NOT EXISTS(SELECT 1 FROM public.memberships m WHERE m.user_id=v_actor AND m.school_id=p_school AND m.status='active' AND m.role_code IN ('teacher','principal')) THEN RAISE EXCEPTION 'School unavailable' USING ERRCODE='42501'; END IF;
 RETURN QUERY
 SELECT p.version,p.mode,p.cap_percent,p.parent_visibility FROM public.assessment_policies p
 WHERE p.school_id=p_school AND p.is_active ORDER BY p.version DESC LIMIT 1;
 IF NOT FOUND THEN RETURN QUERY SELECT 0,'best_score'::text,NULL::numeric,'after_release'::text; END IF;
END $$;
CREATE FUNCTION app.g051_set_school_policy(p_school uuid,p_mode text,p_cap numeric,p_visibility text)
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v_actor uuid:=app.g05_actor(); v_school public.schools%ROWTYPE; v_version integer;
BEGIN
 SELECT * INTO v_school FROM public.schools WHERE id=p_school AND status='active' FOR UPDATE;
 IF NOT FOUND OR NOT EXISTS(SELECT 1 FROM public.tenants t WHERE t.id=v_school.tenant_id AND t.status='active') THEN RAISE EXCEPTION 'School unavailable' USING ERRCODE='42501'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.memberships m WHERE m.user_id=v_actor AND m.school_id=p_school AND m.tenant_id=v_school.tenant_id AND m.status='active' AND m.role_code='principal') THEN RAISE EXCEPTION 'Principal required' USING ERRCODE='42501'; END IF;
 IF p_mode IS NULL OR p_mode NOT IN ('best_score','latest_score','best_capped')
 OR p_visibility IS NULL OR p_visibility NOT IN ('after_release','report_only')
 OR (p_mode='best_capped' AND (p_cap IS NULL OR p_cap<0 OR p_cap>100)) THEN
 RAISE EXCEPTION 'Invalid assessment policy' USING ERRCODE='22023'; END IF;
 SELECT coalesce(max(version),0)+1 INTO v_version FROM public.assessment_policies WHERE school_id=p_school AND tenant_id=v_school.tenant_id;
 UPDATE public.assessment_policies SET is_active=false WHERE school_id=p_school AND tenant_id=v_school.tenant_id AND is_active;
 INSERT INTO public.assessment_policies(tenant_id,school_id,version,mode,cap_percent,parent_visibility,is_active,created_by)
 VALUES(v_school.tenant_id,p_school,v_version,p_mode,CASE WHEN p_mode='best_capped' THEN p_cap ELSE NULL END,p_visibility,true,v_actor);
 RETURN v_version;
END $$;
CREATE FUNCTION public.kabarkelas_school_assessment_policy(p_school uuid)
RETURNS TABLE(policy_version integer,mode text,cap_percent numeric,parent_visibility text)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path='' AS $$ SELECT * FROM app.g051_policy_for_school(p_school) $$;
CREATE FUNCTION public.kabarkelas_set_school_assessment_policy(p_school uuid,p_mode text,p_cap numeric,p_visibility text)
RETURNS integer LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT app.g051_set_school_policy(p_school,p_mode,p_cap,p_visibility) $$;
REVOKE ALL ON FUNCTION app.g051_policy_for_school(uuid),app.g051_set_school_policy(uuid,text,numeric,text),public.kabarkelas_school_assessment_policy(uuid),public.kabarkelas_set_school_assessment_policy(uuid,text,numeric,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION app.g051_policy_for_school(uuid),app.g051_set_school_policy(uuid,text,numeric,text),public.kabarkelas_school_assessment_policy(uuid),public.kabarkelas_set_school_assessment_policy(uuid,text,numeric,text) TO authenticated;
COMMIT;
