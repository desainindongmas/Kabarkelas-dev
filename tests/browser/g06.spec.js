import {test,expect} from '@playwright/test';
test('teacher EWS preview shows academic results, empty attendance, and no guardian data',async({page})=>{
 const user={id:'f0050000-0000-4000-8000-000000001001',email:'teacher@example.invalid',aud:'authenticated',role:'authenticated'};
 const session={access_token:'synthetic-ui-token',refresh_token:'synthetic-refresh',expires_at:Math.floor(Date.now()/1000)+3600,expires_in:3600,token_type:'bearer',user};
 await page.addInitScript(s=>localStorage.setItem('sb-g05-ui-test-auth-token',JSON.stringify(s)),session);
 await page.route('https://g05-ui-test.supabase.co/**',async route=>{
  const path=new URL(route.request().url()).pathname;
  let data;
  if(path==='/auth/v1/user')data=user;
  else if(path.endsWith('/kabarkelas_my_context'))data={state:'active',units:[{membership_id:'m',tenant_id:'t',tenant_name:'Simulasi',school_id:'s',school_name:'SD Demo',role:'teacher'}]};
  else if(path.endsWith('/kabarkelas_ews_academic_preview'))data=[{student_id:'student',student_name:'Nadia Simulasi',assessment_count:2,average_percent:76,requires_review:false}];
  else if(path.endsWith('/kabarkelas_ews_attendance_preview'))data=[];
  else if(path.endsWith('/kabarkelas_ews_my_alerts'))data=[];
  else throw new Error('Unexpected '+path);
  await route.fulfill({status:200,contentType:'application/json',body:JSON.stringify(data)});
 });
 await page.goto('/');
 await page.getByRole('button',{name:'Pratinjau pendampingan siswa (EWS)'}).click();
 await expect(page.getByText(/Rata-rata 76% dari 2 penilaian final/)).toBeVisible();
 await expect(page.getByText(/Belum ada sesi absensi/)).toBeVisible();
 await expect(page.getByText(/Belum ada peringatan yang diaktifkan sekolah/)).toBeVisible();
 await expect(page.getByRole('button',{name:'Aktifkan aturan akademik'})).toHaveCount(0);
});
