// Code map: the whole project and the agent's path through it, as a star map.
//
// Folders are clusters, tinted by what they are (frontend, API, database, tests, config…),
// and files are stars. Files the agent read glow cyan, files it edited burn orange (new
// files green), sized by how much changed and cooling over time. The agent is a comet that
// flies from star to star, leaving a trail; each sub-agent gets its own.
//
// Zoom changes what you see: the Overview shows the project's areas and where the work is,
// Files shows each file, and Symbols shows the functions and classes inside the files the
// agent touched, with the ones it changed lit. Select anything for a details sidebar: what
// it is, what changed, what it imports and what imports it (drawn on the map as its blast
// radius), and which backend pieces it talks to.
//
// Drawn on one canvas, only while the map is showing and something is moving, so it costs
// nothing while the agent is idle or the panel is hidden. Uses helpers from app.js.

(() => {
  const SKIP = new Set(['.git', 'node_modules', '.next', '.open-next', '.nuxt', '.svelte-kit', '.output', '.vercel',
    '.wrangler', '.turbo', '.cache', '.parcel-cache', 'dist', 'build', '.build', 'out', 'coverage', 'DerivedData',
    '.venv', 'venv', '__pycache__', 'target', '.zig-cache', 'zig-out', 'Pods', '.gradle', '.expo', '.temp']);
  const COLORS = { read: '#78dceb', edit: '#ff9f4a', created: '#7fd99a', dir: '#967446', dust: '#8c8374', gold: '#deb86e',
                   imports: '#7fb2e8', importers: '#c792ea' };
  const VERBS = {
    read: 'Reading', edit: 'Editing', write: 'Writing', run: 'Running', search: 'Searching', web: 'Browsing',
    agent: 'Delegating', todo: 'Planning', other: 'Working',
  };
  const MAX_DUST_PER_DIR = 14;
  const MAX_NODES = 520;
  const MAX_FOLDERS = 70;

  // ---------- What each part of the project is ----------

  const ROLES = {
    frontend: ['Frontend', '#7fb2e8', 'browser'], api: ['API & server', '#c792ea', 'server-process'],
    data: ['Database', '#7fd6c2', 'database'], tests: ['Tests', '#dcdcaa', 'beaker'], config: ['Config', '#a8998a', 'settings-gear'],
    docs: ['Docs', '#b8a3f0', 'book'], assets: ['Assets', '#f28cb1', 'file-media'], code: ['Code', '#d9a55b', 'code'],
  };
  const ROLE_RULES = [
    ['tests', /(^|\/)(__tests__|tests?|spec|e2e|cypress|playwright)(\/|$)|\.(test|spec)\.[a-z]+$/i],
    ['data', /(^|\/)(supabase|migrations?|prisma|drizzle|db|database|schema|models|seeds?|sql)(\/|$)|\.(sql|prisma)$|schema\.[a-z]+$/i],
    ['api', /(^|\/)(api|server|routes|functions|workers?|middleware|trpc|actions|handlers|controllers|services|backend|lambda|edge)(\/|$)|(^|\/)(worker|server|middleware)\.[a-z]+$|route\.[jt]sx?$/i],
    ['config', /^[^/]+\.(json|ya?ml|toml|lock|config\.[a-z]+|rc)$|^\.[^/]+$|(^|\/)\.github\/|(^|\/)(Dockerfile|Makefile|Procfile)$|\.config\.[a-z]+$|^(wrangler|vercel|netlify|fly|firebase)\./i],
    ['docs', /\.(md|mdx|txt|rst)$|(^|\/)docs?(\/|$)/i],
    ['assets', /(^|\/)(public|static|assets|images|img|fonts|media)(\/|$)|\.(png|jpe?g|gif|svg|webp|ico|woff2?|ttf|mp4|mp3)$/i],
    ['frontend', /(^|\/)(components?|app|pages|views|screens|ui|hooks|styles|layouts?|src\/routes|client|frontend|web)(\/|$)|\.(tsx|jsx|vue|svelte|astro|css|scss|sass|less|html)$/i],
  ];
  function roleOf(rel) {
    for (const [role, re] of ROLE_RULES) if (re.test(rel)) return role;
    return 'code';
  }
  const dirRoles = new Map(); // folder rel -> { role, counts, files }

  function indexRoles(files) {
    dirRoles.clear();
    for (const rel of files) {
      if (skipped(rel)) continue;
      const role = roleOf(rel);
      const parts = rel.split('/');
      for (let i = 0; i < parts.length; i++) {
        const dir = parts.slice(0, i).join('/');
        let entry = dirRoles.get(dir);
        if (!entry) { entry = { counts: {}, files: 0 }; dirRoles.set(dir, entry); }
        entry.counts[role] = (entry.counts[role] || 0) + 1;
        entry.files++;
      }
    }
    for (const [dir, entry] of dirRoles) {
      // A folder's own name wins (supabase/, api/, tests/); otherwise what most of it is.
      const named = dir && roleOf(dir + '/x');
      const top = Object.entries(entry.counts).sort((a, b) => b[1] - a[1])[0]?.[0] || 'code';
      entry.role = named && named !== 'code' && named !== 'frontend' ? named : top;
    }
  }
  const roleFor = (node) => node.type === 'dir' ? (dirRoles.get(node.rel)?.role || 'code') : roleOf(node.rel);

  // ---------- Model ----------

  const nodes = new Map(); // rel path ('' = root) -> node
  const comets = new Map(); // lane key -> comet
  const pulses = [];        // shockwaves where something was just touched
  let seq = 0;
  let mode = 'map';
  let canvas, ctx, stage, hud, tip, empty, fitBtn, wrap, side, zoomBar, legend;
  let width = 0, height = 0, dpr = 1;
  let alpha = 0;            // layout energy; the simulation runs while > 0
  // `s` stretches x so the map fills the wide, short panel instead of sitting in its middle.
  const cam = { x: 0, y: 0, k: 1, s: 1, tx: 0, ty: 0, tk: 1, ts: 1, auto: true };
  let hover = null, selected = null, roleFilter = null;
  let frame = 0, lastDraw = 0, lastInteract = 0;
  let filesLoaded = false;

  /** The path inside the project. The terminal and the disk can disagree on the folder's
   *  case (~/Desktop/projects vs ~/Desktop/Projects), so compare without it. */
  function relOf(abs) {
    const root = state.root ? canonical(state.root).toLowerCase() : null;
    const path = canonical(abs);
    const rel = root && path.toLowerCase().startsWith(root + '/') ? path.slice(root.length + 1) : abs;
    if (rel === abs) {
      // Outside the project: group under its own folder name.
      const parts = canonical(abs).split('/').filter(Boolean);
      return `↗ ${parts.slice(-2, -1)[0] || '/'}/${parts[parts.length - 1]}`;
    }
    return rel;
  }
  const absOf = (node) => node.abs || (state.root && !node.rel.startsWith('↗') ? `${state.root}/${node.rel}` : null);
  const skipped = (rel) => rel.split('/').some(part => SKIP.has(part));
  const depthOf = (rel) => rel ? rel.split('/').length : 0;

  function ensure(rel, type) {
    let node = nodes.get(rel);
    if (node) return node;
    if (nodes.size >= MAX_NODES && type === 'dust') return null;
    const parentRel = rel.includes('/') ? rel.slice(0, rel.lastIndexOf('/')) : '';
    const parent = rel === '' ? null : ensure(parentRel, 'dir');
    const angle = Math.random() * Math.PI * 2;
    const spread = type === 'dir' ? 60 : 26;
    node = {
      rel, type, parent, name: rel === '' ? (state.root ? basename(state.root) : 'project') : rel.split('/').pop(),
      x: (parent?.x || 0) + Math.cos(angle) * spread, y: (parent?.y || 0) + Math.sin(angle) * spread, vx: 0, vy: 0,
      reads: 0, edits: 0, created: false, last: 0, seq: 0, born: performance.now(), children: 0, touchedInside: 0,
      agents: new Set(), reach: 0, depth: depthOf(rel),
    };
    if (parent) parent.children++;
    nodes.set(rel, node);
    alpha = Math.max(alpha, 0.6);
    return node;
  }

  function reset() {
    nodes.clear();
    comets.clear();
    pulses.length = 0;
    symbols.clear();
    links.clear();
    filesLoaded = false;
    selected = null;
    cam.auto = true;
    ensure('', 'dir');
    renderSide();
  }

  /** The project's shape: every main folder (sized by how much is in it), and faint dust
   *  for the files beside the ones the agent touched. */
  async function loadFiles() {
    if (filesLoaded || !state.root) return;
    filesLoaded = true;
    if (!state.files) state.files = await fs('files').catch(() => []);
    indexRoles(state.files || []);
    refreshDust();
    renderLegend();
    renderHUD();
  }

  function refreshDust() {
    const files = state.files || [];
    // The biggest folders two levels down, so the whole codebase has a shape.
    const folders = [...dirRoles.entries()].filter(([dir]) => dir && depthOf(dir) <= 2 && !skipped(dir))
      .sort((a, b) => b[1].files - a[1].files).slice(0, MAX_FOLDERS);
    for (const [dir] of folders) ensure(dir, 'dir');
    const dirs = new Set([...nodes.values()].filter(n => n.type === 'dir' && (n.touchedInside || !n.parent)).map(n => n.rel));
    const perDir = new Map();
    for (const rel of files) {
      if (skipped(rel)) continue;
      const dir = rel.includes('/') ? rel.slice(0, rel.lastIndexOf('/')) : '';
      if (!dirs.has(dir)) continue;
      const count = perDir.get(dir) || 0;
      if (count >= MAX_DUST_PER_DIR) continue;
      perDir.set(dir, count + 1);
      if (!nodes.has(rel)) ensure(rel, 'dust');
    }
  }

  function touch(abs, kind, { quiet = false, created = false, who = null } = {}) {
    if (!abs) return null;
    const rel = relOf(abs);
    if (!rel || skipped(rel)) return null;
    const node = ensure(rel, 'file');
    node.type = 'file';
    // Keep the path as the app reported it: that's the one it lets the editor open.
    if (!node.abs || kind === 'edit') node.abs = abs;
    if (kind === 'edit') { node.edits++; symbols.delete(node.rel); } else node.reads++;
    if (created) node.created = true;
    if (who) node.agents.add(who);
    node.last = Date.now();
    node.seq = ++seq;
    for (let p = node.parent; p; p = p.parent) p.touchedInside = node.last;
    if (!quiet) pulses.push({ node, kind, t: performance.now() });
    // The project's file list is only fetched for a map someone is looking at.
    if (filesLoaded) refreshDust(); else if (visible()) loadFiles();
    if (selected && (selected === node || node.rel.startsWith(selected.rel + '/') || !selected.rel)) renderSideSoon();
    wake();
    return node;
  }

  /** How bright a star is: hot right after it was touched, settling to a steady glow. */
  function glow(node, now) {
    if (!node.last) return 0;
    const recency = Math.exp(-(now - node.last) / 300000);
    return 0.38 + 0.62 * recency;
  }

  function size(node) {
    if (node.type === 'dir') {
      if (!node.parent) return 5;
      const files = dirRoles.get(node.rel)?.files || 1;
      return Math.min(9, 2.4 + Math.sqrt(files) * 0.5);
    }
    if (node.type !== 'file') return 1.3;
    const change = turnChange(node);
    const lines = change ? lineCounts(change).total : 0;
    return Math.min(11, 3 + Math.sqrt(lines) * 0.45 + node.edits * 0.7 + node.reads * 0.25);
  }

  function colorOf(node) {
    if (node.created || turnChange(node)?.created) return COLORS.created;
    return node.edits ? COLORS.edit : COLORS.read;
  }

  function turnChange(node) {
    if (!node.abs) return null;
    const exact = turn.files.get(canonical(node.abs));
    if (exact) return exact;
    const key = canonical(node.abs).toLowerCase();
    for (const change of turn.files.values()) if (canonical(change.path).toLowerCase() === key) return change;
    return null;
  }

  function lineCounts(change) {
    const hunks = change.hunks || [];
    const added = hunks.reduce((n, h) => n + (h.count || 0), 0);
    const removed = hunks.reduce((n, h) => n + (h.removed?.length || 0), 0);
    return { added, removed, total: added + removed };
  }

  // ---------- Symbols and imports (read on demand, cached) ----------

  const symbols = new Map(); // rel -> [{ name, kind, line }] | 'loading'
  const SYMBOL_RULES = [
    [/^\s*export\s+(?:default\s+)?(?:async\s+)?function\s*\*?\s*([A-Za-z_$][\w$]*)/, 'function'],
    [/^\s*(?:async\s+)?function\s*\*?\s*([A-Za-z_$][\w$]*)/, 'function'],
    [/^\s*(?:export\s+)?(?:default\s+)?(?:abstract\s+)?class\s+([A-Za-z_$][\w$]*)/, 'class'],
    [/^\s*(?:export\s+)?(?:const|let)\s+([A-Za-z_$][\w$]*)\s*(?::[^=]+)?=\s*(?:async\s*)?(?:\([^)]*\)|[A-Za-z_$][\w$]*)\s*(?::[^=]+)?=>/, 'function'],
    [/^\s*(?:export\s+)?(?:interface|type)\s+([A-Za-z_$][\w$]*)/, 'type'],
    [/^\s*(?:export\s+)?enum\s+([A-Za-z_$][\w$]*)/, 'type'],
    [/^\s*(?:async\s+)?def\s+([A-Za-z_]\w*)/, 'function'],
    [/^\s*class\s+([A-Za-z_]\w*)/, 'class'],
    [/^\s*(?:public\s+|private\s+|internal\s+|static\s+|override\s+)*func\s+([A-Za-z_]\w*)/, 'function'],
    [/^\s*(?:public\s+|private\s+|final\s+)*(?:struct|class|enum|protocol|extension)\s+([A-Za-z_]\w*)/, 'class'],
    [/^\s*(?:pub\s+)?fn\s+([A-Za-z_]\w*)/, 'function'],
    [/^\s*func\s+(?:\([^)]*\)\s*)?([A-Za-z_]\w*)/, 'function'],
    [/^\s*create\s+(?:or\s+replace\s+)?(?:table|view|function)\s+(?:if\s+not\s+exists\s+)?(?:public\.)?"?([A-Za-z_]\w*)/i, 'table'],
    [/^\s*model\s+([A-Za-z_]\w*)\s*\{/, 'table'],
  ];
  const contents = new Map(); // rel -> text, for the selected file and symbol views

  async function textOf(node) {
    const abs = absOf(node);
    if (!abs) return null;
    if (contents.has(node.rel)) return contents.get(node.rel);
    const result = await fs('read', { path: abs }).catch(() => null);
    if (!result || result.error || result.content == null || result.content.length > 600000) return null;
    contents.set(node.rel, result.content);
    if (contents.size > 40) contents.delete(contents.keys().next().value);
    return result.content;
  }

  async function loadSymbols(node) {
    if (symbols.has(node.rel)) return symbols.get(node.rel);
    symbols.set(node.rel, 'loading');
    const text = await textOf(node);
    const found = [];
    if (text) {
      text.split('\n').forEach((line, i) => {
        if (line.length > 400) return;
        for (const [re, kind] of SYMBOL_RULES) {
          const m = re.exec(line);
          if (m && !found.some(s => s.name === m[1])) { found.push({ name: m[1], kind, line: i + 1 }); break; }
        }
      });
    }
    symbols.set(node.rel, found.slice(0, 60));
    wake();
    if (selected === node) renderSideSoon();
    return found;
  }

  /** Symbols this turn's change touched: a hunk inside the symbol's span. */
  function changedSymbols(node, list) {
    const change = turnChange(node);
    if (!change || !Array.isArray(list)) return new Set();
    const sorted = list.slice().sort((a, b) => a.line - b.line);
    const hit = new Set();
    for (const h of change.hunks || []) {
      const end = h.start + Math.max(0, (h.count || 1) - 1);
      sorted.forEach((s, i) => {
        const next = sorted[i + 1]?.line ?? Infinity;
        if (h.start < next && end >= s.line) hit.add(s.name);
      });
    }
    return hit;
  }

  const links = new Map(); // rel -> { imports: [rel], importers: [{ rel, line }], loading }
  const EXTS = ['', '.ts', '.tsx', '.js', '.jsx', '.mjs', '.cjs', '.vue', '.svelte', '.py', '.css', '.scss',
                '/index.ts', '/index.tsx', '/index.js', '/index.jsx', '/__init__.py'];

  function resolveImport(fromRel, spec, fileSet) {
    let base;
    if (spec.startsWith('.')) {
      const parts = fromRel.split('/').slice(0, -1);
      for (const piece of spec.split('/')) {
        if (piece === '..') parts.pop(); else if (piece !== '.') parts.push(piece);
      }
      base = parts.join('/');
    } else if (spec.startsWith('@/') || spec.startsWith('~/')) {
      const rest = spec.slice(2);
      for (const prefix of ['src/', '', 'app/']) {
        for (const ext of EXTS) if (fileSet.has(prefix + rest + ext)) return prefix + rest + ext;
      }
      return null;
    } else {
      return null; // a package, not a project file
    }
    for (const ext of EXTS) if (fileSet.has(base + ext)) return base + ext;
    return null;
  }

  const importSpecs = (text) => {
    const specs = new Set();
    for (const m of text.matchAll(/(?:import|export)\s[^'"`;]*?from\s+['"]([^'"]+)['"]|import\s*\(\s*['"]([^'"]+)['"]\s*\)|require\(\s*['"]([^'"]+)['"]\s*\)|^\s*import\s+['"]([^'"]+)['"]/gm)) {
      specs.add(m[1] || m[2] || m[3] || m[4]);
    }
    for (const m of text.matchAll(/^\s*from\s+(\.+)([\w.]*)\s+import/gm)) {
      specs.add((m[1].length === 1 ? './' : '../'.repeat(m[1].length - 1)) + m[2].replace(/\./g, '/'));
    }
    return specs;
  };

  async function loadLinks(node) {
    if (links.has(node.rel)) return links.get(node.rel);
    const entry = { imports: [], importers: [], loading: true };
    links.set(node.rel, entry);
    // Resolving imports needs the project's file list; it may not be loaded yet.
    if (!state.files && visible()) state.files = await fs('files').catch(() => []);
    const fileSet = new Set(state.files || []);
    const text = await textOf(node);
    if (text) {
      for (const spec of importSpecs(text)) {
        const rel = resolveImport(node.rel, spec, fileSet);
        if (rel && rel !== node.rel && !entry.imports.includes(rel)) entry.imports.push(rel);
      }
    }
    // Who imports this file: search the project for its name in import paths, then check
    // each hit really resolves to this file (not another file with the same name).
    const file = node.rel.split('/').pop();
    const stem = file.replace(/\.[^.]+$/, '');
    const name = stem === 'index' ? node.rel.split('/').slice(-2, -1)[0] : stem;
    if (name) {
      const strings = [`/${name}'`, `/${name}"`, `/${name}.js'`, `/${name}.js"`, `/${name}.ts'`, `/${name}.ts"`,
                       `'./${name}'`, `"./${name}"`, `.${name} import`];
      const hits = await fs('backend', { action: 'refs', strings }).catch(() => []);
      for (const hit of Array.isArray(hits) ? hits : []) {
        if (hit.path === node.rel || !/\b(import|from|require)\b/.test(hit.text)) continue;
        const targets = [...importSpecs(hit.text)].map(spec => resolveImport(hit.path, spec, fileSet));
        if (!targets.includes(node.rel)) continue;
        if (!entry.importers.some(i => i.rel === hit.path)) entry.importers.push({ rel: hit.path, line: hit.line });
      }
    }
    entry.loading = false;
    wake();
    if (selected === node) renderSideSoon();
    return entry;
  }

  // ---------- Comets: where each agent is ----------

  const LANE_COLOR_HEX = ['#f28cb1', '#b8a3f0', '#7fd6c2', '#7fb2e8', '#dcdcaa'];

  function comet(key) {
    let c = comets.get(key);
    if (!c) {
      const root = nodes.get('');
      c = { key, x: root?.x || 0, y: root?.y || 0, target: null, trail: [], label: '', detail: '', last: Date.now(),
            color: key === 'main' ? null : LANE_COLOR_HEX[comets.size % LANE_COLOR_HEX.length] };
      comets.set(key, c);
    }
    return c;
  }

  function agentItem(item, quiet) {
    if (item.kind !== 'tool') return;
    const key = item.sub || 'main';
    const path = agentAbs(item.path);
    const action = item.action || 'other';
    let node = null;
    if (path && action !== 'search' && action !== 'web') {
      node = touch(path, action === 'edit' || action === 'write' ? 'edit' : 'read',
                   { quiet, created: action === 'write' && !nodes.get(relOf(path))?.last,
                     who: item.sub || agentName() });
      if (node && (action === 'edit' || action === 'write')) window.backend?.agentTouched(path, 'edit');
    }
    if (quiet) return;
    const c = comet(key);
    c.label = VERBS[action] || VERBS.other;
    c.detail = node ? node.name : (item.command?.split('\n')[0] || item.pattern || item.query || item.description || '');
    c.last = Date.now();
    c.target = node || c.target || nodes.get('');
    wake();
  }

  function status(s) {
    const c = comets.get('main');
    if (c && s) {
      if (s.badge === 'done') { c.label = 'Done'; c.detail = ''; pulses.push({ node: c.target, kind: 'done', t: performance.now() }); }
      else if (s.badge === 'permission' || s.badge === 'input') { c.label = 'Needs you'; }
      else if (s.badge === 'working' && /think/i.test(s.activity || '')) { c.label = 'Thinking'; c.detail = ''; }
    }
    renderHUD();
    wake();
  }

  // ---------- Layout: a small force simulation ----------

  function simulate() {
    const list = [...nodes.values()];
    const n = list.length;
    // Repulsion (n is capped, so the pairwise pass stays cheap).
    for (let i = 0; i < n; i++) {
      const a = list[i];
      for (let j = i + 1; j < n; j++) {
        const b = list[j];
        let dx = b.x - a.x, dy = b.y - a.y;
        let d2 = dx * dx + dy * dy;
        if (d2 > 160000) continue;
        if (d2 < 1) { dx = Math.random() - 0.5; dy = Math.random() - 0.5; }
        // Floor the distance so nodes born on top of each other ease apart instead of flying off.
        d2 = Math.max(d2, 400);
        const strength = (a.type === 'dust' || b.type === 'dust' ? 420 : 2400) / d2;
        const fx = dx * strength, fy = dy * strength;
        a.vx -= fx; a.vy -= fy; b.vx += fx; b.vy += fy;
      }
    }
    // Springs to the parent folder.
    for (const node of list) {
      const p = node.parent;
      if (!p) continue;
      const rest = node.type === 'dir' ? 70 + size(node) * 4 : node.type === 'dust' ? 30 : 46 + size(node) * 2;
      const dx = node.x - p.x, dy = node.y - p.y;
      const d = Math.sqrt(dx * dx + dy * dy) || 1;
      const f = (d - rest) / d * 0.08;
      node.vx -= dx * f; node.vy -= dy * f;
      p.vx += dx * f * 0.5; p.vy += dy * f * 0.5;
    }
    // Weak gravity, a little stronger vertically to suit the wide, short panel.
    const aspect = width && height ? Math.min(3, width / height) : 2;
    for (const node of list) {
      node.vx -= node.x * 0.0025 / aspect;
      node.vy -= node.y * 0.0025 * aspect * 0.6;
      if (!node.parent) { node.x *= 0.9; node.y *= 0.9; node.vx = 0; node.vy = 0; continue; }
      node.vx *= 0.6; node.vy *= 0.6;
      const speed = Math.hypot(node.vx, node.vy);
      if (speed > 12) { node.vx *= 12 / speed; node.vy *= 12 / speed; }
      node.x += node.vx * alpha; node.y += node.vy * alpha;
    }
    // How far each area reaches, for its tinted region.
    for (const node of list) node.reach = 0;
    for (const node of list) {
      for (let p = node.parent; p && p.parent; p = p.parent) {
        p.reach = Math.max(p.reach, Math.hypot(node.x - p.x, node.y - p.y));
      }
    }
    alpha = alpha < 0.02 ? 0 : alpha * 0.985;
  }

  // ---------- Camera and zoom levels ----------

  const LEVELS = [['overview', 'Overview', 0.4], ['files', 'Files', 1.1], ['symbols', 'Symbols', 2.4]];
  // The Overview button shows the whole project with area summaries at any scale; otherwise
  // the level follows the zoom.
  let forcedLevel = null;
  const level = () => forcedLevel || (cam.k < 0.62 ? 'overview' : cam.k > 1.75 ? 'symbols' : 'files');

  function fit() {
    const list = [...nodes.values()];
    if (!list.length || !width) return;
    let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
    for (const n of list) {
      minX = Math.min(minX, n.x); maxX = Math.max(maxX, n.x);
      minY = Math.min(minY, n.y); maxY = Math.max(maxY, n.y);
    }
    const padX = 70, top = 44, bottom = 52;
    const ky = (height - top - bottom) / Math.max(60, maxY - minY);
    const kx = (width - padX * 2) / Math.max(80, maxX - minX);
    const k = Math.max(0.25, Math.min(1.6, ky, kx));
    cam.tk = k;
    cam.ts = Math.max(1, Math.min(2.4, kx / k));
    cam.tx = (minX + maxX) / 2;
    cam.ty = (minY + maxY) / 2 - (top - bottom) / 2 / k;
  }

  function zoomTo(k, x = cam.tx, y = cam.ty) {
    cam.auto = false;
    if (k > 0.62) forcedLevel = null;
    fitBtn.classList.remove('hidden');
    cam.tk = k; cam.tx = x; cam.ty = y;
    lastInteract = performance.now();
    wake();
  }

  const toScreen = (x, y) => [(x - cam.x) * cam.k * cam.s + width / 2, (y - cam.y) * cam.k + height / 2];
  const toWorld = (sx, sy) => [(sx - width / 2) / (cam.k * cam.s) + cam.x, (sy - height / 2) / cam.k + cam.y];

  // ---------- Drawing ----------

  const stars = Array.from({ length: 90 }, () => [Math.random(), Math.random(), Math.random() * 0.8 + 0.2]);
  let placed = [];      // label boxes drawn this frame, so labels don't pile up
  let symbolSpots = []; // clickable symbol satellites drawn this frame

  function free(x, y, w, h) {
    for (const [px, py, pw, ph] of placed) if (x < px + pw && px < x + w && y < py + ph && py < y + h) return false;
    placed.push([x, y, w, h]);
    return true;
  }

  function rgba(hex, a) {
    const v = parseInt(hex.slice(1), 16);
    return `rgba(${v >> 16 & 255},${v >> 8 & 255},${v & 255},${Math.max(0, Math.min(1, a)).toFixed(3)})`;
  }

  function sparkle(x, y, r, color, a, spin) {
    // A four-pointed star with a soft halo.
    const halo = ctx.createRadialGradient(x, y, 0, x, y, r * 3.2);
    halo.addColorStop(0, rgba(color, 0.45 * a));
    halo.addColorStop(1, rgba(color, 0));
    ctx.fillStyle = halo;
    ctx.beginPath(); ctx.arc(x, y, r * 3.2, 0, Math.PI * 2); ctx.fill();
    ctx.save();
    ctx.translate(x, y);
    ctx.rotate(spin);
    ctx.fillStyle = rgba(color, a);
    ctx.beginPath();
    for (let i = 0; i < 8; i++) {
      const rr = i % 2 === 0 ? r * 1.35 : r * 0.38;
      const t = i * Math.PI / 4;
      ctx.lineTo(Math.cos(t) * rr, Math.sin(t) * rr);
    }
    ctx.closePath();
    ctx.fill();
    ctx.fillStyle = rgba('#ffffff', 0.85 * a);
    ctx.beginPath(); ctx.arc(0, 0, Math.max(0.8, r * 0.28), 0, Math.PI * 2); ctx.fill();
    ctx.restore();
  }

  function brandColor() {
    const v = getComputedStyle(document.documentElement).getPropertyValue('--agent-brand').trim();
    return /^#[0-9a-f]{6}$/i.test(v) ? v : '#d97757';
  }

  /** Dim what's outside the role spotlight. */
  const inFilter = (node) => !roleFilter || roleFor(node) === roleFilter;

  function draw(now) {
    const t = performance.now();
    const zoom = level();
    placed = [];
    symbolSpots = [];
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.clearRect(0, 0, width, height);

    // Background stars, drifting a touch with the camera for depth.
    for (const [sx, sy, b] of stars) {
      const x = ((sx * width - cam.x * 0.05 * b) % width + width) % width;
      const y = ((sy * height - cam.y * 0.05 * b) % height + height) % height;
      ctx.fillStyle = `rgba(216,207,191,${(0.05 + b * 0.09).toFixed(3)})`;
      ctx.fillRect(x, y, b > 0.8 ? 1.5 : 1, b > 0.8 ? 1.5 : 1);
    }

    const list = [...nodes.values()];
    const touched = list.filter(n => n.type === 'file' && n.last);

    // Areas: each top-level folder's region, tinted by what it is.
    for (const n of list) {
      if (n.type !== 'dir' || n.depth !== 1 || n.reach < 8) continue;
      const [x, y] = toScreen(n.x, n.y);
      const role = ROLES[roleFor(n)];
      const rx = (n.reach + 26) * cam.k * cam.s, ry = (n.reach + 26) * cam.k;
      const strength = (zoom === 'overview' ? 0.2 : 0.09) * (inFilter(n) ? 1 : 0.25) * (n.touchedInside ? 1.4 : 1);
      ctx.save();
      ctx.translate(x, y);
      ctx.scale(rx / ry, 1);
      const g = ctx.createRadialGradient(0, 0, 0, 0, 0, ry);
      g.addColorStop(0, rgba(role[1], strength));
      g.addColorStop(0.7, rgba(role[1], strength * 0.45));
      g.addColorStop(1, rgba(role[1], 0));
      ctx.fillStyle = g;
      ctx.beginPath(); ctx.arc(0, 0, ry, 0, Math.PI * 2); ctx.fill();
      ctx.restore();
    }

    // Constellation lines: each folder to what's inside.
    ctx.lineWidth = 1;
    for (const n of list) {
      if (!n.parent || (zoom === 'overview' && n.type === 'dust')) continue;
      const [x1, y1] = toScreen(n.x, n.y), [x2, y2] = toScreen(n.parent.x, n.parent.y);
      const lit = n.last || n.touchedInside;
      const dim = inFilter(n) ? 1 : 0.3;
      ctx.strokeStyle = lit ? `rgba(222,184,110,${0.22 * dim})` : `rgba(150,116,70,${0.1 * dim})`;
      ctx.beginPath(); ctx.moveTo(x1, y1); ctx.lineTo(x2, y2); ctx.stroke();
    }

    // The selected file's blast radius: what it imports and what imports it.
    const link = selected && links.get(selected.rel);
    if (link && !link.loading) {
      const [sx, sy] = toScreen(selected.x, selected.y);
      const drawLink = (rel, color, inbound) => {
        const other = nodes.get(rel);
        if (!other) return;
        const [ox, oy] = toScreen(other.x, other.y);
        const mx = (sx + ox) / 2 + (oy - sy) * 0.18, my = (sy + oy) / 2 - (ox - sx) * 0.18;
        ctx.strokeStyle = rgba(color, 0.75);
        ctx.lineWidth = 1.6;
        ctx.setLineDash([5, 4]);
        ctx.lineDashOffset = (inbound ? 1 : -1) * t / 40;
        ctx.beginPath(); ctx.moveTo(ox, oy); ctx.quadraticCurveTo(mx, my, sx, sy); ctx.stroke();
        ctx.setLineDash([]);
        ctx.fillStyle = rgba(color, 0.9);
        ctx.beginPath(); ctx.arc(ox, oy, 3, 0, Math.PI * 2); ctx.fill();
      };
      link.imports.forEach(rel => drawLink(rel, COLORS.imports, false));
      link.importers.forEach(i => drawLink(i.rel, COLORS.importers, true));
    }

    // The agent's recent path, oldest faintest.
    const path = touched.slice().sort((a, b) => a.seq - b.seq).slice(-12);
    if (path.length > 1) {
      for (let i = 1; i < path.length; i++) {
        const [x1, y1] = toScreen(path[i - 1].x, path[i - 1].y), [x2, y2] = toScreen(path[i].x, path[i].y);
        ctx.strokeStyle = rgba(COLORS.gold, (i / path.length) * 0.55);
        ctx.setLineDash([3, 5]);
        ctx.lineDashOffset = -t / 60;
        ctx.lineWidth = 1.2;
        ctx.beginPath(); ctx.moveTo(x1, y1); ctx.lineTo(x2, y2); ctx.stroke();
      }
      ctx.setLineDash([]);
    }

    // Dust and folders (folder names go on after the files', which matter more).
    const folderLabels = [];
    for (const n of list) {
      const [x, y] = toScreen(n.x, n.y);
      if (x < -40 || y < -40 || x > width + 40 || y > height + 40) continue;
      const fade = Math.min(1, (t - n.born) / 600) * (inFilter(n) ? 1 : 0.3);
      if (n.type === 'dust') {
        if (zoom === 'overview') continue;
        ctx.fillStyle = rgba(COLORS.dust, 0.55 * fade);
        ctx.beginPath(); ctx.arc(x, y, 1.6, 0, Math.PI * 2); ctx.fill();
        if (hover === n) label(n.name, x, y + 12, COLORS.dust, 0.9, false, null, true);
      } else if (n.type === 'dir') {
        const lit = n.touchedInside || !n.parent;
        const role = ROLES[roleFor(n)];
        const r = size(n) * (zoom === 'overview' ? 1.5 : 1);
        ctx.fillStyle = rgba(role[1], (lit ? 0.3 : 0.14) * fade);
        ctx.strokeStyle = rgba(lit ? COLORS.gold : role[1], (lit ? 0.85 : 0.55) * fade);
        ctx.lineWidth = selected === n ? 2.4 : 1.2;
        ctx.beginPath(); ctx.arc(x, y, r, 0, Math.PI * 2); ctx.fill(); ctx.stroke();
        const showName = lit || hover === n || selected === n || zoom === 'overview' || cam.k > 1.3 || n.depth === 1;
        if (showName) {
          const count = dirRoles.get(n.rel)?.files;
          const text = n.parent ? `${n.name}/${zoom === 'overview' && count ? ` ${count}` : ''}` : n.name;
          const args = [text, x, y - r - 7, lit ? COLORS.gold : role[1], (lit ? 0.9 : 0.62) * fade, true];
          folderLabels.push(() => label(...args, null, hover === n || selected === n || !n.parent));
        }
        // Overview: how much the agent did in this area.
        if (zoom === 'overview' && n.depth === 1) {
          const inside = touched.filter(f => f.rel.startsWith(n.rel + '/'));
          const edited = inside.filter(f => f.edits).length;
          if (inside.length) {
            const text = [edited ? `${edited} edited` : '', inside.length - edited ? `${inside.length - edited} read` : '']
              .filter(Boolean).join(' · ');
            folderLabels.push(() => badge(text, x, y + r + 9, edited ? COLORS.edit : COLORS.read));
          }
        }
      }
    }

    // Touched files: stars, newest labeled.
    const newest = touched.slice().sort((a, b) => b.seq - a.seq);
    const labeled = new Set(newest.slice(0, zoom === 'overview' ? 4 : 16));
    if (hover?.type === 'file' && hover.last) newest.unshift(hover); // its label goes first
    if (selected?.type === 'file' && selected.last) newest.unshift(selected);
    for (const n of new Set(newest)) {
      const [x, y] = toScreen(n.x, n.y);
      if (x < -60 || y < -60 || x > width + 60 || y > height + 60) continue;
      const scale = zoom === 'overview' ? 0.7 : Math.min(1.25, Math.max(0.75, cam.k));
      const r = size(n) * scale;
      const a = glow(n, now) * (inFilter(n) ? 1 : 0.3);
      const hot = now - n.last < 8000;
      const twinkle = hot ? 0.85 + 0.15 * Math.sin(t / 180 + n.seq) : 1;
      sparkle(x, y, r, colorOf(n), a * twinkle, n.seq * 0.37 + (hot ? t / 2400 : 0));
      const change = turnChange(n);
      if (change) {
        ctx.strokeStyle = rgba(colorOf(n), 0.35 * a);
        ctx.lineWidth = 1;
        ctx.beginPath(); ctx.arc(x, y, r * 2 + 3, 0, Math.PI * 2); ctx.stroke();
      }
      if (selected === n) selectionRing(x, y, r);
      if (zoom === 'symbols' && x > 0 && y > 0 && x < width && y < height) drawSymbols(n, x, y, r, a);
      if (labeled.has(n) || hover === n || selected === n) {
        const counts = change ? lineCounts(change) : null;
        label(n.name, x, y + r + 12, colorOf(n), Math.min(1, a + 0.15), false,
              counts && counts.total && zoom !== 'overview' ? [`+${counts.added}`, `−${counts.removed}`] : null,
              hover === n || selected === n);
      }
    }
    // A selected untouched file still gets its ring, label and symbols.
    if (selected?.type === 'dust') {
      const [x, y] = toScreen(selected.x, selected.y);
      selectionRing(x, y, 2);
      if (zoom === 'symbols') drawSymbols(selected, x, y, 2, 0.8);
      label(selected.name, x, y + 14, COLORS.dust, 1, false, null, true);
    }

    folderLabels.forEach(f => f());

    // Shockwaves where something was just touched.
    for (let i = pulses.length - 1; i >= 0; i--) {
      const p = pulses[i];
      const age = (t - p.t) / (p.kind === 'done' ? 1400 : 900);
      if (age >= 1 || !p.node) { pulses.splice(i, 1); continue; }
      const [x, y] = toScreen(p.node.x, p.node.y);
      const color = p.kind === 'done' ? COLORS.gold : p.kind === 'edit' ? COLORS.edit : COLORS.read;
      ctx.strokeStyle = rgba(color, (1 - age) * 0.8);
      ctx.lineWidth = 2 * (1 - age) + 0.5;
      ctx.beginPath(); ctx.arc(x, y, 6 + age * (p.kind === 'done' ? 60 : 28), 0, Math.PI * 2); ctx.stroke();
    }

    // Comets. Their pills sit on top of everything and only avoid each other.
    placed = [];
    const brand = brandColor();
    for (const c of comets.values()) {
      const idle = Date.now() - c.last;
      if (c.key !== 'main' && idle > 25000) { comets.delete(c.key); continue; }
      if (c.target) {
        c.x += (c.target.x - c.x) * 0.09;
        c.y += (c.target.y - c.y) * 0.09;
      }
      c.trail.push([c.x, c.y]);
      if (c.trail.length > 26) c.trail.shift();
      const color = c.color || brand;
      for (let i = 1; i < c.trail.length; i++) {
        const [x1, y1] = toScreen(...c.trail[i - 1]), [x2, y2] = toScreen(...c.trail[i]);
        ctx.strokeStyle = rgba(color, (i / c.trail.length) * 0.7);
        ctx.lineWidth = (i / c.trail.length) * 4;
        ctx.lineCap = 'round';
        ctx.beginPath(); ctx.moveTo(x1, y1); ctx.lineTo(x2, y2); ctx.stroke();
      }
      const [x, y] = toScreen(c.x, c.y);
      const resting = agent.status?.badge !== 'working' && c.key === 'main';
      const beat = resting ? 0.6 : 0.8 + 0.2 * Math.sin(t / 220);
      const halo = ctx.createRadialGradient(x, y, 0, x, y, 16);
      halo.addColorStop(0, rgba(color, 0.7 * beat));
      halo.addColorStop(1, rgba(color, 0));
      ctx.fillStyle = halo;
      ctx.beginPath(); ctx.arc(x, y, 16, 0, Math.PI * 2); ctx.fill();
      ctx.fillStyle = rgba('#ffffff', 0.95);
      ctx.beginPath(); ctx.arc(x, y, 3, 0, Math.PI * 2); ctx.fill();
      ctx.strokeStyle = rgba(color, 0.9);
      ctx.lineWidth = 1.5;
      ctx.beginPath(); ctx.arc(x, y, 6 + (resting ? 0 : 2 * Math.sin(t / 220)), 0, Math.PI * 2); ctx.stroke();
      const name = c.key === 'main' ? agentName() : c.key;
      const text = [c.label || (resting ? 'Idle' : 'Working'), c.detail].filter(Boolean).join(' · ');
      pill(`${name}  ${text}`, x + 12, y - 14, color);
    }
    updateZoomBar(zoom);
  }

  function selectionRing(x, y, r) {
    ctx.strokeStyle = rgba('#ffffff', 0.85);
    ctx.lineWidth = 1.5;
    ctx.setLineDash([2, 3]);
    ctx.beginPath(); ctx.arc(x, y, r * 2 + 8, 0, Math.PI * 2); ctx.stroke();
    ctx.setLineDash([]);
  }

  /** Symbols orbiting a file star when zoomed in; changed ones lit. */
  function drawSymbols(node, x, y, r, a) {
    const list = symbols.get(node.rel);
    if (!list) { loadSymbols(node); return; }
    if (list === 'loading' || !list.length) return;
    const changed = changedSymbols(node, list);
    const shown = list.slice().sort((p, q) => (changed.has(q.name) - changed.has(p.name)) || p.line - q.line).slice(0, 10);
    const radius = r * 2 + 30;
    ctx.font = '500 10px "JetBrains Mono", Menlo, monospace';
    shown.forEach((s, i) => {
      const angle = -Math.PI / 2 + (i / shown.length) * Math.PI * 2;
      const sx = x + Math.cos(angle) * radius * 1.5, sy = y + Math.sin(angle) * radius;
      const lit = changed.has(s.name);
      const color = lit ? COLORS.edit : s.kind === 'class' ? '#e2c08d' : s.kind === 'type' ? '#7fb2e8' : s.kind === 'table' ? '#7fd6c2' : '#b8a3f0';
      ctx.strokeStyle = rgba(color, 0.25 * a);
      ctx.lineWidth = 1;
      ctx.beginPath(); ctx.moveTo(x, y); ctx.lineTo(sx, sy); ctx.stroke();
      ctx.fillStyle = rgba(color, (lit ? 1 : 0.75) * a);
      ctx.beginPath(); ctx.arc(sx, sy, lit ? 3.4 : 2.4, 0, Math.PI * 2); ctx.fill();
      const text = `${s.kind === 'function' ? 'ƒ ' : s.kind === 'class' ? '◆ ' : s.kind === 'table' ? '▦ ' : 'τ '}${s.name}`;
      const w = ctx.measureText(text).width;
      const lx = sx + (Math.cos(angle) >= 0 ? 6 : -w - 6);
      if (free(lx - 2, sy - 7, w + 4, 14) || lit) {
        ctx.fillStyle = 'rgba(11,10,9,0.6)';
        ctx.fillRect(lx - 2, sy - 7, w + 4, 14);
        ctx.fillStyle = rgba(color, (lit ? 1 : 0.85) * a);
        ctx.textAlign = 'left';
        ctx.textBaseline = 'middle';
        ctx.fillText(text, lx, sy);
      }
      symbolSpots.push({ x: sx, y: sy, node, symbol: s });
    });
  }

  function label(text, x, y, color, a, small, stats, force) {
    ctx.font = `${small ? 600 : 500} ${small ? 10 : 11}px "JetBrains Mono", Menlo, monospace`;
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    const w = ctx.measureText(text).width;
    if (!free(x - w / 2 - 3, y - 7, w + 6, stats ? 26 : 14) && !force) return;
    ctx.fillStyle = 'rgba(11,10,9,0.55)';
    ctx.fillRect(x - w / 2 - 3, y - 7, w + 6, 14);
    ctx.fillStyle = rgba(color, a);
    ctx.fillText(text, x, y);
    if (stats) {
      ctx.font = '500 9.5px "JetBrains Mono", Menlo, monospace';
      const [add, del] = stats;
      const aw = ctx.measureText(add).width, dw = ctx.measureText(del).width;
      const sx = x - (aw + dw + 6) / 2;
      ctx.textAlign = 'left';
      ctx.fillStyle = rgba('#7fd99a', a * 0.9); ctx.fillText(add, sx, y + 12);
      ctx.fillStyle = rgba('#f48771', a * 0.9); ctx.fillText(del, sx + aw + 6, y + 12);
    }
  }

  function badge(text, x, y, color) {
    ctx.font = '600 9.5px "JetBrains Mono", Menlo, monospace';
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    const w = ctx.measureText(text).width + 10;
    if (!free(x - w / 2, y - 7, w, 14)) return;
    ctx.fillStyle = rgba(color, 0.18);
    ctx.strokeStyle = rgba(color, 0.6);
    ctx.lineWidth = 1;
    ctx.beginPath(); ctx.roundRect(x - w / 2, y - 7, w, 14, 7); ctx.fill(); ctx.stroke();
    ctx.fillStyle = rgba(color, 0.95);
    ctx.fillText(text, x, y + 0.5);
  }

  function pill(text, x, y, color) {
    ctx.font = '600 10.5px "JetBrains Mono", Menlo, monospace';
    ctx.textAlign = 'left';
    ctx.textBaseline = 'middle';
    const max = Math.max(60, width - x - 10);
    let shown = text;
    while (ctx.measureText(shown).width > max - 14 && shown.length > 4) shown = shown.slice(0, -2);
    if (shown !== text) shown = shown.slice(0, -1) + '…';
    const w = ctx.measureText(shown).width + 14;
    const left = Math.min(x, width - w - 6);
    // Another agent's pill is here already: stack below it.
    for (const dy of [0, 22, -22, 44, -44]) {
      if (free(left, y - 9 + dy, w, 18)) { y += dy; break; }
    }
    ctx.fillStyle = rgba(color, 0.92);
    ctx.beginPath();
    ctx.roundRect(left, y - 9, w, 18, 9);
    ctx.fill();
    ctx.fillStyle = '#0b0a09';
    ctx.fillText(shown, left + 7, y + 0.5);
  }

  // ---------- HUD, legend, zoom bar, tooltip ----------

  function renderHUD() {
    if (!hud) return;
    const touched = [...nodes.values()].filter(n => n.type === 'file' && n.last);
    const edited = touched.filter(n => n.edits).length;
    const files = [...turn.files.values()];
    const added = files.reduce((n, f) => n + lineCounts(f).added, 0);
    const removed = files.reduce((n, f) => n + lineCounts(f).removed, 0);
    hud.replaceChildren();
    const stat = (value, text, cls) => {
      const s = el('span', 'map-stat' + (cls ? ' ' + cls : ''));
      s.append(el('b', null, String(value)), ` ${text}`);
      return s;
    };
    const total = dirRoles.get('')?.files;
    if (total) hud.append(stat(total.toLocaleString(), 'files'));
    if (!touched.length) return;
    hud.append(stat(touched.length, 'visited'));
    if (edited) hud.append(stat(edited, 'edited', 'edit'));
    if (touched.length - edited) hud.append(stat(touched.length - edited, 'read only', 'read'));
    if (files.length) {
      const lines = el('span', 'map-stat lines');
      lines.append(el('span', 'add', `+${added}`), ' ', el('span', 'del', `−${removed}`), ' this turn');
      hud.append(lines);
    }
  }

  function renderLegend() {
    if (!legend) return;
    legend.replaceChildren();
    // Roles present in this project, biggest first; click one to spotlight it.
    const counts = dirRoles.get('')?.counts || {};
    const roles = Object.keys(ROLES).filter(r => counts[r]).sort((a, b) => counts[b] - counts[a]);
    for (const role of roles) {
      const [name, color] = ROLES[role];
      const chip = el('button', 'map-role' + (roleFilter === role ? ' on' : '') + (roleFilter && roleFilter !== role ? ' off' : ''));
      const dot = el('i');
      dot.style.background = color;
      chip.append(dot, name, el('span', 'n', String(counts[role])));
      chip.title = roleFilter === role ? 'Show everything' : `Spotlight ${name.toLowerCase()} (${counts[role]} files)`;
      chip.onclick = (e) => {
        e.stopPropagation();
        roleFilter = roleFilter === role ? null : role;
        renderLegend();
        wake();
        if (!frame) draw(Date.now());
      };
      legend.append(chip);
    }
    if (roles.length) legend.append(el('span', 'map-legend-sep'));
    for (const [color, text] of [[COLORS.edit, 'edited'], [COLORS.created, 'new'], [COLORS.read, 'read']]) {
      const item = el('span', 'map-key');
      const dot = el('i');
      dot.style.background = color;
      item.append(dot, text);
      legend.append(item);
    }
  }

  let shownLevel = null;
  function updateZoomBar(zoom) {
    if (!zoomBar || zoom === shownLevel) return;
    shownLevel = zoom;
    zoomBar.querySelectorAll('button').forEach(b => b.classList.toggle('on', b.dataset.level === zoom));
  }

  function showTip(node, sx, sy, symbol) {
    if (symbol) {
      tip.replaceChildren(el('div', 'map-tip-path', symbol.name),
        el('div', 'map-tip-info', `${symbol.kind} · ${node.rel}:${symbol.line}`),
        el('div', 'map-tip-hint', 'Click to open at this line'));
    } else if (!node || (node.type === 'dir' && !node.parent)) {
      tip.classList.add('hidden');
      return;
    } else {
      const parts = [ROLES[roleFor(node)][0]];
      if (node.type === 'file') {
        const change = turnChange(node);
        const counts = change ? lineCounts(change) : null;
        if (node.edits) parts.push(`edited ${node.edits}×`);
        if (node.reads) parts.push(`read ${node.reads}×`);
        if (counts?.total) parts.push(`+${counts.added} −${counts.removed}`);
        if (node.last) parts.push(ago(node.last));
      } else if (node.type === 'dust') {
        parts.push('not touched yet');
      } else {
        const files = dirRoles.get(node.rel)?.files;
        if (files) parts.push(`${files} file${files === 1 ? '' : 's'}`);
      }
      tip.replaceChildren(el('div', 'map-tip-path', node.rel + (node.type === 'dir' ? '/' : '')),
                          el('div', 'map-tip-info', parts.join(' · ')),
                          el('div', 'map-tip-hint', node.type === 'dir' ? 'Click for details · double-click to zoom in'
                                                                        : 'Click for details · double-click to open'));
    }
    tip.classList.remove('hidden');
    const w = tip.offsetWidth, h = tip.offsetHeight;
    tip.style.left = `${Math.min(width - w - 8, Math.max(8, sx + 14))}px`;
    tip.style.top = `${sy + h + 20 > height ? sy - h - 12 : sy + 14}px`;
  }

  function ago(time) {
    const s = Math.round((Date.now() - time) / 1000);
    if (s < 5) return 'just now';
    if (s < 60) return `${s}s ago`;
    if (s < 3600) return `${Math.round(s / 60)}m ago`;
    return `${Math.round(s / 3600)}h ago`;
  }

  function hit(sx, sy) {
    for (const spot of symbolSpots) if ((spot.x - sx) ** 2 + (spot.y - sy) ** 2 < 64) return { node: spot.node, symbol: spot.symbol };
    let best = null, bestD = 14 * 14;
    const zoom = level();
    for (const n of nodes.values()) {
      if (zoom === 'overview' && n.type === 'dust') continue;
      const [x, y] = toScreen(n.x, n.y);
      const d = (x - sx) ** 2 + (y - sy) ** 2;
      const bias = n.type === 'file' ? 0.6 : n.type === 'dir' ? 0.9 : 1.2;
      if (d * bias < bestD) { best = n; bestD = d * bias; }
    }
    return best ? { node: best } : null;
  }

  // ---------- Details sidebar ----------

  let sideTimer = 0;
  function renderSideSoon() {
    clearTimeout(sideTimer);
    sideTimer = setTimeout(renderSide, 250);
  }

  function select(node) {
    selected = node;
    if (node && node.type !== 'dir') { loadLinks(node); loadSymbols(node); }
    renderSide();
    requestAnimationFrame(resize);
    wake();
  }

  function section(title, count) {
    const s = el('div', 'side-section');
    const h = el('div', 'side-title', title);
    if (count != null) h.append(el('span', 'side-count', String(count)));
    s.append(h);
    return s;
  }

  function fileRow(rel, extra) {
    const row = el('div', 'side-row link');
    const node = nodes.get(rel);
    row.append(iconEl(rel.split('/').pop()), el('span', 'side-name', rel.split('/').pop()));
    const dir = rel.includes('/') ? rel.slice(0, rel.lastIndexOf('/')) : '';
    if (dir) row.append(el('span', 'side-dim', dir));
    if (extra) row.append(extra);
    if (node?.last) row.classList.add(node.edits ? 'edited' : 'read');
    row.title = `${rel}\nClick to select · double-click to open`;
    row.onclick = () => { const n = nodes.get(rel) || ensure(rel, 'dust'); if (n) { focusOn(n); select(n); } };
    row.ondblclick = () => state.root && openPicked(`${state.root}/${rel}`, null);
    return row;
  }

  function lineStats(change) {
    const c = lineCounts(change);
    const x = el('span', 'side-dim');
    x.append(el('span', 'add', `+${c.added}`), ' ', el('span', 'del', `−${c.removed}`));
    return x;
  }

  const focusOn = (node) => zoomTo(Math.max(cam.k, 1.1), node.x, node.y);

  async function renderSide() {
    if (!side) return;
    const node = selected;
    side.classList.toggle('open', !!node);
    if (!node) { side.replaceChildren(); return; }
    const role = roleFor(node);
    const [roleName, roleColor, roleIcon] = ROLES[role];
    const head = el('div', 'side-head');
    const title = el('div', 'side-heading');
    const icon = node.type === 'dir' ? el('i', 'codicon codicon-folder') : iconEl(node.name);
    title.append(icon, el('span', 'side-file', node.type === 'dir' && node.parent ? `${node.name}/` : node.name));
    const close = el('i', 'codicon codicon-close side-close');
    close.title = 'Close (Esc)';
    close.onclick = () => select(null);
    title.append(close);
    head.append(title);
    if (node.rel) head.append(el('div', 'side-path', node.rel));
    const chips = el('div', 'side-chips');
    const roleChip = el('span', 'side-chip');
    roleChip.style.setProperty('--c', roleColor);
    roleChip.append(el('i', `codicon codicon-${roleIcon}`), roleName);
    chips.append(roleChip);
    const change = node.type !== 'dir' ? turnChange(node) : null;
    if (change?.created || node.created) chips.append(el('span', 'side-chip new', 'New file'));
    else if (change) chips.append(el('span', 'side-chip edit', 'Changed this turn'));
    head.append(chips);
    const body = el('div', 'side-body');
    const parts = [head];

    if (node.type !== 'dir') {
      const actions = el('div', 'side-actions');
      const abs = absOf(node);
      const open = el('button', 'side-btn primary');
      open.append(el('i', 'codicon codicon-go-to-file'), 'Open');
      open.onclick = () => abs && openPicked(abs, null);
      actions.append(open);
      if (change && !change.deleted) {
        const replay = el('button', 'side-btn');
        replay.append(el('i', 'codicon codicon-history'), 'Replay change');
        replay.onclick = () => openPicked(abs, change);
        actions.append(replay);
      }
      parts.push(actions);

      // What the agent did here.
      const activity = section('Agent activity');
      if (node.last) {
        const bits = [];
        if (node.edits) bits.push(`Edited ${node.edits}×`);
        if (node.reads) bits.push(`${node.edits ? 'read' : 'Read'} ${node.reads}×`);
        bits.push(ago(node.last));
        activity.append(el('div', 'side-text', bits.join(' · ')));
        if (node.agents.size) activity.append(el('div', 'side-dim-text', `By ${[...node.agents].join(', ')}`));
      } else {
        activity.append(el('div', 'side-dim-text', 'Not touched by the agent this session.'));
      }
      body.append(activity);

      // This turn's change, as a small diff.
      if (change && !change.deleted) {
        const counts = lineCounts(change);
        const s = section('This turn');
        const stat = el('div', 'side-text');
        const places = (change.hunks || []).length;
        stat.append(el('span', 'add', `+${counts.added}`), ' ', el('span', 'del', `−${counts.removed}`),
                    ` in ${places} place${places === 1 ? '' : 's'}`);
        s.append(stat);
        const text = await textOf(node);
        if (selected !== node) return;
        const lines = text ? text.split('\n') : [];
        const diff = el('div', 'side-diff');
        let shown = 0;
        for (const h of change.hunks || []) {
          if (shown > 16) break;
          diff.append(el('div', 'hunk', `@@ line ${h.start}`));
          for (const r of (h.removed || []).slice(0, 4)) { diff.append(el('div', 'del', r || ' ')); shown++; }
          for (const a of lines.slice(h.start - 1, h.start - 1 + Math.min(h.count, 6))) { diff.append(el('div', 'add', a || ' ')); shown++; }
          if (h.count > 6) diff.append(el('div', 'more', `… ${h.count - 6} more added`));
        }
        s.append(diff);
        body.append(s);
      }

      // Symbols, changed ones first.
      const list = symbols.get(node.rel);
      if (Array.isArray(list) && list.length) {
        const changed = changedSymbols(node, list);
        const s = section('Symbols', list.length);
        const sorted = list.slice().sort((p, q) => (changed.has(q.name) - changed.has(p.name)) || p.line - q.line);
        for (const sym of sorted.slice(0, 14)) {
          const row = el('div', 'side-row link' + (changed.has(sym.name) ? ' edited' : ''));
          const kind = { class: 'class', type: 'interface', table: 'structure' }[sym.kind] || 'method';
          row.append(el('i', `codicon codicon-symbol-${kind}`), el('span', 'side-name', sym.name), el('span', 'side-dim', `:${sym.line}`));
          if (changed.has(sym.name)) row.append(el('span', 'side-flag', 'changed'));
          row.onclick = () => abs && openPickedAt(abs, sym.line);
          s.append(row);
        }
        if (sorted.length > 14) s.append(el('div', 'side-dim-text', `+${sorted.length - 14} more`));
        body.append(s);
      }

      // Blast radius.
      const link = links.get(node.rel);
      if (link) {
        const s = section('Imported by', link.loading ? '…' : link.importers.length);
        if (link.loading) s.append(el('div', 'side-dim-text', 'Searching the project…'));
        else if (!link.importers.length) s.append(el('div', 'side-dim-text', 'Nothing in the project imports this file.'));
        else {
          const tests = link.importers.filter(i => roleOf(i.rel) === 'tests');
          const note = el('div', 'side-note');
          note.textContent = `${change ? 'This change can affect' : 'Changing this affects'} ${link.importers.length} file${link.importers.length === 1 ? '' : 's'}`
            + (tests.length ? `; ${tests.length} test${tests.length === 1 ? '' : 's'} cover${tests.length === 1 ? 's' : ''} it.` : '; no tests import it.');
          s.append(note);
          link.importers.slice(0, 12).forEach(i => s.append(fileRow(i.rel, null)));
          if (link.importers.length > 12) s.append(el('div', 'side-dim-text', `+${link.importers.length - 12} more`));
        }
        body.append(s);
        const s2 = section('Imports', link.loading ? '…' : link.imports.length);
        if (!link.loading && !link.imports.length) s2.append(el('div', 'side-dim-text', 'No project files (packages only).'));
        link.imports.slice(0, 12).forEach(rel => s2.append(fileRow(rel, null)));
        body.append(s2);
      }

      // Backend pieces this file talks to (from the Backend tab's index).
      const backend = window.backend?.linksFor(node.rel) || [];
      if (backend.length) {
        const s = section('Backend', backend.length);
        for (const b of backend.slice(0, 10)) {
          const row = el('div', 'side-row link');
          row.append(el('i', `codicon codicon-${b.icon || 'database'}`), el('span', 'side-name', b.label), el('span', 'side-dim', b.kind));
          if (b.line) row.append(el('span', 'side-dim', `:${b.line}`));
          row.title = 'Show in the Backend tab';
          row.onclick = () => window.backend?.reveal(b.id);
          s.append(row);
        }
        body.append(s);
      }
    } else {
      // A folder: its makeup and what happened inside.
      const entry = dirRoles.get(node.rel);
      if (node.parent) {
        const actions = el('div', 'side-actions');
        const zoom = el('button', 'side-btn primary');
        zoom.append(el('i', 'codicon codicon-zoom-in'), 'Zoom in');
        zoom.onclick = () => zoomTo(Math.max(1.8, cam.k * 1.8), node.x, node.y);
        actions.append(zoom);
        parts.push(actions);
      }
      if (entry) {
        const s = section('Inside', entry.files);
        const bar = el('div', 'side-bar');
        const roles = Object.entries(entry.counts).sort((a, b) => b[1] - a[1]);
        for (const [r, n] of roles) {
          const seg = el('span');
          seg.style.flex = String(n);
          seg.style.background = ROLES[r][1];
          seg.title = `${ROLES[r][0]}: ${n}`;
          bar.append(seg);
        }
        s.append(bar);
        const keys = el('div', 'side-keys');
        for (const [r, n] of roles.slice(0, 6)) {
          const k = el('span');
          const dot = el('i');
          dot.style.background = ROLES[r][1];
          k.append(dot, `${ROLES[r][0]} ${n}`);
          keys.append(k);
        }
        s.append(keys);
        body.append(s);
      }
      const prefix = node.rel ? node.rel + '/' : '';
      const inside = [...nodes.values()].filter(n => n.type === 'file' && n.last && n.rel.startsWith(prefix))
        .sort((a, b) => b.seq - a.seq);
      const s = section('Agent touched here', inside.length);
      if (!inside.length) s.append(el('div', 'side-dim-text', 'Nothing yet.'));
      inside.slice(0, 14).forEach(n => {
        const c = turnChange(n);
        s.append(fileRow(n.rel, c ? lineStats(c) : null));
      });
      body.append(s);
      const subs = [...dirRoles.entries()].filter(([d]) => d.startsWith(prefix) && d !== node.rel && depthOf(d) === node.depth + 1)
        .sort((a, b) => b[1].files - a[1].files);
      if (subs.length) {
        const s2 = section('Folders', subs.length);
        subs.slice(0, 10).forEach(([d, e]) => {
          const row = el('div', 'side-row link');
          const dot = el('i', 'side-dot');
          dot.style.background = ROLES[e.role][1];
          row.append(dot, el('span', 'side-name', d.split('/').pop() + '/'), el('span', 'side-dim', `${e.files} files`));
          row.onclick = () => { const n = ensure(d, 'dir'); focusOn(n); select(n); };
          s2.append(row);
        });
        body.append(s2);
      }
    }
    if (selected !== node) return;
    parts.push(body);
    const scroll = side.querySelector('.side-body')?.scrollTop || 0;
    side.replaceChildren(...parts);
    body.scrollTop = scroll;
  }

  // ---------- Loop ----------

  const visible = () => mode === 'map' && panelVisible && !document.hidden && !$('agent').classList.contains('collapsed');

  function needsMotion() {
    if (alpha > 0 || pulses.length) return true;
    if (agent.status?.badge === 'working') return true;
    const link = selected && links.get(selected.rel);
    if (link && (link.imports.length || link.importers.length)) return true; // the flowing link lines
    if (Math.abs(cam.x - cam.tx) + Math.abs(cam.y - cam.ty) > 0.5 || Math.abs(cam.k - cam.tk) + Math.abs(cam.s - cam.ts) > 0.002) return true;
    const now = Date.now();
    for (const c of comets.values()) {
      if (c.target && Math.abs(c.target.x - c.x) + Math.abs(c.target.y - c.y) > 0.5) return true;
      if (c.trail.length && now - c.last < 3000) return true;
    }
    for (const n of nodes.values()) if (n.last && now - n.last < 8000) return true;
    return false;
  }

  function tick(time) {
    frame = 0;
    if (!visible()) return;
    // ~40 fps is plenty, and leaves the terminal alone.
    if (time - lastDraw < 24) { frame = requestAnimationFrame(tick); return; }
    lastDraw = time;
    if (alpha > 0) simulate();
    if (cam.auto && performance.now() - lastInteract > 400) fit();
    cam.x += (cam.tx - cam.x) * 0.12;
    cam.y += (cam.ty - cam.y) * 0.12;
    cam.k += (cam.tk - cam.k) * 0.12;
    cam.s += (cam.ts - cam.s) * 0.12;
    draw(Date.now());
    if (needsMotion()) frame = requestAnimationFrame(tick);
  }

  function wake() {
    if (!canvas || frame || !visible()) return;
    frame = requestAnimationFrame(tick);
  }

  // A slow heartbeat so stars cool and the HUD stays fresh without a running loop.
  setInterval(() => { if (visible()) { renderHUD(); wake(); draw(Date.now()); } }, 15000);

  // ---------- Building the view ----------

  function resize() {
    if (!stage) return;
    const rect = stage.getBoundingClientRect();
    width = rect.width; height = rect.height;
    dpr = window.devicePixelRatio || 2;
    canvas.width = Math.round(width * dpr);
    canvas.height = Math.round(height * dpr);
    canvas.style.width = `${width}px`;
    canvas.style.height = `${height}px`;
    if (cam.auto) { fit(); cam.x = cam.tx; cam.y = cam.ty; cam.k = cam.tk; cam.s = cam.ts; }
    if (width && height && visible()) draw(Date.now());
    wake();
  }

  function setMode(next) {
    mode = next;
    try { localStorage.setItem('agentPanelMode', mode); } catch {}
    $('agent').classList.toggle('map-mode', mode === 'map');
    $('agent').classList.toggle('backend-mode', mode === 'backend');
    document.querySelectorAll('.agent-mode button').forEach(b => b.classList.toggle('on', b.dataset.mode === mode));
    // The map and the backend need room: open the panel to at least half the editor.
    if (mode !== 'log' && !$('agent').classList.contains('collapsed')) {
      const part = $('editor-part').offsetHeight;
      if (part && $('agent').offsetHeight < part * 0.45) document.documentElement.style.setProperty('--agent-h', `${Math.round(part * 0.52)}px`);
    }
    if (mode === 'map') { loadFiles(); requestAnimationFrame(resize); }
    else if (frame) { cancelAnimationFrame(frame); frame = 0; }
    window.backend?.shown(mode === 'backend');
  }

  function build() {
    // Code / Backend / Log switch in the panel header.
    const switcher = el('div', 'agent-mode');
    for (const [m, icon, name, title] of [
      ['map', 'type-hierarchy', 'Code', 'Code map: the project and where the agent has been'],
      ['backend', 'server-environment', 'Backend', 'Backend: databases, workers, deploys and services'],
      ['log', 'list-flat', 'Log', 'Activity log'],
    ]) {
      const b = el('button');
      b.dataset.mode = m;
      b.title = title;
      b.append(el('i', `codicon codicon-${icon}`), name);
      b.onclick = () => setMode(m);
      switcher.append(b);
    }
    $('agent-name').after(switcher);

    wrap = el('div');
    wrap.id = 'agent-map';
    stage = el('div', 'map-stage');
    canvas = el('canvas');
    ctx = canvas.getContext('2d');
    hud = el('div', 'map-hud');
    tip = el('div', 'map-tip hidden');
    empty = el('div', 'map-empty');
    fitBtn = el('button', 'map-fit hidden');
    fitBtn.append(el('i', 'codicon codicon-screen-full'), 'Fit');
    fitBtn.title = 'Fit everything in view (double-click empty space)';
    legend = el('div', 'map-legend');
    zoomBar = el('div', 'map-zoom');
    const zoomTips = {
      overview: 'The project’s areas and where the work is',
      files: 'Every file',
      symbols: 'Functions and classes inside files, with changed ones lit',
    };
    for (const [key, name, k] of LEVELS) {
      const b = el('button', null, name);
      b.dataset.level = key;
      b.title = zoomTips[key];
      b.onclick = () => {
        if (key === 'overview') {
          forcedLevel = 'overview';
          cam.auto = true;
          fitBtn.classList.add('hidden');
          wake();
          if (!frame) draw(Date.now());
          return;
        }
        forcedLevel = null;
        if (key === 'files' && !selected) { cam.auto = true; fitBtn.classList.add('hidden'); wake(); return; }
        const target = selected || [...nodes.values()].filter(n => n.last).sort((p, q) => q.seq - p.seq)[0];
        zoomTo(k, target?.x ?? cam.tx, target?.y ?? cam.ty);
      };
      zoomBar.append(b);
    }
    const tools = el('div', 'map-tools');
    tools.append(zoomBar, fitBtn);
    stage.append(canvas, hud, legend, tools, empty, tip);
    side = el('div', 'map-side');
    wrap.append(stage, side);
    $('agent-feed').before(wrap);

    const autoFit = () => { cam.auto = true; fitBtn.classList.add('hidden'); wake(); };
    fitBtn.onclick = autoFit;

    let drag = null;
    const point = (e) => { const r = canvas.getBoundingClientRect(); return [e.clientX - r.left, e.clientY - r.top]; };
    canvas.addEventListener('mousedown', (e) => { drag = { x: e.clientX, y: e.clientY, moved: false }; });
    addEventListener('mousemove', (e) => {
      if (!drag) return;
      const dx = e.clientX - drag.x, dy = e.clientY - drag.y;
      if (drag.moved || Math.abs(dx) + Math.abs(dy) > 6) {
        drag.moved = true;
        cam.auto = false; fitBtn.classList.remove('hidden');
        cam.tx -= dx / (cam.k * cam.s); cam.ty -= dy / cam.k;
        cam.x = cam.tx; cam.y = cam.ty;
        drag.x = e.clientX; drag.y = e.clientY;
        lastInteract = performance.now();
        tip.classList.add('hidden');
        wake();
      }
    });
    addEventListener('mouseup', () => { setTimeout(() => { drag = null; }); });
    canvas.addEventListener('mousemove', (e) => {
      if (drag?.moved) return;
      const [sx, sy] = point(e);
      const found = hit(sx, sy);
      const node = found?.node || null;
      if (node !== hover) { hover = node; wake(); if (!frame) draw(Date.now()); }
      canvas.style.cursor = found ? 'pointer' : 'grab';
      showTip(node, sx, sy, found?.symbol);
    });
    canvas.addEventListener('mouseleave', () => { hover = null; tip.classList.add('hidden'); wake(); if (!frame) draw(Date.now()); });
    canvas.addEventListener('click', (e) => {
      if (drag?.moved) return;
      const found = hit(...point(e));
      if (!found) { if (selected) select(null); return; }
      if (found.symbol) { const abs = absOf(found.node); if (abs) openPickedAt(abs, found.symbol.line); return; }
      select(found.node === selected ? null : found.node);
    });
    canvas.addEventListener('dblclick', (e) => {
      const found = hit(...point(e));
      if (!found) { autoFit(); return; }
      const node = found.node;
      if (node.type === 'dir') { zoomTo(Math.max(1.8, cam.k * 1.8), node.x, node.y); return; }
      const abs = absOf(node);
      if (abs) openPicked(abs, null);
    });
    canvas.addEventListener('wheel', (e) => {
      e.preventDefault();
      const [sx, sy] = point(e);
      const [wx, wy] = toWorld(sx, sy);
      const k = Math.max(0.2, Math.min(5, cam.k * Math.exp(-e.deltaY * 0.0022)));
      cam.k = cam.tk = k;
      forcedLevel = null;
      // Keep the point under the cursor fixed.
      cam.x = cam.tx = wx - (sx - width / 2) / (k * cam.s);
      cam.y = cam.ty = wy - (sy - height / 2) / k;
      cam.auto = false; fitBtn.classList.remove('hidden');
      lastInteract = performance.now();
      wake();
    }, { passive: false });
    addEventListener('keydown', (e) => {
      if (e.key === 'Escape' && selected && mode === 'map' && !editor?.hasTextFocus()) select(null);
    });

    new ResizeObserver(resize).observe(stage);
    document.addEventListener('visibilitychange', wake);
    let saved = 'map';
    try { saved = localStorage.getItem('agentPanelMode') || 'map'; } catch {}
    reset();
    setMode(['log', 'backend'].includes(saved) ? saved : 'map');
    updateEmpty();
  }

  function updateEmpty() {
    if (!empty) return;
    const anything = [...nodes.values()].some(n => n.type === 'file' && n.last);
    empty.classList.toggle('hidden', anything);
    if (anything) return;
    const name = agent.status ? agentName() : 'your agent';
    empty.textContent = agent.status
      ? `Waiting for ${name} to move. Every file it reads or edits lights up here.`
      : 'Run claude or codex in this terminal. Every file it reads or edits lights up here as a star.';
  }

  // ---------- Hooks from app.js ----------

  window.starmap = {
    items(items, resetAll) {
      if (resetAll) {
        const keep = filesLoaded;
        const was = selected?.rel;
        reset();
        if (keep && visible()) loadFiles();
        if (was != null && nodes.has(was)) select(nodes.get(was));
      }
      for (const item of items) agentItem(item, resetAll);
      if (resetAll) {
        // Opened mid-session: park the comet on the latest file.
        const last = [...nodes.values()].filter(n => n.last).sort((a, b) => b.seq - a.seq)[0];
        if (last) { const c = comet('main'); c.x = last.x; c.y = last.y; c.target = last; c.label = ''; }
      }
      renderHUD();
      updateEmpty();
      wake();
    },
    change(change) {
      if (change.deleted) return;
      const node = touch(change.path, 'edit', { created: change.created });
      if (node) { contents.delete(node.rel); links.delete(node.rel); }
      if (node && selected === node) { loadLinks(node); loadSymbols(node); }
      const c = comet('main');
      if (node && Date.now() - c.last > 1500) { c.target = node; c.label = 'Editing'; c.detail = node.name; c.last = Date.now(); }
      if (change.created && state.files && node && !state.files.includes(node.rel)) {
        state.files.push(node.rel);
        indexRoles(state.files);
      }
      window.backend?.agentTouched(change.path, 'edit');
      renderHUD();
      updateEmpty();
    },
    turnChanged() { renderHUD(); wake(); if (selected) renderSideSoon(); },
    status(s) { status(s); updateEmpty(); },
    // Wait a moment: a page that's about to be hidden (a background tab's) never needs it.
    folder() { reset(); setTimeout(() => { if (visible()) loadFiles(); }, 1200); renderHUD(); updateEmpty(); wake(); window.backend?.folder(); },
    visible() { if (mode === 'map') { loadFiles(); requestAnimationFrame(resize); } window.backend?.shown(mode === 'backend'); },
    /** Selects a project file on the map (from the Backend tab's code links). */
    reveal(rel, { zoom = true } = {}) {
      setMode('map');
      const node = nodes.get(rel) || ensure(rel, 'dust');
      if (node) { if (zoom) focusOn(node); select(node); }
    },
    roleOf,
    /** Runs the layout to rest and frames it, at once (for screenshots and tests). */
    settle(ticks = 600) {
      alpha = Math.max(alpha, 1);
      for (let i = 0; i < ticks && alpha > 0; i++) simulate();
      if (cam.auto) fit();
      cam.x = cam.tx; cam.y = cam.ty; cam.k = cam.tk; cam.s = cam.ts;
      if (visible()) draw(Date.now());
    },
  };

  build();
})();
