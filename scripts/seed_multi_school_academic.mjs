// KabarKelas multi-school academic content — fase 2 fixture.
// Menambah: guru per mapel (kurikulum SD), 4 ortuwali per kelas (2 siswa per ortu),
// mapel lengkap SD, penilaian + nilai published per siswa, kehadiran, aturan EWS,
// dan pipeline rapor sampai released — semua untuk uji tampilan & EWS.
//
// Pemakaian: node scripts/seed_multi_school_academic.mjs [--verify]
// Idempotent: aman dijalankan berulang.

import { readFileSync } from 'node:fs';
import { homedir } from 'node:os';
import { join } from 'node:path';
import pg from 'pg';

const env = Object.fromEntries(
  readFileSync(join(homedir(), '.kabarkelas', 'secrets.env'), 'utf8').split('\n')
    .filter(l => /^[A-Z_]+=/.test(l))
    .map(l => { const i = l.indexOf('='); return [l.slice(0, i), l.slice(i + 1).trim()]; })
);
const client = new pg.Client({
  host: env.SUPABASE_DB_HOST, port: +env.SUPABASE_DB_PORT,
  user: env.SUPABASE_DB_USER, password: env.SUPABASE_DB_PASSWORD,
  database: 'postgres', ssl: { rejectUnauthorized: false },
});

const TENANT = 'aa11bb22-0001-4a10-9a10-000000000001';
const SCHOOL_A = 'aa11bb22-0001-4a10-9a10-0000000000a1';
const SCHOOL_B = 'aa11bb22-0001-4a10-9a10-0000000000b1';
const PERIOD_CODE = 'Ganjil 2026/2027';
const PASSWORD = 'PilotYayasan2026!';
const uid = n => `aa11bb22-0003-4a10-9a10-${String(n).padStart(12, '0')}`;
const CLASSES = { A1: 'Kelas 4A', A2: 'Kelas 4B', B1: 'Kelas 5A' };
const CLASS_SCHOOL = { A1: SCHOOL_A, A2: SCHOOL_A, B1: SCHOOL_B };
const CLASS_PREFIX = { A1: 'NSA', A2: 'NSB', B1: 'NTB' };
const HOMEROOM = { A1: 5, A2: 6, B1: 7 }; // guru wali kelas
const PRINCIPAL = { [SCHOOL_A]: 2, [SCHOOL_B]: 3 }; // kepala sekolah per sekolah

// mapel kurikulum SD: [code, name]
const SUBJECTS = [
  ['PPKN', 'Pendidikan Pancasila dan Kewarganegaraan'],
  ['BIN', 'Bahasa Indonesia'],
  ['MTK', 'Matematika'],
  ['IPA', 'Ilmu Pengetahuan Alam'],
  ['IPS', 'Ilmu Pengetahuan Sosial'],
  ['BING', 'Bahasa Inggris'],
  ['PJOK', 'Pendidikan Jasmani, Olahraga, dan Kesehatan'],
  ['SBDP', 'Seni Budaya dan Prakarya'],
];
// mapel -> guru per kelas: [classKey, subjectCode, teacherN]
const SUBJECT_TEACHERS = [
  ['A1', 'PPKN', 11], ['A1', 'BIN', 12], ['A1', 'MTK', 5],  ['A1', 'IPA', 13],
  ['A1', 'IPS', 14], ['A1', 'BING', 15], ['A1', 'PJOK', 16], ['A1', 'SBDP', 17],
  ['A2', 'PPKN', 11], ['A2', 'BIN', 12], ['A2', 'MTK', 6],  ['A2', 'IPA', 13],
  ['A2', 'IPS', 14], ['A2', 'BING', 15], ['A2', 'PJOK', 16], ['A2', 'SBDP', 17],
  ['B1', 'PPKN', 18], ['B1', 'BINB', 19], ['B1', 'MTKB', 7],  ['B1', 'IPA', 20],
  ['B1', 'IPS', 14], ['B1', 'BING', 15], ['B1', 'PJOK', 16], ['B1', 'SBDP', 17],
];
// Sekolah B butuh kode mapel berbeda utk MTK & BIN (kode unik per sekolah)
const SUBJECTS_B_EXTRA = [
  ['MTKB', 'Matematika'],
  ['BINB', 'Bahasa Indonesia'],
];
// guru baru: n 11..20 -> email/nama/sekolah
const NEW_TEACHERS = [
  [11, 'pilot.guru-ppkn@kabarkelas.dev', 'Guru PPKn', SCHOOL_A],
  [12, 'pilot.guru-bin@kabarkelas.dev', 'Guru Bahasa Indonesia', SCHOOL_A],
  [13, 'pilot.guru-ipa@kabarkelas.dev', 'Guru IPA', SCHOOL_A],
  [14, 'pilot.guru-ips@kabarkelas.dev', 'Guru IPS', SCHOOL_A],
  [15, 'pilot.guru-bing@kabarkelas.dev', 'Guru Bahasa Inggris', SCHOOL_A],
  [16, 'pilot.guru-pjok@kabarkelas.dev', 'Guru PJOK', SCHOOL_A],
  [17, 'pilot.guru-sbdp@kabarkelas.dev', 'Guru SBdP', SCHOOL_A],
  [18, 'pilot.guru-b-ppkn@kabarkelas.dev', 'Guru PPKn B', SCHOOL_B],
  [19, 'pilot.guru-b-bin@kabarkelas.dev', 'Guru BIN B', SCHOOL_B],
  [20, 'pilot.guru-b-ipa@kabarkelas.dev', 'Guru IPA B', SCHOOL_B],
];
// ortuwali baru: n 21..28 -> [email, nama, sekolah, classKey]
const NEW_GUARDIANS = [
  [21, 'pilot.ortu-a1@kabarkelas.dev', 'Ortu Kelas 4A', SCHOOL_A, 'A1'],
  [22, 'pilot.ortu-a2@kabarkelas.dev', 'Ortu Kelas 4B', SCHOOL_A, 'A2'],
  [23, 'pilot.ortu-b1a@kabarkelas.dev', 'Ortu Kelas 5A-1', SCHOOL_B, 'B1'],
  [24, 'pilot.ortu-b1b@kabarkelas.dev', 'Ortu Kelas 5A-2', SCHOOL_B, 'B1'],
];
// tiap ortu mengampu 2 siswa: index dalam prefix (1..35) -> no urut siswa ke-2*idx-1,2*idx
const GUARDIAN_STUDENTS = { 21: [1, 2], 22: [3, 4], 23: [5, 6], 24: [7, 8] };

const ASSESSMENT_TITLES = ['UH1', 'UH2', 'PTS'];
const LOW_STUDENTS = { A1: [3, 7, 12], A2: [5, 9], B1: [2, 11, 15] }; // siswa berisiko EWS akademik
const ABSENT_STUDENTS = { A1: [4, 8], A2: [6], B1: [3, 10] };        // siswa berisiko EWS kehadiran

const q = s => `'${String(s).replace(/'/g, "''")}'`;

// deterministic PRNG (mulberry32)
function rng(seed) { let t = seed >>> 0; return () => { t += 0x6D2B79F5; let r = Math.imul(t ^ t >>> 15, 1 | t); r ^= r + Math.imul(r ^ r >>> 7, 61 | r); return ((r ^ r >>> 14) >>> 0) / 4294967296; }; }
function scoreFor(classKey, subjectCode, studentIdx, assessmentIdx) {
  const r = rng(classKey.charCodeAt(0) * 1000 + classKey.charCodeAt(1) * 100 + subjectCode.charCodeAt(0) * 10 + studentIdx * 7 + assessmentIdx * 13);
  const low = (LOW_STUDENTS[classKey] ?? []).includes(studentIdx);
  const v = low ? 52 + r() * 16 : 72 + r() * 27; // low: 52-68, normal: 72-99
  return Math.round(v * 2) / 2;
}

function buildSql() {
  const s = [];
  // --- users baru (guru mapel + ortu) ---
  const allUsers = [
    ...NEW_TEACHERS.map(([n, email, meta, school]) => ({ n, email, meta, role: 'teacher', school })),
    ...NEW_GUARDIANS.map(([n, email, meta, school]) => ({ n, email, meta, role: 'guardian', school })),
  ];
  const values = allUsers.map(u => `(${u.n},${q(u.email)},${q(u.meta)})`).join(',');
  s.push(`DO $$
DECLARE rec record; v_uid uuid; v_auth uuid; v_email text;
BEGIN
  FOR rec IN SELECT * FROM (VALUES ${values}) AS x(n,email,display_name) LOOP
    v_auth := 'aa11bb22-0003-4a10-9a10-' || lpad(rec.n::text,12,'0');
    v_email := rec.email;
    IF EXISTS(SELECT 1 FROM auth.users WHERE email=v_email) THEN
      SELECT id INTO v_uid FROM auth.users WHERE email=v_email;
    ELSE
      INSERT INTO auth.users(instance_id,id,aud,role,email,encrypted_password,
        email_confirmed_at,invited_at,confirmation_token,recovery_token,
        email_change_token_new,email_change,last_sign_in_at,
        raw_app_meta_data,raw_user_meta_data,is_super_admin,created_at,updated_at,
        phone,phone_confirmed_at,phone_change,phone_change_token,
        email_change_token_current,email_change_confirm_status,
        reauthentication_token,is_sso_user)
      VALUES('00000000-0000-0000-0000-000000000000',v_auth,
        'authenticated','authenticated',v_email,
        extensions.crypt(${q(PASSWORD)},extensions.gen_salt('bf')),
        now(),now(),'','','','',NULL,
        '{"provider":"email","providers":["email"]}'::jsonb,
        jsonb_build_object('display_name',rec.display_name,'email_verified',true),
        false,now(),now(),NULL,NULL,'','','',0,'',false);
      INSERT INTO auth.identities(id,provider_id,user_id,identity_data,provider,last_sign_in_at,created_at,updated_at)
      VALUES(gen_random_uuid(),v_auth::text,v_auth,
        jsonb_build_object('sub',v_auth::text,'email',v_email,'email_verified',true,'phone_verified',false),
        'email',now(),now(),now());
      v_uid := v_auth;
    END IF;
    IF NOT EXISTS(SELECT 1 FROM public.users WHERE id=v_uid) THEN
      INSERT INTO public.users(id,auth_subject,email) VALUES(v_uid,v_uid::text,v_email);
    END IF;
  END LOOP;
END $$`);
  // memberships
  const memVals = allUsers.map(u => `('${TENANT}'::uuid,'${u.school}'::uuid,'${uid(u.n)}'::uuid,${q(u.role)},'active')`).join(',');
  s.push(`INSERT INTO public.memberships(tenant_id,school_id,user_id,role_code,status)
SELECT v.tenant_id,v.school_id,v.user_id,v.role_code,'active' FROM (VALUES ${memVals}) v(tenant_id,school_id,user_id,role_code)
WHERE NOT EXISTS(SELECT 1 FROM public.memberships m WHERE m.user_id=v.user_id AND m.role_code=v.role_code AND m.school_id=v.school_id AND m.status='active')`);

  // --- subjects tambahan ---
  // Sekolah A: semua SUBJECTS (MTK/BIN/IPA sudah ada dari fase 1)
  // Sekolah B: SUBJECTS tanpa MTK/BIN + MTKB/BINB + IPA (IPA sudah ada)
  const subjectsA = SUBJECTS.filter(([c]) => !['MTK', 'BIN'].includes(c));
  const subjectsB = [...SUBJECTS.filter(([c]) => !['MTK', 'BIN'].includes(c)), ...SUBJECTS_B_EXTRA];
  for (const [code, name] of subjectsA) {
    s.push(`INSERT INTO public.subjects(tenant_id,school_id,code,name) VALUES('${TENANT}','${SCHOOL_A}',${q(code)},${q(name)}) ON CONFLICT(tenant_id,school_id,code) DO NOTHING`);
  }
  for (const [code, name] of subjectsB) {
    s.push(`INSERT INTO public.subjects(tenant_id,school_id,code,name) VALUES('${TENANT}','${SCHOOL_B}',${q(code)},${q(name)}) ON CONFLICT(tenant_id,school_id,code) DO NOTHING`);
  }
  // Samakan nama mapel lama dengan kurikulum
  s.push(`UPDATE public.subjects SET name='Matematika' WHERE tenant_id='${TENANT}' AND code IN ('MTK','MTKB') AND name<>'Matematika'`);
  s.push(`UPDATE public.subjects SET name='Bahasa Indonesia' WHERE tenant_id='${TENANT}' AND code IN ('BIN','BINB') AND name<>'Bahasa Indonesia'`);
  s.push(`UPDATE public.subjects SET name='Ilmu Pengetahuan Alam' WHERE tenant_id='${TENANT}' AND code='IPA' AND name='IPA'`);

  // --- teacher_class_assignments untuk guru mapel ---
  for (const [classKey, subjCode, teacherN] of SUBJECT_TEACHERS) {
    const school = CLASS_SCHOOL[classKey];
    const className = CLASSES[classKey];
    s.push(`INSERT INTO public.teacher_class_assignments(tenant_id,school_id,class_id,teacher_user_id,status)
SELECT '${TENANT}','${school}',c.id,'${uid(teacherN)}','active' FROM public.school_classes c
WHERE c.school_id='${school}' AND c.name=${q(className)}
  AND NOT EXISTS(SELECT 1 FROM public.teacher_class_assignments t WHERE t.class_id=c.id AND t.teacher_user_id='${uid(teacherN)}' AND t.status='active')`);
  }

  // --- lesson_schedules untuk mapel baru (1x/minggu per mapel per kelas) ---
  let wd = 1;
  for (const [classKey, subjCode, teacherN] of SUBJECT_TEACHERS) {
    const school = CLASS_SCHOOL[classKey];
    const className = CLASSES[classKey];
    const weekday = (wd++ % 5) + 1;
    s.push(`INSERT INTO public.lesson_schedules(tenant_id,school_id,class_id,subject_id,teacher_user_id,weekday,start_time,end_time,room,academic_year)
SELECT '${TENANT}','${school}',c.id,sj.id,'${uid(teacherN)}',${weekday},'07:00','07:35','R.${classKey}','${'2026/2027'}'
FROM public.school_classes c, public.subjects sj
WHERE c.school_id='${school}' AND c.name=${q(className)} AND sj.school_id='${school}' AND sj.code=${q(subjCode)}
  AND NOT EXISTS(SELECT 1 FROM public.lesson_schedules ls WHERE ls.class_id=c.id AND ls.subject_id=sj.id AND ls.weekday=${weekday} AND ls.status='active')`);
  }

  // --- assessments + student_grades + snapshots + releases ---
  // assessment per (class, subject, title): 3 kelas x 8 mapel x 3 judul = 72 assessments
  // grades: 35 siswa per kelas → 72*35 = 2520 grade rows
  // Dibangun sebagai satu DO block besar agar lookup id mudah.
  s.push(`DO $$
DECLARE
  v_class record; v_subj record; v_student record;
  v_assess uuid; v_grade uuid;
  v_principal_n int; v_principal uuid; v_score numeric; v_payload jsonb;
  v_period uuid; v_classkey text; v_idx int; v_aidx int; v_title text; v_full_title text;
  v_student_idx int; v_subj_code text;
  low_list int[];
BEGIN
  FOR v_class IN SELECT c.id,c.name,c.school_id FROM public.school_classes c WHERE c.tenant_id='${TENANT}' LOOP
    v_classkey := CASE WHEN v_class.name='Kelas 4A' THEN 'A1' WHEN v_class.name='Kelas 4B' THEN 'A2' ELSE 'B1' END;
    low_list := CASE v_classkey WHEN 'A1' THEN ARRAY[3,7,12] WHEN 'A2' THEN ARRAY[5,9] ELSE ARRAY[2,11,15] END;
    v_principal_n := CASE WHEN v_class.school_id='${SCHOOL_B}' THEN 3 ELSE 2 END;
    v_principal := 'aa11bb22-0003-4a10-9a10-' || lpad(v_principal_n::text,12,'0');
    SELECT id INTO v_period FROM public.academic_periods WHERE school_id=v_class.school_id AND code=${q(PERIOD_CODE)};
    FOR v_subj IN SELECT sj.id,sj.code,sj.name FROM public.subjects sj WHERE sj.school_id=v_class.school_id LOOP
      v_subj_code := v_subj.code;
      FOR v_aidx IN 1..3 LOOP
        v_title := (ARRAY['UH1','UH2','PTS'])[v_aidx];
        v_full_title := v_title || ' ' || v_subj.name || ' ' || v_class.name;
        SELECT id INTO v_assess FROM public.assessments a
        WHERE a.class_id=v_class.id AND a.subject_id=v_subj.id AND a.title=v_full_title;
        IF v_assess IS NULL THEN
          INSERT INTO public.assessments(tenant_id,school_id,class_id,subject_id,period_id,title,max_score,status,published_at,created_by)
          VALUES('${TENANT}',v_class.school_id,v_class.id,v_subj.id,v_period,
            v_full_title,100,'published',now() - interval '10 days',
            COALESCE(
              (SELECT tc.teacher_user_id FROM public.teacher_class_assignments tc
               JOIN public.lesson_schedules ls ON ls.class_id=tc.class_id AND ls.subject_id=v_subj.id AND ls.teacher_user_id=tc.teacher_user_id
               WHERE tc.class_id=v_class.id AND tc.status='active' LIMIT 1),
              (SELECT tc2.teacher_user_id FROM public.teacher_class_assignments tc2 WHERE tc2.class_id=v_class.id AND tc2.status='active' LIMIT 1),
              v_principal))
          RETURNING id INTO v_assess;
        END IF;
        v_idx := 0;
        FOR v_student IN SELECT s.id,s.display_name,s.local_student_no FROM public.students s
          WHERE s.school_id=v_class.school_id AND s.status='active' ORDER BY s.local_student_no LOOP
          v_idx := v_idx + 1;
          v_student_idx := v_idx;
          v_score := 55 + ((v_student_idx * 37 + v_aidx * 11 + ascii(left(v_subj_code,1)) * 3 + ascii(left(v_classkey,1)) * 5) % 45)::numeric;
          IF v_student_idx = ANY(low_list) AND v_aidx >= 2 THEN v_score := 45 + (v_student_idx % 20)::numeric; END IF;
          SELECT id INTO v_grade FROM public.student_grades g WHERE g.assessment_id=v_assess AND g.student_id=v_student.id;
          IF v_grade IS NULL THEN
            INSERT INTO public.student_grades(tenant_id,school_id,assessment_id,student_id,score,status,
              submitted_by,submitted_at,approved_by,approved_at,published_by,published_at,revision)
            VALUES('${TENANT}',v_class.school_id,v_assess,v_student.id,v_score,'published',
              (SELECT tc.teacher_user_id FROM public.teacher_class_assignments tc WHERE tc.class_id=v_class.id AND tc.status='active' LIMIT 1),
              now() - interval '10 days',
              v_principal, now() - interval '9 days',
              v_principal, now() - interval '8 days', 2)
            RETURNING id INTO v_grade;
            v_payload := jsonb_build_object('grade_id',v_grade,'student_id',v_student.id,'student_name',v_student.display_name,
              'subject_name',v_subj.name,'assessment_title',v_full_title,
              'score',v_score,'max_score',100,'grade_status','published','revision',2,
              'submitted_by',(SELECT tc.teacher_user_id FROM public.teacher_class_assignments tc WHERE tc.class_id=v_class.id AND tc.status='active' LIMIT 1),
              'approved_by',v_principal,'published_by',v_principal,'published_at',now() - interval '8 days');
            INSERT INTO public.academic_publication_snapshots(tenant_id,school_id,resource_type,resource_id,version,payload,payload_sha256,published_by,published_at)
            VALUES('${TENANT}',v_class.school_id,'grade',v_grade,2,v_payload,
              encode(sha256(convert_to(v_payload::text,'UTF8')),'hex'),v_principal,now() - interval '8 days');
            v_payload := jsonb_build_object('student_id',v_student.id,'assessment_id',v_assess,
              'effective_score',v_score,'max_score',100,'attempt_count',1,
              'policy_mode','best_score','parent_visibility','after_release','version',1);
            INSERT INTO public.assessment_releases(tenant_id,school_id,grade_id,version,status,policy_mode,effective_score,snapshot,payload_sha256,finalized_by,finalized_at,released_at)
            VALUES('${TENANT}',v_class.school_id,v_grade,1,'released','best_score',v_score,v_payload,
              encode(sha256(convert_to(v_payload::text,'UTF8')),'hex'),v_principal,now() - interval '8 days',now() - interval '8 days');
          END IF;
        END LOOP;
      END LOOP;
    END LOOP;
  END LOOP;
END $$`);

  // --- assessment_policies per school ---
  for (const school of [SCHOOL_A, SCHOOL_B]) {
    s.push(`INSERT INTO public.assessment_policies(tenant_id,school_id,version,mode,cap_percent,parent_visibility,is_active)
SELECT '${TENANT}','${school}',1,'best_score',NULL,'after_release',true
WHERE NOT EXISTS(SELECT 1 FROM public.assessment_policies WHERE school_id='${school}' AND is_active)`);
  }

  // --- kehadiran: 8 sesi published per kelas ---
  for (const [classKey, className] of Object.entries(CLASSES)) {
    const school = CLASS_SCHOOL[classKey];
    const absent = ABSENT_STUDENTS[classKey] ?? [];
    for (let d = 0; d < 8; d++) {
      const date = `2026-11-${String(19 - d * 2).padStart(2, '0')}`;
      s.push(`DO $$
DECLARE v_sess uuid; v_class uuid; v_period uuid; v_stu record; v_code text; v_absent int[] := ARRAY${JSON.stringify(absent)}::int[];
BEGIN
  SELECT id INTO v_class FROM public.school_classes WHERE school_id='${school}' AND name=${q(className)};
  SELECT id INTO v_period FROM public.academic_periods WHERE school_id='${school}' AND code=${q(PERIOD_CODE)};
  IF NOT EXISTS(SELECT 1 FROM public.attendance_sessions WHERE class_id=v_class AND session_date='${date}') THEN
    INSERT INTO public.attendance_sessions(tenant_id,school_id,class_id,period_id,session_date,state,published_at)
    VALUES('${TENANT}','${school}',v_class,v_period,'${date}','published',now());
  END IF;
  SELECT id INTO v_sess FROM public.attendance_sessions WHERE class_id=v_class AND session_date='${date}';
  FOR v_stu IN SELECT s.id,s.local_student_no FROM public.students s WHERE s.school_id='${school}' AND s.status='active' LOOP
    IF (substring(v_stu.local_student_no from '[0-9]+$')::int) = ANY(v_absent) AND ${d} % 2 = 0 THEN v_code := 'absent'; ELSE v_code := 'present'; END IF;
    INSERT INTO public.attendance_records(tenant_id,school_id,session_id,student_id,attendance_code)
    SELECT '${TENANT}','${school}',v_sess,v_stu.id,v_code
    WHERE NOT EXISTS(SELECT 1 FROM public.attendance_records ar WHERE ar.session_id=v_sess AND ar.student_id=v_stu.id);
  END LOOP;
END $$`);
    }
  }

  // --- ews_rules aktif per sekolah ---
  for (const school of [SCHOOL_A, SCHOOL_B]) {
    s.push(`INSERT INTO public.ews_rules(tenant_id,school_id,rule_key,version,state,parameters)
SELECT '${TENANT}','${school}','academic_low_average',1,'active','{"threshold_percent":70,"minimum_assessments":2}'::jsonb
WHERE NOT EXISTS(SELECT 1 FROM public.ews_rules WHERE school_id='${school}' AND rule_key='academic_low_average' AND state='active')`);
    s.push(`INSERT INTO public.ews_rules(tenant_id,school_id,rule_key,version,state,parameters)
SELECT '${TENANT}','${school}','attendance_unexcused',1,'active','{"absent_threshold":3,"lookback_days":30}'::jsonb
WHERE NOT EXISTS(SELECT 1 FROM public.ews_rules WHERE school_id='${school}' AND rule_key='attendance_unexcused' AND state='active')`);
  }

  // --- school_report_reviews released + snapshots per siswa ---
  for (const [classKey, className] of Object.entries(CLASSES)) {
    const school = CLASS_SCHOOL[classKey];
    const homeroom = HOMEROOM[classKey];
    s.push(`DO $$
DECLARE v_class uuid; v_period uuid; v_review uuid; v_principal uuid; v_student record; v_payload jsonb;
BEGIN
  SELECT id INTO v_class FROM public.school_classes WHERE school_id='${school}' AND name=${q(className)};
  SELECT id INTO v_period FROM public.academic_periods WHERE school_id='${school}' AND code=${q(PERIOD_CODE)};
  SELECT user_id INTO v_principal FROM public.memberships WHERE school_id='${school}' AND role_code='principal' AND status='active' LIMIT 1;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_principal::text, 'role','authenticated')::text, true);
  INSERT INTO public.school_report_reviews(tenant_id,school_id,class_id,period_id,version,status,homeroom_user_id,revision,signed_by,signed_at,released_at)
  SELECT '${TENANT}','${school}',v_class,v_period,1,'released','${uid(homeroom)}',2,v_principal,now(),now()
  WHERE NOT EXISTS(SELECT 1 FROM public.school_report_reviews WHERE class_id=v_class AND period_id=v_period AND status='released');
  SELECT id INTO v_review FROM public.school_report_reviews WHERE class_id=v_class AND period_id=v_period AND status='released' ORDER BY version DESC LIMIT 1;
  FOR v_student IN SELECT s.id,s.display_name FROM public.class_student_enrollments e JOIN public.students s ON s.id=e.student_id AND s.school_id=e.school_id WHERE e.class_id=v_class AND e.status='active' AND s.status='active' LOOP
    SELECT jsonb_build_object('student_id',v_student.id,'student_name',v_student.display_name,'report_id',v_review,'report_version',1,'grades',
      COALESCE((SELECT jsonb_agg(jsonb_build_object('subject',sub.name,'assessment',a.title,'score',g.score) ORDER BY sub.name,a.title)
      FROM public.student_grades g JOIN public.assessments a ON a.id=g.assessment_id AND a.tenant_id=g.tenant_id AND a.school_id=g.school_id
      JOIN public.subjects sub ON sub.id=a.subject_id AND sub.tenant_id=a.tenant_id AND sub.school_id=a.school_id
      WHERE a.class_id=v_class AND a.period_id=v_period AND g.student_id=v_student.id AND g.status='published'),'[]'::jsonb))
    INTO v_payload;
    INSERT INTO public.school_report_snapshots(tenant_id,school_id,report_id,student_id,version,payload,payload_sha256,signed_by,signed_at)
    SELECT '${TENANT}','${school}',v_review,v_student.id,1,v_payload,
      encode(sha256(convert_to(v_payload::text,'UTF8')),'hex'),v_principal,now()
    WHERE NOT EXISTS(SELECT 1 FROM public.school_report_snapshots WHERE report_id=v_review AND student_id=v_student.id AND version=1);
  END LOOP;
END $$`);
  }

  // --- guardian_student_links untuk ortu baru ---
  for (const [n, , , school, classKey] of NEW_GUARDIANS) {
    const idxs = GUARDIAN_STUDENTS[n];
    const prefix = CLASS_PREFIX[classKey];
    for (const idx of idxs) {
      const no = `${prefix}-${String(idx).padStart(3, '0')}`;
      const verifiedBy = uid(CLASS_SCHOOL[classKey] === SCHOOL_A ? 2 : 3);
      s.push(`INSERT INTO public.guardian_student_links(tenant_id,school_id,student_id,guardian_user_id,relationship_code,verification_status,verified_by,verified_at)
SELECT '${TENANT}',e.school_id,e.student_id,'${uid(n)}','parent','verified','${verifiedBy}'::uuid,now()
FROM public.class_student_enrollments e JOIN public.students st ON st.id=e.student_id AND st.school_id=e.school_id
WHERE e.school_id='${school}' AND e.status='active' AND st.local_student_no=${q(no)}
  AND NOT EXISTS(SELECT 1 FROM public.guardian_student_links g WHERE g.guardian_user_id='${uid(n)}' AND g.student_id=e.student_id AND g.verification_status='verified')`);
    }
  }

  return s;
}

const VERIFY = `
SELECT 'users_new' k, count(*)::text v FROM public.users WHERE id::text LIKE 'aa11bb22-0003%' AND id::text >= 'aa11bb22-0003-4a10-9a10-000000000011'
UNION ALL SELECT 'subjects', count(*)::text FROM public.subjects WHERE tenant_id='${TENANT}'
UNION ALL SELECT 'assessments', count(*)::text FROM public.assessments WHERE tenant_id='${TENANT}'
UNION ALL SELECT 'student_grades', count(*)::text FROM public.student_grades WHERE tenant_id='${TENANT}'
UNION ALL SELECT 'grades_published', count(*)::text FROM public.student_grades WHERE tenant_id='${TENANT}' AND status='published'
UNION ALL SELECT 'snapshots', count(*)::text FROM public.academic_publication_snapshots WHERE tenant_id='${TENANT}'
UNION ALL SELECT 'releases', count(*)::text FROM public.assessment_releases WHERE tenant_id='${TENANT}'
UNION ALL SELECT 'attendance_sessions', count(*)::text FROM public.attendance_sessions WHERE tenant_id='${TENANT}' AND state='published'
UNION ALL SELECT 'attendance_records', count(*)::text FROM public.attendance_records WHERE tenant_id='${TENANT}'
UNION ALL SELECT 'ews_rules', count(*)::text FROM public.ews_rules WHERE tenant_id='${TENANT}' AND state='active'
UNION ALL SELECT 'report_reviews', count(*)::text FROM public.school_report_reviews WHERE tenant_id='${TENANT}' AND status='released'
UNION ALL SELECT 'report_snapshots', count(*)::text FROM public.school_report_snapshots WHERE tenant_id='${TENANT}'
UNION ALL SELECT 'guardian_links_total', count(*)::text FROM public.guardian_student_links WHERE tenant_id='${TENANT}' AND verification_status='verified'
ORDER BY k`;

async function main() {
  const verifyOnly = process.argv.includes('--verify');
  await client.connect();
  try {
    if (!verifyOnly) {
      const stmts = buildSql().map(x => x.trim()).filter(Boolean);
      let st = '';
      await client.query('BEGIN');
      try {
        for (const stmt of stmts) { st = stmt.slice(0, 120); await client.query(stmt); }
        await client.query('COMMIT');
        console.log(`Seed academic selesai: ${stmts.length} statements.`);
      } catch (e) {
        await client.query('ROLLBACK');
        console.error('Statement gagal:', st); throw e;
      }
    }
    const res = await client.query(VERIFY);
    console.log('\nVerifikasi:');
    for (const r of res.rows) console.log(`  ${r.k.padEnd(24)} ${r.v}`);
  } finally { await client.end(); }
}
main().catch(e => { console.error(e); process.exit(1); });
