import {test,expect} from '@playwright/test';
test('guardian sees published academic trend points only from authorized RPC',async({page})=>{
 const user={id:'f0050000-0000-4000-8000-000000001001',email:'parent@example.invalid',aud:'authenticated',role:'authenticated'};
 const session={access_token:'synthetic-ui-token',refresh_token:'synthetic-refresh',expires_at:Math.floor(Date.now()/1000)+3600,expires_in:3600,token_type:'bearer',user};
 await page.addInitScript(s=>localStorage.setItem('sb-g05-ui-test-auth-token',JSON.stringify(s)),session);
 await page.route('https://g05-ui-test.supabase.co/**',async route=>{
  const p=new URL(route.request().url()).pathname;let data;
  if(p==='/auth/v1/user')data=user;
  else if(p.endsWith('/kabarkelas_my_context'))data={state:'active',units:[{membership_id:'m',tenant_id:'t',tenant_name:'Demo',school_id:'s',school_name:'SD Uji',role:'guardian'}]};
  else if(p.endsWith('/kabarkelas_guardian_academic_trends'))data=[{student_id:'a',student_name:'Nadia',subject_name:'Matematika',assessment_title:'Latihan 1',score_percent:82,released_at:'2026-10-01T00:00:00Z'},{student_id:'a',student_name:'Nadia',subject_name:'Matematika',assessment_title:'Latihan 2',score_percent:70,released_at:'2026-11-01T00:00:00Z'}];
  else throw new Error('Unexpected '+p);
  await route.fulfill({status:200,contentType:'application/json',body:JSON.stringify(data)});
 });
 await page.goto('/');
 const region=page.getByRole('region',{name:'Grafik perkembangan akademik'});
 await region.getByRole('button',{name:'Muat grafik akademik'}).click();
 await expect(region.getByText('Nadia · Matematika')).toBeVisible();
 await expect(region.locator('circle')).toHaveCount(2);
 await expect(region.getByText('Latihan 1 — 82%')).toBeVisible();
});
test('teacher does not receive guardian chart',async({page})=>{
 const user={id:'f0050000-0000-4000-8000-000000001001',email:'teacher@example.invalid',aud:'authenticated',role:'authenticated'};
 const session={access_token:'synthetic-ui-token',refresh_token:'synthetic-refresh',expires_at:Math.floor(Date.now()/1000)+3600,expires_in:3600,token_type:'bearer',user};
 await page.addInitScript(s=>localStorage.setItem('sb-g05-ui-test-auth-token',JSON.stringify(s)),session);
 await page.route('https://g05-ui-test.supabase.co/**',async route=>{
  const p=new URL(route.request().url()).pathname;let data;
  if(p==='/auth/v1/user')data=user;
  else if(p.endsWith('/kabarkelas_my_context'))data={state:'active',units:[{membership_id:'m',tenant_id:'t',tenant_name:'Demo',school_id:'s',school_name:'SD Uji',role:'teacher'}]};
  else throw Error('Unexpected '+p);
  await route.fulfill({status:200,contentType:'application/json',body:JSON.stringify(data)});
 });
 await page.goto('/');
 await expect(page.getByRole('region',{name:'Grafik perkembangan akademik'})).toHaveCount(0);
});
