// Verifikasi isolasi lintas sekolah untuk fixture multi-school pilot.
// Login via Supabase Auth (publishable key) lalu panggil RPC sebagai tiap peran.
// Pemakaian: node scripts/verify_multi_school_isolation.mjs

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
function check(name, ok, detail = '') {
  results.push({ name, ok, detail });
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${detail ? ' — ' + detail : ''}`);
}

// 1. anon ditolak
{
  const client = createClient(env.SUPABASE_URL, env.SUPABASE_PUBLISHABLE_KEY, { auth: { persistSession: false } });
  const { error } = await client.rpc('kabarkelas_schedule_list', { p_school: SCHOOL_A });
  check('anon schedule_list ditolak', !!error, error?.message?.slice(0, 80));
}

// 2. guru A1: sekolah A OK, sekolah B ditolak
{
  const s = await login('pilot.guru-a1@kabarkelas.dev');
  const a = await rpc(s, 'kabarkelas_schedule_list', { p_school: SCHOOL_A });
  check('guru-a1 schedule sekolah A', !a.error && Array.isArray(a.data), `${a.data?.length ?? 0} rows`);
  const b = await rpc(s, 'kabarkelas_schedule_list', { p_school: SCHOOL_B });
  check('guru-a1 schedule sekolah B ditolak', !!b.error, b.error?.message?.slice(0, 80));
  const stA = await rpc(s, 'kabarkelas_pilot_students', { p_school: SCHOOL_A });
  const stB = await rpc(s, 'kabarkelas_pilot_students', { p_school: SCHOOL_B });
  check('guru-a1 students A vs B', !stA.error && !!stB.error, `A=${stA.data?.length ?? 'err'} B=${stB.error ? 'denied' : stB.data?.length}`);
}

// 3. guru AB (lintas): kedua sekolah boleh
{
  const s = await login('pilot.guru-ab@kabarkelas.dev');
  const a = await rpc(s, 'kabarkelas_schedule_list', { p_school: SCHOOL_A });
  const b = await rpc(s, 'kabarkelas_schedule_list', { p_school: SCHOOL_B });
  check('guru-ab akses kedua sekolah', !a.error && !b.error, `A=${a.data?.length} B=${b.data?.length}`);
}

// 4. kepala sekolah 1 vs 2: pengumuman terisolasi
{
  const s1 = await login('pilot.kepala1@kabarkelas.dev');
  const s2 = await login('pilot.kepala2@kabarkelas.dev');
  const a1 = await rpc(s1, 'kabarkelas_announce_list', { p_school: SCHOOL_A });
  const a2for1 = await rpc(s1, 'kabarkelas_announce_list', { p_school: SCHOOL_B });
  const b2 = await rpc(s2, 'kabarkelas_announce_list', { p_school: SCHOOL_B });
  const b1for2 = await rpc(s2, 'kabarkelas_announce_list', { p_school: SCHOOL_A });
  const titles1 = (a1.data ?? []).map(x => x.title);
  const titles2 = (b2.data ?? []).map(x => x.title);
  check('kepala1 hanya lihat pengumuman NSD1', titles1.every(t => t.includes('Nusantara 1')) && titles1.length === 1, JSON.stringify(titles1));
  check('kepala1 akses NSD2 ditolak', !!a2for1.error, a2for1.error?.message?.slice(0, 60));
  check('kepala2 hanya lihat pengumuman NSD2', titles2.every(t => t.includes('Nusantara 2')) && titles2.length === 1, JSON.stringify(titles2));
  check('kepala2 akses NSD1 ditolak', !!b1for2.error, b1for2.error?.message?.slice(0, 60));
}

// 5. ortuwali: hanya siswa ter-link
{
  const sa = await login('pilot.ortu-a@kabarkelas.dev');
  const sb = await login('pilot.ortu-b@kabarkelas.dev');
  const ctxA = await rpc(sa, 'kabarkelas_my_context');
  const unitsA = ctxA.data?.units ?? ctxA.data ?? [];
  check('ortu-a context 1 unit sekolah A', unitsA.length === 1 && unitsA[0].school_id === SCHOOL_A, JSON.stringify(unitsA).slice(0, 120));
  const studentsA = await rpc(sa, 'kabarkelas_my_role_students', { p_school_id: SCHOOL_A });
  const nosA = (studentsA.data ?? []).map(s => s.local_student_no);
  check('ortu-a hanya siswa ter-link (2 anak)', nosA.length === 2 && nosA.every(n => n.startsWith('NS')), JSON.stringify(nosA));
  const studentsB = await rpc(sa, 'kabarkelas_my_role_students', { p_school_id: SCHOOL_B });
  check('ortu-a akses siswa sekolah B kosong/ditolak', !!studentsB.error || (studentsB.data ?? []).length === 0, studentsB.error ? studentsB.error.message?.slice(0, 60) : `rows=${studentsB.data?.length}`);
  const studentsBb = await rpc(sb, 'kabarkelas_my_role_students', { p_school_id: SCHOOL_B });
  const nosB = (studentsBb.data ?? []).map(s => s.local_student_no);
  check('ortu-b hanya siswa NTB-001', nosB.length === 1 && nosB[0] === 'NTB-001', JSON.stringify(nosB));
}

// 6. foundation admin: school_id NULL → pilot RPC menolak (by design, tanpa modul pilot)
{
  const s = await login('pilot.foundasi@kabarkelas.dev');
  const ctx = await rpc(s, 'kabarkelas_my_context');
  const units = ctx.data?.units ?? ctx.data ?? [];
  check('foundasi context yayasan (school_id null)', units.some(u => u.role === 'foundation_admin' && u.school_id === null), JSON.stringify(units).slice(0, 160));
  const schedA = await rpc(s, 'kabarkelas_schedule_list', { p_school: SCHOOL_A });
  const schedB = await rpc(s, 'kabarkelas_schedule_list', { p_school: SCHOOL_B });
  check('foundasi ditolak di RPC pilot (by design)', !!schedA.error && !!schedB.error, `A=${schedA.error ? 'denied' : schedA.data?.length} B=${schedB.error ? 'denied' : schedB.data?.length}`);
}

const fails = results.filter(r => !r.ok);
console.log(`\n${results.length - fails.length}/${results.length} checks PASS`);
process.exit(fails.length ? 1 : 0);
