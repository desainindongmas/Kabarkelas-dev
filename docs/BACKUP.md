# Backup Manual KabarKelas (Supabase FREE tier)

Project: `qajgoqtipvsstqlcyfro` (kabarkelas-dev)
Host pooler: `aws-0-ap-southeast-1.pooler.supabase.com:5432` (session mode — wajib untuk pg_dump)
User: `postgres.qajgoqtipvsstqlcyfro`
Password DB: ada di `C:\Users\Nur Azizah\.kabarkelas\secrets.env` → `SUPABASE_DB_PASSWORD`
**Jangan commit password ke repo mana pun.**

Isi backup: seluruh database Postgres termasuk schema `public` (data app) dan
`auth` (akun login + hash password). File storage Supabase tidak dipakai, jadi
tidak ada yang perlu dibackup terpisah.

---

## Metode A — pg_dump (direkomendasikan, jalan di PC ini)

### 1. Install PostgreSQL client sekali saja

Pilih salah satu:

- ** winget** (PowerShell admin):
  `winget install PostgreSQL.PostgreSQL.17`
- **ZIP tanpa installer**: unduh "Binaries from installer" ZIP dari
  https://www.enterprisedb.com/download-postgresql-binaries → extract ke
  `C:\pgsql` → pakai `C:\pgsql\bin\pg_dump.exe`.

Cek: `pg_dump --version` harus menampilkan PostgreSQL 15+.

### 2. Buat folder backup

```
mkdir C:\Users\"Nur Azizah"\kabarkelas-backups
```

Saran: satu subfolder per bulan, mis. `kabarkelas-backups\2026-11\`.

### 3. Jalankan backup (ganti tanggal tiap kali)

PowerShell:

```powershell
$env:PGPASSWORD = "ISI_DB_PASSWORD_DARI_secrets.env"
pg_dump -h aws-0-ap-southeast-1.pooler.supabase.com -p 5432 `
  -U postgres.qajgoqtipvsstqlcyfro -d postgres `
  -Fc -f "C:\Users\Nur Azizah\kabarkelas-backups\kabarkelas_2026-11-19.dump"
```

Atau satu baris cmd (prompt password akan muncul — lebih aman):

```
pg_dump -h aws-0-ap-southeast-1.pooler.supabase.com -p 5432 -U postgres.qajgoqtipvsstqlcyfro -d postgres -Fc -f "C:\Users\Nur Azizah\kabarkelas-backups\kabarkelas_2026-11-19.dump"
```

Lalu ketik password DB saat diminta.

Hasil yang diharapkan: file `.dump` ukuran beberapa ratus KB – beberapa MB,
`pg_dump: saving complete contents of table ...` tanpa baris `ERROR`.

### 4. Verifikasi isi dump (opsional tapi disarankan sebulan sekali)

```
pg_restore -l "C:\Users\Nur Azizah\kabarkelas-backups\kabarkelas_2026-11-19.dump" | findstr /C:"TABLE DATA public.students" /C:"TABLE DATA auth.users"
```

Harus muncul minimal `TABLE DATA public.students` dan `TABLE DATA auth.users`.

---

## Metode B — Tanpa install apa pun (fallback)

1. Buka https://supabase.com/dashboard/project/qajgoqtipvsstqlcyfro
   → **SQL Editor**.
2. Untuk tiap tabel penting, jalankan `select * from public.<tabel>` lalu
   unduh hasil sebagai CSV (ikon download di hasil query).
   Prioritas: `students`, `memberships`, `guardian_student_links`,
   `academic_grades`, `homework_assignments`, `quiz_schedules`,
   `p5_tahfizh_assessments`, `lesson_schedules`, `announcements`,
   `teacher_leave_requests`, `assignment_scores`.
3. Akun login TIDAK bisa dibackup lewat cara ini — untuk itu tetap perlu
   Metode A atau restore manual akun.

Catatan: Metode B hanya untuk keadaan darurat; Metode A adalah backup sungguhan.

---

## Jadwal yang disarankan

| Kapan | Aksi |
|---|---|
| Mingguan (mis. Minggu malam) | Jalankan Metode A |
| Sebelum setiap deploy migration baru | Jalankan Metode A |
| Sebelum ubah data massal | Jalankan Metode A |
| Bulanan | Salin dump ke lokasi kedua (Google Drive / OneDrive / flashdisk) |

### Otomatisasi mingguan via Task Scheduler (Windows)

1. Buka **Task Scheduler** → Create Task → beri nama `KabarKelas-Backup`.
2. Trigger: Weekly, Minggu, 21:00.
3. Action: Start a program:
   - Program: `C:\Program Files\PostgreSQL\17\bin\pg_dump.exe`
     (sesuaikan path instalasi)
   - Arguments:
     `-h aws-0-ap-southeast-1.pooler.supabase.com -p 5432 -U postgres.qajgoqtipvsstqlcyfro -d postgres -Fc -f "C:\Users\Nur Azizah\kabarkelas-backups\kabarkelas_%date:~10,4%%date:~4,2%%date:~7,2%.dump"`
     (format tanggal di Task Scheduler tidak support `%date%` — lebih mudah:
     buat file `backup.bat` berisi perintah pg_dump dengan nama file manual,
     lalu jadwalkan `backup.bat`.)
4. Karena butuh password, simpan password di file `.pgpass`:
   `%APPDATA%\postgresql\pgpass.conf` berisi:
   `aws-0-ap-southeast-1.pooler.supabase.com:5432:postgres:postgres.qajgoqtipvsstqlcyfro:ISI_DB_PASSWORD`
   (chmod tidak diperlukan di Windows; file ini hanya bisa dibaca user Anda.)

---

## Restore (uji minimal 1× sebelum pilot)

JANGAN restore ke project produksi. Buat project Supabase baru gratis
mis. `kabarkelas-restore-test`, lalu:

```
pg_restore -h aws-0-ap-southeast-1.pooler.supabase.com -p 5432 `
  -U postgres.qajgoqtipvsstqlcyfro -d postgres `
  --clean --if-exists "C:\Users\Nur Azizah\kabarkelas-backups\kabarkelas_2026-11-19.dump"
```

(ganti host/user sesuai project tujuan). Setelah restore, cek:
`select count(*) from public.students;` dan login satu akun pilot di URL project baru.

---

## Batasan yang diketahui (jujur)

- FREE tier tidak punya scheduled backup/PITR otomatis — backup di atas adalah
  satu-satunya perlindungan. RPO efektif = interval backup (mingguan → maks
  kehilangan 7 hari data).
- `pg_dump` lewat pooler session (port 5432). Jangan pakai port 6543
  (transaction mode) — akan error di tengah dump.
- Kalau suatu hari upgrade ke Pro: PITR + leaked-password protection aktif,
  dokumen ini tetap berguna sebagai backup kedua.
