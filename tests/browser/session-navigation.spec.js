// Regression coverage for the live dashboard account controls.
// Uses synthetic users and mocked Supabase responses; not a real Auth E2E test.
import {test, expect} from '@playwright/test';

async function openDashboard(page,{multipleUnits=false}={}){
 const user={id:'f0050000-0000-4000-8000-000000001001',email:'pilot.guru@example.invalid',aud:'authenticated',role:'authenticated'};
 const session={access_token:'synthetic-ui-token',refresh_token:'synthetic-refresh',expires_at:Math.floor(Date.now()/1000)+3600,expires_in:3600,token_type:'bearer',user};
 await page.addInitScript(s=>localStorage.setItem('sb-g05-ui-test-auth-token',JSON.stringify(s)),session);
 let logoutCount=0;
 await page.route('https://g05-ui-test.supabase.co/**', async route=>{
  const path=new URL(route.request().url()).pathname;
  if(path==='/auth/v1/user')return route.fulfill({status:200,contentType:'application/json',body:JSON.stringify(user)});
  if(path==='/auth/v1/logout'){logoutCount++;return route.fulfill({status:204,body:''});}
  if(path.endsWith('/kabarkelas_my_context')){
   const units=[{membership_id:'m1',tenant_id:'t1',tenant_name:'Yayasan Simulasi',school_id:'s1',school_name:'Sekolah A',role:'teacher'}];
   if(multipleUnits)units.push({membership_id:'m2',tenant_id:'t1',tenant_name:'Yayasan Simulasi',school_id:'s1',school_name:'Sekolah A',role:'principal'});
   return route.fulfill({status:200,contentType:'application/json',body:JSON.stringify({state:'active',user_id:'teacher',units})});
  }
  throw new Error('Unexpected Supabase call '+path);
 });
 await page.goto('/');
 if(multipleUnits){
  await expect(page.getByRole('heading',{name:'Pilih unit sekolah'})).toBeVisible();
  await page.getByRole('button',{name:/Yayasan Simulasi.*teacher/}).click();
 }
 await expect(page.getByRole('heading',{name:'Dashboard Guru'})).toBeVisible();
 return ()=>logoutCount;
}

test('sidebar Keluar calls Supabase signOut and shows login',async({page})=>{
 const logouts=await openDashboard(page);
 const button=page.getByRole('navigation',{name:'Navigasi ruang kerja'}).getByRole('button',{name:'Keluar',exact:true});
 await expect(button).toBeVisible();
 await button.click();
 await expect(page.getByRole('heading',{name:'Masuk ke akun Anda'})).toBeVisible();
 expect(logouts()).toBe(1);
});

test('single membership offers Ganti akun, not misleading Ganti unit',async({page})=>{
 const logouts=await openDashboard(page);
 const nav=page.getByRole('navigation',{name:'Navigasi ruang kerja'});
 await expect(nav.getByRole('button',{name:'Ganti unit'})).toHaveCount(0);
 await nav.getByRole('button',{name:'Ganti akun'}).click();
 await expect(page.getByRole('heading',{name:'Masuk ke akun Anda'})).toBeVisible();
 expect(logouts()).toBe(1);
});

test('multiple memberships allow switching only among authorized memberships',async({page})=>{
 const logouts=await openDashboard(page,{multipleUnits:true});
 const nav=page.getByRole('navigation',{name:'Navigasi ruang kerja'});
 await nav.getByRole('button',{name:'Ganti unit'}).click();
 await expect(page.getByRole('heading',{name:'Pilih unit sekolah'})).toBeVisible();
 await page.getByRole('button',{name:/Yayasan Simulasi.*principal/}).click();
 await expect(page.getByRole('heading',{name:'Dashboard Kepala Sekolah'})).toBeVisible();
 expect(logouts()).toBe(0);
});
