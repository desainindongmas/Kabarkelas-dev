# KabarKelas — G0.5

Workflow nilai: `draft → submitted → approved → published`. Guru mengajukan nilai siswa pada kelas yang ditugaskan aktif. Kepala sekolah menyetujui dan menerbitkan dalam sekolahnya; pengaju tidak dapat menyetujui atau menerbitkan pengajuannya sendiri. Orang tua terverifikasi hanya membaca snapshot nilai terbit.

Repository: `desainindongmas/Kabarkelas-dev`. Supabase **development**: `qajgoqtipvsstqlcyfro` (`kabarkelas-dev`). Frontend Vite digunakan di Cloudflare Pages.

## Lokal

Gunakan Node.js 22.12+ dan `npm ci`. Salin `.env.example` ke `.env.local`; isi hanya URL dan **publishable key**. Jalankan `npm run dev`.

Jangan commit password, database URL berpassword, secret key atau service-role key. Semua `VITE_*` masuk ke bundle browser. Tidak ada credential yang diperlukan untuk build dan tes otomatis.

## Verifikasi

```sh
npm run check
npm test
npm run build
# PostgreSQL 17 lokal disposable; jangan arahkan ke Supabase/produksi.
docker run --rm -d --name kabarkelas-g05-db \
  -e POSTGRES_HOST_AUTH_METHOD=trust -p 127.0.0.1:55432:5432 postgres:17-alpine
npm run test:db
npx playwright install chromium
npm run test:ui
```

`TEST_DATABASE_URL` opsional, default `postgres://postgres@127.0.0.1:55432/postgres`. Runner hanya menerima localhost, membuat database uji sendiri, me-replay seluruh migration, lalu menghapus database uji. Kredensial server lokal harus boleh membuat database. CI menjalankan seluruh pemeriksaan yang sama.

Tes SQL memanggil RPC sebagai role `authenticated` dengan claim `auth.uid()` simulasi; tes browser memeriksa UI dengan HTTP/Auth stub. Keduanya bukan bukti login end-to-end di Cloudflare Pages. [Laporan audit dan bukti](docs/G05-verification.md) menjelaskan tes development dengan identitas fiktif yang sudah tersedia.

## Database dan API

13 migration di `supabase/migrations` mencakup 12 migration historis yang dipulihkan dari riwayat database development, ditambah G0.5. Timestamp G0.5 diselaraskan dengan versi yang dicatat Supabase saat penerapan. Jangan menerapkan ulang migration yang sudah tercatat.

- `kabarkelas_grade_workflow(p_school_id)` mengembalikan nilai yang boleh dibaca, `grade_id`, `revision`, dan `allowed_actions`.
- `kabarkelas_transition_grade(p_grade_id, p_action, p_expected_revision)` menerima `submit`, `approve`, atau `publish`. Aktor dan scope ditentukan database dari `auth.uid()` dan penugasan aktif; frontend tidak mengirim user/role/tenant.
- `kabarkelas_my_grades` mempertahankan bentuk respons lama dan membaca snapshot untuk nilai terbit.
- Setiap RPC transisi adalah satu transaksi: row lock, pemeriksaan scope, perubahan status/revisi, snapshot publikasi dan audit. Revisi usang ditolak dengan `40001`, status salah `55000`, izin ditolak `42501`.
- Snapshot dan audit append-only; nilai terbit tidak dapat diedit. Revisi/koreksi setelah publikasi memerlukan workflow terpisah yang belum termasuk G0.5.
- Tabel tetap RLS + tanpa grant langsung bagi `anon`/`authenticated`. Public RPC memakai `SECURITY INVOKER`; entrypoint terprivilegiasi di schema internal `app` memvalidasi identitas dan scope.

## Development smoke test

`supabase/tests/development_nadia_smoke.sql` menjalankan alur pada Nadia Simulasi, nilai Matematika (Simulasi) 82, memakai mapping identitas yang ada. Script selalu `ROLLBACK`: nilai tetap draft setelah tes. Jalankan hanya di proyek development yang sudah diaudit, bukan produksi.

Untuk matriks lengkap, jalankan `BEGIN`, `supabase/tests/fixtures.sql`, `supabase/tests/g05_workflow.sql`, lalu `ROLLBACK` dalam **koneksi/transaksi yang sama**. Fixture sintetis hanya untuk tes; bukan migration atau seed produksi.

Cloudflare Pages: build `npm run build`, output `dist`, env `VITE_SUPABASE_URL` dan `VITE_SUPABASE_PUBLISHABLE_KEY`. Perubahan frontend perlu melalui merge/deploy terpisah; tes lokal tidak membuktikan deployment live.
