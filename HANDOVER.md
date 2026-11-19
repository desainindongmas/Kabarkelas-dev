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
- OPEN: rotasi GitHub PAT yang tertanam di remote URL .git/config;
  leaked-password protection tetap butuh Pro (diterima untuk pilot).
