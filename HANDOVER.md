KabarKelas-dev handover — updated 2026-11-19

## Current state
- Repo: github.com/desainindongmas/Kabarkelas-dev @ main `284b22a`
- Live: https://kabarkelas-dev.pages.dev (Cloudflare Pages auto-deploy)
- Backend: Supabase dev `qajgoqtipvsstqlcyfro` — 45 tables, 39 migrations
- UI: demo-parity patch applied (sidebar nav, KPI overview, EWS tables)

## Pilot features added (G10)
- 8 new tables: lesson_schedules, announcements, announcement_reads,
  teacher_leave_requests, homework_assignments, quiz_schedules,
  assignment_scores, p5_tahfizh_assessments
- 12 public RPCs: schedule, announcement, leave, homework, quiz, parent
  assignments, P5/Tahfizh
- UI modules per role in src/main.js (buildPilotModule/buildPilotModules)

## Seed data
- supabase/seeds/pilot_seed.sql — 35 synthetic students (SIM-001–035),
  3 classes, 3 subjects, 2 schedules, 1 announcement. Already applied.
- supabase/seeds/verify_seed.sql — verification query (passed)

## Known holds
- Supabase FREE tier: no leaked-password protection, no scheduled backup
- npm run test:db requires local PostgreSQL (not available on this machine)
- Browser E2E against live site pending manual verification
