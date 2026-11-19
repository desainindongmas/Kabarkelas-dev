// Verifikasi G12: attendance + schedule write paths
import {readFileSync} from 'node:fs';import {homedir} from 'node:os';import {join} from 'node:path';import pg from 'pg';import {createClient} from '@supabase/supabase-js';
const env=Object.fromEntries(readFileSync(join(homedir(),'.kabarkelas','secrets.env'),'utf8').split('\n').filter(l=>/^[A-Z_]+=/.test(l)).map(l=>{const i=l.indexOf('=');return[l.slice(0,i),l.slice(i+1).trim()]}));
const TENANT='aa11bb22-0001-4a10-9a10-000000000001';
const SCHOOL_A='aa11bb22-0001-4a10-9a10-0000000000a1';
const results=[];
const check=(n,ok,d='')=>{results.push({n,ok});console.log((ok?'PASS':'FAIL')+' '+n+(d?' — '+d:''));};
const db=new pg.Client({host:env.SUPABASE_DB_HOST,port:+env.SUPABASE_DB_PORT,user:env.SUPABASE_DB_USER,password:env.SUPABASE_DB_PASSWORD,database:'postgres',ssl:{rejectUnauthorized:false}});
await db.connect();
const supa=createClient(env.SUPABASE_URL,env.SUPABASE_PUBLISHABLE_KEY);
const {data:auth}=await supa.auth.signInWithPassword({email:'pilot.guru-a1@kabarkelas.dev',password:'PilotYayasan2026!'});
const c=createClient(env.SUPABASE_URL,env.SUPABASE_PUBLISHABLE_KEY,{global:{headers:{Authorization:'Bearer '+auth.session.access_token}},auth:{persistSession:false}});

// class 4A + period + students
const cls=await db.query("SELECT id FROM public.school_classes WHERE school_id=$1 AND name='Kelas 4A'",[SCHOOL_A]);
const period=await db.query("SELECT id FROM public.academic_periods WHERE school_id=$1 AND status='active' LIMIT 1",[SCHOOL_A]);
const subMTK=await db.query("SELECT id FROM public.subjects WHERE school_id=$1 AND code='MTK'",[SCHOOL_A]);
const studs=await db.query(`SELECT s.id FROM public.students s JOIN public.class_student_enrollments e ON e.student_id=s.id AND e.class_id=$1 AND e.status='active' WHERE s.school_id=$2 LIMIT 3`,[cls.rows[0].id,SCHOOL_A]);

// 1. schedule_create sebagai guru-a1 (MTK 4A)
const {data:schedId,error:sErr}=await c.rpc('kabarkelas_schedule_create',{
  p_school:SCHOOL_A,p_class:cls.rows[0].id,p_subject:subMTK.rows[0].id,p_weekday:2,
  p_start:'10:00',p_end:'10:35',p_room:'R.4A',p_year:'2026/2027'});
check('schedule_create guru-a1',!sErr&&!!schedId,sErr?.message||schedId);

// 2. schedule_create mapel salah → ditolak
const subIPA=await db.query("SELECT id FROM public.subjects WHERE school_id=$1 AND code='IPA'",[SCHOOL_A]);
const {error:sErr2}=await c.rpc('kabarkelas_schedule_create',{
  p_school:SCHOOL_A,p_class:cls.rows[0].id,p_subject:subIPA.rows[0].id,p_weekday:3,
  p_start:'10:00',p_end:'10:35',p_room:null,p_year:'2026/2027'});
check('schedule_create IPA ditolak (bukan mapel guru)',!!sErr2,sErr2?.message?.slice(0,60));

// 3. attendance: create + mark + confirm + publish
const today='2026-12-17'; // tanggal unik per run
const {data:sessId,error:aErr}=await c.rpc('kabarkelas_attendance_create',{p_school:SCHOOL_A,p_class:cls.rows[0].id,p_date:today,p_period:period.rows[0].id});
check('attendance_create',!aErr&&!!sessId,aErr?.message||sessId);
if(sessId){
  for(const s of studs.rows){
    const {error:me}=await c.rpc('kabarkelas_attendance_mark',{p_session:sessId,p_student:s.id,p_code:'present'});
    if(me)console.log('mark err',me.message);
  }
  const {error:ce}=await c.rpc('kabarkelas_attendance_transition',{p_session:sessId,p_action:'confirm'});
  check('attendance confirm',!ce,ce?.message);
  const {error:pe}=await c.rpc('kabarkelas_attendance_transition',{p_session:sessId,p_action:'publish'});
  check('attendance publish',!pe,pe?.message);
  const {data:recs}=await c.rpc('kabarkelas_attendance_records',{p_session:sessId});
  check('attendance records',recs?.length===35,recs?.length+' rows');
}

// 4. attendance list
const {data:alist,error:alErr}=await c.rpc('kabarkelas_attendance_list',{p_school:SCHOOL_A});
check('attendance_list',!alErr&&alist?.length>0,alist?.length+' sessions');

// 5. Negative: guru-b1 (NSD2) akses attendance NSD1 → ditolak
const {data:authB}=await supa.auth.signInWithPassword({email:'pilot.guru-b1@kabarkelas.dev',password:'PilotYayasan2026!'});
const cB=createClient(env.SUPABASE_URL,env.SUPABASE_PUBLISHABLE_KEY,{global:{headers:{Authorization:'Bearer '+authB.session.access_token}},auth:{persistSession:false}});
const {error:crossA}=await cB.rpc('kabarkelas_attendance_list',{p_school:SCHOOL_A});
check('cross-school attendance ditolak',!!crossA,crossA?.message?.slice(0,50));

// 6. Guardian ortu-a lihat attendance NSD1 (read-only)
const {data:authO}=await supa.auth.signInWithPassword({email:'pilot.ortu-a@kabarkelas.dev',password:'PilotYayasan2026!'});
const cO=createClient(env.SUPABASE_URL,env.SUPABASE_PUBLISHABLE_KEY,{global:{headers:{Authorization:'Bearer '+authO.session.access_token}},auth:{persistSession:false}});
const {data:oList,error:oErr}=await cO.rpc('kabarkelas_attendance_list',{p_school:SCHOOL_A});
check('ortu attendance list',!oErr&&(oList?.length??0)>0,oList?.length+' sessions');
// sesi published → mark ditolak state; sesi draft → ditolak pilot_can
const {error:oMark}=await cO.rpc('kabarkelas_attendance_mark',{p_session:sessId,p_student:studs.rows[0].id,p_code:'absent'});
check('ortu tidak bisa mark (published)',!!oMark,oMark?.message?.slice(0,50));
const {data:draftId}=await c.rpc('kabarkelas_attendance_create',{p_school:SCHOOL_A,p_class:cls.rows[0].id,p_date:'2026-12-16',p_period:period.rows[0].id});
if(draftId){
  const {error:oMark2}=await cO.rpc('kabarkelas_attendance_mark',{p_session:draftId,p_student:studs.rows[0].id,p_code:'absent'});
  check('ortu ditolak mark sesi draft',!!oMark2,oMark2?.message?.slice(0,50));
}

await db.end();
const fails=results.filter(r=>!r.ok);
console.log(`\n${results.length-fails.length}/${results.length} PASS`);
process.exit(fails.length?1:0);
