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


## Deploy website uji via Vercel

1. Masuk ke https://vercel.com/new menggunakan GitHub Akun A.
2. Import repository `desainindongmas/Kabarkelas-dev`.
3. Framework Preset: Vite. Build Command: `npm run build`; Output Directory: `dist`.
4. Tambahkan Environment Variables:
   - `VITE_SUPABASE_URL`: `https://qajgoqtipvsstqlcyfro.supabase.co`
   - `VITE_SUPABASE_PUBLISHABLE_KEY`: publishable key dari Supabase Dashboard → Project Settings → API Keys.
5. Deploy. Buka alamat Vercel dan login dengan email/password akun guru fiktif yang sudah dibuat (jangan bagikan password kepada ChatGPT).
6. Pastikan halaman menunjukkan SD Demo KabarKelas, bukan SMP Demo KabarKelas ataupun yayasan kedua. Coba logout dan refresh halaman.

**Catatan:** Vite memasukkan variabel `VITE_*` ke bundle browser. Hanya publishable key yang boleh digunakan; jangan masukkan secret key/service_role. Workflow GitHub Actions memeriksa sintaks dan build saat push. Build tidak memerlukan variabel lingkungan karena halaman dapat menampilkan pesan konfigurasi jika variabel belum ada. Fitur akademik tetap belum dibuka.
