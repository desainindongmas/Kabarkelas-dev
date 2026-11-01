BEGIN;
CREATE OR REPLACE FUNCTION public.kabarkelas_my_context()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path=pg_catalog,public,auth
AS $$
DECLARE v_auth uuid := auth.uid(); v_user uuid; v_result jsonb;
BEGIN
  IF v_auth IS NULL THEN RAISE EXCEPTION 'Authentication required' USING ERRCODE='28000'; END IF;
  SELECT id INTO v_user FROM public.users WHERE auth_subject=v_auth::text;
  IF v_user IS NULL THEN RETURN jsonb_build_object('state','not_onboarded','units','[]'::jsonb); END IF;
  SELECT jsonb_build_object(
    'state',CASE WHEN count(*)=0 THEN 'no_active_membership' ELSE 'active' END,
    'user_id',v_user,
    'units',COALESCE(jsonb_agg(jsonb_build_object(
       'membership_id',m.id,'tenant_id',m.tenant_id,'tenant_name',t.name,
       'school_id',m.school_id,'school_name',s.name,'role',m.role_code
    ) ORDER BY t.name,s.name,m.role_code),'[]'::jsonb))
  INTO v_result
  FROM public.memberships m JOIN public.tenants t ON t.id=m.tenant_id
  LEFT JOIN public.schools s ON s.id=m.school_id AND s.tenant_id=m.tenant_id
  WHERE m.user_id=v_user AND m.status='active' AND t.status='active' AND (s.id IS NULL OR s.status='active');
  RETURN v_result;
END $$;
REVOKE ALL ON FUNCTION public.kabarkelas_my_context() FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.kabarkelas_my_context() TO authenticated;
COMMIT;
