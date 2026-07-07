# Build Notes

- Kept the app as a no-build PWA: static `index.html`, `style.css`, ES modules, manifest, service worker, and generated PNG icons.
- Used hash routing with a persistent bottom nav so the mobile shell is simple to wrap in Android later.
- Made the Art Institute of Chicago search work even before Supabase credentials are configured; mutating actions show a setup message until `js/config.js` is filled.
- Put all send, daily claim, read, friend request, friend response, direct-send, and journal loading behavior behind Supabase RPCs. Direct client table writes are limited to profile onboarding, blocks, and reports under RLS.
- `get_journal()` returns sent items, received items, friend request state, and friends in one call so Journal and Friends screens do not fan out queries.
- The daily-painting SQL uses UTC dates for limits and slots, and uses `FOR UPDATE SKIP LOCKED` when claiming queued or recycled paintings.
- Styling is intentionally quiet and monochrome so artwork carries the color: off-white background, near-black text, serif painting/note typography, and compact system-sans controls.
