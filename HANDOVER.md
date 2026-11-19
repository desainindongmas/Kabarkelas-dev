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
- G10 E2E verified live 2026-11-19 as pilot.guru (teacher): all 6 modules render,
  schedule/announcement show seed data, leave request submit→list works.
  Homework/quiz/P5 verified to empty-state only (no seed rows yet).
  Principal/school_admin/guardian roles untested — no pilot passwords exist
  for owner accounts (msubhi.*@gmail.com).
- Fixed post-G10: buildPilotModules was dead code (never invoked) so rollup
  tree-shook all G10 UI out of the bundle; wired into showHome @ 38ec923.
