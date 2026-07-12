# Artdrop

Artdrop is a small vanilla HTML/CSS/JS PWA where people connect through public-domain paintings from The Met collection.

## Setup

1. Create a new Supabase project.
2. Open the Supabase SQL editor, run `supabase/schema.sql` once, then apply the files in `supabase/migrations/` newer than that baseline. Existing installations should apply only the new migrations.
3. In Supabase Auth settings, enable email OTP sign-in.
4. Fill in `js/config.js`:

```js
export const SUPABASE_URL = "https://YOUR_PROJECT.supabase.co";
export const SUPABASE_ANON_KEY = "YOUR_ANON_KEY";
```

5. Serve the app locally from the project root:

```sh
python3 -m http.server
```

6. Open `http://localhost:8000`.

## Notes

- There is no build step and no framework.
- `index.html` loads `js/app.js` as an ES module.
- External JavaScript dependencies are Supabase JS and Leaflet 1.9.4, both loaded from CDNs.
- With placeholder Supabase config, the app still renders and Met search plus map picking work, but auth and sends are disabled.
- Client mutations for sends, friend requests, and friendships go through Supabase RPC functions. Blocks and reports are direct table inserts under RLS.
- The service worker caches the app shell (including `js/config.js`) cache-first. After changing config or shipping app updates, bump `CACHE_NAME` in `sw.js` so clients pick up the new files.
