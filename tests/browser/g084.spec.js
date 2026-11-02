import {test,expect} from '@playwright/test';
test('principal approves school indicator through server RPC',async({page})=>{
 const user={id:'f0050000-0000-4000-8000-000000001002',email:'principal@example.invalid',aud:'authenticated',role:'authenticated'};
 const session={access_token:'synthetic-ui-token',refresh_token:'synthetic-refresh',expires_at:Math.floor(Date.now()/1000)+3600,expires_in:3600,token_type:'bearer',user};
 const calls=[];
 await page.addInitScript(s=>localStorage.setItem('sb-g05-ui-test-auth-token',JSON.stringify(s)),session);
 await page.route('https://g05-ui-test.supabase.co/**',async route=>{
   const path=new URL(route.request().url()).pathname;let body;
   if(path==='/auth/v1/user')body=user;
   else if(path.endsWith('/kabarkelas_my_context'))body={state:'active',units:[{membership_id:'m',tenant_id:'t',tenant_name:'Demo',school_id:'s',school_name:'Sekolah Uji',role:'principal'}]};
   else if(path.endsWith('/kabarkelas_approve_development_indicator')){calls.push(route.request().postDataJSON());body='rubric-id';}
   else throw Error('Unexpected '+path);
   await route.fulfill({status:200,contentType:'application/json',body:JSON.stringify(body)});
 });
 await page.goto('/');
 const region=page.getByRole('region',{name:'Pengelolaan rubrik sekolah'});
 await region.getByPlaceholder('Kode indikator').fill('CHAR-01');
 await region.getByPlaceholder('Nama indikator').fill('Kemandirian');
 await region.getByRole('combobox',{name:'Domain rubrik'}).selectOption('character');
 await region.getByRole('button',{name:'Setujui indikator'}).click();
 await expect(region.getByText('Indikator disetujui dan dapat dipakai guru.')).toBeVisible();
 expect(calls).toEqual([{p_school:'s',p_domain:'character',p_code:'CHAR-01',p_label:'Kemandirian'}]);
});
