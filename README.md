# KabarKelas — Login Starter

Repository utama: GitHub Akun A (`desainindongmas/Kabarkelas-dev`). Database/Auth: Supabase proyek `qajgoqtipvsstqlcyfro` (Akun B). Kedua akun tidak perlu sama.

## Jalankan lokal

1. Pasang Node.js versi terbaru yang didukung Vite 7.
2. Jalankan `npm install`.
3. Salin `.env.example` ke `.env.local` dan isi `VITE_SUPABASE_PUBLISHABLE_KEY` dengan **publishable key**, bukan secret key, dari dashboard Supabase.
4. Jalankan `npm run dev`.
5. Login memakai akun guru yang sudah dibuat pada Supabase Auth.

## Pemeriksaan

`npm run check` untuk sintaks JavaScript; `npm run build` untuk paket produksi. Belum ada deployment atau verifikasi login end-to-end. Fungsi database `public.kabarkelas_my_context()` mengembalikan penugasan pengguna setelah login. Data akademik tetap tertutup.

Jangan pernah commit password akun, database password, `service_role`, ataupun secret key. File `.env.local` sengaja diabaikan Git.
