BEGIN;
ALTER TABLE public.school_report_reviews
 ADD COLUMN homeroom_user_id uuid REFERENCES public.users(id),
 ADD COLUMN revision integer NOT NULL DEFAULT 1 CHECK(revision>0);
CREATE TABLE public.school_report_snapshots (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 tenant_id uuid NOT NULL REFERENCES public.tenants(id),
 school_id uuid NOT NULL REFERENCES public.schools(id),
 report_id uuid NOT NULL REFERENCES public.school_report_reviews(id),
 student_id uuid NOT NULL REFERENCES public.students(id),
 version integer NOT NULL CHECK(version>0),
 payload jsonb NOT NULL,
 payload_sha256 text NOT NULL,
 signed_by uuid NOT NULL REFERENCES public.users(id),
 signed_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 UNIQUE(report_id,student_id,version)
);
ALTER TABLE public.school_report_snapshots ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.school_report_snapshots FORCE ROW LEVEL SECURITY;
REVOKE ALL ON public.school_report_snapshots FROM PUBLIC,anon,authenticated;
CREATE FUNCTION app.g051_block_report_snapshot_changes()
RETURNS trigger LANGUAGE plpgsql SET search_path='' AS $$
BEGIN
 RAISE EXCEPTION 'Signed report snapshots cannot be changed' USING ERRCODE='55000';
END $$;
CREATE TRIGGER g051_signed_reports_no_mutation BEFORE UPDATE OR DELETE ON public.school_report_snapshots
 FOR EACH ROW EXECUTE FUNCTION app.g051_block_report_snapshot_changes();
CREATE TRIGGER g051_signed_reports_no_truncate BEFORE TRUNCATE ON public.school_report_snapshots
 FOR EACH STATEMENT EXECUTE FUNCTION app.g051_block_report_snapshot_changes();
COMMIT;
