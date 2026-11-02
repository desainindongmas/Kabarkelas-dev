import {test,expect} from '@playwright/test';
test('teacher correction and withdrawal sends expected revision and mandatory reason',async({page})=>{
 const user={id:'f0050000-0000-4000-8000-000000001001',email:'teacher@example.invalid',aud:'authenticated',role:'authenticated'};
 const session={access_token:'synthetic-ui-token',refresh_token:'synthetic-refresh',expires_at:Math.floor(Date.now()/1000)+3600,expires_in:3600,token_type:'bearer',user};
 const calls=[];let version=1,withdrawn=false;
 await page.addInitScript(s=>localStorage.setItem('sb-g05-ui-test-auth-token',JSON.stringify(s)),session);
 await page.route('https://g05-ui-test.supabase.co/**',async route=>{
  const p=new URL(route.request().url()).pathname;let data;
  if(p==='/auth/v1/user')data=user;
  else if(p.endsWith('/kabarkelas_my_context'))data={state:'active',units:[{membership_id:'m',tenant_id:'t',tenant_name:'Demo',school_id:'s',school_name:'Sekolah Uji',role:'teacher'}]};
  else if(p.endsWith('/kabarkelas_teacher_observations'))data=[{observation_id:'obs1',student_name:'Siswa Uji',indicator_label:'Kemandirian',domain:'character',score:3,evidence:'Observasi bukti awal',state:withdrawn?'withdrawn':'published',revision:version}];
  else if(p.endsWith('/kabarkelas_update_development_observation')){const v=route.request().postDataJSON();calls.push(v);version++;if(v.p_action==='withdraw')withdrawn=true;data=version;}
  else throw Error('Unexpected '+p);
  await route.fulfill({status:200,contentType:'application/json',body:JSON.stringify(data)});
 });
 await page.goto('/');
 const region=page.getByRole('region',{name:'Koreksi dan pencabutan observasi'});
 await region.getByRole('button',{name:'Muat observasi saya'}).click();
 await region.getByPlaceholder('Alasan koreksi atau pencabutan (minimal 8 karakter)').fill('Verifikasi dokumen terbaru');
 await region.getByRole('button',{name:'Simpan koreksi'}).click();
 await expect(region.getByText('Status: published · Versi 2 · Skor 3/4')).toBeVisible();
 expect(calls[0]).toMatchObject({p_observation:'obs1',p_revision:1,p_action:'correct',p_reason:'Verifikasi dokumen terbaru'});
 await region.getByPlaceholder('Alasan koreksi atau pencabutan (minimal 8 karakter)').fill('Data tidak lagi berlaku');
 await region.getByRole('button',{name:'Cabut observasi'}).click();
 await expect(region.getByText('Status: withdrawn · Versi 3 · Skor 3/4')).toBeVisible();
 expect(calls[1]).toMatchObject({p_observation:'obs1',p_revision:2,p_action:'withdraw',p_reason:'Data tidak lagi berlaku'});
});
