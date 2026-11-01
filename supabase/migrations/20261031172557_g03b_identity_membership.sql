BEGIN;
CREATE INDEX IF NOT EXISTS membership_user_active_idx ON public.memberships(user_id,tenant_id,school_id) WHERE status='active';
CREATE INDEX IF NOT EXISTS membership_tenant_school_idx ON public.memberships(tenant_id,school_id,user_id) WHERE status='active';
CREATE OR REPLACE FUNCTION app.current_user_id() RETURNS uuid LANGUAGE plpgsql STABLE SET search_path = pg_catalog,app AS $$
DECLARE v text; BEGIN v:=current_setting('app.verified_user_id',true); IF v IS NULL OR v='' THEN RETURN NULL; END IF; RETURN v::uuid; EXCEPTION WHEN invalid_text_representation THEN RETURN NULL; END $$;
CREATE OR REPLACE FUNCTION app.has_active_membership(p_tenant uuid,p_school uuid DEFAULT NULL,p_roles text[] DEFAULT NULL) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,app AS $$
 SELECT EXISTS(SELECT 1 FROM public.memberships m WHERE m.user_id=app.current_user_id() AND m.tenant_id=p_tenant AND m.status='active' AND (p_school IS NULL OR m.school_id=p_school) AND (p_roles IS NULL OR m.role_code=ANY(p_roles))) $$;
CREATE POLICY g03b_membership_self_read ON public.memberships FOR SELECT USING(user_id=app.current_user_id() AND status='active');
CREATE POLICY g03b_users_self_read ON public.users FOR SELECT USING(id=app.current_user_id());
CREATE POLICY g03b_tenant_membership_read ON public.tenants FOR SELECT USING(app.has_active_membership(id));
CREATE POLICY g03b_school_membership_read ON public.schools FOR SELECT USING(app.has_active_membership(tenant_id,NULL,ARRAY['foundation_admin','foundation_analyst']) OR app.has_active_membership(tenant_id,id));
REVOKE ALL ON FUNCTION app.current_user_id() FROM PUBLIC;
REVOKE ALL ON FUNCTION app.has_active_membership(uuid,uuid,text[]) FROM PUBLIC;
COMMIT;
