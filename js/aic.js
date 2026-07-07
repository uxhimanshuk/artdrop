const API_ROOT = "https://api.artic.edu/api/v1";
const IIIF_ROOT = "https://www.artic.edu/iiif/2";

export function imageUrl(imageId, width = 843) {
  if (!imageId) return "";
  return `${IIIF_ROOT}/${imageId}/full/${width},/0/default.jpg`;
}

export function normalizeArtwork(item) {
  if (!item || !item.image_id) return null;
  return {
    id: item.id,
    title: item.title || "Untitled",
    artist: item.artist_display || "Unknown artist",
    date: item.date_display || "",
    image_id: item.image_id
  };
}

// The AIC search API rejects two flat query[term][...] params (HTTP 400);
// combined filters must use the bool-must form.
function paintingSearchUrl() {
  const url = new URL(`${API_ROOT}/artworks/search`);
  url.searchParams.append("query[bool][must][][term][is_public_domain]", "true");
  url.searchParams.append("query[bool][must][][term][artwork_type_id]", "1");
  url.searchParams.set("fields", "id,title,artist_display,date_display,image_id");
  url.searchParams.set("limit", "20");
  return url;
}

export async function searchArtworks(query, { signal } = {}) {
  const q = query.trim();
  if (q.length < 2) return [];
  const url = paintingSearchUrl();
  url.searchParams.set("q", q);

  const response = await fetch(url, { signal });
  if (!response.ok) throw new Error("Art search is unavailable.");
  const payload = await response.json();
  return (payload.data || []).map(normalizeArtwork).filter(Boolean);
}

export async function surpriseArtwork({ signal, _attempt = 0 } = {}) {
  // ~1,900 public-domain paintings at 20/page; stay safely inside the range.
  const page = Math.floor(Math.random() * 90) + 1;
  const url = paintingSearchUrl();
  url.searchParams.set("page", String(page));

  const response = await fetch(url, { signal });
  if (!response.ok) throw new Error("Surprise painting is unavailable.");
  const payload = await response.json();
  const works = (payload.data || []).map(normalizeArtwork).filter(Boolean);
  if (!works.length) {
    if (_attempt >= 3) throw new Error("Surprise painting is unavailable.");
    return surpriseArtwork({ signal, _attempt: _attempt + 1 });
  }
  return works[Math.floor(Math.random() * works.length)];
}

export function debounce(fn, delay = 400) {
  let timer = null;
  return (...args) => {
    clearTimeout(timer);
    timer = setTimeout(() => fn(...args), delay);
  };
}
