KabarKelas-dev handover — updated 2026-11-19 (final)

## Current state
- Repo: github.com/desainindongmas/Kabarkelas-dev @ main `6324a7a`
- Live: https://kabarkelas-dev.pages.dev (Cloudflare Pages auto-deploy — pending deploy of latest commit)
- Backend: Supabase dev `qajgoqtipvsstqlcyfro` — 45 tables, 39 migrations
- UI: demo-parity patch applied (sidebar nav, KPI overview, EWS tables)

## Pilot features added (G10)
- 8 new tables: lesson_schedules, announcements, announcement_reads,
  teacher_leave_requests, homework_assignments, quiz_schedules,
  assignment_scores, p5_tahfizh_assessments
- 12 public RPCs + app.* helpers. All verified live via REST with
  pilot.guru@kabarkelas.dev:
  - kabarkelas_schedule_list: 200 (2 rows)
  - kabarkelas_announce_list: 200 (1 row)
  - kabarkelas_p5_list: 200
  - kabarkelas_homework_list: 200
  - kabarkelas_quiz_list: 200
  - kabarkelas_leave_list: 200
- UI modules per role in src/main.js (buildPilotModule/buildPilotModules)

## Seed data applied
- 35 synthetic students (SIM-001–035), 3 classes, 3 subjects,
  2 lesson schedules, 1 announcement — all verified via SQL count query.

## Fixes applied post-push
- RPC return-type mismatch fixed: teacher_user_id/teacher_name column
  order swapped in schedule/homework/quiz/leave list functions.
- users.display_name → COALESCE(u.email,'Guru') since users table has no
  display_name column.

## Known holds
- Supabase FREE tier: no leaked-password protection, no scheduled backup
- npm run test:db requires local PostgreSQL (not available on this machine)
- G10 E2E verified live 2026-11-19 all four roles (see Phase 2 below).
  Homework/quiz/P5 seeded with rows; leave request→approve flow verified.
- Fixed post-G10: buildPilotModules was dead code (never invoked) so rollup
  tree-shook all G10 UI out of the bundle; wired into showHome @ 38ec923.

## Phase 2 (2026-11-19): seed G10 + multi-role pilot accounts
- New pilot accounts (password sama): pilot.kepala (principal),
  pilot.admin (school_admin), pilot.ortu (guardian → SIM-001 verified link).
  Provisioning script: supabase/seeds/pilot_accounts.sql (idempotent).
- G10 content seeded via RPC as pilot.guru: 2 homework (published),
  1 quiz, 5 homework_scores, 4 quiz_scores, 6 P5/Tahfizh records.
- teacher_class_assignments: pilot.guru kini aktif di 5A/5B/6A.
- E2E live verified per role: teacher (semua modul+data), principal
  (leave_decide pending→approved OK), school_admin (jadwal OK),
  guardian (hanya 5 modul, P5 hanya data anak ter-link SIM-001).

## Phase 3 (2026-11-19): hardening tanpa Supabase Pro
- RLS audit 8 tabel G10: semua ENABLE+FORCE RLS, masing-masing 1 SELECT
  policy; write hanya via SECURITY DEFINER RPC.
- Anon denial verified live: semua RPC G10 → 42501, direct table read → 42501.
- Regression test tests/pilot-bundle.test.js: build vite lalu assert string
  RPC G10 ada di bundle (menangkap bug dead-code tree-shake). ~13s.
- Backup manual: docs/BACKUP.md — pg_dump via pooler session :5432,
  jadwal mingguan + pra-migration, restore test ke project terpisah.
- DONE: PAT dihapus dari remote URL (Phase 4); token kini hanya di
  secrets.env + credential helper. Rotasi PAT tetap disarankan.

## Phase 4 (2026-11-19): UI write-paths + remote cleanup
- Remote origin dibersihkan dari PAT; credential helper
  ~/.kabarkelas/git-credential.sh membaca GITHUB_TOKEN dari secrets.env.
- Migration 20261119000002 (applied live): kabarkelas_pilot_options
  (class/subject) + kabarkelas_pilot_students untuk staf.
- appendPilotForms di src/main.js: form buat tugas/kuis + input nilai,
  catat P5/Tahfizh (staf), terbitkan pengumuman (principal/school_admin).
- E2E live: homework_score via UI (valid 87 OK, lintas-kelas ditolak),
  quiz_create via UI, p5_record via UI, announce_create via UI — semua
  tercatat di DB.

## Phase 5 (2026-11-19): fixture multi-school isolasi
- Tenant baru "Yayasan Nusantara Cemerlang" (aa11bb22-…): 2 sekolah
  (SD Nusantara 1 NSD1, SD Nusantara 2 NSD2), 105 siswa sintetis
  (3 kelas x 35), 10 akun pilot lintas peran termasuk guru ab dan
  foundation_admin. Password: PilotYayasan2026! — lihat
  docs/MULTI-SCHOOL-pilot.md.
- scripts/seed_multi_school_pilot.mjs: seed idempotent via pg pooler
  (bukan SQL Editor). scripts/verify_multi_school_isolation.mjs:
  15/15 RPC-level isolation checks PASS — tidak ada kebocoran
  lintas sekolah; foundation_admin by design tanpa modul pilot.

## Phase 6 (2026-11-19): konten akademik + verifikasi UI demo-parity
- scripts/seed_multi_school_academic.mjs: +10 guru mapel (kurikulum SD
  lengkap: PPKn, BIN, MTK, IPA, IPS, B.Inggris, PJOK, SBdP), +4 ortuwali
  baru (2 siswa per ortu), 8 mapel/sekolah, 72 assessments, 4.410 nilai
  published + snapshot + release, 24 sesi kehadiran, EWS rules v2 aktif,
  3 rapor released + 105 snapshot. EWS scan via RPC: 6+5 alerts.
- scripts/verify_multi_school_academic.mjs: 14/14 checks PASS.
- UI live diverifikasi vs branch fix/ui-demo-parity-v2 (demo repo
  C:/Users/Nur Azizah/kabarkelas/Kabarkelas-dev): rendering nilai, EWS,
  rapor, siswa identik — parity terjaga.
- Catatan: tidak ada RPC pembuatan assessment/student_grades — input
  nilai guru hanya untuk grade existing (record_attempt/correct/
  finalize). Pembuatan soal/assessment masih via SQL.
- Sekolah B punya mapel ganda MTK/BIN (legacy) + MTKB/BINB — nilai
  tetap valid, bukan kebocoran.

## Phase 7 (2026-11-19): G11 — teacher-subject authz, buat penilaian, impor CSV
- Migration 20261119000003_g11_teacher_subjects_assessment_import.sql (live):
  - Tabel teacher_subject_assignments (TSA) + backfill 26 baris aktif.
  - g05_access.teacher & g051_can_manage_draft kini subject-scoped:
    guru hanya lihat kelola nilai mapel yang ditugaskan (TSA).
  - RPC baru: kabarkelas_teacher_options, kabarkelas_my_periods,
    kabarkelas_class_students, kabarkelas_create_assessment
    (assessment draft + student_grades draft + assessment_attempts initial).
  - RPC impor (SECURITY DEFINER, app.g11_import_allowed: foundation_admin/
    principal/school_admin): kabarkelas_import_{tenants,schools,users,
    memberships,subjects,classes,students,teacher_assignments,
    guardian_links}. User dibuat langsung di auth.users+identities.
- UI src/main.js: modul pilot baru — guru "Buat penilaian" (opsi
  kelas·mapel dari TSA, periode, input nilai per siswa), admin
  "Impor data massal" (CSV parse client-side → preview → RPC berurutan).
- Sekolah B dedup: MTK/BIN legacy dihapus; assessments/schedules/TSA
  direpoint ke MTKB/BINB. 8 mapel bersih.
- scripts/verify_g11_features.mjs: 13/13 PASS (TSA, create_assessment,
  cross-school/salah-mapel ditolak, finalize, import chain, dedup).
- verify_multi_school_academic.mjs diupdate: ekspektasi subject-scoped
  (guru-a1 hanya MTK; guru-ab IPA NSD1 + MTKB NSD2). 14/14 PASS.
- docs/IMPORT-template.md: spesifikasi CSV per section.
- Catatan: .xlsx tidak didukung — simpan sebagai CSV.

