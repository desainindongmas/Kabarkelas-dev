# Template Impor Data Massal (CSV)

Fitur "Impor data massal" tersedia untuk `foundation_admin`, `principal`, dan `school_admin` di dashboard (modul pilot → "Impor data massal").

## Format file

- Satu file `.csv` (Excel: *Save As → CSV UTF-8*).
- Baris pertama = header. Kolom pertama WAJIB bernama `section`.
- Satu baris = satu record. Kolom yang tidak relevan untuk section tsb boleh dikosongkan.
- Nama section (huruf kecil): `tenant`, `school`, `user`, `membership`, `subject`, `class`, `student`, `assignment`, `guardian`.

## Kolom per section

| section | kolom |
|---|---|
| tenant | `slug`, `name` |
| school | `tenant_slug` atau `tenant_name`, `code`, `name` |
| user | `email`, `display_name`, `password` (opsional, default `KabarKelas2026!`) |
| membership | `email`, `role_code`, `school_code` (kosong = level tenant; wajib untuk principal/teacher/dll) |
| subject | `school_code`, `code`, `name` |
| class | `school_code`, `name`, `academic_year` (opsional) |
| student | `school_code`, `local_student_no`, `display_name`, `class_name` (opsional, untuk enrollment) |
| assignment | `school_code`, `class_name`, `subject_code`, `teacher_email` |
| guardian | `school_code`, `guardian_email`, `student_no`, `relationship` (opsional, default `parent`) |

## Contoh minimal

```csv
section,slug,name,tenant_slug,code,school_code,name,email,display_name,password,role_code,local_student_no,class_name,subject_code,teacher_email,guardian_email,student_no
user,,,,,,,,guru.satu@sekolah.id,Guru Satu,,teacher,,,,,,
membership,,,,,, yayasan-a,,,guru.satu@sekolah.id,,,,principal,,,,,
subject,,,,,,,IPA,,,,,,,,,
class,,,,,,,Kelas 5A,,,,,,,,
student,,,,,,, ,,,,,,005,Ani,,,,
assignment,,,,,,,,,,,,,IPA,guru.satu@sekolah.id,,
guardian,,,,,,,,,,,,,,,,ortu.ani@sekolah.id,005
```

## Catatan

- Urutan eksekusi otomatis: tenant → school → user → membership → subject → class → student → assignment → guardian.
- `user` membuat akun login (email + password) sekaligus; `membership` memberi peran.
- `assignment` mengisi `teacher_class_assignments` + `teacher_subject_assignments` — tanpa ini guru tidak bisa kelola nilai mapel tsb.
- `guardian` membuat tautan wali murid dengan status `verified` (verifikator = principal sekolah).
- Semua operasi idempotent: data yang sudah ada di-skip/diperbarui, bukan diduplikasi.
- Hanya untuk data sintetis/pilot — jangan unggah data siswa asli tanpa persetujuan kebijakan privasi.
