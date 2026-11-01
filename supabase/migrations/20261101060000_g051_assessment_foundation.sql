-- G0.5.1 schema foundation. No migration of historical published G0.5 grades.
CREATE TABLE public.assessment_policies (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 tenant_id uuid NOT NULL REFERENCES public.tenants(id),
 school_id uuid NOT NULL REFERENCES public.schools(id),
 version integer NOT NULL CHECK(version>0),
 mode text NOT NULL CHECK(mode IN ('best_score','latest_score','best_capped')),
 cap_percent numeric CHECK(cap_percent BETWEEN 0 AND 100),
 parent_visibility text NOT NULL DEFAULT 'after_release' CHECK(parent_visibility IN ('after_release','report_only')),
 is_active boolean NOT NULL DEFAULT false,
 created_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(tenant_id,school_id,version),
 CHECK(mode<>'best_capped' OR cap_percent IS NOT NULL)
);
CREATE TABLE public.assessment_attempts (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 tenant_id uuid NOT NULL REFERENCES public.tenants(id),
 school_id uuid NOT NULL REFERENCES public.schools(id),
 grade_id uuid NOT NULL REFERENCES public.student_grades(id),
 attempt_kind text NOT NULL CHECK(attempt_kind IN ('initial','remedial')),
 score numeric NOT NULL CHECK(score>=0 AND score::text<>'NaN'),
 policy_id uuid REFERENCES public.assessment_policies(id),
 recorded_by uuid NOT NULL REFERENCES public.users(id),
 recorded_at timestamptz NOT NULL DEFAULT now(),
 note text,
 UNIQUE(grade_id,attempt_kind,id)
);
CREATE TABLE public.assessment_corrections (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 tenant_id uuid NOT NULL REFERENCES public.tenants(id),
 school_id uuid NOT NULL REFERENCES public.schools(id),
 attempt_id uuid NOT NULL REFERENCES public.assessment_attempts(id),
 previous_score numeric NOT NULL,
 corrected_score numeric NOT NULL,
 reason text NOT NULL CHECK(length(btrim(reason))>=3),
 corrected_by uuid NOT NULL REFERENCES public.users(id),
 corrected_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE public.school_report_reviews (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 tenant_id uuid NOT NULL REFERENCES public.tenants(id),
 school_id uuid NOT NULL REFERENCES public.schools(id),
 class_id uuid NOT NULL REFERENCES public.school_classes(id),
 period_id uuid NOT NULL REFERENCES public.academic_periods(id),
 status text NOT NULL DEFAULT 'draft' CHECK(status IN ('draft','teacher_finalized','homeroom_reviewed','principal_signed','released')),
 version integer NOT NULL DEFAULT 1 CHECK(version>0),
 signed_by uuid REFERENCES public.users(id),
 signed_at timestamptz,
 released_at timestamptz,
 created_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(tenant_id,school_id,class_id,period_id,version)
);
DO $$
DECLARE t text;
BEGIN
 FOREACH t IN ARRAY ARRAY['assessment_policies','assessment_attempts','assessment_corrections','school_report_reviews'] LOOP
  EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY',t);
  EXECUTE format('ALTER TABLE public.%I FORCE ROW LEVEL SECURITY',t);
  EXECUTE format('REVOKE ALL ON public.%I FROM PUBLIC, anon, authenticated',t);
 END LOOP;
END $$;
-- API and permission-checked mutations are intentionally excluded until they have integration tests.
