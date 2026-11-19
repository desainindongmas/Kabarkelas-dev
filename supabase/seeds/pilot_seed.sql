-- KabarKelas pilot seed — 35 siswa sintetis lintas kelas
BEGIN;

DO $$
DECLARE
  v_tenant uuid; v_school uuid;
  v_class_5a uuid; v_class_5b uuid; v_class_6a uuid;
  v_period uuid; v_subject_math uuid; v_subject_ipa uuid; v_subject_bind uuid;
  v_teacher uuid; v_principal uuid;
  v_student_id uuid; v_class uuid; i int;
  v_names text[] := ARRAY[
    'Aisyah Putri','Bima Sakti','Citra Lestari','Dimas Pratama','Elang Ramadhan',
    'Fitriani Sari','Gilang Mahendra','Hana Safitri','Ilham Fadillah','Jihan Amelia',
    'Kirana Dewi','Lukman Hakim','Maya Puspita','Naufal Ramadhan','Oki Setiawan',
    'Putri Ayu','Rafi Akbar','Sinta Permata','Taufik Hidayat','Umaira Zahra',
    'Vino Prasetyo','Wulan Dari','Yusuf Maulana','Zahra Amelia','Arka Wijaya',
    'Bella Anggraini','Cahya Dirgantara','Dewi Lestari','Eka Saputra','Fajar Nugroho',
    'Gita Savitri','Harun Al-Rasyid','Intan Permata','Joko Santoso','Kartika Sari'
  ];
  v_class_names text[] := ARRAY['Kelas 5A Uji','Kelas 5B Uji','Kelas 6A Uji'];
BEGIN
  SELECT id INTO v_tenant FROM public.tenants WHERE slug='yayasan-demo' OR name ILIKE '%demo%' LIMIT 1;
  IF v_tenant IS NULL THEN RAISE EXCEPTION 'Tenant demo tidak ditemukan'; END IF;
  SELECT id INTO v_school FROM public.schools WHERE tenant_id=v_tenant AND status='active' LIMIT 1;
  IF v_school IS NULL THEN RAISE EXCEPTION 'Sekolah demo tidak ditemukan'; END IF;

  FOR i IN 1..3 LOOP
    SELECT id INTO v_class FROM public.school_classes WHERE school_id=v_school AND name=v_class_names[i] LIMIT 1;
    IF v_class IS NULL THEN
      INSERT INTO public.school_classes(tenant_id,school_id,name,academic_year)
      VALUES(v_tenant,v_school,v_class_names[i],'2026/2027') RETURNING id INTO v_class;
    END IF;
    IF i=1 THEN v_class_5a:=v_class; ELSIF i=2 THEN v_class_5b:=v_class; ELSE v_class_6a:=v_class; END IF;
  END LOOP;

  SELECT id INTO v_period FROM public.academic_periods WHERE school_id=v_school AND status='active' LIMIT 1;
  IF v_period IS NULL THEN
    INSERT INTO public.academic_periods(tenant_id,school_id,code,starts_on,ends_on,status)
    VALUES(v_tenant,v_school,'Ganjil 2026/2027','2026-07-13','2026-12-18','active') RETURNING id INTO v_period;
  END IF;

  INSERT INTO public.subjects(tenant_id,school_id,code,name) VALUES
    (v_tenant,v_school,'MTK','Matematika'),
    (v_tenant,v_school,'IPA','IPA'),
    (v_tenant,v_school,'BIN','Bahasa Indonesia')
  ON CONFLICT(tenant_id,school_id,code) DO NOTHING;
  SELECT id INTO v_subject_math FROM public.subjects WHERE school_id=v_school AND code='MTK';
  SELECT id INTO v_subject_ipa FROM public.subjects WHERE school_id=v_school AND code='IPA';
  SELECT id INTO v_subject_bind FROM public.subjects WHERE school_id=v_school AND code='BIN';

  SELECT user_id INTO v_teacher FROM public.memberships WHERE school_id=v_school AND role_code='teacher' AND status='active' LIMIT 1;
  SELECT user_id INTO v_principal FROM public.memberships WHERE school_id=v_school AND role_code='principal' AND status='active' LIMIT 1;

  IF v_teacher IS NOT NULL THEN
    INSERT INTO public.teacher_class_assignments(tenant_id,school_id,class_id,teacher_user_id,status)
    SELECT v_tenant,v_school,c,v_teacher,'active' FROM (VALUES(v_class_5a),(v_class_5b),(v_class_6a)) AS c(id)
    WHERE NOT EXISTS(SELECT 1 FROM public.teacher_class_assignments t WHERE t.school_id=v_school AND t.class_id=c.id AND t.teacher_user_id=v_teacher AND t.status='active');
  END IF;

  IF v_teacher IS NOT NULL THEN
    INSERT INTO public.lesson_schedules(tenant_id,school_id,class_id,subject_id,teacher_user_id,weekday,start_time,end_time,room,academic_year)
    SELECT v_tenant,v_school,v_class_5a,v_subject_math,v_teacher,1,'07:00','07:35','R.5A','2026/2027'
    WHERE NOT EXISTS(SELECT 1 FROM public.lesson_schedules WHERE school_id=v_school AND class_id=v_class_5a AND weekday=1 AND subject_id=v_subject_math);
    INSERT INTO public.lesson_schedules(tenant_id,school_id,class_id,subject_id,teacher_user_id,weekday,start_time,end_time,room,academic_year)
    SELECT v_tenant,v_school,v_class_5b,v_subject_ipa,v_teacher,3,'08:00','08:35','R.5B','2026/2027'
    WHERE NOT EXISTS(SELECT 1 FROM public.lesson_schedules WHERE school_id=v_school AND class_id=v_class_5b AND weekday=3 AND subject_id=v_subject_ipa);
  END IF;

  FOR i IN 1..array_length(v_names,1) LOOP
    v_class:=CASE WHEN i<=15 THEN v_class_5a WHEN i<=28 THEN v_class_5b ELSE v_class_6a END;
    INSERT INTO public.students(tenant_id,school_id,local_student_no,display_name,status)
    VALUES(v_tenant,v_school,'SIM-'||lpad(i::text,3,'0'),v_names[i],'active')
    ON CONFLICT(tenant_id,school_id,local_student_no) DO NOTHING
    RETURNING id INTO v_student_id;

    IF v_student_id IS NULL THEN
      SELECT id INTO v_student_id FROM public.students WHERE school_id=v_school AND local_student_no='SIM-'||lpad(i::text,3,'0');
    END IF;

    INSERT INTO public.class_student_enrollments(tenant_id,school_id,class_id,student_id,status)
    VALUES(v_tenant,v_school,v_class,v_student_id,'active')
    ON CONFLICT DO NOTHING;
  END LOOP;

  IF v_principal IS NOT NULL THEN
    INSERT INTO public.announcements(tenant_id,school_id,title,body,audience_role,audience_class_id,status,published_at,created_by)
    SELECT v_tenant,v_school,'Selamat datang di KabarKelas Pilot',
      'Ini adalah pengumuman pilot. Data yang Anda lihat adalah data sintetis untuk uji coba.',
      NULL,NULL,'published',now(),v_principal
    WHERE NOT EXISTS(SELECT 1 FROM public.announcements WHERE school_id=v_school AND title LIKE 'Selamat datang%');
  END IF;

  RAISE NOTICE 'Seed pilot selesai: 35 siswa sintetis, 3 kelas';
END $$;

COMMIT;
