import { debounce, imageUrl, searchArtworks, surpriseArtwork } from "./aic.js";
import { COUNTRIES, COUNTRY_OPTIONS, countryName } from "./countries.js";
import { isConfigured, supabase } from "./supabase.js";

const view = document.querySelector("#view");
const nav = document.querySelector(".bottom-nav");

const state = {
  route: "today",
  session: null,
  profile: null,
  daily: undefined,
  journal: null,
  searchResults: [],
  selectedArtwork: null,
  composeFriend: null,
  journalTab: "received",
  loading: false,
  message: ""
};

const todayUtc = () => new Date().toISOString().slice(0, 10);
const h = (value = "") =>
  String(value)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#039;");

const countryOptions = (selected = "US") =>
  COUNTRY_OPTIONS.map(
    ([code, name]) => `<option value="${code}" ${code === selected ? "selected" : ""}>${h(name)}</option>`
  ).join("");

function setMessage(message) {
  state.message = message || "";
  render();
}

function screen(title, body, extra = "") {
  return `
    ${configNotice()}
    ${state.message ? `<div class="notice">${h(state.message)}</div>` : ""}
    <div class="screen-head">
      <h1 class="screen-title">${h(title)}</h1>
      ${extra}
    </div>
    ${body}
  `;
}

function configNotice() {
  if (isConfigured) return "";
  return `
    <div class="notice">
      Supabase is not configured yet. Art search and previews work now; auth and sending unlock after filling <code>js/config.js</code>.
    </div>
  `;
}

function requireProfile() {
  if (!isConfigured) return false;
  if (!state.session) return false;
  return Boolean(state.profile);
}

async function init() {
  if ("serviceWorker" in navigator) {
    navigator.serviceWorker.register("./sw.js").catch(() => {});
  }

  state.route = routeFromHash();
  window.addEventListener("hashchange", () => {
    state.route = routeFromHash();
    state.message = "";
    render();
    hydrateRoute();
  });

  if (isConfigured) {
    const { data } = await supabase.auth.getSession();
    state.session = data.session;
    if (state.session) await loadProfile();
    supabase.auth.onAuthStateChange(async (_event, session) => {
      state.session = session;
      state.profile = null;
      state.daily = undefined;
      state.journal = null;
      if (session) await loadProfile();
      render();
      hydrateRoute();
    });
  }

  render();
  hydrateRoute();
}

function routeFromHash() {
  const route = (location.hash || "#today").slice(1).split("?")[0];
  return ["today", "send", "journal", "friends", "you"].includes(route) ? route : "today";
}

async function loadProfile() {
  if (!isConfigured || !state.session) return;
  const { data, error } = await supabase.from("profiles").select("*").eq("id", state.session.user.id).maybeSingle();
  if (error) {
    state.message = error.message;
    return;
  }
  state.profile = data;
}

async function loadJournal(force = false) {
  if (!requireProfile()) return null;
  if (state.journal && !force) return state.journal;
  const { data, error } = await supabase.rpc("get_journal");
  if (error) throw error;
  state.journal = data || { sent: [], received: [], friends: [], friend_requests: { incoming: [], outgoing: [] } };
  return state.journal;
}

async function hydrateRoute() {
  if (!requireProfile()) return;
  try {
    if (state.route === "today") {
      await loadToday();
      await loadJournal(true);
    }
    if (state.route === "journal" || state.route === "friends" || state.route === "send") {
      await loadJournal(state.route !== "send");
    }
  } catch (error) {
    setMessage(error.message);
  }
}

async function loadToday() {
  if (state.daily !== undefined) return;
  const { data, error } = await supabase.rpc("claim_daily");
  if (error) throw error;
  state.daily = data;
}

function render() {
  nav.querySelectorAll("a").forEach((link) => link.classList.toggle("active", link.dataset.route === state.route));
  if (isConfigured && state.session && !state.profile) {
    view.innerHTML = renderOnboarding();
    bindOnboarding();
    return;
  }

  if (state.route === "today") renderToday();
  if (state.route === "send") renderSend();
  if (state.route === "journal") renderJournal();
  if (state.route === "friends") renderFriends();
  if (state.route === "you") renderYou();
}

function renderAuth() {
  return `
    <div class="auth-card stack">
      <p class="muted">Sign in with your email to send and receive paintings.</p>
      <label>Email
        <input id="auth-email" type="email" autocomplete="email" placeholder="you@example.com">
      </label>
      <button id="send-otp">Email me a sign-in link</button>
      <p class="muted">Click the link in the email to sign in. If the email shows a code instead, enter it here:</p>
      <label>Code
        <input id="auth-code" inputmode="numeric" autocomplete="one-time-code" placeholder="123456">
      </label>
      <button id="verify-otp" class="secondary">Verify code</button>
    </div>
  `;
}

function bindAuth() {
  document.querySelector("#send-otp")?.addEventListener("click", async () => {
    const email = document.querySelector("#auth-email").value.trim();
    if (!email) return setMessage("Enter your email address.");
    const { error } = await supabase.auth.signInWithOtp({ email, options: { shouldCreateUser: true } });
    setMessage(error ? error.message : "Check your email for the sign-in link.");
  });
  document.querySelector("#verify-otp")?.addEventListener("click", async () => {
    const email = document.querySelector("#auth-email").value.trim();
    const token = document.querySelector("#auth-code").value.trim();
    if (!email || !token) return setMessage("Enter your email and code.");
    const { error } = await supabase.auth.verifyOtp({ email, token, type: "email" });
    if (error) setMessage(error.message);
  });
}

function renderOnboarding() {
  return screen(
    "You",
    `
      <form id="onboarding" class="auth-card stack">
        <p class="muted">Choose how strangers will see you.</p>
        <label>Username
          <input name="username" minlength="3" maxlength="20" pattern="[A-Za-z0-9_]{3,20}" placeholder="gallery_guest" required>
        </label>
        <label>Country
          <select name="country" required>${countryOptions("US")}</select>
        </label>
        <button>Create profile</button>
      </form>
    `
  );
}

function bindOnboarding() {
  document.querySelector("#onboarding")?.addEventListener("submit", async (event) => {
    event.preventDefault();
    const form = new FormData(event.currentTarget);
    const username = String(form.get("username")).toLowerCase().trim();
    const country = String(form.get("country"));
    const { error } = await supabase.from("profiles").insert({
      id: state.session.user.id,
      username,
      country
    });
    if (error) return setMessage(error.message);
    await loadProfile();
    location.hash = "#today";
    render();
    hydrateRoute();
  });
}

function renderToday() {
  if (isConfigured && !state.session) {
    view.innerHTML = screen("Today", renderAuth());
    bindAuth();
    return;
  }

  const direct = (state.journal?.received || []).filter((item) => item.direct && item.status === "delivered" && !item.read_at);
  const dailyHtml =
    state.daily === undefined
      ? `<div class="empty">Looking for today’s painting.</div>`
      : state.daily
        ? paintingDetail(state.daily, { daily: true })
        : `<div class="empty">No painting today yet — the pool is quiet.</div>`;

  view.innerHTML = screen(
    "Today",
    `
      <div class="stack">
        ${dailyHtml}
        ${
          direct.length
            ? `<h2 class="art-title">From your friends</h2><div class="stack">${direct.map(journalCard).join("")}</div>`
            : ""
        }
      </div>
    `
  );
  bindPaintingActions();
  bindJournalCards();
}

function paintingDetail(send, { daily = false } = {}) {
  const art = send.artwork || {};
  const sender = send.sender || {};
  const canFriend = daily && !send.direct;
  return `
    <article class="art-hero" data-send-id="${h(send.id)}">
      <img src="${h(imageUrl(art.image_id, 843))}" alt="${h(art.title)}">
      <div class="caption">
        <h2 class="art-title">${h(art.title)}</h2>
        <p class="meta">${h(art.artist)}${art.date ? `, ${h(art.date)}` : ""}</p>
      </div>
      <p class="meta">From ${h(sender.username || "Someone")} ${sender.country ? `in ${h(countryName(sender.country))}` : ""}</p>
      <div class="letter">${h(send.note)}</div>
      <div class="actions">
        ${send.read_at ? "" : `<button data-action="mark-read" data-id="${h(send.id)}">Mark as read</button>`}
        ${canFriend ? `<button class="secondary" data-action="friend-reply" data-id="${h(send.id)}">Like & request friendship</button>` : ""}
        ${daily ? `<button class="secondary" data-action="report" data-id="${h(send.id)}">Report</button>` : ""}
        ${daily ? `<button class="danger" data-action="block" data-sender="${h(send.sender_id)}">Block sender</button>` : ""}
      </div>
      <form class="reply-form hide stack" data-reply-for="${h(send.id)}">
        <label>Reply note
          <textarea maxlength="500" placeholder="Tell them what resonated." required></textarea>
        </label>
        <button>Send request</button>
      </form>
    </article>
  `;
}

function bindPaintingActions() {
  document.querySelectorAll("[data-action='mark-read']").forEach((button) => {
    button.addEventListener("click", () => markRead(button.dataset.id));
  });
  document.querySelectorAll("[data-action='friend-reply']").forEach((button) => {
    button.addEventListener("click", async () => {
      await markRead(button.dataset.id);
      document.querySelector(`[data-reply-for="${button.dataset.id}"]`)?.classList.remove("hide");
    });
  });
  document.querySelectorAll(".reply-form").forEach((form) => {
    form.addEventListener("submit", async (event) => {
      event.preventDefault();
      const sendId = form.dataset.replyFor;
      const note = form.querySelector("textarea").value.trim();
      const { error } = await supabase.rpc("request_friend", { p_send_id: sendId, p_reply_note: note });
      if (error) return setMessage(error.message);
      state.journal = null;
      setMessage("Friend request sent.");
    });
  });
  document.querySelectorAll("[data-action='report']").forEach((button) => {
    button.addEventListener("click", async () => {
      const reason = prompt("Reason for report");
      if (!reason) return;
      const { error } = await supabase.from("reports").insert({
        reporter_id: state.session.user.id,
        send_id: button.dataset.id,
        reason: reason.trim()
      });
      setMessage(error ? error.message : "Report sent.");
    });
  });
  document.querySelectorAll("[data-action='block']").forEach((button) => {
    button.addEventListener("click", async () => {
      const { error } = await supabase.from("blocks").insert({
        blocker_id: state.session.user.id,
        blocked_id: button.dataset.sender
      });
      setMessage(error ? error.message : "Sender blocked.");
    });
  });
}

async function markRead(id) {
  if (!requireProfile()) return;
  const { error } = await supabase.rpc("mark_read", { p_send_id: id });
  if (error) return setMessage(error.message);
  if (state.daily?.id === id) state.daily.read_at = new Date().toISOString();
  state.journal = null;
  await loadJournal(true);
  render();
}

function renderSend() {
  const friend = state.composeFriend;
  const remaining = remainingSends();
  view.innerHTML = screen(
    "Send",
    `
      <div class="stack">
        ${
          friend
            ? `<div class="notice split"><span>Sending directly to ${h(friend.username)}</span><button class="ghost" id="clear-friend">Clear</button></div>`
            : ""
        }
        <div class="searchbar">
          <input id="art-search" placeholder="Search paintings" autocomplete="off">
          <button id="surprise" class="secondary">Surprise me</button>
        </div>
        <div id="search-status" class="meta">${state.searchResults.length ? "" : "Search the Art Institute of Chicago collection."}</div>
        <div id="results" class="grid">${state.searchResults.map(artCard).join("")}</div>
        ${state.selectedArtwork ? composePanel(friend, remaining) : ""}
      </div>
    `,
    `<span class="status-pill">${remaining} daily sends left</span>`
  );
  bindSend();
}

function remainingSends() {
  const count = (state.journal?.sent || []).filter(
    (item) => !item.direct && item.created_at && new Date(item.created_at).toISOString().slice(0, 10) === todayUtc()
  ).length;
  return Math.max(0, 3 - count);
}

function artCard(art, index) {
  return `
    <button class="art-card" data-art-index="${index}">
      <img src="${h(imageUrl(art.image_id, 400))}" alt="${h(art.title)}" loading="lazy">
      <span class="body">
        <p class="card-title">${h(art.title)}</p>
        <p class="meta">${h(art.artist)}</p>
      </span>
    </button>
  `;
}

function composePanel(friend, remaining) {
  const art = state.selectedArtwork;
  return `
    <form id="compose" class="compose-panel stack">
      <div class="compose-preview">
        <img src="${h(imageUrl(art.image_id, 843))}" alt="${h(art.title)}">
        <div>
          <h2 class="art-title">${h(art.title)}</h2>
          <p class="meta">${h(art.artist)}${art.date ? `, ${h(art.date)}` : ""}</p>
        </div>
      </div>
      <label>Your note
        <textarea id="compose-note" maxlength="1000" required placeholder="What did this painting stir in you?"></textarea>
      </label>
      <div class="counter"><span id="note-count">0</span>/1000</div>
      ${
        friend
          ? ""
          : `<label>Target country
              <select id="target-country">${countryOptions(state.profile?.country || "US")}</select>
            </label>`
      }
      <button ${!isConfigured || !state.session || (!friend && remaining <= 0) ? "disabled" : ""}>Send painting</button>
    </form>
  `;
}

function bindSend() {
  document.querySelector("#clear-friend")?.addEventListener("click", () => {
    state.composeFriend = null;
    render();
  });
  const searchInput = document.querySelector("#art-search");
  const status = document.querySelector("#search-status");
  const runSearch = debounce(async () => {
    try {
      status.textContent = "Searching.";
      state.searchResults = await searchArtworks(searchInput.value);
      status.textContent = state.searchResults.length ? "" : "No paintings found.";
      render();
    } catch (error) {
      status.textContent = error.message;
    }
  }, 400);
  searchInput?.addEventListener("input", runSearch);
  document.querySelector("#surprise")?.addEventListener("click", async () => {
    try {
      state.selectedArtwork = await surpriseArtwork();
      render();
    } catch (error) {
      setMessage(error.message);
    }
  });
  document.querySelectorAll("[data-art-index]").forEach((button) => {
    button.addEventListener("click", () => {
      state.selectedArtwork = state.searchResults[Number(button.dataset.artIndex)];
      render();
    });
  });
  document.querySelector("#compose-note")?.addEventListener("input", (event) => {
    document.querySelector("#note-count").textContent = String(event.target.value.length);
  });
  document.querySelector("#compose")?.addEventListener("submit", async (event) => {
    event.preventDefault();
    if (!isConfigured) return setMessage("Fill js/config.js before sending paintings.");
    if (!state.session) return setMessage("Sign in before sending paintings.");
    const note = document.querySelector("#compose-note").value.trim();
    const friend = state.composeFriend;
    const payload = friend
      ? { p_artwork: state.selectedArtwork, p_note: note, p_friend_id: friend.id }
      : { p_artwork: state.selectedArtwork, p_note: note, p_target_country: document.querySelector("#target-country").value };
    const rpc = friend ? "send_to_friend" : "send_painting";
    const { error } = await supabase.rpc(rpc, payload);
    if (error) return setMessage(error.message);
    state.selectedArtwork = null;
    state.composeFriend = null;
    state.searchResults = [];
    state.journal = null;
    await loadJournal(true);
    setMessage(friend ? "Painting sent to your friend." : "Painting sent.");
  });
}

function renderJournal() {
  if (isConfigured && !state.session) {
    view.innerHTML = screen("Journal", renderAuth());
    bindAuth();
    return;
  }
  const journal = state.journal || { sent: [], received: [] };
  const items = state.journalTab === "received" ? journal.received || [] : journal.sent || [];
  view.innerHTML = screen(
    "Journal",
    `
      <div class="stack">
        <div class="tabs">
          <button class="${state.journalTab === "received" ? "active" : ""}" data-tab="received">Received</button>
          <button class="${state.journalTab === "sent" ? "active" : ""}" data-tab="sent">Sent</button>
        </div>
        ${items.length ? `<div class="stack">${items.map(journalCard).join("")}</div>` : `<div class="empty">No entries yet.</div>`}
      </div>
    `
  );
  document.querySelectorAll("[data-tab]").forEach((button) => {
    button.addEventListener("click", () => {
      state.journalTab = button.dataset.tab;
      render();
    });
  });
  bindJournalCards();
}

function journalCard(item) {
  const art = item.artwork || {};
  const status = item.friend_request?.status === "accepted" ? "Friended" : labelStatus(item.status);
  return `
    <article class="journal-card" data-open-send="${h(item.id)}">
      <div class="row">
        <img class="thumb" src="${h(imageUrl(art.image_id, 400))}" alt="${h(art.title)}">
        <div class="body">
          <p class="card-title">${h(art.title)}</p>
          <p class="meta">${h(firstLine(item.note))}</p>
          <p class="meta">${h(status)}${item.direct ? " · Direct" : ""}</p>
        </div>
      </div>
    </article>
  `;
}

function labelStatus(status) {
  if (status === "queued") return "Queued";
  if (status === "delivered") return "Delivered";
  if (status === "read") return "Read";
  return status || "";
}

function firstLine(text = "") {
  const line = text.trim().split(/\n/)[0] || "";
  return line.length > 92 ? `${line.slice(0, 89)}...` : line;
}

function bindJournalCards() {
  document.querySelectorAll("[data-open-send]").forEach((card) => {
    card.addEventListener("click", async () => {
      const id = card.dataset.openSend;
      const item = [...(state.journal?.received || []), ...(state.journal?.sent || [])].find((entry) => entry.id === id);
      if (!item || !item.recipient_id && state.route !== "today") return;
      if (item.sender && item.recipient_id !== state.session?.user.id) return;
      view.innerHTML = screen("Today", paintingDetail(item, { daily: !item.direct }));
      bindPaintingActions();
      if (item.recipient_id === state.session?.user.id && !item.read_at) await markRead(item.id);
    });
  });
}

function renderFriends() {
  if (isConfigured && !state.session) {
    view.innerHTML = screen("Friends", renderAuth());
    bindAuth();
    return;
  }
  const requests = state.journal?.friend_requests || { incoming: [], outgoing: [] };
  const friends = state.journal?.friends || [];
  view.innerHTML = screen(
    "Friends",
    `
      <div class="stack">
        <h2 class="art-title">Incoming</h2>
        ${requests.incoming?.length ? requests.incoming.map(requestCard).join("") : `<div class="empty">No incoming requests.</div>`}
        <h2 class="art-title">Outgoing</h2>
        ${requests.outgoing?.length ? requests.outgoing.map(outgoingCard).join("") : `<div class="empty">No outgoing requests.</div>`}
        <h2 class="art-title">Friends</h2>
        ${friends.length ? friends.map(friendCard).join("") : `<div class="empty">No friends yet.</div>`}
      </div>
    `
  );
  bindFriends();
}

function requestCard(request) {
  return `
    <article class="request-card stack">
      <div>
        <p class="card-title">${h(request.from_profile?.username || "Someone")}</p>
        <p class="meta">${h(countryName(request.from_profile?.country))}</p>
      </div>
      <p class="letter">${h(request.reply_note)}</p>
      <div class="actions">
        <button data-respond="${h(request.id)}" data-accept="true">Accept</button>
        <button class="secondary" data-respond="${h(request.id)}" data-accept="false">Decline</button>
      </div>
    </article>
  `;
}

function outgoingCard(request) {
  return `
    <article class="request-card">
      <p class="card-title">${h(request.to_profile?.username || "Someone")}</p>
      <p class="meta">${h(labelStatus(request.status))}</p>
    </article>
  `;
}

function friendCard(friend) {
  return `
    <article class="friend-card split">
      <div>
        <p class="card-title">${h(friend.username)}</p>
        <p class="meta">${h(countryName(friend.country))}</p>
      </div>
      <button data-send-friend="${h(friend.id)}">Send a painting</button>
    </article>
  `;
}

function bindFriends() {
  document.querySelectorAll("[data-respond]").forEach((button) => {
    button.addEventListener("click", async () => {
      const { error } = await supabase.rpc("respond_friend", {
        p_request_id: button.dataset.respond,
        p_accept: button.dataset.accept === "true"
      });
      if (error) return setMessage(error.message);
      await loadJournal(true);
      render();
    });
  });
  document.querySelectorAll("[data-send-friend]").forEach((button) => {
    button.addEventListener("click", () => {
      state.composeFriend = (state.journal?.friends || []).find((friend) => friend.id === button.dataset.sendFriend);
      location.hash = "#send";
    });
  });
}

function renderYou() {
  if (!isConfigured) {
    view.innerHTML = screen("You", renderAuth().replaceAll("<button", "<button disabled"));
    return;
  }
  if (!state.session) {
    view.innerHTML = screen("You", renderAuth());
    bindAuth();
    return;
  }
  view.innerHTML = screen(
    "You",
    `
      <div class="auth-card stack">
        <div>
          <p class="card-title">${h(state.profile?.username || "Profile")}</p>
          <p class="meta">${h(countryName(state.profile?.country))}</p>
        </div>
        <p class="meta">${h(state.session.user.email)}</p>
        <button id="sign-out" class="secondary">Sign out</button>
      </div>
    `
  );
  document.querySelector("#sign-out")?.addEventListener("click", async () => {
    await supabase.auth.signOut();
    state.profile = null;
    state.journal = null;
    state.daily = undefined;
    location.hash = "#today";
  });
}

init();
