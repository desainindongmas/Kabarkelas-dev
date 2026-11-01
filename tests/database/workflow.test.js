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
        await asUser(2);
        await assert.rejects(testClient.query("SELECT public.kabarkelas_record_attempt($1,'remedial',90,'Tidak berhak')",[grade]),e=>e.code==='42501');
      } finally {
        await testClient.query('ROLLBACK').catch(()=>{});
        await testClient.end();
      }
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
