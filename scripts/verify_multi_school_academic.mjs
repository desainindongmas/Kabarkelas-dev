// Verifikasi surface akademik fixture multi-school: nilai, rapor, EWS, ortu baru.
// Pemakaian: node scripts/verify_multi_school_academic.mjs

import { readFileSync } from 'node:fs';
import { homedir } from 'node:os';
import { join } from 'node:path';
import { createClient } from '@supabase/supabase-js';

const env = Object.fromEntries(
  readFileSync(join(homedir(), '.kabarkelas', 'secrets.env'), 'utf8').split('\n')
    .filter(l => /^[A-Z_]+=/.test(l))
    .map(l => { const i = l.indexOf('='); return [l.slice(0, i), l.slice(i + 1).trim()]; })
);
const PW = 'PilotYayasan2026!';
const SCHOOL_A = 'aa11bb22-0001-4a10-9a10-0000000000a1';
const SCHOOL_B = 'aa11bb22-0001-4a10-9a10-0000000000b1';
const supabase = createClient(env.SUPABASE_URL, env.SUPABASE_PUBLISHABLE_KEY);

async function login(email) {
  const { data, error } = await supabase.auth.signInWithPassword({ email, password: PW });
  if (error) throw new Error(`${email}: ${error.message}`);
  return data.session;
}
async function rpc(session, fn, params = {}) {
  const client = createClient(env.SUPABASE_URL, env.SUPABASE_PUBLISHABLE_KEY, {
    global: { headers: { Authorization: `Bearer ${session.access_token}` } },
    auth: { persistSession: false },
  });
  const { data, error } = await client.rpc(fn, params);
  return { data, error };
}
const results = [];
const check = (name, ok, detail = '') => { results.push({ name, ok }); console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${detail ? ' — ' + detail : ''}`); };

// guru A1 (wali 4A + MTK 4A) — grade_workflow harus berisi nilai MTK 4A
{
  const s = await login('pilot.guru-a1@kabarkelas.dev');
  const g = await rpc(s, 'kabarkelas_grade_workflow', { p_school_id: SCHOOL_A });
  const rows = g.data ?? [];
  const mtk = rows.filter(r => r.subject_name === 'Matematika' && r.assessment_title?.includes('Kelas 4A'));
  check('guru-a1 grade_workflow ada nilai MTK 4A', !g.error && mtk.length === 105, `rows=${rows.length} mtk4a=${mtk.length}`);
  const subjects = new Set(rows.map(r => r.subject_name));
  check('guru-a1 melihat semua mapel 4A/4B', ['Matematika','Ilmu Pengetahuan Alam','Bahasa Indonesia','Pendidikan Pancasila dan Kewarganegaraan'].every(x => subjects.has(x)), [...subjects].join(','));
}
// guru mapel baru (PPKn) — harus bisa akses nilai kelasnya
{
  const s = await login('pilot.guru-ppkn@kabarkelas.dev');
  const g = await rpc(s, 'kabarkelas_grade_workflow', { p_school_id: SCHOOL_A });
  const rows = g.data ?? [];
  check('guru-ppkn grade_workflow PPKn', !g.error && rows.some(r => r.subject_name?.includes('Pancasila')), `rows=${rows.length}`);
  const b = await rpc(s, 'kabarkelas_grade_workflow', { p_school_id: SCHOOL_B });
  check('guru-ppkn akses sekolah B ditolak/kosong', !!b.error || (b.data ?? []).length === 0, b.error ? 'denied' : `rows=${b.data?.length}`);
}
// kepala sekolah: class reports released
{
  const s = await login('pilot.kepala1@kabarkelas.dev');
  const r = await rpc(s, 'kabarkelas_my_class_reports', { p_school: SCHOOL_A });
  const rel = (r.data ?? []).filter(x => x.report_status === 'released');
  check('kepala1 rapor released 2 kelas NSD1', !r.error && rel.length === 2, `released=${rel.length}`);
  const s2 = await login('pilot.kepala2@kabarkelas.dev');
  const r2 = await rpc(s2, 'kabarkelas_my_class_reports', { p_school: SCHOOL_B });
  const rel2 = (r2.data ?? []).filter(x => x.report_status === 'released');
  check('kepala2 rapor released 1 kelas NSD2', !r2.error && rel2.length === 1 && rel2[0].class_name === 'Kelas 5A', `released=${rel2.length}`);
}
// ortu baru: nilai harian + rapor anak
{
  const s = await login('pilot.ortu-a1@kabarkelas.dev');
  const pa = await rpc(s, 'kabarkelas_parent_assessments', { p_school: SCHOOL_A });
  check('ortu-a1 parent_assessments ada', !pa.error && (pa.data ?? []).length > 0, `rows=${pa.data?.length}`);
  const rr = await rpc(s, 'kabarkelas_my_released_reports', { p_school: SCHOOL_A });
  const kids = (rr.data ?? []).map(x => x.student_name);
  check('ortu-a1 rapor 2 anak released', !rr.error && kids.length === 2, JSON.stringify(kids));
  const grades = rr.data?.[0]?.grades;
  check('rapor punya daftar nilai per mapel', Array.isArray(grades) && grades.length >= 20, `subjects=${grades?.length}`);
}
// ortu-b: siswa sekolah B
{
  const s = await login('pilot.ortu-b1a@kabarkelas.dev');
  const rr = await rpc(s, 'kabarkelas_my_released_reports', { p_school: SCHOOL_B });
  const kids = (rr.data ?? []).map(x => x.student_name);
  check('ortu-b1a rapor anak NTB-005/006', !rr.error && kids.length === 2, JSON.stringify(kids));
  const pa = await rpc(s, 'kabarkelas_parent_assessments', { p_school: SCHOOL_A });
  check('ortu-b1a nilai sekolah A kosong/ditolak', !!pa.error || (pa.data ?? []).length === 0, pa.error ? 'denied' : `rows=${pa.data?.length}`);
}
// EWS alerts per peran
{
  const s = await login('pilot.kepala1@kabarkelas.dev');
  const a = await rpc(s, 'kabarkelas_ews_my_alerts', { p_school: SCHOOL_A });
  check('kepala1 EWS alerts 6', !a.error && (a.data ?? []).length === 6, `rows=${a.data?.length}`);
  const s2 = await login('pilot.guru-b1@kabarkelas.dev');
  const a2 = await rpc(s2, 'kabarkelas_ews_my_alerts', { p_school: SCHOOL_B });
  const a2b = await rpc(s2, 'kabarkelas_ews_my_alerts', { p_school: SCHOOL_A });
  check('guru-b1 EWS sekolah B 5, sekolah A ditolak', !a2.error && (a2.data ?? []).length === 5 && !!a2b.error, `B=${a2.data?.length} A=${a2b.error ? 'denied' : a2b.data?.length}`);
}
// guru lintas tetap bisa nilai kedua sekolah
{
  const s = await login('pilot.guru-ab@kabarkelas.dev');
  const ga = await rpc(s, 'kabarkelas_grade_workflow', { p_school_id: SCHOOL_A });
  const gb = await rpc(s, 'kabarkelas_grade_workflow', { p_school_id: SCHOOL_B });
  check('guru-ab grade_workflow kedua sekolah', !ga.error && !gb.error && (ga.data ?? []).length > 0 && (gb.data ?? []).length > 0, `A=${ga.data?.length} B=${gb.data?.length}`);
}

const fails = results.filter(r => !r.ok);
console.log(`\n${results.length - fails.length}/${results.length} checks PASS`);
process.exit(fails.length ? 1 : 0);
