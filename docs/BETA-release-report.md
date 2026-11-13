# KabarKelas — Laporan Rilis Beta (2026-11-13)

## Ringkasan eksekutif
KabarKelas versi beta **SIAP DIRILIS** untuk pilot terbatas dengan data sintetis.
Semua gate P0 yang bisa diverifikasi pada stack FREE tier sudah **PASS**; dua item
diketahui HOLD-by-design hingga upgrade Pro (leaked-password protection, scheduled backup).

- URL beta: https://kabarkelas-dev.pages.dev
- Repo: https://github.com/desainindongmas/Kabarkelas-dev @ main `b76a405`
- Backend: Supabase dev `qajgoqtipvsstqlcyfro` (kabarkelas-dev, FREE/NANO)
- Deployment: Cloudflare Pages, bundle live mengandung seluruh fitur G0.5–G0.8.5 + P0 hardening
  (diverifikasi: `kabarkelas_update_development_observation` & UI "Tinjau observasi terdahulu" ada di bundle live).

## Akun pilot (sintetis, aman untuk dibagikan ke calon pilot)
| Peran | Email | Password | Sekolah |
|---|---|---|---|
| Guru | pilot.guru@kabarkelas.dev | PilotKabarKelas2026! | SD Demo KabarKelas (Kelas 5A Uji, siswa Nadia Simulasi) |

Akun peran lain sudah ada (pemilik): msubhi.online@gmail.com (guardian),
muhsubhi24@gmail.com (principal), msubhi.subhi@gmail.com (foundation_admin),
desainindongmas@gmail.com (teacher). Password akun lama tidak dicatat di repo —
minta reset via Supabase Auth > Users > Send password recovery bila perlu.

Data pilot: 2 yayasan demo, 3 sekolah, 3 siswa simulasi (Nadia/Tara/Raka),
4 membership. Tidak ada data siswa asli.

## Hasil gate P0
| Gate | Status | Bukti |
|---|---|---|
| P0-01 Release candidate | PASS | main `b76a405`, CI hijau, bundle live = source remote main |
| P0-02 Scoped observation access | PASS | E2E live: observasi publish→correct→withdraw; RPC menolak non-guru |
| P0-03 Audit immutability | PASS | Trigger append-only menolak UPDATE audit bahkan oleh superuser SQL (42501); 2 baris audit tercatat benar |
| P0-04 Auth config | HOLD (by design) | Leaked-password protection OFF — hanya tersedia Pro plan. Min password 6, signup ON, confirm email ON. Naikkan ke Pro saat pilot pertama bergabung |
| P0-05 Migration parity & recovery | PASS parsial | 37/37 migration applied termasuk `20261112000100_g085_p0_security_hardening`. Local replay 94+ assertion lulus. **Belum ada scheduled backup/PITR (FREE tier)** — jalankan `pg_dump` manual mingguan atau upgrade Pro |
| P0-06 Live E2E | PASS | Login live guru pilot → dashboard → observasi → koreksi → cabut → audit DB terverifikasi. Negative: anon EXECUTE ditolak (42501), authenticated tanpa JWT → 28000, 37/37 tabel RLS+FORCE RLS |

## Verifikasi teknis yang dijalankan
- `npm run check`, `npm test` (17/17), `npm run build`, `npx playwright test` (21/21) — semua hijau
- SQL live: RLS 37/37 tabel aktif; 3 SECURITY DEFINER legacy RPC (my_context, my_students, my_role_students) anon_exec=false, auth_exec=true, fail-closed tanpa JWT
- E2E live di kabarkelas-dev.pages.dev dengan akun pilot.guru@kabarkelas.dev

## Known limitations (jujur untuk pilot)
1. Tanpa leaked-password protection & scheduled backup sampai upgrade Supabase Pro.
2. Belum ada UI untuk mengembalikan observasi withdrawn / melihat log audit (data tetap tersimpan).
3. EWS scan manual oleh kepala sekolah; tidak ada notifikasi realtime.
4. Rapor & nilai harian perlu diisi dulu oleh guru sebelum orang tua melihat sesuatu.
5. Struktur non-tech friendly: semua isolasi data via tenant→school→class→student + RLS;
   perbaikan cukup via SQL Editor dashboard atau RPC bernama jelas; setiap mutasi penting
   tercatat di tabel audit (`academic_workflow_events`, `development_observation_audit`, `report audit`).

## Langkah untuk pilot
1. Sebarkan URL + akun pilot.guru@kabarkelas.dev ke 1–3 sekolah uji.
2. Minta mereka input nilai/remedial/rapor/EWS observasi pada data sintetis.
3. Kumpulkan bug/UX feedback → perbaikan masuk branch fix → PR → merge → Pages auto-deploy.
4. Saat pilot terbukti: upgrade Supabase ke Pro (leaked password + backup), baru buka sekolah nyata.

## Rekomendasi maintenance mingguan (non-tech)
- Cek https://kabarkelas-dev.pages.dev masih 200.
- Login 1 akun, buka dashboard, pastikan data tampil.
- Di Supabase dashboard > Database > Backups: jalankan manual backup/export bilaFREE.
