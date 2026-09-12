# Artdrop

Send a stranger a painting and what you felt about it.

You pick a public-domain work from The Met's collection, write a note, and choose
where it goes — a country, or a pin dropped on a map. Somebody there receives it as
**their one painting for the day**. If it lands, they can like it and send a reply
note back; if it doesn't, it goes unread for three days and returns to the pool for
someone else.

Live at **[artdrop.netlify.app](https://artdrop.netlify.app)**.

---

## Why it's built this way

The constraints are the product. Most of the design work went into deciding what
*not* to allow:

- **One painting a day, received.** Not a feed. The scarcity is the whole
  experience — an inbox of forty paintings is worth less than one.
- **Three sends a day, maximum.** Enough to be generous, not enough to broadcast.
- **No chat.** A reply is a single note attached to a like. Friends can send each
  other paintings directly, and that's the entire relationship model. Adding
  messaging would turn it into a different app with a much worse safety story.
- **Unread for three days → recycled.** Nothing is wasted on someone who isn't
  looking, and nobody accumulates an obligation.
- **Location is coarse by default.** Map-pin targeting finds the nearest person
  without either party learning where the other is; profile coordinates are
  readable only by their own row.

---

## How it works

Vanilla HTML/CSS/JS as a PWA — no framework, no build step — over Supabase
(Postgres, row-level security, email OTP auth). Art comes from The Met Collection
API, which is free, keyless, and serves hotlinkable public-domain images.

**All delivery logic lives in the database, not the client.** Sends, friend
requests and friendships go through Postgres RPC functions with `execute` revoked
from `public`; blocks and reports are direct inserts constrained by RLS. The client
cannot pick its own recipient, exceed its daily quota, or read another person's
row — not because the UI doesn't offer it, but because the database refuses.

The delivery rules were tested by impersonating users inside a throwaway rollback
migration: daily slot allocation, the three-per-day limit, repeat-claim attempts,
friend accept, direct send, pool ordering, three-day recycling, and block rules.
Twelve cases for the core logic, eight more for geo targeting.

### One thing worth knowing if you fork it

The Art Institute of Chicago API was the original source and had to be dropped: its
images sit behind a Cloudflare challenge that 403s any third-party fetch — verified
from a browser, from curl, and through a server-side proxy. The Met has no such
restriction.

---

## Running it

1. Create a Supabase project.
2. In the SQL editor, run `supabase/schema.sql` once, then apply anything in
   `supabase/migrations/` newer than that baseline. Existing installs apply only
   the new migrations.
3. Enable email OTP sign-in in Auth settings.
4. Fill in `js/config.js`:

```js
export const SUPABASE_URL = "https://YOUR_PROJECT.supabase.co";
export const SUPABASE_ANON_KEY = "YOUR_PUBLISHABLE_KEY";
```

5. `python3 -m http.server` from the project root, then open `http://localhost:8000`.

With placeholder config the app still renders, and Met search and map picking work;
auth and sends are disabled.

**Note:** the service worker caches the app shell — including `js/config.js` —
cache-first. After changing config or shipping an update, bump `CACHE_NAME` in
`sw.js` or clients will keep the old files.

External runtime dependencies are Supabase JS and Leaflet 1.9.4, both from CDNs.

---

## On the key in this repo

`js/config.js` contains a Supabase **publishable** key. That is the intended
design: it identifies the project, carries no privileges of its own, and every
table it can reach is governed by row-level security. The policies are in
`supabase/` and are meant to be read. There is no service-role key in this
repository, and there shouldn't be one in any deployment's client bundle.

---

Built by [Himanshu Kalra](https://uxrhimanshu.com). MIT licensed. Artwork is
public domain, served by the Metropolitan Museum of Art Collection API.
