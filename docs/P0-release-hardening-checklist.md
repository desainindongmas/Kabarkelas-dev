# KabarKelas — P0 release hardening and controlled pilot gate

Status: proposed development-only remediation. This document is **not** evidence of production readiness.

## Release baseline / P0-01
- Base: merged `main` through G0.8.4. Candidate: G0.8.5 PR #10 plus this hardening branch.
- This branch is based on `feat/g085-observation-audit`, not on the deployed production SHA.
- Do not merge to `main` or deploy merely because GitHub CI is green.
- Record final commit SHA; inspect compare against current `main`, including any concurrent changes.
- Required checks: `npm ci`, `npm run check`, `npm test`, `npm run build`, `npm run test:db`, `npm run test:ui`.
- Before approving merge, explicitly verify mergeability and get separate owner approval.

## Security / P0-02 and P0-03
- Additive migration `20261112000100_g085_p0_security_hardening.sql` replaces G0.8.5 observation functions with active tenant, school, student and enrollment checks.
- Audit table is append-only at application and table-trigger level. Privileged DDL/superusers can still bypass or disable triggers; storage is **not WORM**.
- Verify SQL regression with synthetic fixtures, including inactive tenant/school/student, revoked assignments, another teacher, stale revision, audit update/delete, and simultaneous requests.
- Investigate legacy `SECURITY DEFINER` RPCs `kabarkelas_my_context`, `kabarkelas_my_students`, `kabarkelas_my_role_students`: verify EXECUTE grants, schema USAGE, identity source, tenant isolation, fail-closed behavior, and anon denial.
- Do not revoke or rewrite legacy RPCs blindly: login and dashboards depend on them.

## Auth / P0-04 (manual configuration gate; NOT applied)
- Check Supabase Auth dashboard for leaked-password protection, password strength, signup policy, MFA and session settings.
- Enabling Auth settings requires a separate explicit owner-approved infrastructure change, followed by re-test with synthetic accounts.
- Document Supabase Database Linter findings, severity, accepted exceptions and reproduction evidence.

## Migration parity and rollback / P0-05 (NO live DB changes)
1. Read the target environment's `supabase_migrations.schema_migrations` and compare ordered version/content against repository migrations; **do not apply** on production or the shared development project during this task.
2. Validate complete ordered migration replay in disposable local PostgreSQL 17 using `npm run test:db`.
3. Confirm fresh-install and existing-G0.8.5 upgrade paths separately; don't edit a migration already recorded by Supabase.
4. Take verified backup/snapshot before any later approved upgrade; test restore to an **isolated** recovery database, not the live database. Record recovery point and elapsed restore time.
5. Review the SQL rollback plan: PostgreSQL DDL rollback can revert an *uncommitted* transaction; an applied committed migration requires a separately reviewed compensating migration or restore. Do not delete migration history or DROP student data.
6. Go/no-go requires an inventory of current environment, written migration/rollback order, pre/post checks, and separate explicit approval before applying.

## Browser E2E / P0-06 (NOT performed)
- Test target commit on staging Cloudflare with synthetic school and users.
- Verify teacher, principal, guardian, foundation logins using real Supabase Auth; never put service-role keys in client variables.
- Verify grade draft/submit/approve/publish, remedial/report release, EWS, approved rubric, observation correction/withdrawal, and guardian reads.
- Negative checks: another tenant, unverified parent, suspended school, revoked teacher assignment, stale update, no cross-role report or EWS access.
- Record network responses, backend audit IDs, screenshots (synthetic only), Cloudflare deployment SHA, Supabase migration versions, and PASS/FAIL.
- Do not use real student data until privacy, operator agreements, recovery, and security gates are approved.

## Explicit hold conditions
- Any unreviewed vulnerability, failed mandatory regression, migration drift, missing restore proof, or missing live E2E => **HOLD**.
- Green mocked Playwright and CI are necessary but not sufficient to release.
- No changes to Supabase project, Cloudflare, DNS, live deployment, or public-facing materials are authorized by this branch.

## P0 tracking
| ID | Item | What this branch proves | Still required |
| --- | --- | --- | --- |
| P0-01 | Release candidate | Source branch and versioned changes | Review SHA, CI, protected-merge approval |
| P0-02 | Scoped observation access | SQL hardening and regression tests | Full negative/real Auth verification |
| P0-03 | Audit immutability | DB trigger and attempted mutation checks | Backup/restore + incident drill |
| P0-04 | Auth and legacy RPC | Documented required checks | Actual Auth config/linter review |
| P0-05 | Migration recovery | Additive migration and local replay | Environment parity and isolated restore |
| P0-06 | Live end-to-end | Written test matrix | Actual staging browser and backend verification |
