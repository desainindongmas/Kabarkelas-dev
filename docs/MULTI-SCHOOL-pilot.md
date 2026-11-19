# Pilot Multi-School — Uji Isolasi Lintas Sekolah (2026-11-19)

Fixture untuk membuktikan tidak ada kebocoran data antar sekolah dalam satu yayasan.

## Struktur

**Yayasan Nusantara Cemerlang** (`yayasan-nusantara`, tenant `aa11bb22-…-0001`)

| Sekolah | Kode | Kelas | Siswa |
|---|---|---|---|
| SD Nusantara 1 | NSD1 | Kelas 4A, 4B | 70 (NSA-*, NSB-*) |
| SD Nusantara 2 | NSD2 | Kelas 5A | 35 (NTB-*) |

**Akun pilot** (password semua: `PilotYayasan2026!`)

| Email | Peran | Cakupan |
|---|---|---|
| pilot.foundasi@kabarkelas.dev | foundation_admin | yayasan (school_id NULL) |
| pilot.kepala1@kabarkelas.dev | principal | SD Nusantara 1 |
| pilot.kepala2@kabarkelas.dev | principal | SD Nusantara 2 |
| pilot.admin1@kabarkelas.dev | school_admin | SD Nusantara 1 |
| pilot.guru-a1@kabarkelas.dev | teacher | NSD1 (Kelas 4A) |
| pilot.guru-a2@kabarkelas.dev | teacher | NSD1 (Kelas 4B) |
| pilot.guru-b1@kabarkelas.dev | teacher | NSD2 (Kelas 5A) |
| pilot.guru-ab@kabarkelas.dev | teacher | **lintas: NSD1 + NSD2** |
| pilot.ortu-a@kabarkelas.dev | guardian | NSD1 (anak NSA-001, NSB-001) |
| pilot.ortu-b@kabarkelas.dev | guardian | NSD2 (anak NTB-001) |

Konten G10 per sekolah: 2 pengumuman (satu per sekolah), 3 tugas (satu per kelas),
5 jadwal pelajaran, 3 mapel per sekolah.

## Menjalankan

```bash
node scripts/seed_multi_school_pilot.mjs           # seed (idempotent)
node scripts/verify_multi_school_isolation.mjs     # uji isolasi via RPC live
```

Kredensial DB dibaca dari `~/.kabarkelas/secrets.env` (`SUPABASE_DB_*`).
Seed menghubungi Supabase langsung via connection pooler — bukan lewat SQL Editor.

## Hasil verifikasi isolasi (2026-11-19, 15/15 PASS)

| Skenario | Hasil |
|---|---|
| anon panggil RPC pilot | ditolak (permission denied) |
| guru NSD1 baca jadwal/siswa NSD2 | `School unavailable` (42501) |
| guru lintas (guru-ab) | akses kedua sekolah — sesuai membership ganda |
| kepala sekolah 1 vs 2 | masing-masing hanya lihat pengumuman sekolahnya |
| ortu-a akses data sekolah B | `[]` (kosong, bukan error — tidak bocor) |
| ortu-a hanya lihat anak ter-link | NSA-001, NSB-001 saja |
| foundation_admin | `my_context` OK; RPC pilot ditolak (by design: `pilot_can` butuh `school_id` cocok, foundation punya NULL) |

## Catatan

- `kabarkelas_my_role_students` mengembalikan `[]` (bukan error) untuk sekolah yang
  tidak diikuti guardian — perilaku benar, bukan kebocoran.
- Foundation roles tidak mendapat modul pilot (`buildPilotModules` → null) dan
  `pilot_can` menolak `school_id NULL` — konsisten, bukan bug.
- Membership foundation_admin memakai `school_id NULL` (sesuai CHECK constraint).
- Semua UUID deterministik (`aa11bb22-…`) — aman untuk idempotent re-seed.

## Fase 2 — konten akademik (2026-11-19)

`node scripts/seed_multi_school_academic.mjs` menambah:
- 10 guru mapel baru (n=11..20): PPKn, BIN, IPA, IPS, B.Inggris, PJOK,
  SBdP untuk NSD1; PPKn/B, BIN/B, IPA/B untuk NSD2 — mapel lengkap
  kurikulum SD (8 mapel per sekolah).
- 4 ortuwali baru (n=21..24), masing-masing 2 siswa per kelas.
- 72 assessments (3 judul × 8 mapel × 3 kelas), 4.410 student_grades
  published + publication snapshots + assessment releases.
- 24 sesi kehadiran published (8 per kelas), 11 siswa flagged absent.
- EWS rules aktif v2 + scan: 6 alerts NSD1, 5 alerts NSD2.
- 3 school_report_reviews released + 105 report snapshots.

Verifikasi: `node scripts/verify_multi_school_academic.mjs` → 14/14 PASS.

Catatan migrasi data:
- `kabarkelas_grade_workflow` per guru menampilkan SEMUA mapel kelas
  binaannya (bukan hanya mapelnya) — otorisasi grade class-scoped,
  bukan subject-scoped. Guru mapel bisa input nilai mapel lain selama
  dia assigned ke kelas itu. Jika ingin subject-scoped, perlu kolom
  mapping guru↔mapel atau cek `lesson_schedules.teacher_user_id`.
- Tidak ada RPC untuk membuat assessment/student_grades — seed nilai
  dilakukan langsung via SQL (postgres). Workflow guru hanya bisa
  record_attempt/correct/finalize pada grade yang sudah ada.
