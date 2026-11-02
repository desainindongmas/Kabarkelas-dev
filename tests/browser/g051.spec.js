import {test,expect} from '@playwright/test';
async function setup(page,role='teacher'){
 const user={id:'f0050000-0000-4000-8000-000000001001',email:'test@example.invalid',aud:'authenticated',role:'authenticated'};
 const session={access_token:'synthetic-ui-token',refresh_token:'synthetic-refresh',expires_at:Math.floor(Date.now()/1000)+3600,expires_in:3600,token_type:'bearer',user};
 await page.addInitScript(s=>localStorage.setItem('sb-g05-ui-test-auth-token',JSON.stringify(s)),session);
 const attempts=[];const calls=[];
 await page.route('https://g05-ui-test.supabase.co/**',async route=>{
  const path=new URL(route.request().url()).pathname;
  const payload=route.request().postDataJSON?.()||{};
  let data=null;
  if(path==='/auth/v1/user')data=user;
  else if(path.endsWith('/kabarkelas_my_context'))data={state:'active',units:[{membership_id:'test',tenant_id:'t1',tenant_name:'Yayasan',school_id:'s1',school_name:'SD Demo',role}]};
  else if(path.endsWith('/kabarkelas_grade_workflow'))data=[{grade_id:'g1',student_name:'Siswa Simulasi',subject_name:'Matematika',assessment_title:'Penilaian',score:65,grade_status:'draft',revision:1,allowed_actions:[]}];
  else if(path.endsWith('/kabarkelas_list_attempts'))data=attempts;
  else if(path.endsWith('/kabarkelas_attempt_summary'))data=[{attempt_count:attempts.length,effective_score:attempts.length?Math.max(...attempts.map(a=>a.score)):null,policy_mode:'best_score'}];
  else if(path.endsWith('/kabarkelas_record_attempt')){calls.push(payload);attempts.push({attempt_id:'attempt-'+attempts.length,attempt_kind:payload.p_kind,score:payload.p_score});data='ok';}
  else if(path.endsWith('/kabarkelas_correct_attempt')){calls.push(payload);attempts.find(a=>a.attempt_id===payload.p_attempt).score=payload.p_new_score;data='corrected';}
  else if(path.endsWith('/kabarkelas_finalize_assessment')){calls.push(payload);data={version:1,status:'released',effective_score:Math.max(...attempts.map(a=>a.score))};}
  else if(path.endsWith('/kabarkelas_school_assessment_policy'))data=[{policy_version:0,mode:'best_score',parent_visibility:'after_release',cap_percent:null}];
  else if(path.endsWith('/kabarkelas_set_school_assessment_policy')){calls.push(payload);data=1;}
  else if(path.endsWith('/kabarkelas_parent_assessments'))data=[{student_name:'Siswa Simulasi',subject_name:'Matematika',assessment_title:'Penilaian',score:70,release_version:1}];
  else if(path.endsWith('/kabarkelas_my_released_reports'))data=[];
  else if(path.endsWith('/kabarkelas_my_class_reports'))data=[];
  else if(path.endsWith('/kabarkelas_report_setup_options'))data=[];
  else if(path.endsWith('/kabarkelas_my_grades'))data=[];
  else if(path.endsWith('/kabarkelas_my_role_students'))data=[];
  else if(path.endsWith('/kabarkelas_my_students'))data=[];
  else throw new Error('Unexpected RPC: '+path);
  await route.fulfill({status:200,contentType:'application/json',body:JSON.stringify(data)});
 });
 await page.goto('/');
 return {attempts,calls};
}
test('guru mengoreksi salah input, mencatat remedial rendah dan finalisasi sendiri',async({page})=>{
 const {calls}=await setup(page,'teacher');
 await page.getByRole('button',{name:'Lihat penilaian akademik',exact:true}).click();
 await page.getByRole('button',{name:'Kelola nilai awal & remedial'}).click();
 await page.getByPlaceholder('Nilai awal',{exact:true}).fill('65');
 await page.getByRole('button',{name:'Catat nilai awal'}).click();
 await expect(page.getByText(/Nilai olahan saat ini: 65/)).toBeVisible();
 await page.getByPlaceholder('Nilai koreksi').first().fill('70');
 await page.getByPlaceholder(/Alasan koreksi/).first().fill('Salah ketik');
 await page.getByRole('button',{name:'Koreksi'}).first().click();
 await expect(page.getByText(/Nilai olahan saat ini: 70/)).toBeVisible();
 await page.getByPlaceholder('Nilai remedial').fill('58');
 await page.getByRole('button',{name:'Tambah remedial'}).click();
 await expect(page.getByText(/Nilai olahan saat ini: 70/)).toBeVisible();
 page.on('dialog',dialog=>dialog.accept());
 await page.getByRole('button',{name:'Finalisasi nilai harian'}).click();
 await expect(page.getByText(/telah dirilis kepada orang tua/)).toBeVisible();
 expect(calls.map(x=>x.p_kind||x.p_reason||x.p_grade)).toEqual(['initial','Salah ketik','remedial','g1']);
});
test('orang tua hanya melihat nilai harian yang dirilis',async({page})=>{
 await setup(page,'guardian');
 await page.getByRole('button',{name:'Lihat nilai harian yang sudah dirilis'}).click();
 await expect(page.getByText(/Penilaian · Nilai 70 · Versi 1/)).toBeVisible();
 await expect(page.getByRole('button',{name:'Kelola nilai awal & remedial'})).toHaveCount(0);
});
test('kepala sekolah dapat memilih kebijakan remedial terbaru dengan konfirmasi',async({page})=>{
 const {calls}=await setup(page,'principal');
 await page.getByRole('button',{name:'Atur kebijakan remedial & rilis nilai'}).click();
 await page.locator('select:has(option[value="latest_score"])').selectOption('latest_score');
 page.on('dialog',dialog=>dialog.accept());
 await page.getByRole('button',{name:'Simpan versi kebijakan baru'}).click();
 await expect(page.getByText(/Kebijakan versi 1 tersimpan/)).toBeVisible();
 expect(calls.at(-1).p_mode).toBe('latest_score');
});
