import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile, readdir } from 'node:fs/promises';
import pg from 'pg';
const base = process.env.TEST_DATABASE_URL || 'postgres://postgres@127.0.0.1:55432/postgres';
const parsed = new URL(base);
if (!['127.0.0.1','localhost','[::1]'].includes(parsed.hostname)) throw new Error('Database tests require a disposable local PostgreSQL server');
const id = n => `f0050000-0000-4000-8000-${String(n).padStart(12,'0')}`;

test('PostgreSQL 17 migration replay, authorization and transaction tests', async t => {
  const admin = new pg.Client({connectionString:base}); await admin.connect();
  const name = `kabarkelas_g05_test_${process.pid}`;
  await admin.query(`CREATE DATABASE ${name}`);
  const url = new URL(base); url.pathname = `/${name}`;
  const db = new pg.Client({connectionString:url.href}); await db.connect();
  try {
    await db.query(`DO $$ BEGIN
      IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='anon') THEN CREATE ROLE anon NOLOGIN; END IF;
      IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='authenticated') THEN CREATE ROLE authenticated NOLOGIN; END IF;
    END $$;
    CREATE SCHEMA auth;
    CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS $$
      SELECT coalesce(nullif(current_setting('request.jwt.claim.sub',true),''),
      nullif(current_setting('request.jwt.claims',true),'')::jsonb->>'sub')::uuid;
    $$;
    GRANT USAGE ON SCHEMA auth TO authenticated,anon;`);
    for (const file of (await readdir('supabase/migrations')).sort()) {
      if(file.endsWith('.sql')) await db.query(await readFile(`supabase/migrations/${file}`,'utf8'));
    }
    const fixtures = await readFile('supabase/tests/fixtures.sql','utf8');
    const suite = await readFile('supabase/tests/g05_workflow.sql','utf8');
    const results = await db.query('BEGIN;\n'+fixtures+'\n'+suite+'\nROLLBACK;');
    const checks = results.flatMap(r=>r.rows).filter(r=>r.test_name);
    assert.ok(checks.length>=50,`Expected >=50 SQL assertions, got ${checks.length}`);
    for(const c of checks) await t.test(c.test_name,()=>assert.equal(c.passed,true));
    await t.test('G0.5.1 attempt and correction server authorization', async () => {
      const testClient = new pg.Client({connectionString:url.href}); await testClient.connect();
      try {
        await testClient.query('BEGIN');
        await testClient.query(fixtures);
        const asUser=async n=>{
          await testClient.query('RESET ROLE');
          await testClient.query("SELECT set_config('request.jwt.claim.sub',$1,true)",[id(1000+n)]);
          await testClient.query('SET LOCAL ROLE authenticated');
        };
        await asUser(1);
        const grade=id(801);
        const first=await testClient.query("SELECT public.kabarkelas_record_attempt($1,'initial',65,'Nilai awal') id",[grade]);
        const attempt=first.rows[0].id;
        await testClient.query("SELECT public.kabarkelas_record_attempt($1,'remedial',58,'Remedial')",[grade]);
        await testClient.query("SELECT public.kabarkelas_correct_attempt($1,70,'Salah mengetik nilai')",[attempt]);
        await testClient.query('RESET ROLE');
        const current=await testClient.query('SELECT score FROM public.assessment_attempts WHERE id=$1',[attempt]);
        assert.equal(Number(current.rows[0].score),70);
        const audit=await testClient.query('SELECT previous_score,corrected_score FROM public.assessment_corrections WHERE attempt_id=$1',[attempt]);
        assert.equal(Number(audit.rows[0].previous_score),65);
        assert.equal(Number(audit.rows[0].corrected_score),70);
        await asUser(1);
        const read=await testClient.query('SELECT allowed_actions FROM public.kabarkelas_grade_workflow($1) WHERE grade_id=$2',[id(201),grade]);
        assert.deepEqual(read.rows[0].allowed_actions,[]);
        await testClient.query('SAVEPOINT legacy');
        await assert.rejects(testClient.query("SELECT public.kabarkelas_transition_grade($1,'submit',1)",[grade]),e=>e.code==='55000');
        await testClient.query('ROLLBACK TO SAVEPOINT legacy');
        await asUser(2);
        await assert.rejects(testClient.query("SELECT public.kabarkelas_record_attempt($1,'remedial',90,'Tidak berhak')",[grade]),e=>e.code==='42501');
      } finally {
        await testClient.query('ROLLBACK').catch(()=>{});
        await testClient.end();
      }
    });
    await t.test('G0.5.1 teacher finalization and class report approval lifecycle',async()=>{
      const client=new pg.Client({connectionString:url.href});await client.connect();
      try{
        await client.query('BEGIN');
        await client.query(fixtures);
        const asUser=async n=>{
          await client.query('RESET ROLE');
          await client.query("SELECT set_config('request.jwt.claim.sub',$1,true)",[id(1000+n)]);
          await client.query('SET LOCAL ROLE authenticated');
        };
        await asUser(1);
        await client.query("SELECT public.kabarkelas_record_attempt($1,'initial',65,'Nilai awal')",[id(801)]);
        await client.query("SELECT public.kabarkelas_record_attempt($1,'remedial',58,'Remedial')",[id(801)]);
        const finalized=await client.query('SELECT public.kabarkelas_finalize_assessment($1) result',[id(801)]);
        assert.equal(finalized.rows[0].result.effective_score,65);
        assert.equal(finalized.rows[0].result.status,'released');
        await asUser(2);
        const created=await client.query('SELECT public.kabarkelas_create_class_report($1,$2,$3) id',[id(301),id(501),id(1)]);
        const report=created.rows[0].id;
        await asUser(1);
        const first=await client.query("SELECT public.kabarkelas_transition_class_report($1,'teacher_finalize',1) result",[report]);
        assert.equal(first.rows[0].result.status,'teacher_finalized');
        const second=await client.query("SELECT public.kabarkelas_transition_class_report($1,'homeroom_review',2) result",[report]);
        assert.equal(second.rows[0].result.status,'homeroom_reviewed');
        await asUser(2);
        const signed=await client.query("SELECT public.kabarkelas_transition_class_report($1,'principal_sign',3) result",[report]);
        assert.equal(signed.rows[0].result.status,'principal_signed');
        await asUser(1);
        const released=await client.query("SELECT public.kabarkelas_transition_class_report($1,'release',4) result",[report]);
        assert.equal(released.rows[0].result.status,'released');
        await asUser(3);
        const grades=await client.query('SELECT * FROM public.kabarkelas_my_released_reports($1)',[id(201)]);
        assert.equal(grades.rows.length,1);
        assert.equal(Number(grades.rows[0].grades[0].score),65);
        const daily=await client.query('SELECT * FROM public.kabarkelas_parent_assessments($1)',[id(201)]);
        assert.equal(daily.rows.length,1);
        assert.equal(Number(daily.rows[0].score),65);
        await client.query('RESET ROLE');
        const audit=await client.query("SELECT count(*)::integer n FROM public.academic_workflow_events WHERE resource_type='report_card' AND resource_id=$1",[report]);
        assert.equal(audit.rows[0].n,5);
        const snaps=await client.query('SELECT count(*)::integer n FROM public.school_report_snapshots WHERE report_id=$1',[report]);
        assert.equal(snaps.rows[0].n,1);
        await asUser(9);
        const hidden=await client.query('SELECT * FROM public.kabarkelas_my_released_reports($1)',[id(201)]);
        assert.equal(hidden.rows.length,0);
      }finally{
        await client.query('ROLLBACK').catch(()=>{});
        await client.end();
      }
    });
    await t.test('G0.5.1 configurable latest remediation and report-only visibility',async()=>{
      const client=new pg.Client({connectionString:url.href});await client.connect();
      try{
        await client.query('BEGIN');
        await client.query(fixtures);
        const asUser=async n=>{
          await client.query('RESET ROLE');
          await client.query("SELECT set_config('request.jwt.claim.sub',$1,true)",[id(1000+n)]);
          await client.query('SET LOCAL ROLE authenticated');
        };
        await asUser(2);
        const saved=await client.query("SELECT public.kabarkelas_set_school_assessment_policy($1,'latest_score',NULL,'report_only') version",[id(201)]);
        assert.equal(saved.rows[0].version,1);
        await asUser(1);
        const policy=await client.query('SELECT * FROM public.kabarkelas_school_assessment_policy($1)',[id(201)]);
        assert.equal(policy.rows[0].mode,'latest_score');
        await client.query("SELECT public.kabarkelas_record_attempt($1,'initial',65,'Nilai awal')",[id(801)]);
        await client.query("SELECT public.kabarkelas_record_attempt($1,'remedial',58,'Remedial')",[id(801)]);
        const result=await client.query('SELECT public.kabarkelas_finalize_assessment($1) result',[id(801)]);
        assert.equal(result.rows[0].result.effective_score,58);
        assert.equal(result.rows[0].result.status,'finalized');
        await asUser(3);
        const hidden=await client.query('SELECT * FROM public.kabarkelas_parent_assessments($1)',[id(201)]);
        assert.equal(hidden.rows.length,0);
        await client.query('RESET ROLE');
        const immutable=await client.query('SELECT count(*)::integer n FROM public.assessment_releases WHERE grade_id=$1 AND status=$2',[id(801),'finalized']);
        assert.equal(immutable.rows[0].n,1);
      }finally{
        await client.query('ROLLBACK').catch(()=>{});
        await client.end();
      }
    });
    await t.test('G0.5.1 correction after release retains old snapshot and publishes new version',async()=>{
      const client=new pg.Client({connectionString:url.href});await client.connect();
      try{
        await client.query('BEGIN');
        await client.query(fixtures);
        const asUser=async n=>{
          await client.query('RESET ROLE');
          await client.query("SELECT set_config('request.jwt.claim.sub',$1,true)",[id(1000+n)]);
          await client.query('SET LOCAL ROLE authenticated');
        };
        await asUser(1);
        const initial=await client.query("SELECT public.kabarkelas_record_attempt($1,'initial',65,'Nilai awal') id",[id(801)]);
        await client.query('SELECT public.kabarkelas_finalize_assessment($1)',[id(801)]);
        await client.query("SELECT public.kabarkelas_correct_attempt($1,70,'Salah memasukkan nilai')",[initial.rows[0].id]);
        const updated=await client.query('SELECT public.kabarkelas_finalize_assessment($1) result',[id(801)]);
        assert.equal(updated.rows[0].result.version,2);
        assert.equal(updated.rows[0].result.effective_score,70);
        await asUser(3);
        const guardian=await client.query('SELECT * FROM public.kabarkelas_parent_assessments($1)',[id(201)]);
        assert.equal(guardian.rows.length,1);
        assert.equal(guardian.rows[0].release_version,2);
        assert.equal(Number(guardian.rows[0].score),70);
        await client.query('RESET ROLE');
        const originals=await client.query('SELECT version,effective_score FROM public.assessment_releases WHERE grade_id=$1 ORDER BY version',[id(801)]);
        assert.deepEqual(originals.rows.map(x=>Number(x.effective_score)),[65,70]);
        await client.query('SAVEPOINT immutable_test');
        await assert.rejects(client.query('UPDATE public.assessment_releases SET effective_score=1 WHERE grade_id=$1',[id(801)]),e=>e.code==='55000');
        await client.query('ROLLBACK TO SAVEPOINT immutable_test');
      }finally{
        await client.query('ROLLBACK').catch(()=>{});
        await client.end();
      }
    });
    await t.test('G0.6 academic preview is scoped to active school personnel',async()=>{
      const client=new pg.Client({connectionString:url.href});await client.connect();
      try {
        await client.query('BEGIN');
        await client.query(fixtures);
        const asUser=async n=>{
          await client.query('RESET ROLE');
          await client.query("SELECT set_config('request.jwt.claim.sub',$1,true)",[id(1000+n)]);
          await client.query('SET LOCAL ROLE authenticated');
        };
        await asUser(1);
        const empty=await client.query('SELECT * FROM public.kabarkelas_ews_academic_preview($1,70,2)',[id(201)]);
        assert.equal(empty.rows.length,0,'Draft grades do not trigger warnings');
        await asUser(3);
        await client.query('SAVEPOINT denied');
        await assert.rejects(client.query('SELECT * FROM public.kabarkelas_ews_academic_preview($1,70,2)',[id(201)]),e=>e.code==='42501');
        await client.query('ROLLBACK TO SAVEPOINT denied');
        await asUser(5);
        await client.query('SAVEPOINT other_school');
        await assert.rejects(client.query('SELECT * FROM public.kabarkelas_ews_academic_preview($1,70,2)',[id(201)]),e=>e.code==='42501');
        await client.query('ROLLBACK TO SAVEPOINT other_school');
      } finally {await client.query('ROLLBACK').catch(()=>{});await client.end();}
    });
    await t.test('G0.6 attendance preview respects staff scope and missing data',async()=>{
      const client=new pg.Client({connectionString:url.href});await client.connect();
      try {
        await client.query('BEGIN');
        await client.query(fixtures);
        const asUser=async n=>{
          await client.query('RESET ROLE');
          await client.query("SELECT set_config('request.jwt.claim.sub',$1,true)",[id(1000+n)]);
          await client.query('SET LOCAL ROLE authenticated');
        };
        await asUser(1);
        const empty=await client.query("SELECT * FROM public.kabarkelas_ews_attendance_preview($1,'2026-01-01','2026-03-01',3)",[id(201)]);
        assert.equal(empty.rows.length,0);
        await asUser(3);
        await client.query('SAVEPOINT guardian_denied');
        await assert.rejects(client.query("SELECT * FROM public.kabarkelas_ews_attendance_preview($1,'2026-01-01','2026-03-01',3)",[id(201)]),e=>e.code==='42501');
        await client.query('ROLLBACK TO SAVEPOINT guardian_denied');
        await asUser(5);
        await client.query('SAVEPOINT cross_school_denied');
        await assert.rejects(client.query("SELECT * FROM public.kabarkelas_ews_attendance_preview($1,'2026-01-01','2026-03-01',3)",[id(201)]),e=>e.code==='42501');
        await client.query('ROLLBACK TO SAVEPOINT cross_school_denied');
      }finally{await client.query('ROLLBACK').catch(()=>{});await client.end();}
    });
    await t.test('G0.6 alert inbox and update deny guardians and other-school users',async()=>{
      const client=new pg.Client({connectionString:url.href});await client.connect();
      try{
        await client.query('BEGIN');await client.query(fixtures);
        const asUser=async n=>{await client.query('RESET ROLE');await client.query("SELECT set_config('request.jwt.claim.sub',$1,true)",[id(1000+n)]);await client.query('SET LOCAL ROLE authenticated');};
        await asUser(1);
        const empty=await client.query('SELECT * FROM public.kabarkelas_ews_my_alerts($1)',[id(201)]);
        assert.equal(empty.rows.length,0);
        await client.query('SAVEPOINT missing');
        await assert.rejects(client.query("SELECT public.kabarkelas_ews_update_alert($1,'open','resolved','Tidak sah')",[id(810)]),e=>e.code==='42501');
        await client.query('ROLLBACK TO SAVEPOINT missing');
        await asUser(3);
        await client.query('SAVEPOINT guardian');
        await assert.rejects(client.query('SELECT * FROM public.kabarkelas_ews_my_alerts($1)',[id(201)]),e=>e.code==='42501');
        await client.query('ROLLBACK TO SAVEPOINT guardian');
        await asUser(5);
        await client.query('SAVEPOINT school');
        await assert.rejects(client.query('SELECT * FROM public.kabarkelas_ews_my_alerts($1)',[id(201)]),e=>e.code==='42501');
        await client.query('ROLLBACK TO SAVEPOINT school');
      }finally{await client.query('ROLLBACK').catch(()=>{});await client.end();}
    });
    await t.test('G0.6 principals activate rules; scans are idempotent; guardians denied',async()=>{
      const client=new pg.Client({connectionString:url.href});await client.connect();
      try{
        await client.query('BEGIN');await client.query(fixtures);
        const asUser=async n=>{await client.query('RESET ROLE');await client.query("SELECT set_config('request.jwt.claim.sub',$1,true)",[id(1000+n)]);await client.query('SET LOCAL ROLE authenticated');};
        await asUser(1);
        await client.query('SAVEPOINT teacher');
        await assert.rejects(client.query("SELECT public.kabarkelas_ews_activate_rule($1,'academic_low_average',$2::jsonb)",[id(201),JSON.stringify({threshold_percent:70,minimum_assessments:2})]),e=>e.code==='42501');
        await client.query('ROLLBACK TO SAVEPOINT teacher');
        await asUser(2);
        const configured=await client.query("SELECT public.kabarkelas_ews_activate_rule($1,'academic_low_average',$2::jsonb) version",[id(201),JSON.stringify({threshold_percent:70,minimum_assessments:2})]);
        assert.equal(configured.rows[0].version,1);
        const a=await client.query("SELECT public.kabarkelas_ews_scan_school($1,'2026-11-02') data",[id(201)]);
        const b=await client.query("SELECT public.kabarkelas_ews_scan_school($1,'2026-11-02') data",[id(201)]);
        assert.equal(a.rows[0].data.created,0);
        assert.equal(b.rows[0].data.created,0);
        await asUser(3);
        await client.query('SAVEPOINT guardian');
        await assert.rejects(client.query("SELECT public.kabarkelas_ews_scan_school($1,'2026-11-02')",[id(201)]),e=>e.code==='42501');
        await client.query('ROLLBACK TO SAVEPOINT guardian');
      }finally{await client.query('ROLLBACK').catch(()=>{});await client.end();}
    });
    await t.test('G0.6 review followup succeeds, audits, and refuses stale replay',async()=>{
      const client=new pg.Client({connectionString:url.href});await client.connect();
      try{
        await client.query('BEGIN');await client.query(fixtures);
        const asUser=async n=>{await client.query('RESET ROLE');await client.query("SELECT set_config('request.jwt.claim.sub',$1,true)",[id(1000+n)]);await client.query('SET LOCAL ROLE authenticated');};
        await asUser(2);
        await client.query("SELECT public.kabarkelas_ews_activate_rule($1,'academic_low_average',$2::jsonb)",[id(201),JSON.stringify({threshold_percent:70,minimum_assessments:2})]);
        await client.query('RESET ROLE');
        const made=await client.query("INSERT INTO public.ews_alerts(tenant_id,school_id,student_id,rule_id,window_key,severity,explanation) SELECT r.tenant_id,r.school_id,$1,r.id,'2026-11-02','review','Contoh simulasi untuk ditinjau' FROM public.ews_rules r WHERE r.school_id=$2 AND r.rule_key='academic_low_average' RETURNING id",[id(401),id(201)]);
        const alert=made.rows[0].id;
        await asUser(1);
        const changed=await client.query("SELECT public.kabarkelas_ews_update_alert($1,'open','under_review','Guru meninjau konteks') data",[alert]);
        assert.equal(changed.rows[0].data.status,'under_review');
        await client.query('SAVEPOINT stale');
        await assert.rejects(client.query("SELECT public.kabarkelas_ews_update_alert($1,'open','dismissed','Pengulangan tidak valid')",[alert]),e=>e.code==='40001');
        await client.query('ROLLBACK TO SAVEPOINT stale');
        await client.query("SELECT public.kabarkelas_ews_update_alert($1,'under_review','resolved','Pendampingan telah dilaksanakan')",[alert]);
        await client.query('RESET ROLE');
        const rows=await client.query('SELECT previous_status,new_status,note FROM public.ews_followups WHERE alert_id=$1 ORDER BY occurred_at',[alert]);
        assert.deepEqual(rows.rows.map(x=>x.new_status),['under_review','resolved']);
      }finally{await client.query('ROLLBACK').catch(()=>{});await client.end();}
    });
    await t.test('G0.6 finds low averages, creates one alert per scan day, and never duplicates',async()=>{
      const client=new pg.Client({connectionString:url.href});await client.connect();
      try{
        await client.query('BEGIN');await client.query(fixtures);
        await client.query("INSERT INTO public.assessments(id,tenant_id,school_id,class_id,subject_id,period_id,title,max_score,created_by) SELECT $1,tenant_id,school_id,class_id,subject_id,period_id,'Penilaian kedua',100,created_by FROM public.assessments WHERE id=$2",[id(704),id(701)]);
        await client.query("INSERT INTO public.student_grades(id,tenant_id,school_id,assessment_id,student_id,score) SELECT $1,tenant_id,school_id,$2,student_id,60 FROM public.student_grades WHERE id=$3",[id(804),id(704),id(801)]);
        const asUser=async n=>{await client.query('RESET ROLE');await client.query("SELECT set_config('request.jwt.claim.sub',$1,true)",[id(1000+n)]);await client.query('SET LOCAL ROLE authenticated');};
        await asUser(1);
        await client.query("SELECT public.kabarkelas_record_attempt($1,'initial',60,'Nilai awal')",[id(801)]);
        await client.query('SELECT public.kabarkelas_finalize_assessment($1)',[id(801)]);
        await client.query("SELECT public.kabarkelas_record_attempt($1,'initial',60,'Nilai awal')",[id(804)]);
        await client.query('SELECT public.kabarkelas_finalize_assessment($1)',[id(804)]);
        await asUser(2);
        await client.query("SELECT public.kabarkelas_ews_activate_rule($1,'academic_low_average',$2::jsonb)",[id(201),JSON.stringify({threshold_percent:70,minimum_assessments:2})]);
        const first=await client.query("SELECT public.kabarkelas_ews_scan_school($1,'2026-11-02') data",[id(201)]);
        const next=await client.query("SELECT public.kabarkelas_ews_scan_school($1,'2026-11-02') data",[id(201)]);
        assert.equal(first.rows[0].data.created,1);
        assert.equal(next.rows[0].data.created,0);
        const alerts=await client.query('SELECT * FROM public.kabarkelas_ews_my_alerts($1)',[id(201)]);
        assert.equal(alerts.rows.length,1);
        assert.equal(alerts.rows[0].student_name,'Siswa Simulasi G05 1');
      }finally{await client.query('ROLLBACK').catch(()=>{});await client.end();}
    });
    await t.test('G0.7 security regression: browser roles cannot read private tables',async()=>{
      const client=new pg.Client({connectionString:url.href});await client.connect();
      try{
        await client.query('BEGIN');await client.query(fixtures);
        for(const role of ['anon','authenticated']){
          await client.query('RESET ROLE');await client.query('SET LOCAL ROLE '+role);
          for(const table of ['student_grades','assessment_attempts','assessment_corrections','assessment_releases','school_report_snapshots','ews_alerts','ews_followups']){
            await client.query('SAVEPOINT deny_select');
            await assert.rejects(client.query('SELECT * FROM public.'+table+' LIMIT 1'),e=>e.code==='42501',role+' should not SELECT '+table);
            await client.query('ROLLBACK TO SAVEPOINT deny_select');
          }
        }
        await client.query('RESET ROLE');
        const grants=await client.query("SELECT count(*)::integer n FROM information_schema.role_table_grants WHERE table_schema='public' AND grantee IN ('anon','authenticated')");
        assert.equal(grants.rows[0].n,0);
      }finally{await client.query('ROLLBACK').catch(()=>{});await client.end();}
    });
    // Separate connections prove row locking, not just sequential JS behavior.
    await db.query(fixtures);
    const connect = async user => {
      const c = new pg.Client({connectionString:url.href}); await c.connect();
      await c.query('BEGIN'); await c.query("SELECT set_config('request.jwt.claim.sub',$1,true)",[id(1000+user)]);
      await c.query('SET LOCAL ROLE authenticated'); return c;
    };
    await t.test('concurrent submissions serialize: exactly one event',async()=>{
      const a=await connect(1), b=await connect(1);
      try{
        const sql='SELECT public.kabarkelas_transition_grade($1,\'submit\',1)';
        await a.query(sql,[id(801)]);
        const pending=b.query(sql,[id(801)]).then(()=>null,e=>e);
        await a.query('COMMIT');
        assert.equal((await pending).code,'40001'); await b.query('ROLLBACK');
        assert.equal((await db.query('SELECT count(*)::int n FROM public.academic_workflow_events WHERE resource_id=$1',[id(801)])).rows[0].n,1);
      }finally{await a.end();await b.end();}
    });
    await t.test('concurrent publications create exactly one immutable snapshot',async()=>{
      const a=await connect(2), b=await connect(2);
      try{
        await a.query("SELECT public.kabarkelas_transition_grade($1,'approve',2)",[id(801)]);
        await a.query('COMMIT'); await a.query('BEGIN');
        await a.query("SELECT set_config('request.jwt.claim.sub',$1,true)",[id(1002)]);await a.query('SET LOCAL ROLE authenticated');
        const sql="SELECT public.kabarkelas_transition_grade($1,'publish',3)";
        await a.query(sql,[id(801)]); const pending=b.query(sql,[id(801)]).then(()=>null,e=>e);
        await a.query('COMMIT'); assert.equal((await pending).code,'40001'); await b.query('ROLLBACK');
        assert.equal((await db.query('SELECT count(*)::int n FROM public.academic_publication_snapshots WHERE resource_id=$1',[id(801)])).rows[0].n,1);
      }finally{await a.end();await b.end();}
    });
  } finally {
    await db.end(); await admin.query(`DROP DATABASE ${name} WITH (FORCE)`); await admin.end();
  }
});
