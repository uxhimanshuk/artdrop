# Build Notes

## v2: Met + map targeting

- Replaced the Art Institute adapter and IIIF URL construction with `js/met.js`, using keyless Met search/object endpoints, normalized public-domain image URLs, bounded surprise lookup, and an in-memory object-detail cache.
- Added Leaflet 1.9.4 with OpenStreetMap tiles for optional onboarding/profile locations and country-or-pin send targeting. A pin send stores its coordinates and selects the nearest eligible located profile using an immutable haversine helper.
- Added `supabase/migrations/20260712000000_met_and_geo.sql` as an additive migration; the original schema and initial migration remain unchanged. Queued or expired unmatched pin sends join the global claim pool.
- Updated the PWA shell cache to v2 and replaced `js/aic.js` with `js/met.js` in its precache list. The obsolete root `_redirects` proxy file was already absent.
- Changed files: `index.html`, `style.css`, `js/app.js`, `js/met.js` (new), `js/aic.js` (deleted), `sw.js`, `supabase/migrations/20260712000000_met_and_geo.sql` (new), `README.md`, `_STATUS.md`, and `BUILD-NOTES.md`.

- Kept the app as a no-build PWA: static `index.html`, `style.css`, ES modules, manifest, service worker, and generated PNG icons.
- Used hash routing with a persistent bottom nav so the mobile shell is simple to wrap in Android later.
- Made art search work even before Supabase credentials are configured; mutating actions show a setup message until `js/config.js` is filled.
- Put all send, daily claim, read, friend request, friend response, direct-send, and journal loading behavior behind Supabase RPCs. Direct client table writes are limited to profile onboarding, blocks, and reports under RLS.
- `get_journal()` returns sent items, received items, friend request state, and friends in one call so Journal and Friends screens do not fan out queries.
- The daily-painting SQL uses UTC dates for limits and slots, and uses `FOR UPDATE SKIP LOCKED` when claiming queued or recycled paintings.
- Styling is intentionally quiet and monochrome so artwork carries the color: off-white background, near-black text, serif painting/note typography, and compact system-sans controls.
