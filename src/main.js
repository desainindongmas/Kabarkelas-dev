import { createClient } from '@supabase/supabase-js';
import './style.css';

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
function logoutButton(box){const b=el('button','Keluar','secondary');b.onclick=async()=>{await supabase.auth.signOut();currentContext=null;activeMembership=null;showLogin();};box.append(b);}
function showMembershipPicker(user,units){const box=panel('Pilih unit sekolah','Anda memiliki lebih dari satu penugasan. Pilih konteks kerja.');box.append(el('p',user.email,'muted'));
 for(const unit of units){const btn=el('button',`${unit.tenant_name} · ${unit.school_name||'Yayasan'} · ${unit.role}`,'unit');btn.onclick=()=>{activeMembership=unit;showHome(user,unit);};box.append(btn);} logoutButton(box);}
function showHome(user,unit){const box=panel('Berhasil masuk','Identitas dan penugasan Anda telah diverifikasi.');box.append(el('p',user.email,'muted'));box.append(el('div',unit.tenant_name,'highlight'));box.append(el('p',`Unit: ${unit.school_name||'Tingkat yayasan'}`));box.append(el('p',`Peran: ${unit.role}`));box.append(el('p','Fitur nilai, rapor, dan data siswa belum dibuka sampai pengujian izin selesai.','notice'));
 const change=el('button','Ganti unit','secondary');change.onclick=()=>{activeMembership=null;showMembershipPicker(user,currentContext.units);};box.append(change);logoutButton(box);}
if(configured){supabase.auth.onAuthStateChange((event)=>{if(event==='SIGNED_OUT'){activeMembership=null;currentContext=null;showLogin();}});loadContext();}else showLogin();
