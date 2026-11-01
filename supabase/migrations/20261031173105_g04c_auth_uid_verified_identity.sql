BEGIN;
CREATE OR REPLACE FUNCTION app.current_user_id() RETURNS uuid
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = pg_catalog,app,public,auth
AS $$
 SELECT u.id FROM public.users u
 WHERE auth.uid() IS NOT NULL
 AND u.auth_subject = auth.uid()::text
 LIMIT 1
$$;
REVOKE ALL ON FUNCTION app.current_user_id() FROM PUBLIC,anon,authenticated;
-- This function is for database-internal permission evaluation only.
-- Exposed tables remain unavailable to anon/authenticated until end-to-end testing.
COMMIT;
