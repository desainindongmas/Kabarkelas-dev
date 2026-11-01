// UI contract tests: Auth and HTTP responses are stubbed; SQL authorization is tested separately.
import { test, expect } from '@playwright/test';
async function setup(page,{role='teacher',status='draft',actions=['submit'],failure=null}={}){
  const user={id:'f0050000-0000-4000-8000-000000001001',email:'teacher@example.invalid',aud:'authenticated',role:'authenticated'};
  const session={access_token:'synthetic-ui-token',refresh_token:'synthetic-refresh',expires_at:Math.floor(Date.now()/1000)+3600,expires_in:3600,token_type:'bearer',user};
  await page.addInitScript(session=>localStorage.setItem('sb-g05-ui-test-auth-token',JSON.stringify(session)),session);
  let current=status; let revision=1; const calls=[];
  await page.route('https://g05-ui-test.supabase.co/**',async route=>{
    const path=new URL(route.request().url()).pathname;
    let data=null; let code=200;
    if(path==='/auth/v1/user') data=user;
    else if(path.endsWith('/kabarkelas_my_context')) data={state:'active',user_id:'teacher',units:[{membership_id:'m1',tenant_id:'t1',tenant_name:'Yayasan Simulasi',school_id:'s1',school_name:'Sekolah Simulasi',role}]};
    else if(path.endsWith('/kabarkelas_grade_workflow')) data=[{grade_id:'g1',student_name:'Nadia Simulasi',subject_name:'Matematika',assessment_title:'Uji Simulasi',score:82,grade_status:current,revision,allowed_actions:actions.filter(a=>({submit:'draft',approve:'submitted',publish:'approved'})[a]===current)}];
    else if(path.endsWith('/kabarkelas_transition_grade')){
      calls.push(route.request().postDataJSON());
      await new Promise(resolve=>setTimeout(resolve,100));
      if(failure){code=400;data={code:failure,message:'denied'};if(failure==='40001'){current='submitted';revision++;}}
      else{current=({submit:'submitted',approve:'approved',publish:'published'})[calls.at(-1).p_action];revision++;data={status:current,revision};}
    }else throw new Error('Unexpected request '+path);
    await route.fulfill({status:code,contentType:'application/json',body:JSON.stringify(data)});
  });
  await page.goto('/');
  await page.getByRole('button',{name:role==='guardian'?'Lihat nilai yang sudah diterbitkan':'Lihat penilaian akademik',exact:true}).click();
  return calls;
}
for(const [role,status,action] of [['teacher','draft','Submit'],['principal','submitted','Approve'],['principal','approved','Publish']]){
  test(`${role} ${action} sends grade ID and revision; refreshes after success`,async({page})=>{
    const calls=await setup(page,{role,status,actions:[action.toLowerCase()]});
    const button=page.getByRole('button',{name:action,exact:true});await button.click();await expect(button).toBeDisabled();
    await expect(page.getByText('Transisi nilai berhasil.')).toBeVisible();
    expect(calls).toEqual([{p_grade_id:'g1',p_action:action.toLowerCase(),p_expected_revision:1}]);
    await expect(page.getByRole('button',{name:action,exact:true})).toHaveCount(0);
  });
}
test('guardian only sees published grade and no workflow buttons',async({page})=>{
 await setup(page,{role:'guardian',status:'published',actions:[]});
 await expect(page.getByText('Uji Simulasi · Nilai 82 · published')).toBeVisible();
 await expect(page.getByRole('button',{name:/^(Submit|Approve|Publish)$/})).toHaveCount(0);
});
test('server denial hides action even for principal',async({page})=>{
 await setup(page,{role:'principal',status:'submitted',actions:[]});
 await expect(page.getByRole('button',{name:'Approve',exact:true})).toHaveCount(0);
});
test('stale revision reloads authoritative state',async({page})=>{
 await setup(page,{failure:'40001'});await page.getByRole('button',{name:'Submit',exact:true}).click();
 await expect(page.getByText(/Status sudah berubah/)).toBeVisible();
 await expect(page.getByText('Uji Simulasi · Nilai 82 · submitted')).toBeVisible();
});
test('permission failure never reports success and re-enables button',async({page})=>{
 await setup(page,{failure:'42501'});const b=page.getByRole('button',{name:'Submit',exact:true});await b.click();
 await expect(page.getByText(/Transisi gagal/)).toBeVisible();await expect(b).toBeEnabled();
 await expect(page.getByText('Transisi nilai berhasil.')).toHaveCount(0);
});
