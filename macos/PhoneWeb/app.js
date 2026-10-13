// Tellurion on your phone: the Mac's tabs, a live view of one, and a keyboard for it.
// Talks to PhoneServer.swift over one WebSocket; see that file for the protocol.
"use strict";

const $ = (id) => document.getElementById(id);
const store = {
  get(key) { try { return localStorage.getItem(key); } catch { return null; } },
  set(key, value) { try { localStorage.setItem(key, value); } catch {} },
  remove(key) { try { localStorage.removeItem(key); } catch {} },
};

const state = {
  token: store.get("gx.token"),
  mac: store.get("gx.mac") || "Mac",
  device: store.get("gx.deviceName") || "",
  tabs: [],
  watching: null,
  ctrl: false,
  fit: store.get("gx.zoom") !== "1:1",
  ws: null,
  connected: false,
  retry: 0,
  retryTimer: null,
  pingTimer: null,
};

// MARK: Pages

// On the Home Screen there's no browser back gesture, so the page gives you its own.
const standalone = navigator.standalone === true || matchMedia("(display-mode: standalone)").matches;
const reduceMotion = matchMedia("(prefers-reduced-motion: reduce)").matches;
const easing = "cubic-bezier(.2, .8, .2, 1)";

function show(page) {
  for (const id of ["pair", "home", "term"]) $(id).hidden = id !== page;
}

/// Slides the tab view in over the list ("in") or away to the right ("out"), from
/// wherever a swipe left it (0 = fully shown, 1 = fully off to the right).
function slide(direction, from = direction === "in" ? 1 : 0) {
  const view = $("term");
  const list = $("home");
  const to = direction === "in" ? 0 : 1;
  const finish = () => {
    view.style.transform = list.style.transform = list.style.opacity = "";
    if (direction === "in") list.hidden = true;
    else view.hidden = true;
  };
  if (reduceMotion) { finish(); return; }
  view.hidden = list.hidden = false;
  const duration = 320 * Math.max(0.35, Math.abs(to - from));
  const listAt = (p) => ({ transform: `translateX(${(p - 1) * 28}%)`, opacity: 0.55 + 0.45 * p });
  view.animate([{ transform: `translateX(${from * 100}%)` }, { transform: `translateX(${to * 100}%)` }],
    { duration, easing, fill: "forwards" }).finished.then(() => {
    view.getAnimations().forEach((a) => a.cancel());
    list.getAnimations().forEach((a) => a.cancel());
    finish();
  });
  list.animate([listAt(from), listAt(to)], { duration, easing, fill: "forwards" });
}

function route() {
  const hash = new URLSearchParams(location.hash.slice(1));
  const code = hash.get("pair");
  if (code) {
    history.replaceState(null, "", location.pathname);
    showPairing(code);
    return;
  }
  if (!state.token) { showPairing(""); return; }
  const tab = hash.get("tab");
  history.replaceState(null, "", location.pathname);
  showHome();
  connect();
  // Reloaded while in a tab: go back to it, with the list behind it.
  if (tab) openTab(tab, { animate: false });
}

// MARK: Pairing

function defaultName() {
  const ua = navigator.userAgent;
  if (/iPad/.test(ua)) return "iPad";
  if (/iPhone/.test(ua)) return "iPhone";
  if (/Android/.test(ua)) return "Android phone";
  return "Phone";
}

function showPairing(code, message) {
  disconnect();
  show("pair");
  $("pair-code").value = code || "";
  $("pair-name").value = state.device || defaultName();
  $("pair-error").textContent = message || "";
  if (!code) setTimeout(() => $("pair-code").focus(), 50);
}

$("pair-form").addEventListener("submit", async (event) => {
  event.preventDefault();
  const code = $("pair-code").value.trim();
  const name = $("pair-name").value.trim() || defaultName();
  if (!code) return;
  $("pair-submit").disabled = true;
  $("pair-error").textContent = "";
  try {
    const response = await fetch("/api/pair", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ code, name }),
    });
    const body = await response.json().catch(() => ({}));
    if (!response.ok || !body.token) {
      $("pair-error").textContent = body.error || (response.status === 403
        ? "This Mac only answers devices signed in to its owner's Tailscale account."
        : "Couldn't pair. Check the code and try again.");
      return;
    }
    state.token = body.token;
    state.mac = body.mac || "Mac";
    state.device = name;
    store.set("gx.token", body.token);
    store.set("gx.mac", state.mac);
    store.set("gx.deviceName", name);
    showHome();
    connect();
  } catch {
    $("pair-error").textContent = "Can't reach your Mac. Is Tailscale on, on both devices?";
  } finally {
    $("pair-submit").disabled = false;
  }
});

function unpaired(message) {
  state.token = null;
  store.remove("gx.token");
  showPairing("", message);
}

// MARK: Connection

function connect() {
  if (!state.token || state.ws) return;
  clearTimeout(state.retryTimer);
  const ws = new WebSocket(`${location.protocol === "https:" ? "wss" : "ws"}://${location.host}/api/ws`);
  state.ws = ws;
  setConnection(state.retry ? "Reconnecting…" : "Connecting…");

  ws.onopen = () => ws.send(JSON.stringify({ t: "hello", token: state.token }));
  ws.onmessage = (event) => {
    let message;
    try { message = JSON.parse(event.data); } catch { return; }
    receive(message);
  };
  ws.onclose = () => {
    if (state.ws !== ws) return;
    state.ws = null;
    state.connected = false;
    clearInterval(state.pingTimer);
    if (!state.token) return;
    // Back off to 10 s while the Mac is away; a visible page retries at once.
    const delay = Math.min(10000, 500 * 2 ** state.retry++);
    setConnection(navigator.onLine === false ? "Offline" : "Reconnecting…", true);
    state.retryTimer = setTimeout(connect, delay);
  };
}

function disconnect() {
  clearTimeout(state.retryTimer);
  clearInterval(state.pingTimer);
  const ws = state.ws;
  state.ws = null;
  state.connected = false;
  if (ws) ws.close();
}

function send(message) {
  if (state.ws && state.connected) state.ws.send(JSON.stringify(message));
}

function setConnection(text, off) {
  for (const id of ["conn", "conn2"]) {
    $(id).textContent = text || "";
    $(id).classList.toggle("off", !!off);
  }
}

function receive(message) {
  switch (message.t) {
    case "hello":
      state.connected = true;
      state.retry = 0;
      state.mac = message.mac || state.mac;
      store.set("gx.mac", state.mac);
      $("mac-name").textContent = state.mac;
      setConnection("");
      clearInterval(state.pingTimer);
      state.pingTimer = setInterval(() => send({ t: "ping" }), 20000);
      if (state.watching) send({ t: "watch", id: state.watching });
      break;
    case "tabs":
      state.tabs = message.tabs || [];
      renderTabs();
      if (state.watching) { renderTermHeader(); renderStrip(); }
      break;
    case "screen":
      screens.set(message.id, message);
      if (message.id === state.watching) drawScreen(message);
      break;
    case "error":
      if (message.code === "unpaired") unpaired("This phone was unpaired on the Mac. Pair it again to continue.");
      break;
  }
}

document.addEventListener("visibilitychange", () => {
  if (document.visibilityState !== "visible" || !state.token) return;
  if (!state.ws) { state.retry = 0; connect(); }
  else if (state.connected) send({ t: "ping" });
});
window.addEventListener("online", () => { if (!state.ws && state.token) { state.retry = 0; connect(); } });

// MARK: Tab list

const attention = new Set(["permission", "input"]);
const activityText = {
  working: "Working",
  permission: "Needs permission",
  input: "Waiting for you",
  done: "Done",
  failed: "Failed",
  ready: "Ready",
};

function showHome() {
  state.watching = null;
  $("mac-name").textContent = state.mac;
  show("home");
  renderTabs();
}

/// The tabs in the list's order: the ones that need you, then each project's.
function orderedTabs() {
  const needs = state.tabs.filter((t) => attention.has(t.activity));
  const groups = new Map();
  for (const tab of state.tabs) {
    if (attention.has(tab.activity)) continue;
    const key = tab.project || "Other";
    if (!groups.has(key)) groups.set(key, []);
    groups.get(key).push(tab);
  }
  return { needs, groups, all: [...needs, ...[...groups.values()].flat()] };
}

function tabName(tab) {
  return tab.task || tab.title || tab.project || "Terminal";
}

function tabMeta(tab) {
  const parts = [];
  if (tab.agentName) parts.push(tab.agentName + (tab.activity ? " · " + (activityText[tab.activity] || tab.activity) : ""));
  if (tab.detail) parts.push(tab.detail);
  else if (tab.pwd && tab.pwd !== tabName(tab)) parts.push(tab.pwd);
  return parts.join(" — ");
}

function el(tag, className, text) {
  const node = document.createElement(tag);
  if (className) node.className = className;
  if (text != null) node.textContent = text;
  return node;
}

function tabRow(tab) {
  const row = el("button", "row");
  row.type = "button";
  row.append(el("span", "dot " + (tab.activity || "")));
  const main = el("span", "main");
  const name = el("div", "name");
  if (attention.has(tab.activity) || tab.activity === "failed") {
    name.append(el("span", "badge " + tab.activity, activityText[tab.activity]));
  }
  name.append(document.createTextNode(tabName(tab)));
  if ("localhost" in tab) {
    let port = "";
    try { port = ":" + new URL(tab.localhost).port; } catch {}
    name.append(el("span", "pill", tab.localhost ? "live" + port : "server"));
  }
  main.append(name, el("div", "meta", tabMeta(tab)));
  row.append(main, el("span", "chev", "›"));
  row.addEventListener("click", () => openTab(tab.id));
  return row;
}

function renderTabs() {
  const list = $("tab-list");
  if ($("home").hidden) return;
  list.replaceChildren();
  if (!state.tabs.length) {
    list.append(el("div", "empty", state.connected ? "No terminal tabs are open on your Mac." : "Connecting to your Mac…"));
    return;
  }
  const { needs, groups } = orderedTabs();
  if (needs.length) {
    list.append(el("div", "group attention", "Needs you"));
    for (const tab of needs) list.append(tabRow(tab));
  }
  for (const [project, tabs] of groups) {
    list.append(el("div", "group", project));
    for (const tab of tabs) list.append(tabRow(tab));
  }
}

$("menu-btn").addEventListener("click", () => {
  $("sheet-info").textContent = `Paired as “${state.device || defaultName()}” with ${state.mac}.`;
  $("sheet").hidden = false;
});
$("sheet-close").addEventListener("click", () => { $("sheet").hidden = true; });
$("sheet").addEventListener("click", (event) => { if (event.target === $("sheet")) $("sheet").hidden = true; });
$("forget-btn").addEventListener("click", () => {
  $("sheet").hidden = true;
  // Tell the Mac to drop this phone too, then forget the token here.
  send({ t: "unpair" });
  setTimeout(() => unpaired("This phone is unpaired. Pair it again from your Mac to use it."), 150);
});

// MARK: Terminal

let term = null;
let lastScreen = null;
/// The last screen seen of each tab, so going back to one shows it at once.
const screens = new Map();
/// Unsent text, per tab.
const drafts = new Map();
/// Set when the page itself asked to go back, so the list slides back in.
let animateNextPop = false;
let charRatio = 0.6;

function measureFont() {
  const canvas = document.createElement("canvas").getContext("2d");
  canvas.font = '100px "JetBrains Mono"';
  const width = canvas.measureText("W").width;
  if (width > 0) charRatio = width / 100;
}

function makeTerm() {
  if (term) return;
  term = new Terminal({
    cols: 80, rows: 24,
    fontFamily: '"JetBrains Mono", ui-monospace, Menlo, monospace',
    fontSize: 11,
    lineHeight: 1,
    scrollback: 0,
    disableStdin: true,
    cursorBlink: false,
    cursorStyle: "block",
    // The view never has focus; keep the cursor solid anyway.
    cursorInactiveStyle: "block",
    allowTransparency: false,
    theme: { background: "#000000", foreground: "#d8cfbf", cursor: "#deb86e", cursorAccent: "#000000" },
  });
  term.open($("screen"));
  showCursor();
}

// xterm draws no cursor until it has had input or switched screens; the view has no
// input of its own, so switch once.
function showCursor() {
  term.write("\x1b[?1049h\x1b[?1049l");
}

function currentTab() {
  return state.tabs.find((t) => t.id === state.watching);
}

/// Points the view at a tab: shows its last known screen straight away, then live.
function watch(id) {
  if (state.watching) drafts.set(state.watching, input.value);
  state.watching = id;
  lastScreen = null;
  makeTerm();
  term.reset();
  showCursor();
  $("screen-wrap").querySelector(".gone")?.remove();
  input.value = drafts.get(id) || "";
  autosize();
  setCtrl(false);
  const cached = screens.get(id);
  if (cached) drawScreen(cached);
  renderTermHeader();
  renderStrip(true);
  applyZoom();
  send({ t: "watch", id });
}

/// From the list: slides the tab in, and puts it in the history so Back returns.
function openTab(id, { animate = true } = {}) {
  watch(id);
  history.pushState({ tab: id }, "", "#tab=" + encodeURIComponent(id));
  show("term");
  if (animate) slide("in");
}

/// Another tab, from the strip, the banner or a swipe on the title. Back still goes to the list.
function switchTab(id, direction = 0) {
  if (id === state.watching) return;
  watch(id);
  history.replaceState({ tab: id }, "", "#tab=" + encodeURIComponent(id));
  if (!reduceMotion) {
    $("screen-wrap").animate([{ transform: `translateX(${direction * 40}px)`, opacity: 0.35 }, { transform: "none", opacity: 1 }],
      { duration: 220, easing });
  }
}

function closeTab(animate) {
  if (state.watching) drafts.set(state.watching, input.value);
  send({ t: "unwatch" });
  input.blur();
  showHome();
  if (animate) {
    $("term").hidden = false;
    slide("out");
  }
}

function goBack() {
  if (history.state && history.state.tab) {
    animateNextPop = true;
    history.back();
  } else {
    closeTab(true);
  }
}

window.addEventListener("popstate", (event) => {
  const animate = animateNextPop;
  animateNextPop = false;
  const tab = event.state && event.state.tab;
  if (tab) {
    // Forward again.
    if ($("term").hidden) { watch(tab); show("term"); }
  } else if (state.watching) {
    // Safari's own swipe has already animated; the page's back button hasn't.
    closeTab(animate);
  }
});

function renderStrip(scroll) {
  const strip = $("strip");
  const { all } = orderedTabs();
  strip.hidden = all.length < 2;
  strip.replaceChildren();
  for (const tab of all) {
    const chip = el("button", "chip" + (tab.id === state.watching ? " active" : ""));
    chip.type = "button";
    chip.append(el("span", "dot " + (tab.activity || "")), el("span", "chip-name", tab.project && tab.agentName ? tab.agentName.split(" ")[0] + " · " + tab.project : tabName(tab)));
    chip.addEventListener("click", () => switchTab(tab.id, all.indexOf(tab) > all.findIndex((t) => t.id === state.watching) ? 1 : -1));
    strip.append(chip);
  }
  if (scroll) strip.querySelector(".active")?.scrollIntoView({ inline: "center", block: "nearest" });
  renderBanner();
}

/// Another agent needs you while you're in this tab.
function renderBanner() {
  const other = state.tabs.find((t) => t.id !== state.watching && attention.has(t.activity));
  const banner = $("banner");
  banner.hidden = !other;
  if (!other) return;
  banner.replaceChildren(el("span", "dot " + other.activity),
    el("span", "banner-text", `${other.agentName || "Agent"} ${other.activity === "permission" ? "needs permission" : "is waiting for you"} · ${tabName(other)}`),
    el("span", "chev", "›"));
  banner.onclick = () => switchTab(other.id, 1);
}

function renderTermHeader() {
  const tab = currentTab();
  if (!tab) {
    if (!state.connected || !state.tabs.length) return;
    // Closed on the Mac.
    if (!$("screen-wrap").querySelector(".gone")) $("screen-wrap").append(el("div", "gone", "This tab was closed on your Mac."));
    $("choices").hidden = true;
    return;
  }
  $("term-title").textContent = tabName(tab);
  $("term-sub").textContent = tabMeta(tab);
  const needs = attention.has(tab.activity);
  $("choices").hidden = !needs;
  if (needs) $("choices-label").textContent = activityText[tab.activity];
}

$("back-btn").addEventListener("click", goBack);

// Swipe the title left or right for the next or previous tab.
{
  let start = null;
  const bar = $("term").querySelector(".bar");
  bar.addEventListener("touchstart", (e) => { const t = e.touches[0]; start = { x: t.clientX, y: t.clientY }; }, { passive: true });
  bar.addEventListener("touchend", (e) => {
    if (!start) return;
    const t = e.changedTouches[0];
    const dx = t.clientX - start.x, dy = t.clientY - start.y;
    start = null;
    if (Math.abs(dx) < 50 || Math.abs(dy) > Math.abs(dx) * 0.6) return;
    const { all } = orderedTabs();
    const index = all.findIndex((tab) => tab.id === state.watching);
    const next = all[index + (dx < 0 ? 1 : -1)];
    if (next) switchTab(next.id, dx < 0 ? 1 : -1);
  });
}

// On the Home Screen: drag from the left edge to go back, like a native app.
{
  let drag = null;
  const view = $("term");
  view.addEventListener("touchstart", (e) => {
    if (!standalone || e.touches.length !== 1 || e.touches[0].clientX > 24) return;
    drag = { x: e.touches[0].clientX, y: e.touches[0].clientY, dx: 0, time: performance.now(), active: false };
  }, { passive: true });
  view.addEventListener("touchmove", (e) => {
    if (!drag) return;
    const t = e.touches[0];
    drag.dx = Math.max(0, t.clientX - drag.x);
    if (!drag.active) {
      if (Math.abs(t.clientY - drag.y) > drag.dx) { drag = null; return; }
      if (drag.dx < 8) return;
      drag.active = true;
      $("home").hidden = false;
      renderTabs();
    }
    e.preventDefault();
    const p = drag.dx / innerWidth;
    view.style.transform = `translateX(${drag.dx}px)`;
    $("home").style.transform = `translateX(${(p - 1) * 28}%)`;
    $("home").style.opacity = String(0.55 + 0.45 * p);
  }, { passive: false });
  const end = () => {
    if (!drag || !drag.active) { drag = null; return; }
    const p = drag.dx / innerWidth;
    const fast = drag.dx / (performance.now() - drag.time) > 0.5;
    drag = null;
    view.style.transform = "";
    if (p > 0.35 || fast) {
      slide("out", p);
      if (state.watching) drafts.set(state.watching, input.value);
      send({ t: "unwatch" });
      input.blur();
      state.watching = null;
      renderTabs();
      // The slide already ran; the history entry just follows.
      if (history.state && history.state.tab) history.back();
    } else {
      slide("in", p);
    }
  };
  view.addEventListener("touchend", end);
  view.addEventListener("touchcancel", end);
}

function drawScreen(screen) {
  if (!term) return;
  const resized = !lastScreen || lastScreen.cols !== screen.cols || lastScreen.rows !== screen.rows;
  if (resized) term.resize(Math.max(2, screen.cols), Math.max(1, screen.rows));
  if (!lastScreen || lastScreen.bg !== screen.bg || lastScreen.fg !== screen.fg) {
    term.options.theme = { background: screen.bg, foreground: screen.fg, cursor: "#deb86e", cursorAccent: screen.bg };
    $("screen-wrap").style.setProperty("--term-bg", screen.bg);
  }
  lastScreen = screen;
  // Repaint every row in place, then put the cursor where the Mac has it.
  const rows = screen.vt.split(/\r?\n/);
  let out = "\x1b[0m\x1b[H\x1b[2J";
  for (let i = 0; i < rows.length && i < screen.rows; i++) out += `\x1b[${i + 1};1H` + rows[i];
  out += `\x1b[0m\x1b[${screen.y + 1};${screen.x + 1}H\x1b[?25${screen.cursor ? "h" : "l"}`;
  term.write(out);
  if (resized) applyZoom();
  else if (!state.fit) followCursor(screen);
}

function applyZoom() {
  $("zoom-btn").textContent = state.fit ? "Fit" : "1:1";
  $("screen-wrap").classList.toggle("fit", state.fit);
  if (!term) return;
  const cols = lastScreen ? lastScreen.cols : term.cols;
  const width = $("screen-wrap").clientWidth - 12;
  const size = state.fit ? Math.max(3, Math.floor((width / (cols * charRatio)) * 0.97 * 10) / 10) : 12;
  if (term.options.fontSize !== size) term.options.fontSize = size;
  if (lastScreen && !state.fit) requestAnimationFrame(() => followCursor(lastScreen));
}

// In 1:1, keep the cursor's column on screen.
function followCursor(screen) {
  const wrap = $("screen-wrap");
  const cell = term.options.fontSize * charRatio;
  const x = 6 + screen.x * cell;
  if (x < wrap.scrollLeft + 24 || x > wrap.scrollLeft + wrap.clientWidth - 24) {
    wrap.scrollLeft = Math.max(0, x - wrap.clientWidth / 2);
  }
  const lineHeight = term.options.fontSize * 1.2;
  const y = 6 + screen.y * lineHeight;
  if (y < wrap.scrollTop || y > wrap.scrollTop + wrap.clientHeight - lineHeight * 2) {
    wrap.scrollTop = Math.max(0, y - wrap.clientHeight / 2);
  }
}

$("zoom-btn").addEventListener("click", () => {
  state.fit = !state.fit;
  store.set("gx.zoom", state.fit ? "fit" : "1:1");
  applyZoom();
});
window.addEventListener("resize", () => { if (!$("term").hidden) applyZoom(); });

// MARK: Typing

function pressKey(key, mods) {
  if (!state.watching) return;
  send({ t: "key", id: state.watching, key, mods: mods || [] });
}

function setCtrl(on) {
  state.ctrl = on;
  $("ctrl-btn").setAttribute("aria-pressed", on ? "true" : "false");
}

$("ctrl-btn").addEventListener("click", () => setCtrl(!state.ctrl));

for (const button of document.querySelectorAll("#keys [data-key], #choices [data-key]")) {
  // Keep the phone keyboard up while tapping keys.
  button.addEventListener("pointerdown", (event) => event.preventDefault());
  button.addEventListener("click", () => {
    const mods = button.dataset.mods ? button.dataset.mods.split(",") : [];
    if (state.ctrl && !mods.includes("ctrl")) mods.push("ctrl");
    pressKey(button.dataset.key, mods);
    setCtrl(false);
  });
}
$("ctrl-btn").addEventListener("pointerdown", (event) => event.preventDefault());

const input = $("input");

function autosize() {
  input.style.height = "auto";
  input.style.height = Math.min(120, input.scrollHeight) + "px";
}

// With Ctrl on, the next letter typed goes straight to the terminal as Ctrl-letter.
input.addEventListener("beforeinput", (event) => {
  if (!state.ctrl || event.inputType !== "insertText" || !event.data) return;
  const char = event.data.slice(-1);
  if (!/^[a-z0-9 \[\]\\]$/i.test(char)) return;
  event.preventDefault();
  pressKey(char.toLowerCase(), ["ctrl"]);
  setCtrl(false);
});
input.addEventListener("input", autosize);

function submit() {
  const text = input.value;
  if (text) send({ t: "text", id: state.watching, text });
  pressKey("enter");
  input.value = "";
  autosize();
}

$("composer").addEventListener("submit", (event) => { event.preventDefault(); submit(); });
input.addEventListener("keydown", (event) => {
  // Return sends; Shift-Return (hardware keyboards) adds a line.
  if (event.key === "Enter" && !event.shiftKey && !event.isComposing) {
    event.preventDefault();
    submit();
  }
});
$("send-btn").addEventListener("pointerdown", (event) => event.preventDefault());

// MARK: Start

document.fonts.load('12px "JetBrains Mono"').catch(() => {}).finally(() => {
  measureFont();
  route();
});
window.addEventListener("hashchange", () => { if (location.hash.includes("pair=")) route(); });
