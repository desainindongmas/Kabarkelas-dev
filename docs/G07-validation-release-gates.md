# G0.7 — Validation, security gate and UI foundation

## Proven
- G0.5.1 and G0.6 merged into main, scoped RPCs remain installed in Supabase development.
- Database security linter: role grants and SECURITY DEFINER warnings need careful interpretation; RPC definer functions are intentionally used in the project, but must validate authorization on each call.
- Automated PostgreSQL test now denies direct SELECT on private academic, EWS, grade and report tables for both anon/authenticated.
- CSS foundation adds responsive sizes, focus-visible affordances, accessible touch targets and reduced-motion support while keeping existing DOM contracts stable.

## Not proven / external dependencies
- Cloudflare Pages deployment was not independently accessible from this execution environment (DNS resolution failed); no claim that post-merge live browser was smoke-tested.
- Browser suite runs against mocked Supabase Auth/RPC. Green Playwright means UI contract, not an authenticated live deployment test.
- Supabase Auth leaked-password protection remains a security advisor warning that needs account-side configuration before genuine production users.
- Three legacy public SECURITY DEFINER RPC warnings require targeted security review; do not blindly revoke as authentication and initial student dashboards depend on them.
- No production data migration or live-student change was made by G0.7.

## Required pre-production acceptance
1. Verify Cloudflare Pages deployed the main branch commit SHA.
2. Smoke-test teacher, principal, guardian and foundation using synthetic school users (no real students).
3. Confirm no EWS inbox/notes visible to guardian or foundation and no cross-school data leak.
4. Turn on leaked-password protection in Supabase Auth configuration and re-run security linter.
5. Audit intentionally exposed SECURITY DEFINER RPCs and perform appropriate negative authorization tests.
6. Maintain CI green before merge.
