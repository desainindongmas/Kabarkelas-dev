// Verifikasi G11: teacher-subject authz, create_assessment, import RPCs
// Jalankan: node scripts/verify_g11_features.mjs
import {readFileSync} from 'node:fs';import {homedir} from 'node:os';import {join} from 'node:path';import pg from 'pg';import {createClient} from '@supabase/supabase-js';

const env=Object.fromEntries(readFileSync(join(homedir(),'.kabarkelas','secrets.env'),'utf8').split('\n').filter(l=>/^[A-Z_]+=/.test(l)).map(l=>{const i=l.indexOf('=');return[l.slice(0,i),l.slice(i+1).trim()]}));
const TENANT='aa11bb22-0001-4a10-9a10-000000000001';
const SCHOOL_A='aa11bb22-0001-4a10-9a10-0000000000a1';
const SCHOOL_B='aa11bb22-0001-4a10-9a10-0000000000b1';
const results=[];
const check=(name,ok,detail='')=>{results.push({name,ok,detail});console.log((ok?'PASS':'FAIL')+' '+name+(detail?' — '+detail:''));};

const db=new pg.Client({host:env.SUPABASE_DB_HOST,port:+env.SUPABASE_DB_PORT,user:env.SUPABASE_DB_USER,password:env.SUPABASE_DB_PASSWORD,database:'postgres',ssl:{rejectUnauthorized:false}});
await db.connect();

// 1. TSA coverage: every (class,subject) pair di kedua sekolah punya guru
const tsa=await db.query(`SELECT c.name cls,sj.code sub,u.email FROM public.teacher_subject_assignments t
 JOIN public.school_classes c ON c.id=t.class_id JOIN public.subjects sj ON sj.id=t.subject_id JOIN public.users u ON u.id=t.teacher_user_id
 WHERE t.tenant_id=$1 AND t.status='active' ORDER BY c.name,sj.code`,[TENANT]);
check('TSA aktif >=24',tsa.rows.length>=24,tsa.rows.length+' rows');

// 2. teacher_options RPC sebagai guru-a1 (NSD1, MTK 4A)
const supa=createClient(env.SUPABASE_URL,env.SUPABASE_PUBLISHABLE_KEY);
const {data:authA}=await supa.auth.signInWithPassword({email:'pilot.guru-a1@kabarkelas.dev',password:'PilotYayasan2026!'});
const cA=createClient(env.SUPABASE_URL,env.SUPABASE_PUBLISHABLE_KEY,{global:{headers:{Authorization:'Bearer '+authA.session.access_token}},auth:{persistSession:false}});
const {data:opts,error:optErr}=await cA.rpc('kabarkelas_teacher_options',{p_school:SCHOOL_A});
check('teacher_options NSD1',!optErr&&opts?.length>0,opts?.length+' pairs');

// 3. create_assessment sebagai guru-a1: MTK Kelas 4A
const clsA=await db.query("SELECT id FROM public.school_classes WHERE school_id=$1 AND name='Kelas 4A'",[SCHOOL_A]);
const subMTK=await db.query("SELECT id FROM public.subjects WHERE school_id=$1 AND code='MTK'",[SCHOOL_A]);
const period=await db.query("SELECT id FROM public.academic_periods WHERE school_id=$1 AND status='active' LIMIT 1",[SCHOOL_A]);
const studs=await db.query(`SELECT s.id FROM public.students s JOIN public.class_student_enrollments e ON e.student_id=s.id AND e.class_id=$1 AND e.status='active' WHERE s.school_id=$2 AND s.status='active' LIMIT 3`,[clsA.rows[0].id,SCHOOL_A]);
const scores=studs.rows.map((s,i)=>({student_id:s.id,score:70+i*10}));
const {data:assessId,error:createErr}=await cA.rpc('kabarkelas_create_assessment',{
  p_school:SCHOOL_A,p_class:clsA.rows[0].id,p_subject:subMTK.rows[0].id,p_period:period.rows[0].id,
  p_title:'UH Verifikasi G11',p_max_score:100,p_scores:scores});
check('create_assessment guru-a1',!createErr&&!!assessId,createErr?.message||assessId);

// 4. Negative: guru-b1 (NSD2) coba create di NSD1 → harus ditolak
const {data:authB}=await supa.auth.signInWithPassword({email:'pilot.guru-b1@kabarkelas.dev',password:'PilotYayasan2026!'});
const cB=createClient(env.SUPABASE_URL,env.SUPABASE_PUBLISHABLE_KEY,{global:{headers:{Authorization:'Bearer '+authB.session.access_token}},auth:{persistSession:false}});
const {error:crossErr}=await cB.rpc('kabarkelas_create_assessment',{
  p_school:SCHOOL_A,p_class:clsA.rows[0].id,p_subject:subMTK.rows[0].id,p_period:period.rows[0].id,
  p_title:'Cross-school attempt',p_max_score:100,p_scores:scores});
check('cross-school create ditolak',!!crossErr,crossErr?.message?.slice(0,60));

// 5. guru salah mapel: guru-ipa coba MTK → ditolak
const {data:authIPA}=await supa.auth.signInWithPassword({email:'pilot.guru-ipa@kabarkelas.dev',password:'PilotYayasan2026!'});
const cIPA=createClient(env.SUPABASE_URL,env.SUPABASE_PUBLISHABLE_KEY,{global:{headers:{Authorization:'Bearer '+authIPA.session.access_token}},auth:{persistSession:false}});
const {error:subjErr}=await cIPA.rpc('kabarkelas_create_assessment',{
  p_school:SCHOOL_A,p_class:clsA.rows[0].id,p_subject:subMTK.rows[0].id,p_period:period.rows[0].id,
  p_title:'Wrong subject',p_max_score:100,p_scores:scores});
check('salah mapel ditolak',!!subjErr,subjErr?.message?.slice(0,60));

// 6. Finalisasi: grade draft + attempt sudah dibuat → finalize per grade
const grades=await db.query("SELECT id FROM public.student_grades WHERE assessment_id=$1 AND status='draft'",[assessId]);
check('draft grades dibuat',grades.rows.length===scores.length,grades.rows.length+' grades');
// finalize satu grade via RPC guru-a1
if(grades.rows.length){
  const {data:finData,error:finErr}=await cA.rpc('kabarkelas_finalize_assessment',{p_grade:grades.rows[0].id});
  check('finalize_assessment',!finErr,finErr?.message||JSON.stringify(finData).slice(0,80));
}

// 7. Import RPCs: foundation_admin buat tenant+school+user+membership
const {data:authF}=await supa.auth.signInWithPassword({email:'pilot.foundasi@kabarkelas.dev',password:'PilotYayasan2026!'});
const cF=createClient(env.SUPABASE_URL,env.SUPABASE_PUBLISHABLE_KEY,{global:{headers:{Authorization:'Bearer '+authF.session.access_token}},auth:{persistSession:false}});
const {data:tData,error:tErr}=await cF.rpc('kabarkelas_import_tenants',{p_rows:[{slug:'import-test',name:'Import Test Yayasan'}]});
check('import_tenants',!tErr,JSON.stringify(tData).slice(0,120));
const tId=tData?.[0]?.tenant_id;
if(tId){
  const {data:sData,error:sErr}=await cF.rpc('kabarkelas_import_schools',{p_rows:[{tenant_slug:'import-test',code:'IMP1',name:'Sekolah Impor 1'}]});
  check('import_schools',!sErr,JSON.stringify(sData).slice(0,120));
  const {data:uData,error:uErr}=await cF.rpc('kabarkelas_import_users',{p_rows:[{email:'import.test@kabarkelas.dev',display_name:'Import Test',password:'TestImport2026!'}]});
  check('import_users',!uErr,JSON.stringify(uData).slice(0,150));
  const uId=uData?.results?.[0]?.user_id;
  if(uId){
    const {data:mData,error:mErr}=await cF.rpc('kabarkelas_import_memberships',{p_rows:[{email:'import.test@kabarkelas.dev',school_code:'IMP1',role_code:'principal'}]});
    check('import_memberships school-level',!mErr,JSON.stringify(mData).slice(0,120));
  }
}

// 8. Import ditolak untuk guru
const {error:gErr}=await cA.rpc('kabarkelas_import_users',{p_rows:[{email:'x@x.com'}]});
check('import ditolak untuk guru',!!gErr,gErr?.message?.slice(0,60));

// 9. School B dedup: tidak ada MTK/BIN legacy
const legacy=await db.query("SELECT count(*) c FROM public.subjects WHERE school_id=$1 AND code IN('MTK','BIN')",[SCHOOL_B]);
check('NSD2 legacy subjects hilang',legacy.rows[0].c==='0',legacy.rows[0].c+' rows');

await db.end();
const fails=results.filter(r=>!r.ok);
console.log(`\n${results.length-fails.length}/${results.length} PASS`);
process.exit(fails.length?1:0);
