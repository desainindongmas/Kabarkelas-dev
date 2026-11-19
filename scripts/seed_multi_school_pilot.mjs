// KabarKelas multi-school pilot fixture — 1 yayasan, 2 sekolah.
// Fixture isolasi lintas sekolah: tenant baru, 2 sekolah, 2 kepala sekolah,
// 4 guru (2 di sekolah A, 1 di sekolah B, 1 lintas A+B), 3 kelas x 35 siswa,
// 1 admin yayasan, konten G10 per sekolah untuk uji kebocoran data.
//
// Pemakaian:
//   node scripts/seed_multi_school_pilot.mjs           # seed (idempotent)
//   node scripts/seed_multi_school_pilot.mjs --verify  # verifikasi saja
//
// Kredensial dibaca dari ~/.kabarkelas/secrets.env (SUPABASE_DB_*).
// Semua data sintetis; password pilot: PilotYayasan2026! (lihat docs/MULTI-SCHOOL-pilot.md).

import { readFileSync } from 'node:fs';
import { homedir } from 'node:os';
import { join } from 'node:path';
import pg from 'pg';

const envPath = join(homedir(), '.kabarkelas', 'secrets.env');
const env = Object.fromEntries(
  readFileSync(envPath, 'utf8').split('\n')
    .filter(l => /^[A-Z_]+=/.test(l))
    .map(l => { const i = l.indexOf('='); return [l.slice(0, i), l.slice(i + 1).trim()]; })
);
for (const k of ['SUPABASE_DB_HOST', 'SUPABASE_DB_PORT', 'SUPABASE_DB_USER', 'SUPABASE_DB_PASSWORD']) {
  if (!env[k]) throw new Error(`secrets.env missing ${k}`);
}

const client = new pg.Client({
  host: env.SUPABASE_DB_HOST,
  port: Number(env.SUPABASE_DB_PORT),
  user: env.SUPABASE_DB_USER,
  password: env.SUPABASE_DB_PASSWORD,
  database: 'postgres',
  ssl: { rejectUnauthorized: false },
});

// ---------- Fixture constants ----------
const TENANT = 'aa11bb22-0001-4a10-9a10-000000000001';
const TENANT_SLUG = 'yayasan-nusantara';
const TENANT_NAME = 'Yayasan Nusantara Cemerlang';
const SCHOOL_A = 'aa11bb22-0001-4a10-9a10-0000000000a1'; // SD Nusantara 1
const SCHOOL_B = 'aa11bb22-0001-4a10-9a10-0000000000b1'; // SD Nusantara 2
const PASSWORD = 'PilotYayasan2026!';
const ACADEMIC_YEAR = '2026/2027';
const PERIOD_CODE = 'Ganjil 2026/2027';

const SCHOOL_A_NAME = 'SD Nusantara 1';
const SCHOOL_B_NAME = 'SD Nusantara 2';

// users: n -> [email, display_name, memberships[[schoolId|null,'role']...]]
const USERS = [
  [1, 'pilot.foundasi@kabarkelas.dev', 'Admin Yayasan Pilot', [[null, 'foundation_admin']]],
  [2, 'pilot.kepala1@kabarkelas.dev', 'Kepala SD Nusantara 1', [[SCHOOL_A, 'principal']]],
  [3, 'pilot.kepala2@kabarkelas.dev', 'Kepala SD Nusantara 2', [[SCHOOL_B, 'principal']]],
  [4, 'pilot.admin1@kabarkelas.dev', 'Admin SD Nusantara 1', [[SCHOOL_A, 'school_admin']]],
  [5, 'pilot.guru-a1@kabarkelas.dev', 'Guru A1 Nusantara 1', [[SCHOOL_A, 'teacher']]],
  [6, 'pilot.guru-a2@kabarkelas.dev', 'Guru A2 Nusantara 1', [[SCHOOL_A, 'teacher']]],
  [7, 'pilot.guru-b1@kabarkelas.dev', 'Guru B1 Nusantara 2', [[SCHOOL_B, 'teacher']]],
  [8, 'pilot.guru-ab@kabarkelas.dev', 'Guru AB Lintas', [[SCHOOL_A, 'teacher'], [SCHOOL_B, 'teacher']]],
  [9, 'pilot.ortu-a@kabarkelas.dev', 'Orang Tua Pilot A', [[SCHOOL_A, 'guardian']]],
  [10, 'pilot.ortu-b@kabarkelas.dev', 'Orang Tua Pilot B', [[SCHOOL_B, 'guardian']]],
];
// public.users.id == auth.users.id == deterministic uuid (…0003 prefix)
const uid = n => `aa11bb22-0003-4a10-9a10-${String(n).padStart(12, '0')}`;

// classes: [schoolId, key, name, studentCount, noPrefix]
const CLASSES = [
  [SCHOOL_A, 'A1', 'Kelas 4A', 35, 'NSA'],
  [SCHOOL_A, 'A2', 'Kelas 4B', 35, 'NSB'],
  [SCHOOL_B, 'B1', 'Kelas 5A', 35, 'NTB'],
];
const SUBJECTS = [['MTK', 'Matematika'], ['IPA', 'IPA'], ['BIN', 'Bahasa Indonesia']];

// teacher_class_assignments: [classKey, teacherUserN]
const CLASS_TEACHERS = [
  ['A1', 5], ['A1', 8], ['A2', 6], ['A2', 8], ['B1', 7], ['B1', 8],
];
// lesson_schedules: [classKey, subjectCode, teacherN, weekday, start, end, room]
const SCHEDULES = [
  ['A1', 'MTK', 5, 1, '07:00', '07:35', 'R.4A'],
  ['A1', 'IPA', 8, 2, '08:00', '08:35', 'R.4A'],
  ['A2', 'BIN', 6, 3, '09:00', '09:35', 'R.4B'],
  ['B1', 'MTK', 8, 1, '07:00', '07:35', 'R.5A'],
  ['B1', 'IPA', 7, 4, '10:00', '10:35', 'R.5A'],
];
// announcements: [schoolId|null(both), title, body, audience_role|null, audience_classKey|null, createdByN]
const ANNOUNCEMENTS = [
  [SCHOOL_A, 'Pengumuman SD Nusantara 1', 'Halo warga NSD1 — data sintetis pilot.', null, null, 2],
  [SCHOOL_B, 'Pengumuman SD Nusantara 2', 'Halo warga NSD2 — data sintetis pilot.', null, null, 3],
];
// homework per school: [schoolId, classKey, subjectCode, teacherN, title]
const HOMEWORK = [
  [SCHOOL_A, 'A1', 'MTK', 5, 'Tugas Matematika 4A #1'],
  [SCHOOL_A, 'A2', 'BIN', 6, 'Tugas Bahasa 4B #1'],
  [SCHOOL_B, 'B1', 'IPA', 7, 'Tugas IPA 5A #1'],
];

const FIRST_NAMES = [
  'Aisyah','Bima','Citra','Dimas','Elang','Fitriani','Gilang','Hana','Ilham','Jihan',
  'Kirana','Lukman','Maya','Naufal','Oki','Putri','Rafi','Sinta','Taufik','Umaira',
  'Vino','Wulan','Yusuf','Zahra','Arka','Bella','Cahya','Dewi','Eka','Fajar',
  'Gita','Harun','Intan','Joko','Kartika',
];
const LAST_NAMES = ['Pratama','Sari','Ramadhan','Lestari','Mahendra','Safitri','Fadillah','Amelia','Dewi','Hakim'];

function studentNo(cls, i) { return `${cls[4]}-${String(i).padStart(3, '0')}`; }
function studentName(cls, i) {
  return `${FIRST_NAMES[(i * 7 + cls[1].charCodeAt(1)) % FIRST_NAMES.length]} ${LAST_NAMES[(i * 3 + cls[1].charCodeAt(0)) % LAST_NAMES.length]}`;
}
const classKey = (schoolId, name) => CLASSES.find(c => c[0] === schoolId && c[2] === name)?.[1];

// ---------- SQL builder ----------
const q = s => `'${String(s).replace(/'/g, "''")}'`;

function buildSeedSql() {
  const stmts = [];
  stmts.push(`BEGIN`);
  stmts.push(`INSERT INTO public.tenants(id,slug,name,status) VALUES('${TENANT}',${q(TENANT_SLUG)},${q(TENANT_NAME)},'active') ON CONFLICT(slug) DO NOTHING`);
  stmts.push(`INSERT INTO public.schools(id,tenant_id,code,name,status) VALUES
    ('${SCHOOL_A}','${TENANT}','NSD1',${q(SCHOOL_A_NAME)},'active'),
    ('${SCHOOL_B}','${TENANT}','NSD2',${q(SCHOOL_B_NAME)},'active')
    ON CONFLICT(tenant_id,code) DO NOTHING`);

  // users + memberships (single DO block, mirrors pilot_accounts.sql)
  const values = USERS.map(([n, email, meta]) => `(${n},${q(email)},${q(meta)})`).join(',');
  const membershipValues = USERS.flatMap(([n, , , ms]) =>
    ms.map(([s, r]) => `('${TENANT}'::uuid,${s ? `'${s}'::uuid` : 'NULL::uuid'},'aa11bb22-0003-4a10-9a10-${String(n).padStart(12, '0')}'::uuid,${q(r)},'active')`)
  ).join(',');
  stmts.push(`DO $$
DECLARE rec record; v_uid uuid; v_auth uuid; v_email text;
BEGIN
  FOR rec IN SELECT * FROM (VALUES ${values}) AS x(n,email,display_name) LOOP
    v_uid := 'aa11bb22-0002-4a10-9a10-' || lpad(rec.n::text,12,'0');
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

  // memberships via VALUES insert with NOT EXISTS guard
  stmts.push(`INSERT INTO public.memberships(tenant_id,school_id,user_id,role_code,status)
SELECT v.tenant_id,v.school_id,v.user_id,v.role_code,'active'
FROM (VALUES ${membershipValues}) AS v(tenant_id,school_id,user_id,role_code)
WHERE NOT EXISTS(
  SELECT 1 FROM public.memberships m
  WHERE m.user_id=v.user_id AND m.role_code=v.role_code
    AND m.school_id IS NOT DISTINCT FROM v.school_id AND m.status='active')`);

  // academic periods per school
  for (const s of [SCHOOL_A, SCHOOL_B]) {
    stmts.push(`INSERT INTO public.academic_periods(tenant_id,school_id,code,starts_on,ends_on,status)
SELECT '${TENANT}','${s}',${q(PERIOD_CODE)},'2026-07-13','2026-12-18','active'
WHERE NOT EXISTS(SELECT 1 FROM public.academic_periods WHERE school_id='${s}' AND code=${q(PERIOD_CODE)})`);
  }

  // subjects per school
  for (const s of [SCHOOL_A, SCHOOL_B]) {
    for (const [code, name] of SUBJECTS) {
      stmts.push(`INSERT INTO public.subjects(tenant_id,school_id,code,name)
VALUES('${TENANT}','${s}',${q(code)},${q(name)}) ON CONFLICT(tenant_id,school_id,code) DO NOTHING`);
    }
  }

  // classes per school
  for (const [school, key, name, count, prefix] of CLASSES) {
    stmts.push(`INSERT INTO public.school_classes(tenant_id,school_id,name,academic_year)
SELECT '${TENANT}','${school}',${q(name)},${q(ACADEMIC_YEAR)}
WHERE NOT EXISTS(SELECT 1 FROM public.school_classes WHERE school_id='${school}' AND name=${q(name)} AND academic_year=${q(ACADEMIC_YEAR)})`);
    // students
    for (let i = 1; i <= count; i++) {
      stmts.push(`INSERT INTO public.students(tenant_id,school_id,local_student_no,display_name,status)
VALUES('${TENANT}','${school}',${q(studentNo([school, key, name, count, prefix], i))},${q(studentName([school, key, name, count, prefix], i))},'active')
ON CONFLICT(tenant_id,school_id,local_student_no) DO NOTHING`);
    }
    // enrollments: join students by local_student_no
    stmts.push(`INSERT INTO public.class_student_enrollments(tenant_id,school_id,class_id,student_id,status)
SELECT '${TENANT}','${school}',c.id,st.id,'active'
FROM public.school_classes c
JOIN public.students st ON st.school_id='${school}' AND st.local_student_no LIKE ${q(prefix + '-%')}
WHERE c.school_id='${school}' AND c.name=${q(name)}
  AND NOT EXISTS(SELECT 1 FROM public.class_student_enrollments e
    WHERE e.class_id=c.id AND e.student_id=st.id AND e.status='active')`);
  }

  // teacher_class_assignments
  for (const [classKeyName, teacherN] of CLASS_TEACHERS) {
    const cls = CLASSES.find(c => c[1] === classKeyName);
    stmts.push(`INSERT INTO public.teacher_class_assignments(tenant_id,school_id,class_id,teacher_user_id,status)
SELECT '${TENANT}','${cls[0]}',c.id,'${uid(teacherN)}','active'
FROM public.school_classes c
WHERE c.school_id='${cls[0]}' AND c.name=${q(cls[2])}
  AND NOT EXISTS(SELECT 1 FROM public.teacher_class_assignments t
    WHERE t.class_id=c.id AND t.teacher_user_id='${uid(teacherN)}' AND t.status='active')`);
  }

  // lesson_schedules
  for (const [classKeyName, subjCode, teacherN, weekday, start, end, room] of SCHEDULES) {
    const cls = CLASSES.find(c => c[1] === classKeyName);
    stmts.push(`INSERT INTO public.lesson_schedules(tenant_id,school_id,class_id,subject_id,teacher_user_id,weekday,start_time,end_time,room,academic_year)
SELECT '${TENANT}','${cls[0]}',c.id,sj.id,'${uid(teacherN)}',${weekday},'${start}','${end}',${q(room)},${q(ACADEMIC_YEAR)}
FROM public.school_classes c, public.subjects sj
WHERE c.school_id='${cls[0]}' AND c.name=${q(cls[2])}
  AND sj.school_id='${cls[0]}' AND sj.code=${q(subjCode)}
  AND NOT EXISTS(SELECT 1 FROM public.lesson_schedules ls
    WHERE ls.class_id=c.id AND ls.subject_id=sj.id AND ls.weekday=${weekday} AND ls.status='active')`);
  }

  // guardian links: ortu-a -> first student of each A class; ortu-b -> first of B class
  stmts.push(`INSERT INTO public.guardian_student_links(tenant_id,school_id,student_id,guardian_user_id,relationship_code,verification_status,verified_by,verified_at)
SELECT '${TENANT}',e.school_id,e.student_id,'${uid(9)}','parent','verified','${uid(2)}',now()
FROM public.class_student_enrollments e
JOIN public.students st ON st.id=e.student_id AND st.school_id=e.school_id
JOIN public.school_classes c ON c.id=e.class_id AND c.school_id=e.school_id
WHERE e.school_id='${SCHOOL_A}' AND e.status='active' AND st.local_student_no IN ('NSA-001','NSB-001')
  AND NOT EXISTS(SELECT 1 FROM public.guardian_student_links g
    WHERE g.guardian_user_id='${uid(9)}' AND g.student_id=e.student_id AND g.verification_status='verified')`);
  stmts.push(`INSERT INTO public.guardian_student_links(tenant_id,school_id,student_id,guardian_user_id,relationship_code,verification_status,verified_by,verified_at)
SELECT '${TENANT}',e.school_id,e.student_id,'${uid(10)}','parent','verified','${uid(3)}',now()
FROM public.class_student_enrollments e
JOIN public.students st ON st.id=e.student_id AND st.school_id=e.school_id
WHERE e.school_id='${SCHOOL_B}' AND e.status='active' AND st.local_student_no='NTB-001'
  AND NOT EXISTS(SELECT 1 FROM public.guardian_student_links g
    WHERE g.guardian_user_id='${uid(10)}' AND g.student_id=e.student_id AND g.verification_status='verified')`);

  // announcements
  for (const [school, title, body, , , createdBy] of ANNOUNCEMENTS) {
    stmts.push(`INSERT INTO public.announcements(tenant_id,school_id,title,body,audience_role,audience_class_id,status,published_at,created_by)
SELECT '${TENANT}','${school}',${q(title)},${q(body)},NULL,NULL,'published',now(),'${uid(createdBy)}'
WHERE NOT EXISTS(SELECT 1 FROM public.announcements WHERE school_id='${school}' AND title=${q(title)})`);
  }

  // homework (published)
  for (const [school, classKeyName, subjCode, teacherN, title] of HOMEWORK) {
    const cls = CLASSES.find(c => c[1] === classKeyName);
    stmts.push(`INSERT INTO public.homework_assignments(tenant_id,school_id,class_id,subject_id,teacher_user_id,title,instructions,assigned_on,due_on,max_score,status,published_at)
SELECT '${TENANT}','${cls[0]}',c.id,sj.id,'${uid(teacherN)}',${q(title)},'Kerjakan di buku tugas.',CURRENT_DATE,CURRENT_DATE+7,100,'published',now()
FROM public.school_classes c, public.subjects sj
WHERE c.school_id='${cls[0]}' AND c.name=${q(cls[2])}
  AND sj.school_id='${cls[0]}' AND sj.code=${q(subjCode)}
  AND NOT EXISTS(SELECT 1 FROM public.homework_assignments h
    WHERE h.school_id='${cls[0]}' AND h.class_id=c.id AND h.title=${q(title)})`);
  }

  return stmts.filter(s => s !== 'BEGIN' && s !== 'COMMIT');
}

const VERIFY_SQL = `
SELECT 'tenants' k, count(*)::text v FROM public.tenants WHERE id='${TENANT}'
UNION ALL SELECT 'schools', count(*)::text FROM public.schools WHERE tenant_id='${TENANT}'
UNION ALL SELECT 'users', count(*)::text FROM public.users u JOIN public.memberships m ON m.user_id=u.id WHERE m.tenant_id='${TENANT}'
UNION ALL SELECT 'memberships', count(*)::text FROM public.memberships WHERE tenant_id='${TENANT}'
UNION ALL SELECT 'classes', count(*)::text FROM public.school_classes WHERE tenant_id='${TENANT}'
UNION ALL SELECT 'students', count(*)::text FROM public.students WHERE tenant_id='${TENANT}'
UNION ALL SELECT 'enrollments', count(*)::text FROM public.class_student_enrollments WHERE tenant_id='${TENANT}' AND status='active'
UNION ALL SELECT 'teacher_assignments', count(*)::text FROM public.teacher_class_assignments WHERE tenant_id='${TENANT}' AND status='active'
UNION ALL SELECT 'schedules', count(*)::text FROM public.lesson_schedules WHERE tenant_id='${TENANT}' AND status='active'
UNION ALL SELECT 'announcements', count(*)::text FROM public.announcements WHERE tenant_id='${TENANT}'
UNION ALL SELECT 'homework', count(*)::text FROM public.homework_assignments WHERE tenant_id='${TENANT}'
UNION ALL SELECT 'guardian_links', count(*)::text FROM public.guardian_student_links WHERE tenant_id='${TENANT}' AND verification_status='verified'
UNION ALL SELECT 'orphan_students', count(*)::text FROM public.students st
  WHERE st.tenant_id='${TENANT}' AND NOT EXISTS(
    SELECT 1 FROM public.class_student_enrollments e WHERE e.student_id=st.id AND e.status='active')
ORDER BY k`;

async function main() {
  const verifyOnly = process.argv.includes('--verify');
  await client.connect();
  try {
    if (!verifyOnly) {
      const stmts = buildSeedSql();
      let st = '';
      await client.query('BEGIN');
      try {
        for (const stmt of stmts) {
          st = stmt;
          await client.query(st);
        }
        await client.query('COMMIT');
        console.log('Seed multi-school pilot selesai.');
      } catch (e) {
        await client.query('ROLLBACK');
        console.error('Statement gagal:', st.slice(0, 400));
        throw e;
      }
    }
    const res = await client.query(VERIFY_SQL);
    console.log('\nVerifikasi:');
    for (const r of res.rows) console.log(`  ${r.k.padEnd(22)} ${r.v}`);
  } finally {
    await client.end();
  }
}

main().catch(e => { console.error(e); process.exit(1); });
