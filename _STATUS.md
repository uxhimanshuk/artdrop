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
- [ ] Supabase project: apply schema, fill `js/config.js`, seed test profiles
- [ ] Netlify site + deploy (fill SITE_ID in deploy.sh after site creation)
- [ ] Two-account end-to-end test (send → claim → read → friend → direct send; rate limit; pool recycle)
- [ ] Verify AIC IIIF images render in a real browser (curl gets Cloudflare-403; expected bot filter, unverified)
- [ ] TWA APK

## Awaiting
- Himanshu: create/log into a Supabase project (supabase.com) — needed before schema can be applied

## Next
Supabase setup: apply schema.sql in SQL editor, enable email OTP, fill js/config.js.
