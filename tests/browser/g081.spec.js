import {test,expect} from '@playwright/test';
async function setup(page,role,{fail=false}={}){
 const user={id:'f0050000-0000-4000-8000-000000001001',email:'demo@example.invalid',aud:'authenticated',role:'authenticated'};
 const session={access_token:'synthetic-ui-token',refresh_token:'synthetic-refresh',expires_at:Math.floor(Date.now()/1000)+3600,expires_in:3600,token_type:'bearer',user};
 await page.addInitScript(s=>localStorage.setItem('sb-g05-ui-test-auth-token',JSON.stringify(s)),session);
 await page.route('https://g05-ui-test.supabase.co/**',async route=>{
   const path=new URL(route.request().url()).pathname;
   if(path==='/auth/v1/user')return route.fulfill({status:200,contentType:'application/json',body:JSON.stringify(user)});
   if(path.endsWith('/kabarkelas_my_context'))return route.fulfill({status:200,contentType:'application/json',body:JSON.stringify({state:'active',units:[{membership_id:'m',tenant_id:'t',tenant_name:'Demo',school_id:'s',school_name:'SD Simulasi',role}]})});
   if(path.endsWith('/kabarkelas_my_students')||path.endsWith('/kabarkelas_my_role_students')){
     if(fail)return route.fulfill({status:403,contentType:'application/json',body:JSON.stringify({message:'denied',code:'42501'})});
     return route.fulfill({status:200,contentType:'application/json',body:JSON.stringify([{local_student_no:'SIM-001',display_name:'Siswa A'},{local_student_no:'SIM-002',display_name:'Siswa B'}])});
   }
   if(path.endsWith('/kabarkelas_ews_my_alerts'))return route.fulfill({status:200,contentType:'application/json',body:JSON.stringify([{alert_status:'open'},{alert_status:'resolved'},{alert_status:'under_review'}])});
   throw Error('Unexpected '+path);
 });
 await page.goto('/');
}
test('G0.8.1 teacher sees API-based student and active EWS counts',async({page})=>{
 await setup(page,'teacher');
 const region=page.getByRole('region',{name:'Ringkasan data sekolah'});
 await expect(region.getByText('Siswa dalam cakupan')).toBeVisible();
 await expect(region.getByText('2', {exact:true})).toHaveCount(2);
 await expect(region.getByText('Ringkasan berhasil dimuat dari API sekolah.')).toBeVisible();
});
test('G0.8.1 guardian cannot see EWS cards',async({page})=>{
 await setup(page,'guardian');
 const region=page.getByRole('region',{name:'Ringkasan data sekolah'});
 await expect(region.getByText('Anak terhubung')).toBeVisible();
 await expect(region.getByText('Peringatan perlu tindak lanjut')).toHaveCount(0);
});
test('G0.8.1 API denial does not fabricate metrics',async({page})=>{
 await setup(page,'teacher',{fail:true});
 const region=page.getByRole('region',{name:'Ringkasan data sekolah'});
 await expect(region.getByText('Ringkasan belum dapat dimuat. Tidak ada angka perkiraan yang ditampilkan.')).toBeVisible();
 await expect(region.locator('.live-kpi-card')).toHaveCount(0);
});
