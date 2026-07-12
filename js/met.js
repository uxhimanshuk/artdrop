const API_ROOT = "https://collectionapi.metmuseum.org/public/collection/v1";
const SEARCH_DETAIL_LIMIT = 24;
const SURPRISE_ID_LIMIT = 60;
const SURPRISE_ATTEMPTS = 20;
const SURPRISE_TERMS = [
  "landscape",
  "portrait",
  "flowers",
  "sea",
  "winter",
  "garden",
  "dance",
  "night",
  "mountain",
  "river",
  "reading",
  "music"
];

const objectCache = new Map();

export function normalizeArtwork(item) {
  if (!item?.isPublicDomain || !item.primaryImageSmall) return null;
  return {
    id: item.objectID,
    title: item.title || "Untitled",
    artist: item.artistDisplayName || "Unknown artist",
    date: item.objectDate || "",
    image_small: item.primaryImageSmall,
    image_large: item.primaryImage || item.primaryImageSmall
  };
}

async function fetchObject(id, { signal } = {}) {
  if (!objectCache.has(id)) {
    const request = fetch(`${API_ROOT}/objects/${id}`, { signal })
      .then((response) => {
        if (!response.ok) throw new Error("Painting details are unavailable.");
        return response.json();
      })
      .catch((error) => {
        objectCache.delete(id);
        throw error;
      });
    objectCache.set(id, request);
  }
  return objectCache.get(id);
}

async function searchIds(query, { signal } = {}) {
  const url = new URL(`${API_ROOT}/search`);
  url.searchParams.set("q", query);
  url.searchParams.set("hasImages", "true");
  url.searchParams.set("medium", "Paintings");
  const response = await fetch(url, { signal });
  if (!response.ok) throw new Error("Art search is unavailable.");
  const payload = await response.json();
  return payload.objectIDs || [];
}

export async function searchArtworks(query, { signal } = {}) {
  const q = query.trim();
  if (q.length < 2) return [];
  const ids = (await searchIds(q, { signal })).slice(0, SEARCH_DETAIL_LIMIT);
  const details = await Promise.allSettled(ids.map((id) => fetchObject(id, { signal })));
  return details
    .filter((result) => result.status === "fulfilled")
    .map((result) => normalizeArtwork(result.value))
    .filter(Boolean)
    .slice(0, 12);
}

export async function surpriseArtwork({ signal } = {}) {
  const term = SURPRISE_TERMS[Math.floor(Math.random() * SURPRISE_TERMS.length)];
  const ids = (await searchIds(term, { signal })).slice(0, SURPRISE_ID_LIMIT);

  for (let attempt = 0; attempt < Math.min(SURPRISE_ATTEMPTS, ids.length); attempt += 1) {
    const index = Math.floor(Math.random() * ids.length);
    const [id] = ids.splice(index, 1);
    try {
      const artwork = normalizeArtwork(await fetchObject(id, { signal }));
      if (artwork) return artwork;
    } catch (error) {
      if (error.name === "AbortError") throw error;
    }
  }
  throw new Error("Surprise painting is unavailable.");
}

export function debounce(fn, delay = 400) {
  let timer = null;
  return (...args) => {
    clearTimeout(timer);
    timer = setTimeout(() => fn(...args), delay);
  };
}
