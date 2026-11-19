import { createClient } from '@supabase/supabase-js';
import './style.css';
import { availableActions } from './workflow-rules.js';

const url = import.meta.env.VITE_SUPABASE_URL;
const key = import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY;
const app = document.querySelector('#app');
const configured = Boolean(url && key && !key.startsWith('REPLACE_'));
const supabase = configured ? createClient(url, key, {auth:{autoRefreshToken:true,persistSession:true,detectSessionInUrl:true}}) : null;
let currentContext = null;
let activeMembership = null;

function el(tag, text, className) {
  const node = document.createElement(tag);
  if (text != null) node.textContent = text;
  if (className) node.className = className;
  return node;
}
function panel(title, subtitle) {
  app.replaceChildren();
  const box = el('section', null, 'card');
  const brand = el('div', '📚 KabarKelas', 'brand');
  box.append(brand,el('h1',title),el('p',subtitle,'muted'));
  app.append(box);
  return box;
}
function message(box, text, isError = false) {
  let status = box.querySelector('[role="status"]');
  if(!status){status = el('p'); status.setAttribute('role','status'); status.setAttribute('aria-live','polite');box.append(status);}
  status.className = isError ? 'error' : 'muted';
  status.textContent = text;
}
function showLogin() {
 const box = panel('Masuk ke akun Anda','Gunakan akun yang sudah didaftarkan oleh sekolah.');
 if(!configured){message(box,'Konfigurasi Supabase belum tersedia. Isi .env.local sesuai panduan README.',true);return;}
 const form = el('form');
 const email = el('input'); email.type='email'; email.autocomplete='email'; email.placeholder='Email'; email.required=true;
 const pass = el('input'); pass.type='password';pass.autocomplete='current-password';pass.placeholder='Password';pass.required=true;
 const btn=el('button','Masuk');btn.type='submit';
 const reset=el('button','Lupa password?','link');reset.type='button';
 reset.onclick=async()=>{if(!email.value.trim()){message(box,'Isi email dahulu.',true);return;} const {error}=await supabase.auth.resetPasswordForEmail(email.value.trim(),{redirectTo:window.location.origin});message(box,error?'Permintaan belum dapat diproses. Periksa email dan coba lagi.':'Jika email terdaftar, instruksi pemulihan akan dikirim.',Boolean(error));};
 form.append(email,pass,btn,reset);box.append(form);
 form.onsubmit=async(event)=>{event.preventDefault();btn.disabled=true;message(box,'Memeriksa akun...');try{const {error}=await supabase.auth.signInWithPassword({email:email.value.trim(),password:pass.value});if(error){message(box,'Email atau password tidak cocok, atau akun belum dapat digunakan.',true);}else await loadContext();}catch{message(box,'Koneksi login sedang bermasalah. Coba lagi.',true);}finally{btn.disabled=false;}};
}
async function loadContext(){
 const {data:{user},error:userError}=await supabase.auth.getUser();
 if(userError||!user){showLogin();return;}
 const {data,error}=await supabase.rpc('kabarkelas_my_context');
 if(error){const box=panel('Akses belum tersedia','Login berhasil, tetapi hak akses sekolah belum dapat diperiksa.');message(box,'Hubungi admin KabarKelas. Data siswa tetap tertutup.',true);logoutButton(box);return;}
 currentContext=data;
 if(data?.state!=='active'||!Array.isArray(data.units)||data.units.length===0){const box=panel('Menunggu penugasan','Login berhasil, tetapi belum ada yayasan atau unit sekolah yang ditugaskan untuk akun ini.');message(box,'Hubungi administrator sekolah untuk aktivasi penugasan.');logoutButton(box);return;}
 if(activeMembership && !data.units.some(m=>m.membership_id===activeMembership.membership_id)) activeMembership=null;
 if(data.units.length===1) activeMembership=data.units[0];
 if(activeMembership)showHome(user,activeMembership); else showMembershipPicker(user,data.units);
}
function logoutButton(box,label='Keluar'){
 const b=el('button',label,'secondary');
 b.type='button';
 b.dataset.accountAction='true';
 b.onclick=async()=>{
  if(b.disabled)return;
  b.disabled=true;
  try{
   const {error}=await supabase.auth.signOut();
   if(error)throw error;
   currentContext=null;activeMembership=null;showLogin();
  }catch{
   b.disabled=false;
   const target=b.closest('.card')||box;
   message(target,'Gagal keluar dari akun. Periksa koneksi dan coba lagi.',true);
  }
 };
 box.append(b);
}
function showMembershipPicker(user,units){const box=panel('Pilih unit sekolah','Anda memiliki lebih dari satu penugasan. Pilih konteks kerja.');box.append(el('p',user.email,'muted'));
 for(const unit of units){const btn=el('button',`${unit.tenant_name} · ${unit.school_name||'Yayasan'} · ${unit.role}`,'unit');btn.onclick=()=>{activeMembership=unit;showHome(user,unit);};box.append(btn);} logoutButton(box);}
function showHome(user,unit){const box=panel('Dashboard KabarKelas','Ruang kerja sekolah yang terhubung ke data sesuai penugasan.');box.classList.add('dashboard-card');box.append(el('p',user.email,'muted'));box.append(el('div',unit.tenant_name,'highlight'));box.append(el('p',`Unit: ${unit.school_name||'Tingkat yayasan'}`));box.append(el('p',`Peran: ${unit.role}`));box.append(el('p','Nilai tersedia sesuai penugasan. Orang tua hanya melihat nilai yang sudah diterbitkan.','notice'));
 if(unit.role==='teacher' && unit.school_id) {
   const studentsButton=el('button','Lihat siswa yang saya ajar','secondary');
   const studentsRegion=el('div',null,'student-results');
   studentsButton.onclick=async()=>{
     studentsButton.disabled=true;
     studentsRegion.replaceChildren(el('p','Memuat daftar siswa...','muted'));
     try{
       const {data,error}=await supabase.rpc('kabarkelas_my_students',{p_school_id:unit.school_id});
       if(error) throw error;
       studentsRegion.replaceChildren(el('h2','Siswa di kelas saya'));
       if(!Array.isArray(data)||!data.length) studentsRegion.append(el('p','Belum ada siswa yang ditugaskan ke kelas Anda.','muted'));
       else for(const s of data){
         const item=el('div',null,'student-row');
         item.append(el('strong',s.display_name),el('p',`${s.class_name} · ${s.local_student_no}`,'muted'));
         studentsRegion.append(item);
       }
     }catch{
       studentsRegion.replaceChildren(el('p','Daftar siswa tidak bisa dimuat. Coba lagi atau hubungi administrator.','error'));
     }finally{studentsButton.disabled=false;}
   };
   box.append(studentsButton,studentsRegion);
 }
 if((unit.role==='guardian'||unit.role==='principal') && unit.school_id){
   const b=el('button',unit.role==='guardian'?'Lihat anak saya':'Lihat siswa sekolah','secondary');
   const results=el('div',null,'student-results');
   b.onclick=async()=>{
     b.disabled=true;results.replaceChildren(el('p','Memuat data...','muted'));
     try{
       const {data,error}=await supabase.rpc('kabarkelas_my_role_students',{p_school_id:unit.school_id});
       if(error) throw error;
       results.replaceChildren(el('h2',unit.role==='guardian'?'Anak saya':'Siswa sekolah'));
       if(!Array.isArray(data)||data.length===0)results.append(el('p','Tidak ada data siswa yang boleh ditampilkan.','muted'));
       else for(const s of data){
         const item=el('div',null,'student-row');
         item.append(el('strong',s.display_name),el('p',s.local_student_no,'muted'));
         results.append(item);
       }
     }catch{results.replaceChildren(el('p','Data siswa gagal dimuat.','error'))}
     finally{b.disabled=false;}
   };box.append(b,results);
 }
 if(unit.role==='foundation_admin') box.append(el('p','Akses yayasan ke data siswa individual tidak diberikan secara otomatis.','notice'));
 if(['teacher','principal','guardian'].includes(unit.role) && unit.school_id){
   const gradeButton=el('button',unit.role==='guardian'?'Lihat nilai yang sudah diterbitkan':'Lihat penilaian akademik','secondary');
   const gradeResults=el('div',null,'grade-results');
   gradeButton.onclick=async()=>{
     gradeButton.disabled=true;gradeResults.replaceChildren(el('p','Memuat penilaian...','muted'));
     try{
       const {data,error}=await supabase.rpc('kabarkelas_grade_workflow',{p_school_id:unit.school_id});
       if(error) throw error;
       gradeResults.replaceChildren(el('h2','Penilaian akademik'));
       if(!Array.isArray(data)||!data.length) gradeResults.append(el('p','Belum ada nilai yang dapat ditampilkan.','muted'));
       else for(const grade of data){
         const item=el('div',null,'student-row');
         item.append(el('strong',grade.student_name+' · '+grade.subject_name),el('p',grade.assessment_title+' · Nilai '+grade.score+' · '+grade.grade_status,'muted'));
         for(const action of availableActions(grade,unit.role)){
           const actionButton=el('button',({submit:'Submit',approve:'Approve',publish:'Publish'})[action]);
           actionButton.type='button';
           actionButton.onclick=async()=>{
             actionButton.disabled=true;
             message(item,'Memproses...');
             try{
               const {error}=await supabase.rpc('kabarkelas_transition_grade',{
                 p_grade_id:grade.grade_id,p_action:action,p_expected_revision:grade.revision,
               });
               if(error) throw error;
               await gradeButton.onclick();
               if(gradeResults.isConnected) message(gradeResults,'Transisi nilai berhasil.');
             }catch(error){
               if(error.code==='40001'||error.code==='55000'){
                 await gradeButton.onclick();
                 message(gradeResults,'Status sudah berubah. Data terbaru dimuat; periksa kembali sebelum melanjutkan.',true);
               }else{
                 message(item,'Transisi gagal. Periksa koneksi dan penugasan, lalu muat ulang nilai sebelum mencoba lagi.',true);
               }
             }finally{if(actionButton.isConnected) actionButton.disabled=false;}
           };
           item.append(actionButton);
         }
         if(unit.role==='teacher' && grade.grade_status==='draft'){
           const manage=el('button','Kelola nilai awal & remedial','secondary');
           manage.type='button';
           const area=el('div',null,'student-results');
           const refresh=async()=>{
             area.replaceChildren(el('p','Memuat percobaan nilai...','muted'));
             const [{data:attempts,error:attemptError},{data:summary,error:summaryError}]=await Promise.all([
               supabase.rpc('kabarkelas_list_attempts',{p_grade:grade.grade_id}),
               supabase.rpc('kabarkelas_attempt_summary',{p_grade:grade.grade_id})
             ]);
             if(attemptError||summaryError) throw new Error('Gagal membaca data');
             area.replaceChildren(el('p','Nilai awal dan remedial tersimpan terpisah. Koreksi memerlukan alasan.','muted'));
             const first=summary?.[0];
             if(first?.attempt_count>0) area.append(el('p','Nilai olahan saat ini: '+first.effective_score+' · kebijakan: '+first.policy_mode,'highlight'));
             for(const attempt of attempts||[]){
               const line=el('div',null,'student-row');
               line.append(el('strong',(attempt.attempt_kind==='initial'?'Nilai awal':'Remedial')+' · '+attempt.score));
               const edit=el('input');edit.type='number';edit.min='0';edit.step='0.01';edit.placeholder='Nilai koreksi';
               const reason=el('input');reason.placeholder='Alasan koreksi (minimal 3 karakter)';
               const save=el('button','Koreksi','secondary');save.type='button';
               save.onclick=async()=>{
                 const score=Number(edit.value);
                 if(!edit.value.trim()||!Number.isFinite(score)||reason.value.trim().length<3){message(area,'Isi nilai dan alasan koreksi.',true);return;}
                 save.disabled=true;
                 const {error}=await supabase.rpc('kabarkelas_correct_attempt',{p_attempt:attempt.attempt_id,p_new_score:score,p_reason:reason.value.trim()});
                 if(error){message(area,'Koreksi ditolak. Periksa nilai dan hak akses.',true);save.disabled=false;return;}
                 try{await refresh();}catch{message(area,'Data tidak bisa dimuat ulang.',true);}
               };
               line.append(edit,reason,save);area.append(line);
             }
             const kind=(attempts||[]).some(x=>x.attempt_kind==='initial')?'remedial':'initial';
             const scoreInput=el('input');scoreInput.type='number';scoreInput.min='0';scoreInput.step='0.01';scoreInput.placeholder=kind==='initial'?'Nilai awal':'Nilai remedial';
             const note=el('input');note.placeholder='Catatan (opsional)';
             const add=el('button',kind==='initial'?'Catat nilai awal':'Tambah remedial','secondary');add.type='button';
             add.onclick=async()=>{
               const value=Number(scoreInput.value);
               if(!scoreInput.value.trim()||!Number.isFinite(value)){message(area,'Masukkan nilai yang benar.',true);return;}
               add.disabled=true;
               const {error}=await supabase.rpc('kabarkelas_record_attempt',{p_grade:grade.grade_id,p_kind:kind,p_score:value,p_note:note.value});
               if(error){message(area,'Nilai tidak tersimpan. Periksa batas nilai dan penugasan.',true);add.disabled=false;return;}
               try{await refresh();}catch{message(area,'Data tidak bisa dimuat ulang.',true);}
             };
             area.append(scoreInput,note,add);
             if(first?.attempt_count>0){
               const finalize=el('button','Finalisasi nilai harian','secondary');finalize.type='button';
               finalize.onclick=async()=>{
                 if(!window.confirm('Finalisasi versi nilai saat ini sesuai kebijakan sekolah?'))return;
                 finalize.disabled=true;
                 const {data,error}=await supabase.rpc('kabarkelas_finalize_assessment',{p_grade:grade.grade_id});
                 if(error){message(area,'Finalisasi ditolak. Periksa data dan penugasan.',true);finalize.disabled=false;return;}
                 message(area,'Versi '+data.version+' '+(data.status==='released'?'telah dirilis kepada orang tua.':'difinalisasi untuk rapor.')+' Nilai: '+data.effective_score);
                 finalize.disabled=false;
               };area.append(finalize);
             }
           };
           manage.onclick=async()=>{manage.disabled=true;try{await refresh();}catch{message(area,'Fitur remedial belum dapat dimuat.',true);}finally{manage.disabled=false;}};
           item.append(manage,area);
         }
         gradeResults.append(item);
       }
     }catch{gradeResults.replaceChildren(el('p','Data penilaian tidak dapat dimuat.','error'))}
     finally{gradeButton.disabled=false;}
   };box.append(gradeButton,gradeResults);
 }
 if(unit.role==='guardian' && unit.school_id){
   const dailyButton=el('button','Lihat nilai harian yang sudah dirilis','secondary');
   const dailyResults=el('div',null,'grade-results');
   dailyButton.onclick=async()=>{
     dailyButton.disabled=true;
     const {data,error}=await supabase.rpc('kabarkelas_parent_assessments',{p_school:unit.school_id});
     dailyResults.replaceChildren(el('h2','Nilai pembelajaran yang dirilis'));
     if(error)dailyResults.append(el('p','Nilai harian tidak bisa dimuat.','error'));
     else if(!data?.length)dailyResults.append(el('p','Belum ada nilai harian yang dirilis.','muted'));
     else for(const item of data){
       const line=el('div',null,'student-row');
       line.append(el('strong',item.student_name+' · '+item.subject_name),el('p',item.assessment_title+' · Nilai '+item.score+' · Versi '+item.release_version,'muted'));
       dailyResults.append(line);
     }
     dailyButton.disabled=false;
   };
   box.append(dailyButton,dailyResults);
 }
 if((unit.role==='teacher'||unit.role==='principal') && unit.school_id){
   const reportsButton=el('button','Kelola rapor semester','secondary');
   const reportsArea=el('div',null,'grade-results');
   const refreshReports=async()=>{
     reportsArea.replaceChildren(el('p','Memuat paket rapor...','muted'));
     const {data,error}=await supabase.rpc('kabarkelas_my_class_reports',{p_school:unit.school_id});
     if(error){reportsArea.replaceChildren(el('p','Paket rapor tidak dapat dimuat.','error'));return;}
     reportsArea.replaceChildren(el('h2','Paket rapor semester'));
     if(!data?.length)reportsArea.append(el('p','Belum ada paket rapor untuk sekolah ini.','muted'));
     for(const report of data||[]){
       const line=el('div',null,'student-row');
       line.append(el('strong',report.class_name+' · '+report.period_code),el('p','Status: '+report.report_status+' · Versi '+report.report_version,'muted'));
       for(const action of report.allowed_actions||[]){
         const labels={teacher_finalize:'Finalisasi guru',homeroom_review:'Periksa wali kelas',principal_sign:'Sahkan kepala sekolah',release:'Terbitkan rapor'};
         const b=el('button',labels[action]||action,'secondary');b.type='button';
         b.onclick=async()=>{
           if(action==='release' && !window.confirm('Terbitkan rapor yang sudah disahkan kepada orang tua?'))return;
           b.disabled=true;
           const {error:transitionError}=await supabase.rpc('kabarkelas_transition_class_report',{
             p_report:report.report_id,p_action:action,p_revision:report.report_revision
           });
           if(transitionError){message(line,'Tindakan ditolak atau versi rapor telah berubah. Muat ulang.',true);b.disabled=false;return;}
           await refreshReports();
         };
         line.append(b);
       }
       reportsArea.append(line);
     }
     if(unit.role==='principal'){
       const setup=await supabase.rpc('kabarkelas_report_setup_options',{p_school:unit.school_id});
       if(setup.error){message(reportsArea,'Opsi pembuatan rapor belum dapat dimuat.',true);return;}
       if(setup.data?.length){
         const section=el('div',null,'student-row');
         section.append(el('h3','Buat paket rapor kelas'));
         const picker=el('select');
         for(const [index,opt] of setup.data.entries()){
           const o=el('option',opt.class_name+' · '+opt.period_code+' · Wali: '+opt.homeroom_label);
           o.value=String(index);picker.append(o);
         }
         const create=el('button','Buat paket rapor','secondary');create.type='button';
         create.onclick=async()=>{
           const selected=setup.data[Number(picker.value)||0];
           create.disabled=true;
           const {error:createError}=await supabase.rpc('kabarkelas_create_class_report',{
             p_class:selected.class_id,p_period:selected.period_id,p_homeroom:selected.homeroom_user_id
           });
           if(createError){message(section,'Pembuatan rapor ditolak. Periksa paket sebelumnya.',true);create.disabled=false;return;}
           await refreshReports();
         };
         section.append(picker,create);reportsArea.append(section);
       }
     }
   };
   reportsButton.onclick=async()=>{reportsButton.disabled=true;try{await refreshReports();}catch{reportsArea.replaceChildren(el('p','Rapor tidak dapat dimuat.','error'));}finally{reportsButton.disabled=false;}};
   box.append(reportsButton,reportsArea);
 }
 if(unit.role==='guardian' && unit.school_id){
   const button=el('button','Lihat rapor yang diterbitkan','secondary');
   const area=el('div',null,'grade-results');
   button.onclick=async()=>{
     button.disabled=true;
     const {data,error}=await supabase.rpc('kabarkelas_my_released_reports',{p_school:unit.school_id});
     area.replaceChildren(el('h2','Rapor semester'));
     if(error)area.append(el('p','Rapor tidak dapat dimuat.','error'));
     else if(!data?.length)area.append(el('p','Belum ada rapor yang diterbitkan.','muted'));
     else for(const report of data){
       const line=el('div',null,'student-row');
       line.append(el('strong',report.student_name+' · '+report.class_name),el('p',report.period_code+' · Versi '+report.report_version,'muted'));
       for(const grade of report.grades||[]){
         line.append(el('p',grade.subject+' · '+grade.assessment+' · '+grade.score,'muted'));
       }
       area.append(line);
     }
     button.disabled=false;
   };
   box.append(button,area);
 }
 if(unit.role==='principal' && unit.school_id){
   const policyButton=el('button','Atur kebijakan remedial & rilis nilai','secondary');
   const policyArea=el('div',null,'student-results');
   policyButton.onclick=async()=>{
     policyButton.disabled=true;
     const {data,error}=await supabase.rpc('kabarkelas_school_assessment_policy',{p_school:unit.school_id});
     if(error){policyArea.replaceChildren(el('p','Kebijakan tidak dapat dimuat.','error'));policyButton.disabled=false;return;}
     const policy=data?.[0]||{mode:'best_score',parent_visibility:'after_release',cap_percent:null,policy_version:0};
     policyArea.replaceChildren(el('h2','Kebijakan penilaian sekolah'),el('p','Versi aktif: '+policy.policy_version,'muted'));
     const mode=el('select');
     for(const [v,label] of [['best_score','Ambil nilai terbaik'],['latest_score','Gunakan nilai remedial terbaru'],['best_capped','Nilai terbaik dengan batas']]){
       const o=el('option',label);o.value=v;mode.append(o);
     }
     mode.value=policy.mode;
     const cap=el('input');cap.type='number';cap.min='0';cap.max='100';cap.placeholder='Batas maksimum (%)';cap.value=String(policy.cap_percent??75);
     const visibility=el('select');
     for(const [v,label] of [['after_release','Rilis nilai harian setelah finalisasi'],['report_only','Hanya tampil di rapor resmi']]){
       const o=el('option',label);o.value=v;visibility.append(o);
     }
     visibility.value=policy.parent_visibility;
     const save=el('button','Simpan versi kebijakan baru','secondary');save.type='button';
     save.onclick=async()=>{
       if(mode.value==='latest_score' && !window.confirm('Kebijakan ini dapat membuat hasil olahan lebih rendah dari nilai awal. Lanjutkan?'))return;
       save.disabled=true;
       const {data:version,error:saveError}=await supabase.rpc('kabarkelas_set_school_assessment_policy',{
         p_school:unit.school_id,p_mode:mode.value,p_cap:mode.value==='best_capped'?Number(cap.value):null,p_visibility:visibility.value
       });
       if(saveError){message(policyArea,'Perubahan kebijakan ditolak. Periksa penugasan atau nilai batas.',true);save.disabled=false;return;}
       message(policyArea,'Kebijakan versi '+version+' tersimpan. Nilai yang telah diterbitkan tidak diubah.');
       save.disabled=false;
     };
     policyArea.append(mode,cap,visibility,save);
     policyButton.disabled=false;
   };
   box.append(policyButton,policyArea);
 }
 if((unit.role==='teacher'||unit.role==='principal') && unit.school_id){
   const ewsButton=el('button','Pratinjau pendampingan siswa (EWS)','secondary');
   const ewsArea=el('div',null,'grade-results');
  ewsButton.onclick=async()=>{
    ewsButton.disabled=true;
    ewsArea.replaceChildren(el('p','Memuat indikator EWS...','muted'));
    const today=new Date();
    const end=today.toISOString().slice(0,10);
    const start=new Date(today.getTime()-29*86400000).toISOString().slice(0,10);
    const [academic,attendance]=await Promise.all([
      supabase.rpc('kabarkelas_ews_academic_preview',{p_school:unit.school_id,p_threshold:70,p_min_assessments:2}),
      supabase.rpc('kabarkelas_ews_attendance_preview',{p_school:unit.school_id,p_start:start,p_end:end,p_absent_threshold:3})
    ]);
    ewsArea.replaceChildren();
    const intro=el('div',null,'ews-intro');
    intro.append(el('h2','Early Warning System'),el('p','Peringatan adalah awal percakapan pendampingan, bukan label untuk siswa. Aturan sekolah menentukan indikator; tindak lanjut dicatat per status.','muted'));
    const counters=el('div',null,'kpi-grid');
    const mkCounter=(label,value,detail,kind)=>{const c=el('div',null,'kpi-card');c.append(el('p',label,'kpi-label'),el('strong',String(value),'kpi-value'+(kind==='warn'?' warn':'')),el('p',detail,'kpi-detail'));counters.append(c);};
    const flaggedA=(academic.data||[]).filter(x=>x.requires_review);
    const flaggedT=(attendance.data||[]).filter(x=>x.requires_review);
    const flaggedStudents=new Set([...flaggedA,...flaggedT].map(x=>x.student_id||x.student_name));
    mkCounter('Siswa perlu perhatian',flaggedStudents.size,flaggedA.length+' sinyal akademik · '+flaggedT.length+' sinyal kehadiran',flaggedStudents.size?'warn':'');
    mkCounter('Ambang akademik','70%','Rata-rata di bawah ambang, min. 2 penilaian final');
    mkCounter('Ambang kehadiran','3×','Tidak hadir tanpa keterangan / 30 hari');
    intro.append(counters);ewsArea.append(intro);
    // Academic signals table
    const acadBox=el('div',null,'dashboard-module');acadBox.style.marginTop='16px';
    const ah=el('div',null,'module-head');ah.append(el('h3','Sinyal akademik'));acadBox.append(ah);
    if(academic.error)acadBox.append(el('p','Indikator akademik tidak tersedia untuk akun ini.','error'));
    else if(!academic.data?.length)acadBox.append(el('p','Belum ada siswa dengan minimal dua penilaian final.','empty-note'));
    else{
      const tbl=el('table',null,'alert-table');const thead=el('thead');const hr=el('tr');
      for(const h of ['Siswa','Rata-rata','Status'])hr.append(el('th',h));
      thead.append(hr);tbl.append(thead);const tb=el('tbody');
      for(const entry of academic.data){
        const tr=el('tr');
        const tdn=el('td');tdn.append(el('strong',entry.student_name));tr.append(tdn);
        const tdp=el('td');tdp.append(el('span','Rata-rata '));tdp.append(el('strong',Number(entry.average_percent).toLocaleString('id-ID')+'%'));tdp.append(el('span',' dari '+entry.assessment_count+' penilaian final','sub'));tr.append(tdp);
        const tds=el('td');tds.append(entry.requires_review?el('span','Perlu ditinjau','badge badge-review'):el('span','Aman','badge badge-ok'));tr.append(tds);
        tb.append(tr);
      }
      tbl.append(tb);acadBox.append(tbl);
    }
    ewsArea.append(acadBox);
    // Attendance signals table
    const attBox=el('div',null,'dashboard-module');attBox.style.marginTop='16px';
    const atth=el('div',null,'module-head');atth.append(el('h3','Kehadiran — 30 hari terakhir'));attBox.append(atth);
    if(attendance.error)attBox.append(el('p','Data kehadiran belum bisa dimuat.','muted'));
    else if(!attendance.data?.length)attBox.append(el('p','Belum ada sesi absensi yang diterbitkan pada periode ini.','empty-note'));
    else{
      const tbl=el('table',null,'alert-table');const thead=el('thead');const hr=el('tr');
      for(const h of ['Siswa','Tidak hadir','Sesi','Status'])hr.append(el('th',h));
      thead.append(hr);tbl.append(thead);const tb=el('tbody');
      for(const record of attendance.data){
        const tr=el('tr');
        const tdn=el('td');tdn.append(el('strong',record.student_name));tr.append(tdn);
        const tdu=el('td');tdu.append(document.createTextNode(String(record.unexcused_absences)));tr.append(tdu);
        const tds=el('td');tds.append(document.createTextNode(String(record.session_count)+' sesi'));tr.append(tds);
        const tdst=el('td');tdst.append(record.requires_review?el('span','Perlu peninjauan','badge badge-review'):el('span','Aman','badge badge-ok'));tr.append(tdst);
        tb.append(tr);
      }
      tbl.append(tb);attBox.append(tbl);
    }
    ewsArea.append(attBox);
    ewsArea.append(el('p','Ambang 70% dan 3 ketidakhadiran tanpa keterangan adalah aturan simulasi; data tidak dibagikan ke orang tua.','muted'));
    if(unit.role==='principal'){
      const tools=el('div',null,'student-row');
      tools.append(el('h3','Aturan deteksi sekolah'));
      const configure=el('button','Aktifkan aturan akademik (70%, minimal 2 nilai)','secondary');
      configure.onclick=async()=>{
        configure.disabled=true;
        const {error}=await supabase.rpc('kabarkelas_ews_activate_rule',{
          p_school:unit.school_id,p_key:'academic_low_average',
          p_parameters:{threshold_percent:70,minimum_assessments:2}
        });
        message(tools,error?'Pengaturan aturan ditolak.':'Aturan akademik berhasil diaktifkan.',!!error);
        configure.disabled=false;
      };
      const attendanceBtn=el('button','Aktifkan aturan absensi (3 kali / 30 hari)','secondary');
      attendanceBtn.onclick=async()=>{
        attendanceBtn.disabled=true;
        const {error}=await supabase.rpc('kabarkelas_ews_activate_rule',{
          p_school:unit.school_id,p_key:'attendance_unexcused',
          p_parameters:{absent_threshold:3,lookback_days:30}
        });
        message(tools,error?'Pengaturan aturan ditolak.':'Aturan absensi berhasil diaktifkan.',!!error);
        attendanceBtn.disabled=false;
      };
      const scan=el('button','Jalankan deteksi hari ini','secondary');
      scan.onclick=async()=>{
        scan.disabled=true;
        const {data,error}=await supabase.rpc('kabarkelas_ews_scan_school',{p_school:unit.school_id});
        if(error){message(tools,'Deteksi gagal; periksa pengaturan sekolah.',true);scan.disabled=false;return;}
        message(tools,(data.created||0)+' peringatan baru tercatat untuk ditinjau.');
        ewsButton.click();
      };
      tools.append(configure,attendanceBtn,scan);ewsArea.append(tools);
    }
    const alerts=await supabase.rpc('kabarkelas_ews_my_alerts',{p_school:unit.school_id});
    ewsArea.append(el('h3','Tindak lanjut peringatan'));
    if(alerts.error) ewsArea.append(el('p','Daftar tindak lanjut belum bisa dimuat.','muted'));
    else if(!alerts.data?.length) ewsArea.append(el('p','Belum ada peringatan yang diaktifkan sekolah.','muted'));
    else{
      const tbl=el('table',null,'alert-table');const thead=el('thead');const hr=el('tr');
      for(const h of ['Siswa','Sinyal','Risiko','Status','Tindak lanjut'])hr.append(el('th',h));
      thead.append(hr);tbl.append(thead);const tb=el('tbody');
      for(const alert of alerts.data){
        const tr=el('tr');
        const tdn=el('td');tdn.append(el('strong',alert.student_name));tr.append(tdn);
        const tds2=el('td');tds2.append(el('span',alert.explanation||'—'));tr.append(tds2);
        const tdr=el('td');tdr.append(severityBadge(alert.severity));tr.append(tdr);
        const tdst=el('td');tdst.append(statusBadge(alert.alert_status));tr.append(tdst);
        const tdn2=el('td');
        const note=el('input');note.placeholder='Catatan (min. 5 karakter)';note.style.marginTop='0';note.style.marginBottom='6px';
        tdn2.append(note);
        const actions=alert.alert_status==='open'?['under_review','dismissed']:alert.alert_status==='under_review'?['resolved','dismissed']:['open'];
        for(const action of actions){
          const btn=el('button',({under_review:'Mulai tinjauan',resolved:'Selesaikan',dismissed:'Tutup',open:'Buka lagi'})[action],'secondary');
          btn.type='button';btn.style.width='auto';btn.style.marginTop='4px';btn.style.display='block';
          btn.onclick=async()=>{
            if(note.value.trim().length<5){message(tr,'Isi catatan minimal 5 karakter.',true);return;}
            btn.disabled=true;
            const {error}=await supabase.rpc('kabarkelas_ews_update_alert',{p_alert:alert.alert_id,p_expected_status:alert.alert_status,p_next_status:action,p_note:note.value.trim()});
            if(error){message(tr,'Perubahan ditolak atau status telah berubah. Muat ulang.',true);btn.disabled=false;return;}
            ewsButton.click();
          };
          tdn2.append(btn);
        }
        tr.append(tdn2);tb.append(tr);
      }
      tbl.append(tb);ewsArea.append(tbl);
    }
    ewsButton.disabled=false;
  };
   box.append(ewsButton,ewsArea);
 }
 if(currentContext?.units?.length>1){
  const change=el('button','Ganti unit','secondary');
  change.type='button';
  change.dataset.accountAction='true';
  change.onclick=()=>{activeMembership=null;showMembershipPicker(user,currentContext.units);};
  box.append(change);
 }
 const pilotModules=buildPilotModules(unit);
 if(pilotModules) box.append(pilotModules);
 logoutButton(box,'Ganti akun');
 logoutButton(box);
 decorateDashboard(box,user,unit);
}
const ROLE_LABELS={teacher:'Guru',principal:'Kepala sekolah',guardian:'Orang tua',foundation_admin:'Yayasan',school_admin:'Kepala sekolah'};
const NAV_GROUPS={
  teacher:[['AKADEMIK',['Lihat penilaian akademik','Kelola nilai awal & remedial','Observasi kompetensi & karakter','Tinjau observasi terdahulu','Kelola rapor semester']],['SEKOLAH',['Pratinjau pendampingan siswa (EWS)']]],
  principal:[['AKADEMIK',['Lihat penilaian akademik','Kelola rapor semester','Atur kebijakan remedial & rilis nilai','Rubrik kompetensi & karakter']],['SEKOLAH',['Pratinjau pendampingan siswa (EWS)','Lihat siswa sekolah']]],
  guardian:[['AKADEMIK',['Lihat nilai yang sudah diterbitkan','Lihat rapor yang diterbitkan','Lihat nilai harian yang sudah dirilis','Perkembangan akademik','Jaring kompetensi & karakter']],['SISWA',['Lihat anak saya']]],
  foundation_admin:[],
  school_admin:[['AKADEMIK',['Lihat penilaian akademik','Kelola rapor semester']],['SEKOLAH',['Pratinjau pendampingan siswa (EWS)','Lihat siswa sekolah']]],
};
function decorateDashboard(box,user,unit){
  const content=el('div',null,'dashboard-main');
  const top=el('header',null,'dashboard-topbar');
  top.id='dashboard-overview';
  const topText=el('div');
  topText.append(el('p','KABARKELAS / RUANG KERJA','eyebrow'));
  const titles={teacher:'Dashboard Guru',principal:'Dashboard Kepala Sekolah',guardian:'Perkembangan Anak',foundation_admin:'Dashboard Yayasan',school_admin:'Dashboard Sekolah'};
  topText.append(el('h1',titles[unit.role]||'Dashboard Sekolah'));
  topText.append(el('p',`${unit.school_name||unit.tenant_name} · ${user.email||''}`,'muted'));
  top.append(topText);
  const welcome=el('div',null,'welcome-panel');
  const hour=new Date().getHours();
  const greet=hour<11?'Selamat pagi':hour<15?'Selamat siang':hour<19?'Selamat sore':'Selamat malam';
  const displayName=(user.email||'').split('@')[0];
  welcome.append(el('span',greet+', '+displayName,'welcome-label'),el('strong',unit.tenant_name||'Yayasan'),el('p','Data, nilai, dan pendampingan siswa sesuai hak akses peran Anda.','muted'));
  const sections=el('div',null,'section-grid');
  const homeChildren=[...box.children];
  const groups=[];
  let current=null;
  const accountActions=[];
  for(const node of homeChildren){
    if(node.tagName==='BUTTON' && node.dataset.accountAction==='true'){
      accountActions.push(node);
    }else if(node.tagName==='BUTTON'){
      current=el('section',null,'dashboard-module');
      const heading=el('h2',node.textContent,'module-title');
      current.append(heading,node);groups.push(current);
    }else if(node.classList?.contains('student-results')||node.classList?.contains('grade-results')){
      if(current)current.append(node);else sections.append(node);
    }else if(node.tagName==='H1'||node.classList?.contains('brand')||node.classList?.contains('notice')){
      // Layout title and branding move to the permanent shell.
    }else{
      if(!current){welcome.append(node);}else current.append(node);
    }
  }
  const nav=el('nav',null,'dashboard-nav');
  nav.setAttribute('aria-label','Navigasi ruang kerja');
  const brand=el('div','📚 KabarKelas','dashboard-brand');
  nav.append(brand,el('p',unit.school_name||unit.tenant_name,'nav-school'));
  const role=el('p',(ROLE_LABELS[unit.role]||unit.role),'role-label');
  nav.append(role,el('p','MENU UTAMA','nav-label'));
  const mainLink=el('a','Ringkasan','nav-item');mainLink.href='#dashboard-overview';nav.append(mainLink);
  const groupTitles=NAV_GROUPS[unit.role]||[];
  const matched=new Set();
  let navIndex=0;
  for(const [groupName,names] of groupTitles){
    const visible=groups.filter(g=>names.includes(g.querySelector('.module-title')?.textContent));
    if(!visible.length)continue;
    nav.append(el('p',groupName,'nav-label'));
    for(const g of visible){
      matched.add(g);
      g.id='module-'+(navIndex++);
      const name=g.querySelector('.module-title').textContent;
      const item=el('a',name,'nav-item');item.href='#'+g.id;
      if(/EWS|pendampingan/i.test(name)){const badge=el('span','','nav-item-count');badge.textContent='EWS';item.append(badge);}
      nav.append(item);sections.append(g);
    }
  }
  const rest=groups.filter(g=>!matched.has(g));
  if(rest.length){nav.append(el('p','LAINNYA','nav-label'));for(const g of rest){g.id='module-'+(navIndex++);const item=el('a',g.querySelector('.module-title').textContent,'nav-item');item.href='#'+g.id;nav.append(item);sections.append(g);}}
  for(const action of accountActions){
    action.className='nav-item nav-action';
    nav.append(action);
  }
  content.append(top,welcome,buildOverview(unit),buildLiveOverview(unit));
  if(unit.role==='principal' && unit.school_id)content.append(buildPrincipalRubricManager(unit));
  if(unit.role==='teacher' && unit.school_id){content.append(buildTeacherDevelopment(unit));content.append(buildTeacherObservationReview(unit));}
  if(unit.role==='guardian' && unit.school_id){content.append(buildGuardianAcademicTrends(unit));content.append(buildGuardianRadar(unit));}
  content.append(sections);
  box.replaceChildren(nav,content);
  box.setAttribute('aria-label','Dashboard KabarKelas');
}
if(configured){supabase.auth.onAuthStateChange((event)=>{if(event==='SIGNED_OUT'){activeMembership=null;currentContext=null;showLogin();}});loadContext();}else showLogin();

function buildGuardianAcademicTrends(unit){
 const section=el('section',null,'guardian-trends');
 section.setAttribute('aria-label','Grafik perkembangan akademik');
 section.append(el('h2','Perkembangan akademik'));
 const info=el('p','Hanya nilai yang telah dirilis untuk anak terverifikasi. Setiap titik mewakili satu penilaian.','muted');
 const status=el('p','Tekan Muat grafik untuk menampilkan perkembangan.','muted');
 const button=el('button','Muat grafik akademik','secondary');
 const result=el('div',null,'academic-chart-results');
 section.append(info,button,status,result);
 button.onclick=async()=>{
  button.disabled=true;result.replaceChildren();status.textContent='Memuat nilai yang diterbitkan...';
  try{
   const {data,error}=await supabase.rpc('kabarkelas_guardian_academic_trends',{p_school:unit.school_id});
   if(error||!Array.isArray(data))throw new Error('Data unavailable');
   if(!data.length){status.textContent='Belum tersedia penilaian yang telah dirilis untuk anak Anda.';return;}
   const groups=new Map();
   for(const item of data){
    const pct=Number(item.score_percent);
    if(!Number.isFinite(pct)||pct<0||pct>100)continue;
    const key=String(item.student_id)+'|'+String(item.subject_name);
    if(!groups.has(key))groups.set(key,{name:item.student_name,subject:item.subject_name,points:[]});
    groups.get(key).points.push({...item,pct});
   }
   if(!groups.size){status.textContent='Belum tersedia nilai terverifikasi untuk grafik.';return;}
   status.textContent='Data perkembangan diambil dari penilaian yang sudah dirilis.';
   for(const group of groups.values()){
    const card=el('div',null,'trend-card');
    card.append(el('h3',group.name+' · '+group.subject));
    const svg=document.createElementNS('http://www.w3.org/2000/svg','svg');
    svg.setAttribute('viewBox','0 0 600 170');svg.setAttribute('role','img');
    svg.setAttribute('aria-label','Grafik perkembangan '+group.name+' mata pelajaran '+group.subject);
    const make=(tag,attrs)=>{const node=document.createElementNS('http://www.w3.org/2000/svg',tag);for(const [key,value] of Object.entries(attrs))node.setAttribute(key,String(value));return node;};
    for(const tick of [0,50,100]){
      const y=145-tick*1.15;
      svg.append(make('line',{x1:28,y1:y,x2:570,y2:y,stroke:'#deebe8','stroke-width':1}));
      const label=make('text',{x:0,y:y+4,fill:'#638083','font-size':12});label.textContent=String(tick);svg.append(label);
    }
    const points=group.points.map((p,i)=>({x:group.points.length===1?300:36+i*(520/(group.points.length-1)),y:145-p.pct*1.15,p}));
    if(points.length>1)svg.append(make('polyline',{points:points.map(p=>p.x+','+p.y).join(' '),fill:'none',stroke:'#147f75','stroke-width':3,'stroke-linejoin':'round','stroke-linecap':'round'}));
    for(const pt of points)svg.append(make('circle',{cx:pt.x,cy:pt.y,r:5,fill:'#147f75'}));
    card.append(svg);
    const list=el('ul',null,'trend-values');
    for(const pt of points){const li=el('li',pt.p.assessment_title+' — '+pt.p.pct.toLocaleString('id-ID')+'%');list.append(li);}
    card.append(list);result.append(card);
   }
  }catch{status.textContent='Grafik belum dapat dimuat. Tidak ada nilai perkiraan yang ditampilkan.';}
  finally{button.disabled=false;}
 };
 return section;
}

// ===== Ringkasan overview: KPI strip + EWS priority table (demo parity) =====
function buildOverview(unit){
  const section=el('section',null,'live-overview');
  section.setAttribute('aria-label','Ringkasan harian');
  const head=el('div',null,'module-head');
  head.append(el('h2','Ringkasan harian'));
  const refresh=el('button','Muat ringkasan','secondary');refresh.type='button';
  head.append(refresh);
  section.append(head);
  const grid=el('div',null,'kpi-grid');
  const ewsBox=el('div',null,'ews-priority');
  const state=el('p','Ringkasan dihitung dari data yang boleh diakses peran Anda.','muted');
  section.append(grid,ewsBox,state);
  const kpi=(label,value,detail,kind)=>{
    const card=el('div',null,'kpi-card');
    card.append(el('p',label,'kpi-label'),el('strong',String(value),'kpi-value'+(kind==='warn'?' warn':'')),el('p',detail,'kpi-detail'));
    grid.append(card);
  };
  let generation=0;
  const load=async()=>{
    const version=++generation;
    refresh.disabled=true;state.textContent='Memuat data terbaru...';grid.replaceChildren();ewsBox.replaceChildren();
    if(!unit.school_id){
      if(unit.role==='foundation_admin'){
        kpi('Unit sekolah','—','Agregat yayasan belum tersedia dari API yang berizin');
        state.textContent='Akses yayasan bersifat agregat; data siswa individual tidak dibuka.';
      }else state.textContent='Penugasan sekolah belum tersedia.';
      refresh.disabled=false;return;
    }
    try{
      const studentMethod=unit.role==='teacher'?'kabarkelas_my_students':'kabarkelas_my_role_students';
      const {data:students,error:studentError}=await supabase.rpc(studentMethod,{p_school_id:unit.school_id});
      if(version!==generation)return;
      if(studentError||!Array.isArray(students))throw new Error('students');
      const count=new Set(students.map(x=>x.id||x.student_id||x.local_student_no).filter(Boolean)).size;
      kpi(unit.role==='guardian'?'Anak terverifikasi':'Siswa aktif tercakup',count,'Sesuai penugasan aktif');

      if(unit.role==='guardian'){
        const [{data:trends,error:tErr},{data:rel,error:rErr}]=await Promise.all([
          supabase.rpc('kabarkelas_guardian_academic_trends',{p_school:unit.school_id}),
          supabase.rpc('kabarkelas_my_released_reports',{p_school:unit.school_id})
        ]);
        if(version!==generation)return;
        const pcts=(Array.isArray(trends)?trends:[]).map(x=>Number(x.score_percent)).filter(n=>Number.isFinite(n)&&n>=0&&n<=100);
        kpi('Rata-rata nilai',pcts.length?Math.round(pcts.reduce((a,b)=>a+b,0)/pcts.length)+'/100':'—',pcts.length?pcts.length+' penilaian dirilis':'Belum ada nilai dirilis');
        kpi('Rapor terbit',Array.isArray(rel)?rel.length:0,'Rapor semester yang sudah diterbitkan');
        state.textContent='Ringkasan berhasil dimuat.';
      }else{
        // teacher / principal / school_admin: grades + EWS + reports
        const [{data:grades,error:gErr},{data:alerts,error:aErr},{data:reports,error:rpErr}]=await Promise.all([
          supabase.rpc('kabarkelas_grade_workflow',{p_school_id:unit.school_id}),
          supabase.rpc('kabarkelas_ews_my_alerts',{p_school:unit.school_id}).catch(()=>({data:null,error:true})),
          supabase.rpc('kabarkelas_my_class_reports',{p_school:unit.school_id}).catch(()=>({data:null,error:true}))
        ]);
        if(version!==generation)return;
        const gradeList=Array.isArray(grades)?grades:[];
        const published=gradeList.filter(g=>g.grade_status==='published').length;
        const draft=gradeList.filter(g=>g.grade_status==='draft').length;
        const submitted=gradeList.filter(g=>g.grade_status==='submitted'||g.grade_status==='approved').length;
        kpi('Penilaian',gradeList.length,draft+' draf · '+submitted+' proses · '+published+' terbit');
        const alertList=Array.isArray(alerts)?alerts:[];
        const open=alertList.filter(a=>a.alert_status==='open').length;
        const review=alertList.filter(a=>a.alert_status==='under_review').length;
        kpi('Perlu pendampingan',open+review,open+' terbuka · '+review+' ditinjau','warn');
        const reportList=Array.isArray(reports)?reports:[];
        kpi('Paket rapor',reportList.length,reportList.filter(r=>['teacher_finalize','homeroom_review','principal_sign','release'].includes((r.allowed_actions||[])[0]||'')).length+' menunggu tindakan');
        // EWS priority table
        ewsBox.append(buildEwsPriority(unit,alertList));
        state.textContent='Ringkasan berhasil dimuat dari API sekolah.';
      }
    }catch{
      if(version===generation){grid.replaceChildren();state.textContent='Ringkasan belum dapat dimuat. Tidak ada angka perkiraan yang ditampilkan.';}
    }finally{if(version===generation)refresh.disabled=false;}
  };
  refresh.onclick=load;
  // Lazy: ringkasan hanya dimuat saat pengguna menekan tombol, agar dashboard awal tidak memicu RPC tambahan.
  return section;
}

function severityBadge(sev){
  // ews severity: monitor | review ; derive high risk from alert signal/rule if needed
  if(sev==='review')return el('span','Perlu perhatian','badge badge-review');
  return el('span','Pantau','badge badge-ok');
}
function statusBadge(st){
  const map={open:['Terbuka','badge-high'],under_review:['Ditinjau','badge-review'],resolved:['Selesai','badge-ok'],dismissed:['Ditutup','badge-draft']};
  const [label,cls]=map[st]||[st,'badge-draft'];
  return el('span',label,'badge '+cls);
}
function buildEwsPriority(unit,alerts){
  const box=el('div',null,'dashboard-module');
  box.style.marginTop='18px';
  const head=el('div',null,'module-head');
  head.append(el('h3','Early Warning System — prioritas pendampingan'));
  const all=el('button','Lihat semua','ghost');all.type='button';
  all.onclick=()=>{document.getElementById('module-ews')?.scrollIntoView({behavior:'smooth'});};
  head.append(all);
  box.append(head);
  if(!alerts.length){box.append(el('p','Belum ada peringatan EWS aktif untuk sekolah ini.','empty-note'));return box;}
  const sorted=[...alerts].sort((a,b)=>{
    const rank=s=>s.alert_status==='open'?0:s.alert_status==='under_review'?1:2;
    return rank(a)-rank(b)||String(b.detected_at).localeCompare(String(a.detected_at));
  }).slice(0,8);
  const table=el('table',null,'alert-table');
  const thead=el('thead');const hr=el('tr');
  for(const h of ['Siswa','Sinyal','Risiko','Status'])hr.append(el('th',h));
  thead.append(hr);table.append(thead);
  const tbody=el('tbody');
  for(const a of sorted){
    const tr=el('tr');
    const tdName=el('td');tdName.append(el('strong',a.student_name));
    tdName.append(el('span',a.signal?humanizeSignal(a.signal):'Peringatan','sub'));
    tr.append(tdName);
    const tdSig=el('td');tdSig.append(el('span',a.explanation||'—'));tr.append(tdSig);
    const tdRisk=el('td');tdRisk.append(severityBadge(a.severity));tr.append(tdRisk);
    const tdSt=el('td');tdSt.append(statusBadge(a.alert_status));tr.append(tdSt);
    tbody.append(tr);
  }
  table.append(tbody);box.append(table);
  if(alerts.length>8)box.append(el('p',`+ ${alerts.length-8} peringatan lainnya — buka modul EWS untuk tindak lanjut.`,'muted'));
  return box;
}
function humanizeSignal(sig){
  return String(sig).replace(/_/g,' ').replace(/\b\w/g,c=>c.toUpperCase());
}
function buildLiveOverview(unit){
  const section=el('section',null,'live-overview');
  section.setAttribute('aria-label','Ringkasan data sekolah');
  section.append(el('h2','Ringkasan dari data sekolah'));
  const intro=el('p','Statistik dihitung dari data yang dapat diakses oleh peran Anda. Angka kosong bukan data simulasi.','muted');
  const grid=el('div',null,'live-overview-grid');
  const state=el('p','Pilih Perbarui ringkasan untuk mengambil data terbaru.','muted');
  section.append(intro,grid,state);
  const button=el('button','Perbarui ringkasan','secondary');button.type='button';
  section.append(button);
  const createCard=(label,value,detail)=>{
    const card=el('div',null,'live-kpi-card');
    card.append(el('p',label,'muted'),el('strong',String(value),'live-kpi-value'),el('p',detail,'muted'));grid.append(card);
  };
  let generation=0;
  const load=async()=>{
    const version=++generation;
    if(!unit.school_id){grid.replaceChildren();state.textContent='Ringkasan agregat yayasan belum tersedia dari API yang berizin.';return;}
    button.disabled=true;state.textContent='Mengambil data terbaru...';grid.replaceChildren();
    try{
      if(unit.role==='foundation_admin'){
        state.textContent='Data agregat yayasan belum tersedia. Data siswa individual tidak dibuka.';return;
      }
      const studentMethod=unit.role==='teacher'?'kabarkelas_my_students':'kabarkelas_my_role_students';
      const {data:students,error:studentError}=await supabase.rpc(studentMethod,{p_school_id:unit.school_id});
      if(version!==generation)return;
      if(studentError||!Array.isArray(students))throw new Error('Student data unavailable');
      createCard(unit.role==='guardian'?'Anak terhubung':'Siswa dalam cakupan',new Set(students.map(x=>x.id||x.local_student_no).filter(Boolean)).size,'Sesuai penugasan dan hak akses');
      if(unit.role==='principal'||unit.role==='teacher'){
        const {data:alerts,error:alertError}=await supabase.rpc('kabarkelas_ews_my_alerts',{p_school:unit.school_id});
        if(version!==generation)return;
        if(!alertError&&Array.isArray(alerts)){
          createCard('Peringatan perlu tindak lanjut',alerts.filter(x=>x.alert_status==='open'||x.alert_status==='under_review').length,'Peringatan EWS yang belum ditutup');
        }else createCard('Peringatan EWS','—','Belum dapat dimuat');
      }
      state.textContent='Ringkasan berhasil dimuat dari API sekolah.';
    }catch{
      if(version===generation){grid.replaceChildren();state.textContent='Ringkasan belum dapat dimuat. Tidak ada angka perkiraan yang ditampilkan.';}
    }finally{if(version===generation)button.disabled=false;}
  };
  button.onclick=load;
  return section;
}

function buildPrincipalRubricManager(unit){
 const section=el('section',null,'guardian-trends');section.setAttribute('aria-label','Pengelolaan rubrik sekolah');
 section.append(el('h2','Rubrik kompetensi & karakter'),el('p','Kepala sekolah menyetujui indikator sebelum digunakan oleh guru.','muted'));
 const form=el('form');
 const domain=el('select');domain.setAttribute('aria-label','Domain rubrik');
 for(const [code,label] of [['academic_competency','Kompetensi akademik'],['character','Karakter']]){const opt=el('option',label);opt.value=code;domain.append(opt);}
 const code=el('input');code.placeholder='Kode indikator';code.required=true;code.maxLength=50;
 const label=el('input');label.placeholder='Nama indikator';label.required=true;label.maxLength=120;
 const save=el('button','Setujui indikator');save.type='submit';
 form.append(domain,code,label,save);
 form.onsubmit=async(event)=>{
   event.preventDefault();save.disabled=true;
   const {error}=await supabase.rpc('kabarkelas_approve_development_indicator',{p_school:unit.school_id,p_domain:domain.value,p_code:code.value.trim(),p_label:label.value.trim()});
   message(section,error?'Persetujuan ditolak.':'Indikator disetujui dan dapat dipakai guru.',!!error);save.disabled=false;
 };
 section.append(form);return section;
}
function buildTeacherObservationReview(unit){
 const wrap=el('section',null,'guardian-trends');wrap.setAttribute('aria-label','Koreksi dan pencabutan observasi');
 wrap.append(el('h2','Tinjau observasi terdahulu'),el('p','Koreksi dan pencabutan membutuhkan alasan minimal 8 karakter. Semua perubahan tercatat pada audit.','muted'));
 const load=el('button','Muat observasi saya','secondary');const area=el('div');wrap.append(load,area);
 load.onclick=async()=>{
  load.disabled=true;area.replaceChildren(el('p','Memuat observasi...','muted'));
  try{
   const {data,error}=await supabase.rpc('kabarkelas_teacher_observations',{p_school:unit.school_id});
   if(error||!Array.isArray(data))throw new Error('Unavailable');
   area.replaceChildren();
   if(!data.length){area.append(el('p','Belum ada observasi yang dapat dikelola.','muted'));return;}
   for(const obs of data){
    const card=el('div',null,'student-row');
    card.append(el('strong',obs.student_name+' · '+obs.indicator_label),el('p','Status: '+obs.state+' · Versi '+obs.revision+' · Skor '+obs.score+'/4','muted'));
    if(obs.state==='withdrawn'){area.append(card);continue;}
    const score=el('select');score.setAttribute('aria-label','Skor koreksi '+obs.indicator_label);
    for(let n=1;n<=4;n++){const o=el('option','Skor '+n);o.value=String(n);score.append(o);}score.value=String(obs.score);
    const evidence=el('textarea');evidence.value=obs.evidence;evidence.setAttribute('aria-label','Bukti koreksi '+obs.indicator_label);
    const reason=el('textarea');reason.placeholder='Alasan koreksi atau pencabutan (minimal 8 karakter)';reason.minLength=8;
    const actions=el('div',null,'observation-actions');
    for(const [action,label] of [['correct','Simpan koreksi'],['withdraw','Cabut observasi']]){
      const b=el('button',label,'secondary');b.type='button';
      b.onclick=async()=>{
        if(reason.value.trim().length<8){message(card,'Alasan minimal 8 karakter.',true);return;}
        b.disabled=true;
        const {error}=await supabase.rpc('kabarkelas_update_development_observation',{p_observation:obs.observation_id,p_revision:obs.revision,p_action:action,p_score:Number(score.value),p_evidence:evidence.value.trim(),p_reason:reason.value.trim()});
        if(error){message(card,'Perubahan ditolak atau versi sudah berubah. Muat observasi kembali.',true);b.disabled=false;return;}
        await load.onclick();
      };actions.append(b);
    }
    card.append(score,evidence,reason,actions);area.append(card);
   }
  }catch{area.replaceChildren(el('p','Observasi belum dapat dimuat.','error'));}
  finally{load.disabled=false;}
 };
 return wrap;
}
function buildTeacherDevelopment(unit){
 const wrap=el('section',null,'guardian-trends');wrap.setAttribute('aria-label','Observasi kompetensi dan karakter guru');
 wrap.append(el('h2','Observasi kompetensi & karakter'),el('p','Skala 1–4 berdasarkan bukti pengamatan. Data draf tidak dapat dilihat orang tua.','muted'));
 const load=el('button','Pilih siswa untuk observasi','secondary');const area=el('div');wrap.append(load,area);
 load.onclick=async()=>{
  load.disabled=true;area.replaceChildren(el('p','Memuat pilihan siswa...','muted'));
  try{
   const {data,error}=await supabase.rpc('kabarkelas_teacher_development_options',{p_school:unit.school_id});
   if(error||!Array.isArray(data))throw new Error('Options unavailable');
   area.replaceChildren();
   if(!data.length){area.append(el('p','Belum ada kelas dan siswa dalam penugasan aktif.','muted'));return;}
   const form=el('form');const student=el('select');student.setAttribute('aria-label','Siswa dan kelas');
   for(const record of data){const opt=el('option',record.student_name+' — '+record.class_name);opt.value=String(data.indexOf(record));student.append(opt);}
   const domain=el('select');domain.setAttribute('aria-label','Domain observasi');
   for(const [key,label] of [['academic_competency','Kompetensi akademik'],['character','Karakter']]){const opt=el('option',label);opt.value=key;domain.append(opt);}
   const indicatorsResponse=await supabase.rpc('kabarkelas_development_indicators',{p_school:unit.school_id});
   if(indicatorsResponse.error)throw new Error('Rubric unavailable');
   const indicators=indicatorsResponse.data||[];
   if(!indicators.length){area.replaceChildren(el('p','Kepala sekolah belum menyetujui rubrik observasi.','muted'));return;}
   const rubric=el('select');rubric.setAttribute('aria-label','Indikator rubrik disetujui');
   const renderRubric=()=>{
     rubric.replaceChildren();
     for(const [index,item] of indicators.entries())if(item.domain===domain.value){
       const opt=el('option',item.indicator_label+' ('+item.indicator_code+')');opt.value=String(index);rubric.append(opt);
     }
   };
   domain.onchange=renderRubric;renderRubric();
   const score=el('select');score.setAttribute('aria-label','Tingkat perkembangan');
   for(let i=1;i<=4;i++){const opt=el('option','Tingkat '+i);opt.value=String(i);score.append(opt);}
   const evidence=el('textarea');evidence.placeholder='Bukti pengamatan (minimal 8 karakter)';evidence.required=true;evidence.minLength=8;evidence.maxLength=1000;
   const publish=el('input');publish.type='checkbox';publish.style.width='auto';publish.setAttribute('aria-label','Terbitkan ke orang tua');
   const publishLabel=el('label','Terbitkan kepada orang tua setelah diperiksa');publishLabel.prepend(publish);
   const submit=el('button','Simpan observasi');submit.type='submit';
   form.append(student,domain,rubric,score,evidence,publishLabel,submit);
   form.onsubmit=async(event)=>{
    event.preventDefault();const record=data[Number(student.value)];if(!record)return;
    const approved=indicators[Number(rubric.value)];if(!approved){message(area,'Belum ada indikator disetujui untuk domain ini.',true);return;}
    submit.disabled=true;
    const {error}=await supabase.rpc('kabarkelas_teacher_development_observe',{p_school:unit.school_id,p_student:record.student_id,p_class:record.class_id,p_domain:domain.value,p_code:approved.indicator_code,p_label:approved.indicator_label,p_score:Number(score.value),p_evidence:evidence.value.trim(),p_publish:publish.checked});
    message(area,error?'Observasi ditolak. Periksa penugasan dan nilai.':publish.checked?'Observasi berhasil diterbitkan.':'Observasi berhasil disimpan sebagai draf.',!!error);
    submit.disabled=false;if(!error){evidence.value='';publish.checked=false;}
   };
   area.append(form);
  }catch{area.replaceChildren(el('p','Pilihan siswa tidak dapat dimuat.','error'));}
  finally{load.disabled=false;}
 };
 return wrap;
}
function buildGuardianRadar(unit){
 const wrap=el('section',null,'guardian-trends');wrap.setAttribute('aria-label','Grafik jaring perkembangan');
 wrap.append(el('h2','Jaring kompetensi & karakter'),el('p','Hanya observasi terbit dari guru. Skala 1–4; grafik merupakan rata-rata pengamatan, bukan diagnosis.','muted'));
 const button=el('button','Muat jaring perkembangan','secondary');const area=el('div',null,'academic-chart-results');
 wrap.append(button,area);
 button.onclick=async()=>{
  button.disabled=true;area.replaceChildren(el('p','Memuat observasi terbit...','muted'));
  try{
   const {data,error}=await supabase.rpc('kabarkelas_guardian_development_radar',{p_school:unit.school_id});
   if(error||!Array.isArray(data))throw new Error('Unavailable');
   area.replaceChildren();
   if(!data.length){area.append(el('p','Belum ada observasi kompetensi atau karakter yang diterbitkan.','muted'));return;}
   const groups=new Map();
   for(const item of data){const val=Number(item.average_score);
    if(!Number.isFinite(val)||val<1||val>4)continue;
    const key=item.student_name+' · '+item.domain;
    if(!groups.has(key))groups.set(key,[]);
    groups.get(key).push({...item,val});
   }
   if(!groups.size){area.append(el('p','Belum ada indikator valid untuk grafik.','muted'));return;}
   for(const [name,items] of groups){
    const card=el('div',null,'trend-card');card.append(el('h3',name.replace('academic_competency','Kompetensi akademik').replace('character','Karakter')));
    const svg=document.createElementNS('http://www.w3.org/2000/svg','svg');svg.setAttribute('viewBox','0 0 360 320');svg.setAttribute('role','img');svg.setAttribute('aria-label','Grafik radar '+name);
    const make=(tag,attrs)=>{const n=document.createElementNS('http://www.w3.org/2000/svg',tag);for(const [k,v] of Object.entries(attrs))n.setAttribute(k,String(v));return n;};
    const n=items.length,loc=(i,r)=>[180+Math.sin(2*Math.PI*i/n)*r,145-Math.cos(2*Math.PI*i/n)*r],points=r=>items.map((_,i)=>loc(i,r).join(',')).join(' ');
    if(n>=3){for(let r=25;r<=100;r+=25)svg.append(make('polygon',{points:points(r),fill:'none',stroke:'#d4e8e3','stroke-width':1}));}
    else{for(let r=25;r<=100;r+=25)svg.append(make('circle',{cx:180,cy:145,r,fill:'none',stroke:'#d4e8e3'}));}
    for(let i=0;i<n;i++){const [x,y]=loc(i,100);svg.append(make('line',{x1:180,y1:145,x2:x,y2:y,stroke:'#d4e8e3'}));}
    if(n>=3)svg.append(make('polygon',{points:items.map((item,i)=>loc(i,item.val*25).join(',')).join(' '),fill:'#17897a44',stroke:'#168779','stroke-width':3}));
    else for(let i=0;i<n;i++){const [x,y]=loc(i,items[i].val*25);svg.append(make('circle',{cx:x,cy:y,r:6,fill:'#168779'}));}
    card.append(svg);
    const list=el('ul',null,'trend-values');for(const item of items)list.append(el('li',item.indicator_label+' — '+item.val.toLocaleString('id-ID')+'/4 ('+item.observation_count+' observasi)'));
    card.append(list);area.append(card);
   }
  }catch{area.replaceChildren(el('p','Grafik tidak dapat dimuat; tidak ada skor perkiraan yang ditampilkan.','error'));}
  finally{button.disabled=false;}
 };
 return wrap;
}

// Form input untuk modul pilot (staf: teacher/principal/school_admin)
function appendPilotForms(unit,kind,area,school,reload){
  const isStaff=['teacher','principal','school_admin'].includes(unit.role);
  const canManageAnnouncement=(unit.role==='principal'||unit.role==='school_admin');
  if(kind==='announcement'&&canManageAnnouncement){
    const form=el('form');form.style.marginTop='12px';
    const title=el('input');title.placeholder='Judul pengumuman';title.required=true;
    const body=el('textarea');body.placeholder='Isi pengumuman';body.required=true;body.rows=3;body.style.width='100%';
    const submit=el('button','Terbitkan pengumuman','secondary');submit.type='submit';
    form.append(title,body,submit);
    form.onsubmit=async(ev)=>{ev.preventDefault();submit.disabled=true;
      const {error}=await supabase.rpc('kabarkelas_announce_create',{p_school:school,p_title:title.value,p_body:body.value});
      if(error)message(area,'Pengumuman gagal diterbitkan.',true);else reload();
      submit.disabled=false;};
    area.append(form);
    return;
  }
  if(!isStaff||!['homework','quiz','p5'].includes(kind))return;
  (async()=>{
    const [opts,students,items]=await Promise.all([
      supabase.rpc('kabarkelas_pilot_options',{p_school:school}),
      supabase.rpc('kabarkelas_pilot_students',{p_school:school}),
      kind==='homework'?supabase.rpc('kabarkelas_homework_list',{p_school:school}):kind==='quiz'?supabase.rpc('kabarkelas_quiz_list',{p_school:school}):Promise.resolve({data:[]})
    ]);
    const classes=(opts.data||[]).filter(o=>o.kind==='class');
    const subjects=(opts.data||[]).filter(o=>o.kind==='subject');
    const studs=students.data||[];
    const select=(pairs,ph)=>{const s=el('select');const o=el('option',ph);o.value='';s.append(o);for(const p of pairs){const op=el('option',p.name);op.value=p.id;s.append(op);}return s;};
    const studentSelect=()=>select(studs.map(s2=>({id:s2.student_id,name:`${s2.display_name} · ${s2.class_name}`})),'Pilih siswa');
    if(kind==='homework'){
      const f1=el('form');f1.style.marginTop='12px';
      const cls=select(classes,'Pilih kelas');const sub=select(subjects,'Pilih mapel');
      const ti=el('input');ti.placeholder='Judul tugas';ti.required=true;
      const ins=el('textarea');ins.placeholder='Petunjuk (opsional)';ins.rows=2;ins.style.width='100%';
      const asg=el('input');asg.type='date';asg.required=true;asg.value=new Date().toISOString().slice(0,10);
      const due=el('input');due.type='date';due.required=true;
      const mx=el('input');mx.type='number';mx.min='1';mx.value='100';mx.required=true;mx.style.width='90px';
      const b1=el('button','Beri tugas','secondary');b1.type='submit';
      f1.append(el('p','Beri tugas baru','muted'),cls,sub,ti,ins,asg,due,mx,b1);
      f1.onsubmit=async(ev)=>{ev.preventDefault();b1.disabled=true;
        const {error}=await supabase.rpc('kabarkelas_homework_create',{p_school:school,p_class:cls.value,p_subject:sub.value,p_title:ti.value,p_instructions:ins.value,p_assigned:asg.value,p_due:due.value,p_max:Number(mx.value)});
        if(error)message(area,'Tugas gagal dibuat.',true);else reload();
        b1.disabled=false;};
      area.append(f1);
      const f2=el('form');f2.style.marginTop='12px';
      const hw=select((items.data||[]).map(h=>({id:h.id,name:`${h.title} · ${h.class_name}`})),'Pilih tugas');
      const st=studentSelect();
      const sc=el('input');sc.type='number';sc.min='0';sc.step='0.5';sc.placeholder='Nilai';sc.required=true;sc.style.width='90px';
      const nt=el('input');nt.placeholder='Catatan (opsional)';
      const b2=el('button','Simpan nilai','secondary');b2.type='submit';
      f2.append(el('p','Input nilai tugas','muted'),hw,st,sc,nt,b2);
      f2.onsubmit=async(ev)=>{ev.preventDefault();if(!hw.value||!st.value){message(area,'Pilih tugas dan siswa dulu.',true);return;}b2.disabled=true;
        const {error}=await supabase.rpc('kabarkelas_homework_score',{p_homework:hw.value,p_student:st.value,p_score:Number(sc.value),p_note:nt.value});
        if(error)message(area,'Nilai gagal disimpan.',true);else reload();
        b2.disabled=false;};
      area.append(f2);
    }else if(kind==='quiz'){
      const f1=el('form');f1.style.marginTop='12px';
      const cls=select(classes,'Pilih kelas');const sub=select(subjects,'Pilih mapel');
      const ti=el('input');ti.placeholder='Judul kuis';ti.required=true;
      const qd=el('input');qd.type='date';qd.required=true;qd.value=new Date().toISOString().slice(0,10);
      const ts=el('input');ts.type='time';
      const te=el('input');te.type='time';
      const mx=el('input');mx.type='number';mx.min='1';mx.value='100';mx.required=true;mx.style.width='90px';
      const nt0=el('input');nt0.placeholder='Catatan (opsional)';
      const b1=el('button','Jadwalkan kuis','secondary');b1.type='submit';
      f1.append(el('p','Jadwalkan kuis baru','muted'),cls,sub,ti,qd,ts,te,mx,nt0,b1);
      f1.onsubmit=async(ev)=>{ev.preventDefault();b1.disabled=true;
        const {error}=await supabase.rpc('kabarkelas_quiz_create',{p_school:school,p_class:cls.value,p_subject:sub.value,p_title:ti.value,p_quiz_on:qd.value,p_start:ts.value||null,p_end:te.value||null,p_max:Number(mx.value),p_notes:nt0.value});
        if(error)message(area,'Kuis gagal dijadwalkan.',true);else reload();
        b1.disabled=false;};
      area.append(f1);
      const f2=el('form');f2.style.marginTop='12px';
      const qz=select((items.data||[]).map(q=>({id:q.id,name:`${q.title} · ${q.class_name}`})),'Pilih kuis');
      const st=studentSelect();
      const sc=el('input');sc.type='number';sc.min='0';sc.step='0.5';sc.placeholder='Nilai';sc.required=true;sc.style.width='90px';
      const nt=el('input');nt.placeholder='Catatan (opsional)';
      const b2=el('button','Simpan nilai','secondary');b2.type='submit';
      f2.append(el('p','Input nilai kuis','muted'),qz,st,sc,nt,b2);
      f2.onsubmit=async(ev)=>{ev.preventDefault();if(!qz.value||!st.value){message(area,'Pilih kuis dan siswa dulu.',true);return;}b2.disabled=true;
        const {error}=await supabase.rpc('kabarkelas_quiz_score',{p_quiz:qz.value,p_student:st.value,p_score:Number(sc.value),p_note:nt.value});
        if(error)message(area,'Nilai gagal disimpan.',true);else reload();
        b2.disabled=false;};
      area.append(f2);
    }else if(kind==='p5'){
      const f=el('form');f.style.marginTop='12px';
      const st=studentSelect();
      const cat=el('select');
      for(const [v,l] of [['p5','P5'],['tahfizh','Tahfizh']]){const o=el('option',l);o.value=v;cat.append(o);}
      const ind=el('input');ind.placeholder='Indikator (min. 3 karakter)';ind.required=true;
      const sc=el('input');sc.type='number';sc.min='0';sc.max='100';sc.placeholder='Skor 0-100';sc.required=true;sc.style.width='90px';
      const nt=el('input');nt.placeholder='Catatan (opsional)';
      const b=el('button','Catat penilaian','secondary');b.type='submit';
      f.append(el('p','Catat P5/Tahfizh','muted'),st,cat,ind,sc,nt,b);
      f.onsubmit=async(ev)=>{ev.preventDefault();b.disabled=true;
        const {error}=await supabase.rpc('kabarkelas_p5_record',{p_school:school,p_student:st.value,p_category:cat.value,p_indicator:ind.value,p_score:Number(sc.value),p_note:nt.value});
        if(error)message(area,'Penilaian gagal dicatat.',true);else reload();
        b.disabled=false;};
      area.append(f);
    }
  })();
}

// ===== Pilot features =====
function buildPilotModule(unit, kind){
  const titles={
    schedule:'Jadwal pelajaran',attendance:'Kehadiran',announcement:'Pengumuman',
    leave:'Izin guru',homework:'Tugas',quiz:'Kuis',p5:'P5 & Tahfizh',
  };
  const title=titles[kind]||kind;
  const btn=el('button',title,'secondary');
  const area=el('div',null,'grade-results');
  btn.onclick=async()=>{
    btn.disabled=true;area.replaceChildren(el('p','Memuat...','muted'));
    try{
      const school=unit.school_id;
      if(kind==='schedule'){
        const {data,error}=await supabase.rpc('kabarkelas_schedule_list',{p_school:school});
        area.replaceChildren(el('h2',title));
        if(error)area.append(el('p','Jadwal tidak dapat dimuat.','error'));
        else if(!data?.length)area.append(el('p','Belum ada jadwal.','muted'));
        else{
          const days=['','Senin','Selasa','Rabu','Kamis','Jumat','Sabtu','Minggu'];
          const tbl=el('table',null,'alert-table');
          const head=el('tr');for(const h of ['Hari','Kelas','Mapel','Guru','Jam','Ruang'])head.append(el('th',h));
          const thead=el('thead');thead.append(head);tbl.append(thead);
          const tb=el('tbody');
          for(const s of data){
            const tr=el('tr');
            tr.append(el('td',days[s.weekday]||s.weekday),el('td',s.class_name),el('td',s.subject_name),el('td',s.teacher_name),el('td',(s.start_time||'').slice(0,5)+'–'+(s.end_time||'').slice(0,5)),el('td',s.room||'—'));
            tb.append(tr);
          }
          tbl.append(tb);area.append(tbl);
        }
      }else if(kind==='announcement'){
        const {data,error}=await supabase.rpc('kabarkelas_announce_list',{p_school:school});
        area.replaceChildren(el('h2',title));
        if(error)area.append(el('p','Pengumuman tidak dapat dimuat.','error'));
        else if(!data?.length)area.append(el('p','Belum ada pengumuman.','muted'));
        else for(const a of data){
          const line=el('div',null,'student-row');
          line.append(el('strong',a.title),el('p',a.body,'muted'),el('p',new Date(a.published_at).toLocaleDateString('id-ID')+' · '+a.creator_name,'muted'));
          area.append(line);
        }
      }else if(kind==='leave'){
        const {data,error}=await supabase.rpc('kabarkelas_leave_list',{p_school:school});
        area.replaceChildren(el('h2',title));
        if(error)area.append(el('p','Izin tidak dapat dimuat.','error'));
        else if(!data?.length)area.append(el('p','Belum ada pengajuan izin.','muted'));
        else for(const l of data){
          const line=el('div',null,'student-row');
          line.append(el('strong',l.teacher_name+' · '+l.leave_type),el('p',l.starts_on+' s.d. '+l.ends_on+' · '+l.reason,'muted'),el('p','Status: '+l.status,'muted'));
          if((unit.role==='principal'||unit.role==='school_admin') && l.status==='pending'){
            const approve=el('button','Setujui','secondary');const reject=el('button','Tolak','secondary');
            approve.onclick=async()=>{await supabase.rpc('kabarkelas_leave_decide',{p_leave:l.id,p_approve:true});btn.onclick();};
            reject.onclick=async()=>{await supabase.rpc('kabarkelas_leave_decide',{p_leave:l.id,p_approve:false});btn.onclick();};
            line.append(approve,reject);
          }
          area.append(line);
        }
        if(unit.role==='teacher'){
          const form=el('form');form.style.marginTop='12px';
          const type=el('select');for(const [v,l] of [['sick','Sakit'],['personal','Pribadi'],['official','Resmi'],['other','Lainnya']]){const o=el('option',l);o.value=v;type.append(o);}
          const start=el('input');start.type='date';start.required=true;
          const end=el('input');end.type='date';end.required=true;
          const reason=el('input');reason.placeholder='Alasan (min. 5 karakter)';reason.required=true;
          const submit=el('button','Ajukan izin','secondary');submit.type='submit';
          form.append(type,start,end,reason,submit);
          form.onsubmit=async(ev)=>{ev.preventDefault();submit.disabled=true;
            const {error}=await supabase.rpc('kabarkelas_leave_request',{p_school:school,p_type:type.value,p_start:start.value,p_end:end.value,p_reason:reason.value});
            if(error)message(area,'Izin gagal diajukan.',true);else btn.onclick();
            submit.disabled=false;};
          area.append(form);
        }
      }else if(kind==='homework'||kind==='quiz'){
        const rpc=kind==='homework'?'kabarkelas_homework_list':'kabarkelas_quiz_list';
        const {data,error}=await supabase.rpc(rpc,{p_school:school});
        area.replaceChildren(el('h2',title));
        if(error)area.append(el('p','Data tidak dapat dimuat.','error'));
        else if(!data?.length)area.append(el('p','Belum ada data.','muted'));
        else for(const item of data){
          const line=el('div',null,'student-row');
          const when=kind==='homework'?item.due_on:item.quiz_on;
          line.append(el('strong',item.title),el('p',item.class_name+' · '+item.subject_name+' · '+item.teacher_name,'muted'),el('p',(kind==='homework'?'Tenggat: ':'Tanggal: ')+when+' · Maks '+item.max_score,'muted'));
          area.append(line);
        }
      }else if(kind==='p5'){
        const {data,error}=await supabase.rpc('kabarkelas_p5_list',{p_school:school});
        area.replaceChildren(el('h2',title));
        if(error)area.append(el('p','Data P5/Tahfizh tidak dapat dimuat.','error'));
        else if(!data?.length)area.append(el('p','Belum ada penilaian P5/Tahfizh.','muted'));
        else for(const p of data){
          const line=el('div',null,'student-row');
          line.append(el('strong',p.student_name+' · '+p.category),el('p',p.indicator+' · Skor '+p.score+'/100','muted'),el('p','Oleh '+p.assessor_name+' · '+p.assessed_on,'muted'));
          area.append(line);
        }
      }
      appendPilotForms(unit,kind,area,school,()=>{btn.onclick();});
    }catch(e){area.replaceChildren(el('p','Modul belum tersedia.','error'));}
    finally{btn.disabled=false;}
  };
  return {btn,area};
}

function buildPilotModules(unit){
  const wrap=el('section',null,'dashboard-module');
  wrap.append(el('h2','Modul pilot'));
  const allowed={
    teacher:['schedule','announcement','leave','homework','quiz','p5'],
    principal:['schedule','announcement','leave','homework','quiz','p5'],
    school_admin:['schedule','announcement','leave','homework','quiz','p5'],
    guardian:['schedule','announcement','homework','quiz','p5'],
  };
  const kinds=allowed[unit.role]||[];
  if(!kinds.length)return null;
  const grid=el('div',null,'kpi-grid');
  for(const kind of kinds){
    const mod=buildPilotModule(unit,kind);
    const card=el('div',null,'kpi-card');
    card.append(mod.btn,mod.area);
    grid.append(card);
  }
  wrap.append(grid);
  return wrap;
}
