// Ghostty Custom code editor: a VS Code–style workbench around Monaco.
// File access goes through the native `fs` message handler (EditorWebView.swift).
'use strict';

const fs = (op, args = {}) => window.webkit.messageHandlers.fs.postMessage({ op, ...args });
const log = (message) => fs('log', { message: String(message) }).catch(() => {});
window.addEventListener('error', (e) => log(`${e.message} @ ${e.filename}:${e.lineno}`));
window.addEventListener('unhandledrejection', (e) => log(`unhandled: ${e.reason?.stack || e.reason}`));
const $ = (id) => document.getElementById(id);

const state = {
  root: null,        // absolute folder path
  children: new Map(), // dir path -> [{name, path, isDir}]
  expanded: new Set(),
  selected: null,
  tabs: [],          // {path, model, viewState, savedVersion, mtime, conflict}
  active: null,      // path
  files: null,       // cached list for quick open
};
let editor = null;
let monacoRef = null;

// ---------- Icons ----------------------------------------------------------

const ICONS = {
  js: ['symbol-method', '#cbcb41'], mjs: ['symbol-method', '#cbcb41'], cjs: ['symbol-method', '#cbcb41'],
  jsx: ['symbol-method', '#519aba'], ts: ['symbol-method', '#519aba'], tsx: ['symbol-method', '#519aba'],
  json: ['json', '#cbcb41'], md: ['markdown', '#519aba'], py: ['symbol-method', '#4b8bbe'],
  swift: ['symbol-method', '#e37933'], zig: ['symbol-method', '#f7a41d'], rs: ['symbol-method', '#dea584'],
  go: ['symbol-method', '#519aba'], rb: ['ruby', '#cc3e44'], java: ['symbol-method', '#cc3e44'],
  c: ['symbol-method', '#519aba'], h: ['symbol-method', '#a074c4'], cpp: ['symbol-method', '#519aba'],
  css: ['symbol-color', '#519aba'], scss: ['symbol-color', '#f55385'], html: ['code', '#e37933'],
  sh: ['terminal', '#4d5a5e'], zsh: ['terminal', '#4d5a5e'], yml: ['settings', '#a074c4'], yaml: ['settings', '#a074c4'],
  toml: ['settings', '#6d8086'], lock: ['lock', '#6d8086'], png: ['file-media', '#a074c4'], jpg: ['file-media', '#a074c4'],
  svg: ['file-media', '#e37933'], gif: ['file-media', '#a074c4'], sql: ['database', '#f55385'], txt: ['file', '#cccccc'],
};
function iconFor(name) {
  if (name === 'package.json') return ['json', '#8dc149'];
  if (name.startsWith('.git')) return ['source-control', '#41535b'];
  if (name.startsWith('.env')) return ['settings', '#cbcb41'];
  const ext = name.includes('.') ? name.split('.').pop().toLowerCase() : '';
  return ICONS[ext] || ['file', '#9d9d9d'];
}
function iconEl(name) {
  const [icon, color] = iconFor(name);
  const i = document.createElement('i');
  i.className = `codicon codicon-${icon} icon`;
  i.style.color = color;
  return i;
}
const basename = (p) => p.split('/').pop();
const relative = (p) => (state.root && p.startsWith(state.root + '/')) ? p.slice(state.root.length + 1) : p;

// ---------- Explorer -------------------------------------------------------

async function loadDir(path) {
  const entries = await fs('list', { path });
  state.children.set(path, entries);
  return entries;
}

function renderTree() {
  const tree = $('tree');
  const frag = document.createDocumentFragment();
  const walk = (dir, depth) => {
    for (const entry of state.children.get(dir) || []) {
      const row = document.createElement('div');
      row.className = 'row' + (state.selected === entry.path ? ' selected' : '');
      row.style.paddingLeft = `${8 + depth * 8}px`;
      row.dataset.path = entry.path;
      const twistie = document.createElement('i');
      twistie.className = 'twistie codicon ' +
        (entry.isDir ? (state.expanded.has(entry.path) ? 'codicon-chevron-down' : 'codicon-chevron-right') : '');
      row.append(twistie);
      if (!entry.isDir) row.append(iconEl(entry.name));
      const label = document.createElement('span');
      label.className = 'label';
      label.textContent = entry.name;
      row.append(label);
      if (!entry.isDir && state.tabs.some(t => t.path === entry.path && isDirty(t))) row.classList.add('modified');
      row.onclick = () => onRowClick(entry);
      frag.append(row);
      if (entry.isDir && state.expanded.has(entry.path)) walk(entry.path, depth + 1);
    }
  };
  if (state.root) walk(state.root, 0);
  tree.replaceChildren(frag);
}

async function onRowClick(entry) {
  state.selected = entry.path;
  if (entry.isDir) {
    if (state.expanded.has(entry.path)) {
      state.expanded.delete(entry.path);
    } else {
      state.expanded.add(entry.path);
      if (!state.children.has(entry.path)) await loadDir(entry.path);
    }
    renderTree();
  } else {
    renderTree();
    openFile(entry.path);
  }
}

async function refreshExplorer() {
  if (!state.root) return;
  const dirs = [state.root, ...state.expanded];
  await Promise.all(dirs.map(d => loadDir(d).catch(() => { state.expanded.delete(d); })));
  state.files = null;
  renderTree();
}

// ---------- Tabs & models --------------------------------------------------

const isDirty = (tab) => tab.model.getAlternativeVersionId() !== tab.savedVersion;

async function openFile(path, { line } = {}) {
  let tab = state.tabs.find(t => t.path === path);
  if (!tab) {
    let result;
    try { result = await fs('read', { path }); } catch (e) { return showError(e); }
    if (result.error) return showError(result.error);
    const uri = monacoRef.Uri.file(path);
    const model = monacoRef.editor.getModel(uri) || monacoRef.editor.createModel(result.content, undefined, uri);
    tab = { path, model, viewState: null, savedVersion: model.getAlternativeVersionId(), mtime: result.mtime, conflict: false };
    model.onDidChangeContent(() => { renderTabs(); });
    state.tabs.push(tab);
  }
  activate(path);
  if (line) { editor.revealLineInCenter(line); editor.setPosition({ lineNumber: line, column: 1 }); }
}

function activate(path) {
  const current = state.tabs.find(t => t.path === state.active);
  if (current) current.viewState = editor.saveViewState();
  state.active = path;
  const tab = state.tabs.find(t => t.path === path);
  $('watermark').classList.toggle('hidden', !!tab);
  if (tab) {
    editor.setModel(tab.model);
    if (tab.viewState) editor.restoreViewState(tab.viewState);
    editor.focus();
    state.selected = path;
  } else {
    editor.setModel(null);
  }
  renderTabs();
  renderBreadcrumbs();
  renderStatus();
  renderTree();
}

async function closeTab(path) {
  const index = state.tabs.findIndex(t => t.path === path);
  if (index < 0) return;
  const tab = state.tabs[index];
  if (isDirty(tab) && !confirm(`Do you want to save the changes you made to ${basename(path)}?\n\nOK saves, Cancel discards.`)) {
    // Discard.
  } else if (isDirty(tab)) {
    await save(tab);
  }
  state.tabs.splice(index, 1);
  tab.model.dispose();
  if (state.active === path) {
    const next = state.tabs[Math.min(index, state.tabs.length - 1)];
    state.active = null;
    activate(next ? next.path : null);
  } else {
    renderTabs();
  }
}

function renderTabs() {
  const bar = $('tabs');
  const counts = {};
  state.tabs.forEach(t => { const n = basename(t.path); counts[n] = (counts[n] || 0) + 1; });
  bar.replaceChildren(...state.tabs.map(tab => {
    const el = document.createElement('div');
    el.className = 'tab' + (tab.path === state.active ? ' active' : '') + (isDirty(tab) ? ' dirty' : '') +
      (tab.conflict ? ' conflict' : '');
    el.title = tab.conflict ? `${tab.path}\nChanged on disk while you have unsaved edits` : tab.path;
    el.append(iconEl(basename(tab.path)));
    const name = document.createElement('span');
    name.className = 'name';
    name.textContent = basename(tab.path);
    el.append(name);
    if (counts[basename(tab.path)] > 1) {
      const desc = document.createElement('span');
      desc.className = 'desc';
      desc.textContent = relative(tab.path).split('/').slice(-2, -1)[0] || '';
      el.append(desc);
    }
    const close = document.createElement('span');
    close.className = 'close';
    close.innerHTML = '<i class="codicon codicon-close"></i>';
    close.onclick = (e) => { e.stopPropagation(); closeTab(tab.path); };
    el.append(close);
    el.onclick = () => activate(tab.path);
    el.onauxclick = (e) => { if (e.button === 1) closeTab(tab.path); };
    return el;
  }));
  bar.querySelector('.tab.active')?.scrollIntoView({ inline: 'nearest' });
}

function renderBreadcrumbs() {
  const el = $('breadcrumbs');
  if (!state.active) { el.replaceChildren(); return; }
  const parts = relative(state.active).split('/');
  const nodes = [];
  parts.forEach((part, i) => {
    if (i > 0) { const c = document.createElement('i'); c.className = 'codicon codicon-chevron-right'; nodes.push(c); }
    if (i === parts.length - 1) nodes.push(iconEl(part));
    const s = document.createElement('span');
    s.textContent = part;
    nodes.push(s);
  });
  el.replaceChildren(...nodes);
}

// ---------- Saving & disk sync ----------------------------------------------

async function save(tab = state.tabs.find(t => t.path === state.active)) {
  if (!tab) return;
  const result = await fs('write', { path: tab.path, content: tab.model.getValue() });
  if (result.error) return showError(result.error);
  tab.savedVersion = tab.model.getAlternativeVersionId();
  tab.mtime = result.mtime;
  tab.conflict = false;
  renderTabs();
  renderTree();
}

// Agents edit files constantly; keep open files in sync with the disk.
async function syncWithDisk() {
  if (!state.tabs.length || document.hidden) return;
  const mtimes = await fs('stat', { paths: state.tabs.map(t => t.path) });
  for (const tab of state.tabs) {
    const mtime = mtimes[tab.path];
    if (mtime == null || mtime === tab.mtime) continue;
    if (isDirty(tab)) { tab.conflict = true; continue; }
    const result = await fs('read', { path: tab.path });
    if (result.error) continue;
    tab.mtime = result.mtime;
    if (result.content !== tab.model.getValue()) {
      const isActive = tab.path === state.active;
      const view = isActive ? editor.saveViewState() : null;
      tab.model.pushEditOperations([], [{ range: tab.model.getFullModelRange(), text: result.content }], () => null);
      tab.savedVersion = tab.model.getAlternativeVersionId();
      if (isActive && view) editor.restoreViewState(view);
    }
  }
  renderTabs();
}

// ---------- Status bar ------------------------------------------------------

let branch = '';
function renderStatus() {
  $('sb-branch').innerHTML = branch ? `<i class="codicon codicon-source-control"></i>${escapeHTML(branch)}` : '';
  const model = editor?.getModel();
  if (!model) { ['sb-position', 'sb-indent', 'sb-eol', 'sb-language'].forEach(id => $(id).textContent = ''); return; }
  const pos = editor.getPosition();
  const sel = editor.getSelection();
  const selected = sel && !sel.isEmpty() ? ` (${model.getValueInRange(sel).length} selected)` : '';
  $('sb-position').textContent = pos ? `Ln ${pos.lineNumber}, Col ${pos.column}${selected}` : '';
  const opts = model.getOptions();
  $('sb-indent').textContent = opts.insertSpaces ? `Spaces: ${opts.tabSize}` : `Tab Size: ${opts.tabSize}`;
  $('sb-eol').textContent = model.getEOL() === '\n' ? 'LF' : 'CRLF';
  const lang = monacoRef.languages.getLanguages().find(l => l.id === model.getLanguageId());
  $('sb-language').textContent = lang?.aliases?.[0] || model.getLanguageId();
}
const escapeHTML = (s) => s.replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));

// ---------- Quick open (⌘P) ------------------------------------------------

let qoItems = [];
let qoIndex = 0;

async function quickOpen() {
  if (!state.root) return;
  $('quickopen').classList.remove('hidden');
  const input = $('qo-input');
  input.value = '';
  input.focus();
  if (!state.files) state.files = await fs('files');
  filterQuickOpen();
}

function fuzzy(query, text) {
  // Subsequence match; rewards consecutive and word-start hits.
  let score = 0, ti = 0, streak = 0; const hits = [];
  const q = query.toLowerCase(), t = text.toLowerCase();
  for (const ch of q) {
    const found = t.indexOf(ch, ti);
    if (found < 0) return null;
    streak = found === ti ? streak + 1 : 0;
    score += 1 + streak * 2 + (found === 0 || '/._-'.includes(text[found - 1]) ? 3 : 0);
    hits.push(found);
    ti = found + 1;
  }
  return { score: score - text.length * 0.01, hits };
}

function filterQuickOpen() {
  const query = $('qo-input').value.trim();
  const files = state.files || [];
  let results;
  if (!query) {
    const recent = state.tabs.map(t => relative(t.path));
    results = [...recent, ...files.filter(f => !recent.includes(f))].slice(0, 60).map(f => ({ f, hits: [] }));
  } else {
    results = [];
    for (const f of files) {
      const name = f.split('/').pop();
      const m = fuzzy(query, name) || fuzzy(query, f);
      if (m) results.push({ f, hits: fuzzy(query, name)?.hits || [], score: m.score + (fuzzy(query, name) ? 10 : 0) });
    }
    results.sort((a, b) => b.score - a.score);
    results = results.slice(0, 60);
  }
  qoItems = results;
  qoIndex = 0;
  renderQuickOpen();
}

function renderQuickOpen() {
  $('qo-list').replaceChildren(...qoItems.map((r, i) => {
    const el = document.createElement('div');
    el.className = 'qo-item' + (i === qoIndex ? ' active' : '');
    const name = r.f.split('/').pop();
    const nameEl = document.createElement('span');
    nameEl.className = 'name';
    nameEl.innerHTML = [...name].map((c, ci) => r.hits.includes(ci) ? `<b>${escapeHTML(c)}</b>` : escapeHTML(c)).join('');
    const dir = document.createElement('span');
    dir.className = 'dir';
    dir.textContent = r.f.includes('/') ? r.f.slice(0, r.f.lastIndexOf('/')) : '';
    el.append(iconEl(name), nameEl, dir);
    el.onmousedown = (e) => { e.preventDefault(); qoIndex = i; acceptQuickOpen(); };
    return el;
  }));
  $('qo-list').children[qoIndex]?.scrollIntoView({ block: 'nearest' });
}

function acceptQuickOpen() {
  const item = qoItems[qoIndex];
  closeQuickOpen();
  if (item) openFile(state.root + '/' + item.f);
}
function closeQuickOpen() {
  $('quickopen').classList.add('hidden');
  if (editor?.getModel()) editor.focus();
}

$('qo-input').addEventListener('input', filterQuickOpen);
$('qo-input').addEventListener('keydown', (e) => {
  if (e.key === 'ArrowDown') { qoIndex = Math.min(qoIndex + 1, qoItems.length - 1); renderQuickOpen(); e.preventDefault(); }
  else if (e.key === 'ArrowUp') { qoIndex = Math.max(qoIndex - 1, 0); renderQuickOpen(); e.preventDefault(); }
  else if (e.key === 'Enter') { acceptQuickOpen(); e.preventDefault(); }
  else if (e.key === 'Escape') { closeQuickOpen(); e.preventDefault(); }
});
$('qo-input').addEventListener('blur', () => setTimeout(closeQuickOpen, 100));

// ---------- Layout ----------------------------------------------------------

(() => {
  const sash = $('sash');
  const explorer = $('explorer');
  sash.addEventListener('mousedown', (e) => {
    sash.classList.add('active');
    const startX = e.clientX, startW = explorer.offsetWidth;
    const move = (ev) => { explorer.style.width = `${Math.max(140, Math.min(500, startW + ev.clientX - startX))}px`; };
    const up = () => { sash.classList.remove('active'); removeEventListener('mousemove', move); removeEventListener('mouseup', up); };
    addEventListener('mousemove', move);
    addEventListener('mouseup', up);
  });
})();

function toggleExplorer() {
  $('explorer').classList.toggle('collapsed');
  $('sash').classList.toggle('hidden', $('explorer').classList.contains('collapsed'));
}

$('refresh').onclick = refreshExplorer;
$('collapse').onclick = () => { state.expanded.clear(); renderTree(); };

// Shortcuts that should work anywhere in the panel, not only inside the editor.
document.addEventListener('keydown', (e) => {
  if (!e.metaKey) return;
  const key = e.key.toLowerCase();
  if (key === 'p' && !e.shiftKey) { e.preventDefault(); quickOpen(); }
  else if (key === 's') { e.preventDefault(); save(); }
  else if (key === 'w') { e.preventDefault(); if (state.active) closeTab(state.active); }
  else if (key === 'b') { e.preventDefault(); toggleExplorer(); }
}, true);

function showError(message) {
  log(message);
  alert(String(message));
}

// ---------- Terminal theme ----------------------------------------------------

const hex = (c) => c.replace('#', '');
const toRGB = (c) => { const h = hex(c); return [0, 2, 4].map(i => parseInt(h.slice(i, i + 2), 16)); };
const toHex = (rgb) => '#' + rgb.map(v => Math.round(Math.max(0, Math.min(255, v))).toString(16).padStart(2, '0')).join('');
const mix = (a, b, t) => { const [x, y] = [toRGB(a), toRGB(b)]; return toHex(x.map((v, i) => v + (y[i] - v) * t)); };
const luminance = (c) => {
  const [r, g, b] = toRGB(c).map(v => { v /= 255; return v <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4; });
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
};
const contrast = (a, b) => { const [x, y] = [luminance(a), luminance(b)].sort((m, n) => n - m); return (x + 0.05) / (y + 0.05); };
/** Moves a palette color toward the foreground until it's readable on the background. */
function readable(color, bg, fg, min = 3.2) {
  let c = color;
  for (let i = 0; i < 12 && contrast(c, bg) < min; i++) c = mix(c, fg, 0.18);
  return c;
}

let terminalTheme = null;

function applyTheme(t) {
  if (!monacoRef) { terminalTheme = t; return; }
  const bg = t.background, fg = t.foreground, p = t.palette;
  const dark = luminance(bg) < 0.4;
  const pick = (...indices) => readable(p[indices.find(i => p[i]) ?? 7] || fg, bg, fg);

  // Workbench: shades of the terminal background, like the terminal's own chrome.
  const vars = {
    '--bg-editor': bg,
    '--bg-side': mix(bg, fg, dark ? 0.035 : 0.05),
    '--bg-tab-inactive': mix(bg, fg, dark ? 0.035 : 0.05),
    '--bg-hover': mix(bg, fg, 0.08),
    '--bg-selected': mix(bg, fg, 0.14),
    '--bg-input': mix(bg, fg, 0.1),
    '--border': mix(bg, fg, 0.12),
    '--fg': fg,
    '--fg-muted': mix(fg, bg, 0.35),
    '--fg-dim': mix(fg, bg, 0.55),
    '--accent': pick(12, 4, 13),
    '--modified': pick(11, 3),
    '--font-mono': `${t.fontFamily ? `"${t.fontFamily}", ` : ''}"JetBrains Mono", Menlo, monospace`,
  };
  for (const [k, v] of Object.entries(vars)) document.documentElement.style.setProperty(k, v);

  // Syntax colors from the ANSI palette (bright variants first, as terminal themes intend).
  const c = {
    keyword: pick(13, 5, 12), string: pick(10, 2, 11), number: pick(11, 3, 14), type: pick(14, 6, 12),
    func: pick(12, 4, 14), tag: pick(9, 1), attr: pick(11, 3), regexp: pick(9, 1),
    comment: mix(fg, bg, 0.5), delimiter: mix(fg, bg, 0.2),
  };
  const rule = (token, color, fontStyle) => ({ token, foreground: hex(color), ...(fontStyle ? { fontStyle } : {}) });
  monacoRef.editor.defineTheme('terminal', {
    base: dark ? 'vs-dark' : 'vs',
    inherit: true,
    rules: [
      rule('', fg), rule('comment', c.comment, 'italic'), rule('keyword', c.keyword), rule('storage', c.keyword),
      rule('string', c.string), rule('string.escape', c.number), rule('number', c.number), rule('constant', c.number),
      rule('type', c.type), rule('type.identifier', c.type), rule('namespace', c.type), rule('predefined', c.func),
      rule('function', c.func), rule('identifier', fg), rule('variable', fg), rule('delimiter', c.delimiter),
      rule('operator', c.delimiter), rule('tag', c.tag), rule('attribute.name', c.attr),
      rule('attribute.value', c.string), rule('regexp', c.regexp), rule('annotation', c.attr),
      rule('string.key.json', c.func), rule('string.value.json', c.string), rule('key', c.func),
    ],
    colors: {
      'editor.background': bg,
      'editor.foreground': fg,
      'editorCursor.foreground': t.cursor || fg,
      'editor.selectionBackground': (t.selectionBackground || mix(bg, fg, 0.25)) + 'aa',
      'editor.inactiveSelectionBackground': (t.selectionBackground || mix(bg, fg, 0.25)) + '55',
      'editor.lineHighlightBackground': mix(bg, fg, 0.05),
      'editor.lineHighlightBorder': mix(bg, fg, 0.05),
      'editorLineNumber.foreground': mix(fg, bg, 0.62),
      'editorLineNumber.activeForeground': fg,
      'editorIndentGuide.background1': mix(bg, fg, 0.1),
      'editorIndentGuide.activeBackground1': mix(bg, fg, 0.25),
      'editorGutter.background': bg,
      'editorWidget.background': mix(bg, fg, 0.05),
      'editorWidget.border': mix(bg, fg, 0.15),
      'editorSuggestWidget.selectedBackground': mix(bg, fg, 0.14),
      'editor.findMatchBackground': (t.selectionBackground || c.number) + '88',
      'editor.findMatchHighlightBackground': c.number + '33',
      'minimap.background': bg,
      'scrollbarSlider.background': mix(bg, fg, 0.18) + '88',
      'scrollbarSlider.hoverBackground': mix(bg, fg, 0.28) + 'aa',
      'focusBorder': vars['--accent'],
    },
  });
  monacoRef.editor.setTheme('terminal');
  const fontSize = t.fontSize || 13;
  editor.updateOptions({ fontFamily: vars['--font-mono'], fontSize, lineHeight: Math.round(fontSize * 1.55) });
  document.fonts.ready.then(() => monacoRef.editor.remeasureFonts());
}

// ---------- Native entry points ---------------------------------------------

window.app = {
  async openFolder(root, name, gitBranch) {
    if (state.root !== root) {
      state.root = root;
      state.children.clear();
      state.expanded.clear();
      state.files = null;
      $('root-name').textContent = (name || basename(root)).toUpperCase();
      await loadDir(root);
    }
    branch = gitBranch || '';
    renderTree();
    renderStatus();
  },
  openFile(path, line) { openFile(path, { line }); },
  setTheme(theme) { applyTheme(theme); },
  focus() { (editor?.getModel() ? editor : $('tree')).focus(); },
};

// ---------- Monaco ----------------------------------------------------------

require.config({ paths: { vs: 'vs' } });
require(['vs/editor/editor.main'], () => {
  monacoRef = window.monaco;
  monacoRef.editor.defineTheme('dark-modern', {
    base: 'vs-dark', inherit: true, rules: [],
    colors: {
      'editor.background': '#1f1f1f',
      'editorGutter.background': '#1f1f1f',
      'editorLineNumber.foreground': '#6e7681',
      'editorLineNumber.activeForeground': '#cccccc',
      'editor.lineHighlightBorder': '#282828',
      'editorWidget.background': '#202020',
      'editorWidget.border': '#313131',
      'minimap.background': '#1f1f1f',
      'scrollbarSlider.background': '#79797933',
    },
  });
  editor = monacoRef.editor.create($('editor'), {
    theme: 'dark-modern',
    model: null,
    automaticLayout: true,
    fontFamily: 'Menlo, "SF Mono", Monaco, monospace',
    fontSize: 13,
    lineHeight: 20,
    minimap: { enabled: true, renderCharacters: false, scale: 1 },
    smoothScrolling: true,
    cursorBlinking: 'smooth',
    cursorSmoothCaretAnimation: 'on',
    bracketPairColorization: { enabled: true },
    guides: { bracketPairs: 'active', indentation: true },
    stickyScroll: { enabled: true },
    renderLineHighlight: 'all',
    scrollBeyondLastLine: false,
    padding: { top: 4 },
    fixedOverflowWidgets: true,
  });
  if (terminalTheme) applyTheme(terminalTheme);
  editor.onDidChangeCursorPosition(renderStatus);
  editor.onDidChangeCursorSelection(renderStatus);
  const { KeyMod, KeyCode } = monacoRef;
  editor.addCommand(KeyMod.CtrlCmd | KeyCode.KeyS, () => save());
  editor.addCommand(KeyMod.CtrlCmd | KeyCode.KeyW, () => state.active && closeTab(state.active));
  editor.addCommand(KeyMod.CtrlCmd | KeyCode.KeyP, () => quickOpen());
  editor.addCommand(KeyMod.CtrlCmd | KeyCode.KeyB, () => toggleExplorer());

  setInterval(syncWithDisk, 2000);
  window.addEventListener('focus', () => { refreshExplorer(); syncWithDisk(); });
  fs('ready');
});
