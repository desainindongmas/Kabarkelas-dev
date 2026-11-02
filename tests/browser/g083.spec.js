import {test,expect} from '@playwright/test';
async function setup(page,role){
 const user={id:'f0050000-0000-4000-8000-000000001001',email:'demo@example.invalid',aud:'authenticated',role:'authenticated'};
 const session={access_token:'synthetic-ui-token',refresh_token:'synthetic-refresh',expires_at:Math.floor(Date.now()/1000)+3600,expires_in:3600,token_type:'bearer',user};
 await page.addInitScript(s=>localStorage.setItem('sb-g05-ui-test-auth-token',JSON.stringify(s)),session);
 await page.route('https://g05-ui-test.supabase.co/**',async route=>{
 const p=new URL(route.request().url()).pathname;let data;
 if(p==='/auth/v1/user')data=user;
 else if(p.endsWith('/kabarkelas_my_context'))data={state:'active',units:[{membership_id:'m',tenant_id:'t',tenant_name:'Yayasan Demo',school_id:'s',school_name:'Sekolah Demo',role}]};
 else if(p.endsWith('/kabarkelas_guardian_development_radar'))data=[{student_name:'Nadia',domain:'character',indicator_code:'CHAR-01',indicator_label:'Kemandirian',average_score:3,observation_count:2},{student_name:'Nadia',domain:'character',indicator_code:'CHAR-02',indicator_label:'Kerja sama',average_score:4,observation_count:1},{student_name:'Nadia',domain:'character',indicator_code:'CHAR-03',indicator_label:'Tanggung jawab',average_score:2,observation_count:1}];
 else if(p.endsWith('/kabarkelas_teacher_development_options'))data=[{student_id:'student-1',student_name:'Nadia',class_id:'class-1',class_name:'Kelas 5A'}];
 else if(p.endsWith('/kabarkelas_teacher_development_observe'))data='observation-id';
 else throw new Error('Unexpected '+p);
 await route.fulfill({status:200,contentType:'application/json',body:JSON.stringify(data)});
 });
 await page.goto('/');
}
test('guardian sees published development indicators with real API fields',async({page})=>{
 await setup(page,'guardian');
 const region=page.getByRole('region',{name:'Grafik jaring perkembangan'});
 await region.getByRole('button',{name:'Muat jaring perkembangan'}).click();
 await expect(region.getByText('Nadia · Karakter')).toBeVisible();
 await expect(region.getByText('Kemandirian — 3/4 (2 observasi)')).toBeVisible();
 await expect(region.locator('polygon')).toHaveCount(5);
});
test('teacher can record evidence but cannot see guardian radar',async({page})=>{
 await setup(page,'teacher');
 await expect(page.getByRole('region',{name:'Grafik jaring perkembangan'})).toHaveCount(0);
 const region=page.getByRole('region',{name:'Observasi kompetensi dan karakter guru'});
 await region.getByRole('button',{name:'Pilih siswa untuk observasi'}).click();
 await region.getByPlaceholder('Kode indikator (mis. KOM-01)').fill('CHAR-01');
 await region.getByPlaceholder('Nama indikator yang diamati').fill('Kemandirian');
 await region.getByPlaceholder('Bukti pengamatan (minimal 8 karakter)').fill('Mengerjakan tugas secara mandiri');
 await region.getByRole('button',{name:'Simpan observasi'}).click();
 await expect(region.getByText('Observasi berhasil disimpan sebagai draf.')).toBeVisible();
});
