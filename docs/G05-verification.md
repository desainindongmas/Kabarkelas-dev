# G0.5 audit dan verifikasi — 1 November 2026 UTC

## Baseline yang diperiksa

- GitHub `main`: `3535b5579e9eea4573516284965763a2b4f1e485`.
- Supabase `qajgoqtipvsstqlcyfro`, nama **kabarkelas-dev**, PostgreSQL 17.11; proyek production tidak disentuh.
- 12 migration tersimpan di database tetapi belum ada di repository. Dipulihkan dari `supabase_migrations.schema_migrations`, tanpa data siswa atau credential.
- Fungsi transisi belum ada. `kabarkelas_grade_workflow_preview` hanya SELECT; bukan implementasi transisi.
- Tes lama gagal `ERR_MODULE_NOT_FOUND` untuk `src/workflow-rules.js`; CI belum menjalankan tes.
- Semua tabel public sudah RLS; tidak ada grant tabel untuk PUBLIC/anon/authenticated. Pembacaan lama memakai baris nilai mutable untuk nilai terbit.
- Nadia Simulasi: Matematika (Simulasi), 82, draft, revision 1.

## Implementasi dan keputusan keamanan

Migration `20261101043419_g05_grade_approval_publication.sql` diterapkan **setelah** replay migration, tes SQL, sintaks, build dan tes browser lokal lulus. File awal dibuat dengan Supabase CLI `migration new`; versi filename kemudian disamakan dengan versi penerapan MCP agar tidak terjadi drift riwayat.

Identitas berasal dari `auth.uid()` → `users.auth_subject`; metadata user dan parameter aktor tidak dipakai untuk otorisasi. Status aktif tenant, sekolah, siswa, membership, kelas guru dan enrollment diperiksa. Guru harus ditugaskan pada kelas assessment, bukan sekadar sekolah yang sama. Enrollment yang belum mulai atau sudah berakhir ditolak.

Grade dikunci `FOR UPDATE`. Baris sumber otorisasi dikunci `FOR SHARE` sampai commit. Optimistic revision mencegah replay/permintaan usang. Approver berbeda dari submitter, termasuk akun multi-peran. Publikasi, snapshot ber-checksum SHA-256, dan audit berisi identitas Auth dilakukan atomik. Kegagalan audit membatalkan seluruh perubahan.

RPC public baru/yang diganti memakai invoker; dua entrypoint definer ada di schema internal `app`, dengan `search_path` kosong, pengecekan Auth dan scope mandiri. Grant USAGE schema tidak membuka helper lain: EXECUTE helper ditolak. Tabel tetap tanpa grant langsung. Trigger menolak UPDATE/DELETE snapshot dan audit, serta TRUNCATE; nilai terbit dibekukan. Superuser/pemilik schema tetap dapat mengubah DDL/menonaktifkan trigger: ini bukan penyimpanan WORM di luar kontrol administrator.

## Bukti pengujian yang benar-benar dijalankan

| Pemeriksaan | Hasil |
| --- | --- |
| `npm run check` | Lulus seluruh JS aplikasi, script dan tes |
| `npm test` | 4/4 lulus |
| `npm run build` | Lulus, bundle Vite 7.3.7 dibuat |
| `npm audit --audit-level=low` | 0 kerentanan, termasuk dependency development |
| Pemeriksaan secret dan whitespace | Lulus untuk seluruh berkas kandidat commit |
| PostgreSQL 17 lokal | 94 assertion SQL + 2 tes konkurensi lulus; Node melaporkan 97 termasuk parent test |
| Playwright Chromium | 7/7 lulus (HTTP/Auth stub, bukan login live) |
| Supabase development, matriks SQL | 94/94 lulus dengan role authenticated/anon; seluruh fixture di-rollback |
| Supabase development, Nadia dan aktor yang ada | 9/9 lulus: submit, approve, publish, guardian melihat 82, audit 3, snapshot 1; rollback |
| Pemeriksaan sesudah rollback | Nadia 82/draft/revision 1; 0 fixture tenant; 0 audit/snapshot uji tertinggal; 0 grant tabel runtime |

Matriks mencakup anonymous/unmapped Auth, spoof metadata dan identitas lama, tenant/sekolah lain, guru tanpa penugasan kelas, membership/assignment/enrollment nonaktif, self-approval, status loncat, revisi usang, score kosong/NaN/melebihi maksimum, duplicate request, guardian belum terverifikasi/dicabut, draft/submitted/approved tersembunyi, immutability dan rollback saat audit gagal. Dua koneksi PostgreSQL menguji submit dan publish bersamaan; hanya satu event/snapshot dihasilkan.

Smoke test Nadia pertama gagal pada pencarian fixture karena label mata pelajaran sebenarnya `Matematika (Simulasi)`, bukan `Matematika`. Selector diperbaiki ke label terverifikasi lalu seluruh sembilan assertion lulus. Tidak ada kegagalan tes yang disembunyikan atau dianggap sukses.

Vite 7.1.7 memiliki advisory high pada dev server. Diperbarui ke 7.3.7; seluruh tes aplikasi/browser dan build diulang dan lulus. MD5 isi migration lokal dan riwayat Supabase sama: `3e282495aae657d0de541d1a596e34f6`.

## Temuan audit yang masih ada

- [Leaked password protection](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection) masih disabled; konfigurasi Auth ini tidak diubah oleh migration workflow.
- [SECURITY DEFINER executable](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable): tiga RPC lama `kabarkelas_my_context`, `kabarkelas_my_students`, `kabarkelas_my_role_students`. Jumlah berkurang dari empat karena read nilai diubah menjadi invoker. RPC lama sudah diperiksa untuk Auth dan scope, tetapi migrasi struktur tiga RPC ini di luar G0.5.
- [RLS tanpa policy](https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy): 18 INFO, sesuai desain akses RPC dengan grant tabel ditutup. Ini tidak berarti semua tabel boleh dibaca.
- Performance advisor awal mencatat 30 [foreign key tanpa indeks](https://supabase.com/docs/guides/database/database-linter?lint=0001_unindexed_foreign_keys) dan 5 indeks belum terpakai. Migration menambah indeks FK aktor workflow dan student lookup; indeks domain lain tidak diubah.
- Branch utama tidak memiliki required status checks pada saat audit. CI sekarang menjalankan semua tes pada push dan PR, tetapi konfigurasi proteksi branch tidak diubah.

Tes SQL memodelkan claim yang normalnya disetel PostgREST setelah validasi JWT. Password login, penerbitan JWT, dan deployment Cloudflare live tidak diuji ulang dalam sesi ini. Tidak ada password atau secret key yang diminta/disimpan. Perubahan frontend disiapkan dalam branch/PR; tidak ada perubahan data produksi atau publikasi permanen nilai Nadia.
