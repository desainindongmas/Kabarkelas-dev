-- KabarKelas pilot accounts provisioning (G10 multi-role)
-- Menyediakan akun pilot.*@kabarkelas.dev untuk seluruh peran di sekolah demo.
-- Jalankan via Supabase SQL Editor atau Management API sebagai postgres.
-- Password semua akun pilot: PilotKabarKelas2026! (sudah didokumentasikan di docs/BETA-release-report.md)
-- Idempotent: aman dijalankan berulang.

DO $$
DECLARE
  v_tenant uuid := 'fdf1dbbd-18d3-48e2-abe4-8c874f046530'; -- Yayasan Demo KabarKelas
  v_school uuid := 'a91050a3-2463-4c54-9cf8-f06f9e991543'; -- SD Demo KabarKelas
  v_principal uuid := '6e5f528d-243f-4e9b-bb19-f2925aa4e2bd'; -- muhsubhi24@gmail.com
  rec record; v_uid uuid; v_student uuid;
BEGIN
  FOR rec IN SELECT * FROM (VALUES
    ('pilot.kepala@kabarkelas.dev','Kepala Pilot Demo','principal'),
    ('pilot.admin@kabarkelas.dev','Admin Pilot Demo','school_admin'),
    ('pilot.ortu@kabarkelas.dev','Orang Tua Pilot Demo','guardian')
  ) AS x(email,display_name,role_code) LOOP
    IF EXISTS(SELECT 1 FROM auth.users WHERE email=rec.email) THEN
      SELECT id INTO v_uid FROM auth.users WHERE email=rec.email;
    ELSE
      INSERT INTO auth.users(instance_id,id,aud,role,email,encrypted_password,
        email_confirmed_at,invited_at,confirmation_token,recovery_token,
        email_change_token_new,email_change,last_sign_in_at,
        raw_app_meta_data,raw_user_meta_data,is_super_admin,created_at,updated_at,
        phone,phone_confirmed_at,phone_change,phone_change_token,
        email_change_token_current,email_change_confirm_status,
        reauthentication_token,is_sso_user)
      VALUES('00000000-0000-0000-0000-000000000000',gen_random_uuid(),
        'authenticated','authenticated',rec.email,
        extensions.crypt('PilotKabarKelas2026!',extensions.gen_salt('bf')),
        now(),now(),'','','','',NULL,
        '{"provider":"email","providers":["email"]}'::jsonb,
        jsonb_build_object('display_name',rec.display_name,'email_verified',true),
        false,now(),now(),NULL,NULL,'','','',0,'',false)
      RETURNING id INTO v_uid;
      INSERT INTO auth.identities(id,provider_id,user_id,identity_data,provider,last_sign_in_at,created_at,updated_at)
      VALUES(gen_random_uuid(),v_uid::text,v_uid,
        jsonb_build_object('sub',v_uid::text,'email',rec.email,'email_verified',true,'phone_verified',false),
        'email',now(),now(),now());
    END IF;

    IF NOT EXISTS(SELECT 1 FROM public.users WHERE id=v_uid) THEN
      INSERT INTO public.users(id,auth_subject,email) VALUES(v_uid,v_uid::text,rec.email);
    END IF;

    IF NOT EXISTS(SELECT 1 FROM public.memberships WHERE user_id=v_uid AND school_id=v_school AND role_code=rec.role_code AND status='active') THEN
      INSERT INTO public.memberships(tenant_id,school_id,user_id,role_code,status)
      VALUES(v_tenant,v_school,v_uid,rec.role_code,'active');
    END IF;

    IF rec.role_code='guardian' THEN
      -- Kaitkan ke siswa sintetis SIM-001 (Aisyah Putri, Kelas 5A Uji)
      SELECT id INTO v_student FROM public.students WHERE school_id=v_school AND local_student_no='SIM-001';
      IF v_student IS NOT NULL AND NOT EXISTS(
        SELECT 1 FROM public.guardian_student_links
        WHERE guardian_user_id=v_uid AND student_id=v_student AND verification_status='verified') THEN
        INSERT INTO public.guardian_student_links(tenant_id,school_id,student_id,guardian_user_id,relationship_code,verification_status,verified_by,verified_at)
        VALUES(v_tenant,v_school,v_student,v_uid,'parent','verified',v_principal,now());
      END IF;
    END IF;

    RAISE NOTICE 'provisioned % as %', rec.email, rec.role_code;
  END LOOP;
END $$;

-- Catatan: akun pilot.guru@kabarkelas.dev (teacher) sudah ada sebelumnya.
-- Konten G10 (homework, quiz, scores, P5) di-seed via RPC oleh pilot.guru pada 2026-11-19:
--   2 homework_assignments (published), 1 quiz_schedules, 5 homework_scores,
--   4 quiz_scores, 6 p5_tahfizh_assessments — lihat HANDOVER.md.
