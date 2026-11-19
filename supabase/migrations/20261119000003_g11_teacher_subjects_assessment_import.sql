-- G11: teacher↔subject mapping, teacher-scoped grade authz, assessment creation,
-- and bulk CSV import RPCs for onboarding (yayasan→siswa→ortu).
BEGIN;

-- ============ 1. teacher_subject_assignments ============
CREATE TABLE public.teacher_subject_assignments(
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL, school_id uuid NOT NULL,
  class_id uuid NOT NULL, subject_id uuid NOT NULL,
  teacher_user_id uuid NOT NULL REFERENCES public.users(id),
  status text NOT NULL DEFAULT 'active' CHECK(status IN('active','ended')),
  created_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY(tenant_id,school_id,class_id) REFERENCES public.school_classes(tenant_id,school_id,id),
  FOREIGN KEY(tenant_id,school_id,subject_id) REFERENCES public.subjects(tenant_id,school_id,id),
  UNIQUE(tenant_id,school_id,id),
  CHECK((tenant_id,school_id,class_id,subject_id,teacher_user_id) IS NOT NULL)
);
CREATE UNIQUE INDEX tsa_one_active ON public.teacher_subject_assignments(tenant_id,school_id,class_id,subject_id,teacher_user_id) WHERE status='active';
ALTER TABLE public.teacher_subject_assignments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.teacher_subject_assignments FORCE ROW LEVEL SECURITY;
CREATE POLICY tsa_read ON public.teacher_subject_assignments FOR SELECT USING(app.has_active_membership(tenant_id,school_id));
REVOKE ALL ON public.teacher_subject_assignments FROM PUBLIC,anon,authenticated;

-- ============ 2. Tighten grade authz to subject scope ============
-- g05_access.teacher: teacher must be assigned to the assessment's subject
CREATE OR REPLACE FUNCTION app.g05_access(p_grade uuid, p_user uuid)
RETURNS TABLE(teacher boolean, principal boolean, guardian boolean)
LANGUAGE sql STABLE SET search_path = '' AS $$
SELECT
  EXISTS(SELECT 1 FROM public.memberships m WHERE m.user_id=p_user AND m.tenant_id=g.tenant_id AND m.school_id=g.school_id AND m.role_code='teacher' AND m.status='active')
  AND EXISTS(SELECT 1 FROM public.teacher_class_assignments tc
    JOIN public.class_student_enrollments en ON en.tenant_id=tc.tenant_id AND en.school_id=tc.school_id AND en.class_id=tc.class_id
    WHERE tc.tenant_id=g.tenant_id AND tc.school_id=g.school_id AND tc.class_id=a.class_id
      AND tc.teacher_user_id=p_user AND tc.status='active' AND en.student_id=g.student_id AND en.status='active'
      AND en.started_at<=statement_timestamp() AND (en.ended_at IS NULL OR en.ended_at>statement_timestamp()))
  AND EXISTS(SELECT 1 FROM public.teacher_subject_assignments tsa
    WHERE tsa.tenant_id=g.tenant_id AND tsa.school_id=g.school_id
      AND tsa.class_id=a.class_id AND tsa.subject_id=a.subject_id
      AND tsa.teacher_user_id=p_user AND tsa.status='active'),
  EXISTS(SELECT 1 FROM public.memberships m WHERE m.user_id=p_user AND m.tenant_id=g.tenant_id AND m.school_id=g.school_id AND m.role_code='principal' AND m.status='active'),
  EXISTS(SELECT 1 FROM public.memberships m WHERE m.user_id=p_user AND m.tenant_id=g.tenant_id AND m.school_id=g.school_id AND m.role_code='guardian' AND m.status='active')
  AND EXISTS(SELECT 1 FROM public.guardian_student_links l WHERE l.tenant_id=g.tenant_id AND l.school_id=g.school_id AND l.student_id=g.student_id AND l.guardian_user_id=p_user AND l.verification_status='verified')
FROM public.student_grades g
JOIN public.assessments a ON (a.tenant_id,a.school_id,a.id)=(g.tenant_id,g.school_id,g.assessment_id)
JOIN public.students s ON (s.tenant_id,s.school_id,s.id)=(g.tenant_id,g.school_id,g.student_id) AND s.status='active'
JOIN public.schools sch ON (sch.tenant_id,sch.id)=(g.tenant_id,g.school_id) AND sch.status='active'
JOIN public.tenants t ON t.id=g.tenant_id AND t.status='active'
WHERE g.id=p_grade;
$$;

-- g051_can_manage_draft: same subject-scope tightening
CREATE OR REPLACE FUNCTION app.g051_can_manage_draft(p_grade uuid,p_actor uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
 SELECT EXISTS(
 SELECT 1 FROM public.student_grades g
 JOIN public.assessments a ON (a.id,a.school_id,a.tenant_id)=(g.assessment_id,g.school_id,g.tenant_id)
 JOIN public.students s ON (s.id,s.school_id,s.tenant_id)=(g.student_id,g.school_id,g.tenant_id) AND s.status='active'
 JOIN public.schools sc ON sc.id=g.school_id AND sc.tenant_id=g.tenant_id AND sc.status='active'
 JOIN public.tenants t ON t.id=g.tenant_id AND t.status='active'
 JOIN public.memberships m ON m.user_id=p_actor AND m.tenant_id=g.tenant_id AND m.school_id=g.school_id AND m.role_code='teacher' AND m.status='active'
 JOIN public.teacher_class_assignments tc ON tc.tenant_id=g.tenant_id AND tc.school_id=g.school_id AND tc.class_id=a.class_id AND tc.teacher_user_id=p_actor AND tc.status='active'
 JOIN public.teacher_subject_assignments tsa ON tsa.tenant_id=g.tenant_id AND tsa.school_id=g.school_id AND tsa.class_id=a.class_id AND tsa.subject_id=a.subject_id AND tsa.teacher_user_id=p_actor AND tsa.status='active'
 JOIN public.class_student_enrollments en ON en.tenant_id=g.tenant_id AND en.school_id=g.school_id AND en.class_id=a.class_id AND en.student_id=g.student_id AND en.status='active' AND en.started_at<=now() AND (en.ended_at IS NULL OR en.ended_at>now())
 WHERE g.id=p_grade AND g.status='draft');
$$;

-- ============ 3. Teacher subject/class options for UI ============
CREATE FUNCTION public.kabarkelas_teacher_options(p_school uuid)
RETURNS TABLE(class_id uuid,class_name text,subject_id uuid,subject_name text)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE v_actor uuid:=app.g05_actor();
BEGIN
 IF NOT EXISTS(SELECT 1 FROM public.memberships m JOIN public.schools s ON s.id=m.school_id AND s.tenant_id=m.tenant_id AND s.status='active' JOIN public.tenants t ON t.id=m.tenant_id AND t.status='active' WHERE m.school_id=p_school AND m.user_id=v_actor AND m.status='active' AND m.role_code='teacher') THEN
  RAISE EXCEPTION 'School unavailable' USING ERRCODE='42501'; END IF;
 RETURN QUERY
 SELECT DISTINCT c.id,c.name,sj.id,sj.name
 FROM public.teacher_subject_assignments tsa
 JOIN public.school_classes c ON c.id=tsa.class_id AND c.school_id=tsa.school_id AND c.tenant_id=tsa.tenant_id
 JOIN public.subjects sj ON sj.id=tsa.subject_id AND sj.school_id=tsa.school_id AND sj.tenant_id=tsa.tenant_id
 WHERE tsa.school_id=p_school AND tsa.teacher_user_id=v_actor AND tsa.status='active'
 ORDER BY c.name,sj.name;
END $$;
REVOKE ALL ON FUNCTION public.kabarkelas_teacher_options(uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.kabarkelas_teacher_options(uuid) TO authenticated;

-- ============ 4. Create assessment + draft grades + initial attempts ============
CREATE FUNCTION public.kabarkelas_create_assessment(
  p_school uuid, p_class uuid, p_subject uuid, p_period uuid,
  p_title text, p_max_score numeric, p_scores jsonb)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE
 v_actor uuid:=app.g05_actor();
 v_assess uuid; v_student uuid; v_score numeric; v_grade uuid; v_attempt uuid;
 v_entry jsonb; v_class public.school_classes%ROWTYPE;
BEGIN
 IF p_title IS NULL OR length(btrim(p_title))<3 THEN RAISE EXCEPTION 'Title required' USING ERRCODE='22023'; END IF;
 IF p_max_score IS NULL OR p_max_score<=0 THEN RAISE EXCEPTION 'Invalid max score' USING ERRCODE='22023'; END IF;
 IF p_scores IS NULL OR jsonb_typeof(p_scores)<>'array' THEN RAISE EXCEPTION 'Scores must be array' USING ERRCODE='22023'; END IF;
 SELECT * INTO v_class FROM public.school_classes WHERE id=p_class AND school_id=p_school;
 IF NOT FOUND THEN RAISE EXCEPTION 'Class unavailable' USING ERRCODE='42501'; END IF;
 -- teacher harus assigned ke mapel ini
 IF NOT EXISTS(SELECT 1 FROM public.teacher_subject_assignments tsa
   WHERE tsa.tenant_id=v_class.tenant_id AND tsa.school_id=p_school AND tsa.class_id=p_class
     AND tsa.subject_id=p_subject AND tsa.teacher_user_id=v_actor AND tsa.status='active') THEN
  RAISE EXCEPTION 'Subject not assigned' USING ERRCODE='42501'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.academic_periods ap WHERE ap.id=p_period AND ap.school_id=p_school AND ap.status='active') THEN
  RAISE EXCEPTION 'Period unavailable' USING ERRCODE='42501'; END IF;
 INSERT INTO public.assessments(tenant_id,school_id,class_id,subject_id,period_id,title,max_score,status,created_by)
 VALUES(v_class.tenant_id,p_school,p_class,p_subject,p_period,btrim(p_title),p_max_score,'draft',v_actor)
 RETURNING id INTO v_assess;
 FOR v_entry IN SELECT value FROM jsonb_array_elements(p_scores) LOOP
  SELECT s.id INTO v_student FROM public.students s
   JOIN public.class_student_enrollments e ON e.student_id=s.id AND e.class_id=p_class AND e.status='active'
   WHERE s.school_id=p_school AND s.status='active' AND s.id=(v_entry->>'student_id')::uuid;
  IF v_student IS NULL THEN RAISE EXCEPTION 'Student not in class' USING ERRCODE='42501'; END IF;
  v_score:=(v_entry->>'score')::numeric;
  IF v_score IS NULL OR v_score<0 OR v_score>p_max_score THEN RAISE EXCEPTION 'Score out of range' USING ERRCODE='23514'; END IF;
  INSERT INTO public.student_grades(tenant_id,school_id,assessment_id,student_id,score,status,revision)
  VALUES(v_class.tenant_id,p_school,v_assess,v_student,NULL,'draft',1)
  RETURNING id INTO v_grade;
  INSERT INTO public.assessment_attempts(tenant_id,school_id,grade_id,attempt_kind,score,recorded_by,note)
  VALUES(v_class.tenant_id,p_school,v_grade,'initial',v_score,v_actor,'input awal');
 END LOOP;
 RETURN v_assess;
END $$;
REVOKE ALL ON FUNCTION public.kabarkelas_create_assessment(uuid,uuid,uuid,uuid,text,numeric,jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.kabarkelas_create_assessment(uuid,uuid,uuid,uuid,text,numeric,jsonb) TO authenticated;

-- ============ 5. Import RPCs (foundation_admin / principal / school_admin) ============
CREATE FUNCTION app.g11_import_allowed(p_school uuid DEFAULT NULL) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
 SELECT EXISTS(
   SELECT 1 FROM public.memberships m
   JOIN public.tenants t ON t.id=m.tenant_id AND t.status='active'
   LEFT JOIN public.schools s ON s.id=m.school_id AND s.tenant_id=m.tenant_id AND s.status='active'
   WHERE m.user_id=app.g05_actor() AND m.status='active'
     AND m.role_code IN ('foundation_admin','principal','school_admin')
     AND (p_school IS NULL OR m.school_id=p_school OR m.role_code='foundation_admin')
     AND (m.school_id IS NULL OR s.id IS NOT NULL)
 )
$$;

-- create auth user + public.users + memberships; returns user_id
CREATE FUNCTION public.kabarkelas_import_users(p_rows jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v_actor uuid:=app.g05_actor(); rec jsonb; v_uid uuid; v_auth uuid; v_email text; v_created int:=0; v_results jsonb:='[]';
BEGIN
 IF NOT app.g11_import_allowed() THEN RAISE EXCEPTION 'Import not allowed' USING ERRCODE='42501'; END IF;
 FOR rec IN SELECT value FROM jsonb_array_elements(p_rows) LOOP
  v_email:=lower(btrim(rec->>'email'));
  IF v_email IS NULL OR v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' THEN
   v_results:=v_results||jsonb_build_object('email',v_email,'error','invalid email'); CONTINUE; END IF;
  IF EXISTS(SELECT 1 FROM auth.users WHERE email=v_email) THEN
   SELECT id INTO v_uid FROM auth.users WHERE email=v_email;
  ELSE
   v_auth:=gen_random_uuid(); v_uid:=v_auth;
   INSERT INTO auth.users(instance_id,id,aud,role,email,encrypted_password,
     email_confirmed_at,invited_at,confirmation_token,recovery_token,
     email_change_token_new,email_change,last_sign_in_at,
     raw_app_meta_data,raw_user_meta_data,is_super_admin,created_at,updated_at,
     phone,phone_confirmed_at,phone_change,phone_change_token,
     email_change_token_current,email_change_confirm_status,
     reauthentication_token,is_sso_user)
   VALUES('00000000-0000-0000-0000-000000000000',v_auth,
     'authenticated','authenticated',v_email,
     extensions.crypt(COALESCE(rec->>'password','KabarKelas2026!'),extensions.gen_salt('bf')),
     now(),now(),'','','','',NULL,
     '{"provider":"email","providers":["email"]}'::jsonb,
     jsonb_build_object('display_name',rec->>'display_name','email_verified',true),
     false,now(),now(),NULL,NULL,'','','',0,'',false);
   INSERT INTO auth.identities(id,provider_id,user_id,identity_data,provider,last_sign_in_at,created_at,updated_at)
   VALUES(gen_random_uuid(),v_auth::text,v_auth,
     jsonb_build_object('sub',v_auth::text,'email',v_email,'email_verified',true,'phone_verified',false),
     'email',now(),now(),now());
  END IF;
  IF NOT EXISTS(SELECT 1 FROM public.users WHERE id=v_uid) THEN
   INSERT INTO public.users(id,auth_subject,email) VALUES(v_uid,v_uid::text,v_email);
  END IF;
  -- memberships ditangani terpisah via kabarkelas_import_memberships
  v_created:=v_created+1;
  v_results:=v_results||jsonb_build_object('email',v_email,'user_id',v_uid);
 END LOOP;
 RETURN jsonb_build_object('created',v_created,'results',v_results);
END $$;
REVOKE ALL ON FUNCTION public.kabarkelas_import_users(jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.kabarkelas_import_users(jsonb) TO authenticated;

-- schools
CREATE FUNCTION public.kabarkelas_import_schools(p_rows jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE rec jsonb; v_id uuid; v_tenant uuid; v_results jsonb:='[]';
BEGIN
 IF NOT app.g11_import_allowed() THEN RAISE EXCEPTION 'Import not allowed' USING ERRCODE='42501'; END IF;
 FOR rec IN SELECT value FROM jsonb_array_elements(p_rows) LOOP
  SELECT id INTO v_tenant FROM public.tenants WHERE slug=rec->>'tenant_slug' OR name=rec->>'tenant_name' LIMIT 1;
  IF v_tenant IS NULL THEN v_results:=v_results||jsonb_build_object('code',rec->>'code','error','tenant not found'); CONTINUE; END IF;
  INSERT INTO public.schools(tenant_id,code,name,status)
  VALUES(v_tenant,rec->>'code',rec->>'name','active')
  ON CONFLICT(tenant_id,code) DO UPDATE SET name=EXCLUDED.name RETURNING id INTO v_id;
  v_results:=v_results||jsonb_build_object('code',rec->>'code','school_id',v_id);
 END LOOP;
 RETURN v_results;
END $$;
REVOKE ALL ON FUNCTION public.kabarkelas_import_schools(jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.kabarkelas_import_schools(jsonb) TO authenticated;

-- subjects
CREATE FUNCTION public.kabarkelas_import_subjects(p_rows jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE rec jsonb; v_school uuid; v_results jsonb:='[]';
BEGIN
 IF NOT app.g11_import_allowed() THEN RAISE EXCEPTION 'Import not allowed' USING ERRCODE='42501'; END IF;
 FOR rec IN SELECT value FROM jsonb_array_elements(p_rows) LOOP
  SELECT id INTO v_school FROM public.schools WHERE code=rec->>'school_code' LIMIT 1;
  IF v_school IS NULL THEN v_results:=v_results||jsonb_build_object('code',rec->>'code','error','school not found'); CONTINUE; END IF;
  INSERT INTO public.subjects(tenant_id,school_id,code,name)
  SELECT s.tenant_id,v_school,rec->>'code',rec->>'name' FROM public.schools s WHERE s.id=v_school
  ON CONFLICT(tenant_id,school_id,code) DO UPDATE SET name=EXCLUDED.name;
  v_results:=v_results||jsonb_build_object('code',rec->>'code','school_code',rec->>'school_code','ok',true);
 END LOOP;
 RETURN v_results;
END $$;
REVOKE ALL ON FUNCTION public.kabarkelas_import_subjects(jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.kabarkelas_import_subjects(jsonb) TO authenticated;

-- classes + enrollments
CREATE FUNCTION public.kabarkelas_import_classes(p_rows jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE rec jsonb; v_school uuid; v_class uuid; v_student uuid; v_stu jsonb; v_results jsonb:='[]';
BEGIN
 IF NOT app.g11_import_allowed() THEN RAISE EXCEPTION 'Import not allowed' USING ERRCODE='42501'; END IF;
 FOR rec IN SELECT value FROM jsonb_array_elements(p_rows) LOOP
  SELECT id INTO v_school FROM public.schools WHERE code=rec->>'school_code' LIMIT 1;
  IF v_school IS NULL THEN v_results:=v_results||jsonb_build_object('name',rec->>'name','error','school not found'); CONTINUE; END IF;
  INSERT INTO public.school_classes(tenant_id,school_id,name,academic_year)
  SELECT s.tenant_id,v_school,rec->>'name',COALESCE(rec->>'academic_year','2026/2027') FROM public.schools s WHERE s.id=v_school
  ON CONFLICT(tenant_id,school_id,name,academic_year) DO NOTHING
  RETURNING id INTO v_class;
  IF v_class IS NULL THEN SELECT id INTO v_class FROM public.school_classes WHERE school_id=v_school AND name=rec->>'name' LIMIT 1; END IF;
  -- students array: [{local_student_no,display_name}]
  IF rec ? 'students' AND jsonb_typeof(rec->'students')='array' THEN
   FOR v_stu IN SELECT value FROM jsonb_array_elements(rec->'students') LOOP
    INSERT INTO public.students(tenant_id,school_id,local_student_no,display_name,status)
    SELECT s.tenant_id,v_school,v_stu->>'local_student_no',v_stu->>'display_name','active' FROM public.schools s WHERE s.id=v_school
    ON CONFLICT(tenant_id,school_id,local_student_no) DO NOTHING
    RETURNING id INTO v_student;
    IF v_student IS NULL THEN SELECT id INTO v_student FROM public.students WHERE school_id=v_school AND local_student_no=v_stu->>'local_student_no'; END IF;
    INSERT INTO public.class_student_enrollments(tenant_id,school_id,class_id,student_id,status)
    SELECT s.tenant_id,v_school,v_class,v_student,'active' FROM public.schools s WHERE s.id=v_school
      AND NOT EXISTS(SELECT 1 FROM public.class_student_enrollments e WHERE e.class_id=v_class AND e.student_id=v_student AND e.status='active');
   END LOOP;
  END IF;
  v_results:=v_results||jsonb_build_object('name',rec->>'name','class_id',v_class,'school_code',rec->>'school_code');
 END LOOP;
 RETURN v_results;
END $$;
REVOKE ALL ON FUNCTION public.kabarkelas_import_classes(jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.kabarkelas_import_classes(jsonb) TO authenticated;

-- teacher assignments (class + subject)
CREATE FUNCTION public.kabarkelas_import_teacher_assignments(p_rows jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE rec jsonb; v_class uuid; v_subject uuid; v_teacher uuid; v_results jsonb:='[]';
BEGIN
 IF NOT app.g11_import_allowed() THEN RAISE EXCEPTION 'Import not allowed' USING ERRCODE='42501'; END IF;
 FOR rec IN SELECT value FROM jsonb_array_elements(p_rows) LOOP
  SELECT c.id INTO v_class FROM public.school_classes c JOIN public.schools s ON s.id=c.school_id WHERE c.name=rec->>'class_name' AND s.code=rec->>'school_code' LIMIT 1;
  SELECT sj.id INTO v_subject FROM public.subjects sj JOIN public.schools s ON s.id=sj.school_id WHERE sj.code=rec->>'subject_code' AND s.code=rec->>'school_code' LIMIT 1;
  SELECT u.id INTO v_teacher FROM public.users u WHERE u.email=lower(rec->>'teacher_email');
  IF v_class IS NULL OR v_subject IS NULL OR v_teacher IS NULL THEN
   v_results:=v_results||jsonb_build_object('class',rec->>'class_name','subject',rec->>'subject_code','error','lookup failed'); CONTINUE; END IF;
  INSERT INTO public.teacher_class_assignments(tenant_id,school_id,class_id,teacher_user_id,status)
  SELECT c.tenant_id,c.school_id,v_class,v_teacher,'active' FROM public.school_classes c WHERE c.id=v_class
  AND NOT EXISTS(SELECT 1 FROM public.teacher_class_assignments t WHERE t.class_id=v_class AND t.teacher_user_id=v_teacher AND t.status='active');
  INSERT INTO public.teacher_subject_assignments(tenant_id,school_id,class_id,subject_id,teacher_user_id,status)
  SELECT c.tenant_id,c.school_id,v_class,v_subject,v_teacher,'active' FROM public.school_classes c WHERE c.id=v_class
  AND NOT EXISTS(SELECT 1 FROM public.teacher_subject_assignments t WHERE t.class_id=v_class AND t.subject_id=v_subject AND t.teacher_user_id=v_teacher AND t.status='active');
  v_results:=v_results||jsonb_build_object('class',rec->>'class_name','subject',rec->>'subject_code','teacher',rec->>'teacher_email','ok',true);
 END LOOP;
 RETURN v_results;
END $$;
REVOKE ALL ON FUNCTION public.kabarkelas_import_teacher_assignments(jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.kabarkelas_import_teacher_assignments(jsonb) TO authenticated;

-- memberships (role per school/tenant)
CREATE FUNCTION public.kabarkelas_import_memberships(p_rows jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE rec jsonb; v_user uuid; v_school uuid; v_tenant uuid; v_results jsonb:='[]';
BEGIN
 IF NOT app.g11_import_allowed() THEN RAISE EXCEPTION 'Import not allowed' USING ERRCODE='42501'; END IF;
 FOR rec IN SELECT value FROM jsonb_array_elements(p_rows) LOOP
  SELECT id INTO v_user FROM public.users WHERE email=lower(rec->>'email');
  IF rec->>'school_code' IS NOT NULL AND rec->>'school_code'<>'null' THEN
   SELECT id INTO v_school FROM public.schools WHERE code=rec->>'school_code' LIMIT 1;
   SELECT tenant_id INTO v_tenant FROM public.schools WHERE id=v_school;
  ELSE
   SELECT id INTO v_tenant FROM public.tenants WHERE slug=rec->>'tenant_slug' OR name=rec->>'tenant_name' LIMIT 1;
   v_school:=NULL;
  END IF;
  IF v_user IS NULL OR v_tenant IS NULL THEN v_results:=v_results||jsonb_build_object('email',rec->>'email','error','lookup failed'); CONTINUE; END IF;
  INSERT INTO public.memberships(tenant_id,school_id,user_id,role_code,status)
  VALUES(v_tenant,v_school,v_user,rec->>'role_code','active')
  ON CONFLICT DO NOTHING;
  v_results:=v_results||jsonb_build_object('email',rec->>'email','role',rec->>'role_code','ok',true);
 END LOOP;
 RETURN v_results;
END $$;
REVOKE ALL ON FUNCTION public.kabarkelas_import_memberships(jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.kabarkelas_import_memberships(jsonb) TO authenticated;

-- guardian links
CREATE FUNCTION public.kabarkelas_import_guardian_links(p_rows jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE rec jsonb; v_guardian uuid; v_student uuid; v_school uuid; v_principal uuid; v_results jsonb:='[]';
BEGIN
 IF NOT app.g11_import_allowed() THEN RAISE EXCEPTION 'Import not allowed' USING ERRCODE='42501'; END IF;
 FOR rec IN SELECT value FROM jsonb_array_elements(p_rows) LOOP
  SELECT id INTO v_guardian FROM public.users WHERE email=lower(rec->>'guardian_email');
  SELECT s.id INTO v_student FROM public.students s WHERE s.local_student_no=rec->>'student_no' AND s.school_id=(SELECT id FROM public.schools WHERE code=rec->>'school_code' LIMIT 1);
  SELECT id INTO v_school FROM public.schools WHERE code=rec->>'school_code' LIMIT 1;
  SELECT user_id INTO v_principal FROM public.memberships WHERE school_id=v_school AND role_code='principal' AND status='active' LIMIT 1;
  IF v_guardian IS NULL OR v_student IS NULL OR v_school IS NULL THEN
   v_results:=v_results||jsonb_build_object('guardian',rec->>'guardian_email','student',rec->>'student_no','error','lookup failed'); CONTINUE; END IF;
  INSERT INTO public.guardian_student_links(tenant_id,school_id,student_id,guardian_user_id,relationship_code,verification_status,verified_by,verified_at)
  SELECT s.tenant_id,v_school,v_student,v_guardian,COALESCE(rec->>'relationship','parent'),'verified',v_principal,now()
  FROM public.students s WHERE s.id=v_student
  ON CONFLICT DO NOTHING;
  v_results:=v_results||jsonb_build_object('guardian',rec->>'guardian_email','student',rec->>'student_no','ok',true);
 END LOOP;
 RETURN v_results;
END $$;
REVOKE ALL ON FUNCTION public.kabarkelas_import_guardian_links(jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.kabarkelas_import_guardian_links(jsonb) TO authenticated;

-- periode akademik aktif untuk form guru
CREATE OR REPLACE FUNCTION public.kabarkelas_my_periods(p_school uuid)
RETURNS TABLE(id uuid,code text,name text,start_date date,end_date date)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE v_actor uuid:=app.g05_actor();
BEGIN
 IF NOT EXISTS(SELECT 1 FROM public.memberships m JOIN public.schools s ON s.id=m.school_id AND s.tenant_id=m.tenant_id AND s.status='active' JOIN public.tenants t ON t.id=m.tenant_id AND t.status='active' WHERE m.school_id=p_school AND m.user_id=v_actor AND m.status='active') THEN
  RAISE EXCEPTION 'School unavailable' USING ERRCODE='42501'; END IF;
 RETURN QUERY SELECT ap.id,ap.code,ap.code,ap.starts_on,ap.ends_on FROM public.academic_periods ap
 WHERE ap.school_id=p_school AND ap.status='active' ORDER BY ap.starts_on DESC;
END $$;
REVOKE ALL ON FUNCTION public.kabarkelas_my_periods(uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.kabarkelas_my_periods(uuid) TO authenticated;
-- daftar siswa per kelas untuk form penilaian guru
CREATE FUNCTION public.kabarkelas_class_students(p_school uuid,p_class uuid)
RETURNS TABLE(student_id uuid,display_name text,local_student_no text)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE v_actor uuid:=app.g05_actor();
BEGIN
 IF NOT EXISTS(SELECT 1 FROM public.memberships m JOIN public.schools s ON s.id=m.school_id AND s.tenant_id=m.tenant_id AND s.status='active' JOIN public.tenants t ON t.id=m.tenant_id AND t.status='active' WHERE m.school_id=p_school AND m.user_id=v_actor AND m.status='active' AND m.role_code IN('teacher','principal','school_admin')) THEN
  RAISE EXCEPTION 'School unavailable' USING ERRCODE='42501'; END IF;
 RETURN QUERY SELECT s.id,s.display_name,s.local_student_no
 FROM public.students s
 JOIN public.class_student_enrollments e ON e.student_id=s.id AND e.class_id=p_class AND e.status='active'
 WHERE s.school_id=p_school AND s.status='active' ORDER BY s.display_name;
END $$;
REVOKE ALL ON FUNCTION public.kabarkelas_class_students(uuid,uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.kabarkelas_class_students(uuid,uuid) TO authenticated;


-- tenants (foundation_admin only)
CREATE FUNCTION public.kabarkelas_import_tenants(p_rows jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE rec jsonb; v_id uuid; v_results jsonb:='[]';
BEGIN
 IF NOT app.g11_import_allowed() THEN RAISE EXCEPTION 'Import not allowed' USING ERRCODE='42501'; END IF;
 FOR rec IN SELECT value FROM jsonb_array_elements(p_rows) LOOP
  INSERT INTO public.tenants(slug,name,status)
  VALUES(rec->>'slug',rec->>'name','active')
  ON CONFLICT(slug) DO UPDATE SET name=EXCLUDED.name RETURNING id INTO v_id;
  v_results:=v_results||jsonb_build_object('slug',rec->>'slug','tenant_id',v_id);
 END LOOP;
 RETURN v_results;
END $$;
REVOKE ALL ON FUNCTION public.kabarkelas_import_tenants(jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.kabarkelas_import_tenants(jsonb) TO authenticated;

-- students (school-scoped, opsional terpisah dari class)
CREATE FUNCTION public.kabarkelas_import_students(p_rows jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE rec jsonb; v_school uuid; v_id uuid; v_results jsonb:='[]';
BEGIN
 IF NOT app.g11_import_allowed() THEN RAISE EXCEPTION 'Import not allowed' USING ERRCODE='42501'; END IF;
 FOR rec IN SELECT value FROM jsonb_array_elements(p_rows) LOOP
  SELECT id INTO v_school FROM public.schools WHERE code=rec->>'school_code' LIMIT 1;
  IF v_school IS NULL THEN v_results:=v_results||jsonb_build_object('no',rec->>'local_student_no','error','school not found'); CONTINUE; END IF;
  INSERT INTO public.students(tenant_id,school_id,local_student_no,display_name,status)
  SELECT s.tenant_id,v_school,rec->>'local_student_no',rec->>'display_name','active' FROM public.schools s WHERE s.id=v_school
  ON CONFLICT(tenant_id,school_id,local_student_no) DO UPDATE SET display_name=EXCLUDED.display_name RETURNING id INTO v_id;
  IF rec ? 'class_name' AND rec->>'class_name'<>'' THEN
   INSERT INTO public.class_student_enrollments(tenant_id,school_id,class_id,student_id,status)
   SELECT c.tenant_id,c.school_id,c.id,v_id,'active' FROM public.school_classes c
   WHERE c.school_id=v_school AND c.name=rec->>'class_name'
   AND NOT EXISTS(SELECT 1 FROM public.class_student_enrollments e WHERE e.class_id=c.id AND e.student_id=v_id AND e.status='active');
  END IF;
  v_results:=v_results||jsonb_build_object('no',rec->>'local_student_no','student_id',v_id);
 END LOOP;
 RETURN v_results;
END $$;
REVOKE ALL ON FUNCTION public.kabarkelas_import_students(jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.kabarkelas_import_students(jsonb) TO authenticated;

COMMIT;
