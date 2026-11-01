BEGIN;
DO $$ DECLARE t record; BEGIN FOR t IN SELECT tablename FROM pg_tables WHERE schemaname='public' LOOP EXECUTE format('REVOKE ALL PRIVILEGES ON TABLE public.%I FROM anon, authenticated',t.tablename); END LOOP; END $$;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA public FROM anon,authenticated;
REVOKE USAGE ON SCHEMA app FROM anon,authenticated,public;
ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE ALL ON TABLES FROM anon,authenticated;
COMMIT;
