import {test,expect} from '@playwright/test';
test('G0.8 teacher dashboard renders responsive navigation and preserves student module',async({page})=>{
 const user={id:'f0050000-0000-4000-8000-000000001001',email:'teacher@example.invalid',aud:'authenticated',role:'authenticated'};
 const session={access_token:'synthetic-ui-token',refresh_token:'synthetic-refresh',expires_at:Math.floor(Date.now()/1000)+3600,expires_in:3600,token_type:'bearer',user};
 await page.addInitScript(s=>localStorage.setItem('sb-g05-ui-test-auth-token',JSON.stringify(s)),session);
 await page.route('https://g05-ui-test.supabase.co/**',async route=>{
   const path=new URL(route.request().url()).pathname;
   let data;
   if(path==='/auth/v1/user')data=user;
   else if(path.endsWith('/kabarkelas_my_context'))data={state:'active',units:[{membership_id:'m',tenant_id:'t',tenant_name:'Yayasan Simulasi',school_id:'s',school_name:'SD Demo',role:'teacher'}]};
   else if(path.endsWith('/kabarkelas_my_students'))data=[{display_name:'Nadia Simulasi',class_name:'Kelas 5A Uji',local_student_no:'SIM-001'}];
   else throw Error('Unexpected RPC '+path);
   await route.fulfill({status:200,contentType:'application/json',body:JSON.stringify(data)});
 });
 await page.goto('/');
 await expect(page.getByRole('heading',{name:'Dashboard Guru'})).toBeVisible();
 await expect(page.getByRole('navigation',{name:'Navigasi ruang kerja'})).toBeVisible();
 await page.getByRole('button',{name:'Lihat siswa yang saya ajar',exact:true}).click();
 await expect(page.getByText('Nadia Simulasi')).toBeVisible();
 await page.setViewportSize({width:390,height:844});
 await expect(page.getByRole('heading',{name:'Dashboard Guru'})).toBeVisible();
 await expect(page.getByRole('button',{name:'Ganti unit',exact:true})).toBeVisible();
});
