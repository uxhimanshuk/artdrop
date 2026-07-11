# Artdrop — Status

Working name; rename anytime before deploy.

## Context
Social app: send a stranger a famous painting + your thoughts/feelings about it. Pick a target country; a random person there receives it as their **one painting per day**. Unread for 3 days → recycled into the country pool. If it resonates, they like + friend-request with a reply note; friends can then send paintings to each other directly (no chat in MVP).

- Art source: Art Institute of Chicago API (free, keyless, public-domain paintings, IIIF images)
- Stack: vanilla JS PWA (no build step) + Supabase free tier (email OTP auth, Postgres + RLS, RPC functions hold all delivery logic)
- Deploy: Netlify (guarded `deploy.sh`), then Bubblewrap TWA → Android APK (german-worksheets pattern)
- Build executed mostly by Codex CLI, reviewed by Claude
- Full plan: `~/.claude/plans/hey-help-me-build-stateless-yao.md`

## To-do
- [x] Codex build: `supabase/schema.sql` + PWA (index.html, app.js, style.css, js/, manifest, sw)
- [x] Review Codex output — fixed AIC double-`query[term]` 400 (bool-must form), tightened RPC grants (revoke from public), README SW-cache note
- [x] Supabase: project `zsmugtneymgohyekehdr` linked (CLI), schema pushed as migration `20260711000000_init`, `js/config.js` filled (sb_publishable key — legacy JWT keys disabled on new projects), auth site_url → artdrop.netlify.app
- [x] Netlify: **live at https://artdrop.netlify.app** (site id in deploy.sh; deployed via draft→promote fallback)
- [x] Logic e2e: 12/12 PASS via throwaway rollback migration impersonating users in SQL (delivery, daily slot, 3/day limit, repeat-claim, friend accept, direct send, pool oldest-first, 3-day recycle, block rules). DB left clean (0 profiles).
- [ ] Himanshu: open artdrop.netlify.app, sign in (magic link email), create profile, send a painting — confirms UI + AIC images in a real browser (curl gets Cloudflare-403 on IIIF; browsers expected fine, unverified)
- [ ] TWA APK after UI confirmed

## Notes
- Free tier: no custom email templates with default SMTP → sign-in email is a **magic link** (no code); ~2 auth emails/hour rate limit. Custom SMTP (e.g. Resend) is the upgrade path.
- Service-role secret never materialized locally (blocked by policy); admin-API testing not used — SQL impersonation test instead.

## Next
Himanshu smoke-tests the live app in a browser; then Bubblewrap TWA APK.
