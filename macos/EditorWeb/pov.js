// AI POV: the agent's work replayed on a virtual workstation, as if you were at the keyboard.
//
// Every step comes from the agent's real session (its transcript and the files on disk):
//   - reads open the real file in a real editor and walk the cursor over the lines read;
//   - edits start from the file as it was, select and delete the old code, and type the new
//     code keystroke by keystroke, ending exactly as the file is now on disk;
//   - commands are typed into a terminal and print their real output (scrollback kept);
//   - searches type the query, list the real results and open the file with matches lit;
//   - web visits type the URL and load the actual page in a real (native) browser;
//   - thoughts and replies appear in a chat pane; plans show as a live todo list.
// A pixel pointer moves and clicks between them. Uses helpers from app.js.

(() => {
  const SPRITES = {
    claude: [['..oooooooo..', '..okooooko..', 'oooooooooooo', 'oooooooooooo', '..oooooooo..', '..o.o..o.o..'], { o: '#d97757', k: '#0b0a09' }],
    codex: [['...oooo...', '.oo....oo.', 'o..oooo..o', 'o.o....o.o', 'o.o.cc.o.o', 'o.o....o.o', 'o..oooo..o', '.oo....oo.', '...oooo...'], { o: '#d8cfbf', c: '#78dceb' }],
    other: [['..oooooo..', '.o......o.', '.o.cc.c.o.', '.o......o.', '..oooooo..', '..o....o..'], { o: '#967446', c: '#78dceb' }],
  };
  const POINTER = [
    'k.........', 'kk........', 'kwk.......', 'kwwk......', 'kwwwk.....', 'kwwwwk....', 'kwwwwwk...', 'kwwwwwwk..',
    'kwwwwwwwk.', 'kwwwwkkkkk', 'kwwkwk....', 'kwk.kwk...', 'kk..kwk...', 'k....kwk..', '.....kwk..', '......kk..',
  ];
  const KIND = {
    prompt: ['YOU ASKED', '--x-gold'], thinking: ['THINKING', '--x-think'], message: ['REPLYING', '--x-text'],
    read: ['READING', '--x-read'], edit: ['EDITING', '--x-edit'], write: ['WRITING', '--x-live'], run: ['RUNNING', '--x-run'],
    search: ['SEARCHING', '--x-search'], web: ['BROWSING', '--x-web'], agent: ['SUB-AGENT', '--x-agent'],
    todo: ['PLANNING', '--x-gold'], other: ['USING A TOOL', '--x-muted'], disk: ['EDITING', '--x-edit'],
  };
  const APPS = [['editor', 'EDITOR'], ['terminal', 'TERMINAL'], ['browser', 'BROWSER'], ['search', 'SEARCH'], ['chat', 'CHAT']];

  const state = {
    on: false, steps: [], byId: new Map(), queue: [], playing: null, busy: false,
    files: new Map(), live: true, replayTimer: null, token: 0, app: null,
  };
  let speed = 1;
  /** True when far enough behind the agent that animations are skipped. */
  let hurry = false;
  const wait = (ms) => new Promise(r => setTimeout(r, hurry ? Math.min(ms / speed, 60) : ms / speed));
  /** How long ago the step happened, i.e. how far behind the replay is. */
  const lagOf = (step) => Date.now() - step.time;
  /** Files larger than this open as the region around what the agent touched. */
  const BIG_FILE = 250_000;

  // ---------- Pixel drawing ----------

  function bitmap(rows, colors, px) {
    const canvas = document.createElement('canvas');
    const w = Math.max(...rows.map(r => r.length));
    const scale = window.devicePixelRatio || 2;
    canvas.width = w * px * scale; canvas.height = rows.length * px * scale;
    canvas.style.width = `${w * px}px`; canvas.style.height = `${rows.length * px}px`;
    canvas.className = 'pov-bitmap';
    const g = canvas.getContext('2d');
    g.scale(scale, scale);
    rows.forEach((row, y) => [...row].forEach((c, x) => {
      if (c === '.' || !colors[c]) return;
      g.fillStyle = colors[c];
      g.fillRect(x * px, y * px, px, px);
    }));
    return canvas;
  }
  const sprite = (kind, px = 2) => { const [rows, colors] = SPRITES[kind] || SPRITES.other; return bitmap(rows, colors, px); };

  // ---------- The workstation ----------

  let stage, body, apps = {}, appTabs = {}, pointer, headSprite, headLabel, headDetail, ffBadge, stepCounter, liveBtn;
  let rail, railCount, todoBox, waitBanner, timeline;
  let povEditor = null, editorTitle, editorView, findDecorations = null;
  let term, termLines, searchBox, searchQuery, searchResults, chatLog, browserBar, browserURL, browserView, browserProgress;

  function build() {
    stage = el('div', 'pov hidden');
    stage.id = 'pov';

    const head = el('div', 'pov-head');
    headSprite = el('span', 'pov-head-sprite');
    headLabel = el('span', 'pov-head-label', 'WAITING FOR THE AGENT');
    headDetail = el('span', 'pov-head-detail', '');
    ffBadge = el('span', 'pov-ff hidden', '▸▸ CATCHING UP');
    stepCounter = el('span', 'pov-counter', '');
    liveBtn = el('span', 'pov-live', '● LIVE');
    liveBtn.onclick = () => goLive();
    head.append(headSprite, headLabel, headDetail, ffBadge, el('span', 'pov-spacer'), stepCounter, liveBtn);

    body = el('div', 'pov-body');

    // Left: the files the agent has touched (its "explorer"), and its plan.
    const side = el('div', 'pov-side');
    const railHead = el('div', 'pov-side-head');
    railCount = el('span', 'pov-side-count', '0');
    railHead.append(el('span', null, 'FILES'), el('span', 'pov-rule'), railCount);
    rail = el('div', 'pov-rail');
    todoBox = el('div', 'pov-plan-wrap hidden');
    side.append(railHead, rail, todoBox);

    // Right: the screen with its apps.
    const screen = el('div', 'pov-screen');
    const tabs = el('div', 'pov-apps');
    for (const [key, label] of APPS) {
      const tab = el('span', 'pov-app-tab', label);
      tab.dataset.app = key;
      tabs.append(tab);
      appTabs[key] = tab;
    }
    const views = el('div', 'pov-views');
    apps.editor = buildEditor();
    apps.terminal = buildTerminal();
    apps.browser = buildBrowser();
    apps.search = buildSearch();
    apps.chat = buildChat();
    for (const [key] of APPS) { apps[key].classList.add('pov-app'); views.append(apps[key]); }
    screen.append(tabs, views);

    pointer = el('div', 'pov-pointer');
    pointer.append(bitmap(POINTER, { k: '#0b0a09', w: '#f4ead2' }, 1.5));
    body.append(side, screen, pointer);

    waitBanner = el('div', 'pov-wait hidden');
    timeline = el('div', 'pov-timeline');
    stage.append(head, body, waitBanner, timeline);
    $('editor-part').append(stage);
    showApp('chat', { instant: true });
    new ResizeObserver(() => syncBrowser()).observe(stage);
  }

  function buildEditor() {
    const view = el('div', 'pov-editor');
    editorTitle = el('div', 'pov-editor-tab', 'no file open');
    editorView = el('div', 'pov-editor-view');
    view.append(editorTitle, editorView);
    return view;
  }

  function ensureEditor() {
    if (povEditor || !monacoRef) return povEditor;
    povEditor = monacoRef.editor.create(editorView, {
      model: null, readOnly: true, domReadOnly: true, automaticLayout: true,
      fontFamily: editor?.getOption(monacoRef.editor.EditorOption.fontFamily),
      fontSize: 13, lineHeight: 21, minimap: { enabled: false }, scrollBeyondLastLine: false,
      renderLineHighlight: 'all', cursorBlinking: 'solid', cursorStyle: 'line', cursorWidth: 2,
      smoothScrolling: true, stickyScroll: { enabled: false }, contextmenu: false, padding: { top: 8 },
      scrollbar: { verticalScrollbarSize: 6, horizontalScrollbarSize: 6 },
    });
    return povEditor;
  }

  function buildTerminal() {
    const view = el('div', 'pov-terminal');
    term = el('div', 'pov-term-screen');
    termLines = el('div', 'pov-term-lines');
    term.append(termLines);
    view.append(term);
    return view;
  }

  function buildBrowser() {
    const view = el('div', 'pov-browser-app');
    browserBar = el('div', 'pov-urlbar');
    browserURL = el('span', 'pov-url', '');
    browserBar.append(el('span', 'pov-nav', '‹  ›  ⟳'), browserURL);
    browserProgress = el('div', 'pov-progress done');
    browserView = el('div', 'pov-browser-view');
    browserView.append(el('div', 'pov-browser-empty', 'Pages the agent visits load here.'));
    view.append(browserBar, browserProgress, browserView);
    return view;
  }

  function buildSearch() {
    const view = el('div', 'pov-search');
    searchBox = el('div', 'pov-search-box');
    searchQuery = el('span', 'pov-search-q');
    searchBox.append(el('span', 'pov-search-icon', '⌕'), searchQuery);
    searchResults = el('div', 'pov-search-results');
    view.append(searchBox, searchResults);
    return view;
  }

  function buildChat() {
    const view = el('div', 'pov-chat');
    chatLog = el('div', 'pov-chat-log');
    chatLog.append(el('div', 'pov-chat-empty', 'The agent\'s thoughts and replies appear here as it works.'));
    view.append(chatLog);
    return view;
  }

  // ---------- Pointer and apps ----------

  /** Glides the pointer to an element (in steps, like a pixel sprite), optionally clicking. */
  async function pointAt(target, { click = false, dx = 12, dy = 10 } = {}) {
    if (!target || !body) return;
    const b = body.getBoundingClientRect(), r = target.getBoundingClientRect();
    const x = Math.max(0, Math.min(r.left - b.left + dx, b.width - 20));
    const y = Math.max(0, Math.min(r.top - b.top + dy, b.height - 20));
    pointer.classList.toggle('jump', hurry || speed > 2);
    pointer.style.transform = `translate(${x}px, ${y}px)`;
    pointer.classList.add('show');
    if (hurry) return;
    await wait(300);
    if (click) {
      pointer.classList.remove('click'); void pointer.offsetWidth; pointer.classList.add('click');
      await wait(140);
    }
  }

  async function showApp(key, { instant = false } = {}) {
    if (state.app === key) return;
    if (!instant) await pointAt(appTabs[key], { click: true, dx: 20, dy: 8 });
    state.app = key;
    for (const [name] of APPS) {
      apps[name].classList.toggle('active', name === key);
      appTabs[name].classList.toggle('active', name === key);
    }
    if (key === 'editor') povEditor?.layout();
    syncBrowser();
  }

  /** Lays the native browser over the browser pane (or hides it). */
  function syncBrowser(url) {
    if (!browserView) return;
    const visible = state.on && state.app === 'browser' && browserView.dataset.loaded === '1';
    if (!visible) { fs('browser', { hide: true }).catch(() => {}); return; }
    const r = browserView.getBoundingClientRect();
    fs('browser', { x: r.left, y: r.top, w: r.width, h: r.height, url: url || browserView.dataset.url }).catch(() => {});
  }

  // ---------- Typing ----------

  /** Types text into a DOM node a few characters per frame. */
  function typeText(node, text, { cps = 80, token } = {}) {
    return new Promise(resolve => {
      const total = text.length;
      node.textContent = '';
      if (!total) return resolve();
      if (hurry) { node.textContent = text; return resolve(); }
      const start = performance.now();
      const caret = el('span', 'pov-caret');
      const content = document.createTextNode('');
      node.append(content, caret);
      const tick = (now) => {
        if (token !== state.token) { content.data = text; caret.remove(); return resolve(); }
        const n = Math.min(total, Math.floor((now - start) / 1000 * cps * speed) + 1);
        content.data = text.slice(0, n);
        if (n < total) requestAnimationFrame(tick);
        else { caret.remove(); resolve(); }
      };
      requestAnimationFrame(tick);
    });
  }

  /** Types `text` into the editor at `position`, keystroke by keystroke; returns the end. */
  async function typeInEditor(model, position, text, token) {
    const instance = ensureEditor();
    // Long insertions type the start, then the rest appears as a paste would; when behind,
    // it all appears at once.
    const typed = hurry ? '' : text.length > 700 ? text.slice(0, 400) : text;
    let pos = position;
    const cps = 220 * speed;
    const started = performance.now();
    let done = 0;
    while (done < typed.length) {
      if (token !== state.token) break;
      await new Promise(requestAnimationFrame);
      const target = Math.min(typed.length, Math.floor((performance.now() - started) / 1000 * cps) + 1);
      const chunk = typed.slice(done, target);
      if (!chunk) continue;
      model.applyEdits([{ range: new monacoRef.Range(pos.lineNumber, pos.column, pos.lineNumber, pos.column), text: chunk }]);
      pos = model.modifyPosition(pos, chunk.length);
      instance.setPosition(pos);
      instance.revealPositionInCenterIfOutsideViewport(pos);
      done = target;
    }
    const rest = text.slice(done);
    if (rest) {
      model.applyEdits([{ range: new monacoRef.Range(pos.lineNumber, pos.column, pos.lineNumber, pos.column), text: rest }]);
      pos = model.modifyPosition(pos, rest.length);
      instance.setPosition(pos);
    }
    return pos;
  }

  // ---------- Files (the agent's explorer) ----------

  function railEntry(path) {
    const key = canonical(path);
    let row = rail.querySelector(`[data-key="${CSS.escape(key)}"]`);
    if (!row) {
      row = el('div', 'pov-rail-file');
      row.dataset.key = key;
      row.title = relative(path);
      row.append(el('span', 'pov-rail-mark'), el('span', 'pov-rail-name', basename(path)),
        el('span', 'pov-rail-dir', relative(path).split('/').slice(0, -1).join('/')));
      row.onclick = () => { toggle(false); openFile(path); };
      rail.append(row);
    }
    return row;
  }

  function touchFile(path, kind) {
    if (!path || !rail) return null;
    const key = canonical(path);
    const entry = state.files.get(key) || { path, kind };
    entry.kind = kind === 'read' && (entry.kind === 'edit' || entry.kind === 'write') ? entry.kind : kind;
    state.files.set(key, entry);
    const row = railEntry(path);
    row.className = `pov-rail-file k-${entry.kind}`;
    rail.querySelectorAll('.pov-rail-file.now').forEach(r => r.classList.remove('now'));
    row.classList.add('now');
    railCount.textContent = String(state.files.size);
    row.scrollIntoView({ block: 'nearest' });
    return row;
  }

  /** Clicks the file in the rail and opens its content (or given content) in the editor. */
  async function openInEditor(path, content, token) {
    const row = touchFile(path, 'read');
    await pointAt(row, { click: true });
    if (token !== state.token) return null;
    await showApp('editor', { instant: true });
    const instance = ensureEditor();
    if (!instance) return null;
    findDecorations?.clear();
    const uri = monacoRef.Uri.from({ scheme: 'pov', path });
    let model = monacoRef.editor.getModel(uri);
    if (!model) model = monacoRef.editor.createModel(content, undefined, uri);
    else if (model.getValue() !== content) model.setValue(content);
    instance.setModel(model);
    editorTitle.textContent = relative(path);
    return model;
  }

  async function readFile(path) {
    try { const r = await fs('read', { path }); return r.error ? null : r.content; } catch { return null; }
  }

  // ---------- Steps ----------

  function kindOf(item) {
    if (item.kind === 'prompt' || item.kind === 'thinking' || item.kind === 'message') return item.kind;
    if (item.kind === 'tool') return item.action && KIND[item.action] ? item.action : 'other';
    return null;
  }

  function addStep(step, { play = true } = {}) {
    step.index = state.steps.length;
    step.time = Date.now();
    state.steps.push(step);
    if (step.id) state.byId.set(step.id, step);
    if (!stage) return;
    renderBlock(step);
    stepCounter.textContent = `STEP ${state.steps.length}`;
    if (play && state.on && state.live) { state.queue.push(step); run(); }
  }

  function item(entry, isReset) {
    if (entry.kind === 'result') {
      const step = state.byId.get(entry.id);
      if (!step) return;
      step.result = entry;
      step.onResult?.(entry);
      renderBlock(step);
      return;
    }
    const kind = kindOf(entry);
    if (kind) addStep({ kind, item: entry, id: entry.kind === 'tool' ? entry.id : null, sub: entry.sub }, { play: !isReset });
  }

  function reset(items) {
    state.steps = []; state.byId.clear(); state.queue = [];
    items.forEach(i => item(i, true));
    if (!stage) return;
    renderTimeline();
    if (state.on) { state.queue = state.steps.slice(-4); run(); }
  }

  /** A change on disk that no tool call explains (sed, scripts): replay it too. */
  function diskChange(change) {
    const path = change.path;
    const explained = state.steps.slice(-6).some(s => (s.kind === 'edit' || s.kind === 'write') &&
      samePath(agentAbs(s.item.path), path) && Date.now() - s.time < 8000);
    if (explained || change.deleted) return;
    addStep({ kind: 'disk', item: { path, hunks: change.hunks, created: change.created } });
  }

  function status(s) {
    if (!stage) build();
    const waiting = s && (s.badge === 'permission' || s.badge === 'input');
    waitBanner.classList.toggle('hidden', !waiting);
    if (waiting) {
      waitBanner.replaceChildren(el('span', 'pov-wait-dot'),
        el('span', 'pov-wait-title', s.badge === 'permission' ? 'WAITING FOR YOUR PERMISSION' : 'WAITING FOR YOUR ANSWER'),
        el('span', 'pov-wait-detail', s.detail || ''));
    }
    if (s) headSprite.replaceChildren(sprite(s.kind === 'codex' ? 'codex' : s.kind === 'claude' ? 'claude' : 'other', 2));
  }

  // ---------- Playback ----------

  async function run() {
    if (state.busy || !state.on) return;
    state.busy = true;
    try {
      while (state.queue.length && state.on) {
        const step = state.queue.shift();
        // Pace by how far behind the agent the replay is, so it never falls behind for long.
        const lag = state.live ? lagOf(step) : 0;
        const waiting = state.queue.length;
        speed = lag > 6000 || waiting > 4 ? 4 : lag > 2500 || waiting > 1 ? 2 : 1;
        hurry = lag > 9000 || waiting > 6;
        ffBadge.classList.toggle('hidden', speed === 1);
        // Well behind: skip what's only looking (reads, searches, thoughts) and already old.
        if (lag > 12000 && waiting > 0 && ['read', 'search', 'thinking', 'other'].includes(step.kind)) {
          if (window.povDebug) log(`pov skip ${step.kind} lag=${lag}`);
          continue;
        }
        if (window.povDebug) log(`pov play ${step.kind} lag=${lag} queued=${waiting} speed=${speed}${hurry ? ' hurry' : ''}`);
        await play(step);
      }
    } finally {
      state.busy = false;
      ffBadge.classList.add('hidden');
    }
  }

  async function play(step) {
    const token = ++state.token;
    state.playing = step;
    const [label, color] = KIND[step.kind] || KIND.other;
    headLabel.textContent = label;
    headLabel.style.color = `var(${color})`;
    headDetail.textContent = step.sub ? `↳ ${step.sub}` : '';
    timeline.querySelectorAll('.pov-block.now').forEach(b => b.classList.remove('now'));
    step.block?.classList.add('now');
    step.block?.scrollIntoView({ block: 'nearest', inline: 'nearest' });
    try {
      await (ACTIONS[step.kind] || ACTIONS.other)(step, token);
    } catch (e) {
      log(`pov: ${e?.stack || e}`);
    }
    if (token === state.token && !hurry) await wait(state.queue.length ? 150 : 450);
  }

  function goLive() {
    state.live = true;
    liveBtn.classList.remove('paused');
    liveBtn.textContent = '● LIVE';
    clearTimeout(state.replayTimer);
    state.token++;
    state.busy = false;
    const last = state.steps[state.steps.length - 1];
    state.queue = last ? [last] : [];
    run();
  }

  function replay(step) {
    state.live = false;
    liveBtn.classList.add('paused');
    liveBtn.textContent = '▶ BACK TO LIVE';
    state.queue = [];
    state.token++;
    state.busy = false;
    speed = 1;
    play(step);
    clearTimeout(state.replayTimer);
    state.replayTimer = setTimeout(goLive, 45000);
  }

  // ---------- What each kind of step does on the screen ----------

  function chatEntry(cls, label) {
    chatLog.querySelector('.pov-chat-empty')?.remove();
    const entry = el('div', `pov-msg ${cls}`);
    if (label) entry.append(el('div', 'pov-msg-label', label));
    const text = el('div', 'pov-msg-text');
    entry.append(text);
    chatLog.append(entry);
    while (chatLog.children.length > 40) chatLog.firstChild.remove();
    return text;
  }

  const scrollChat = () => { chatLog.scrollTop = chatLog.scrollHeight; };

  function termPrint(text, cls) {
    const line = el('div', `pov-term-line ${cls || ''}`, text);
    termLines.append(line);
    while (termLines.children.length > 400) termLines.firstChild.remove();
    term.scrollTop = term.scrollHeight;
    return line;
  }

  const projectName = () => (state.rootName = $('root-name')?.textContent?.toLowerCase() || 'project');

  const ACTIONS = {
    async prompt(step, token) {
      await showApp('chat');
      const text = chatEntry('you', 'YOU');
      scrollChat();
      await typeText(text, step.item.text || '', { cps: 160, token });
      scrollChat();
    },

    async thinking(step, token) {
      await showApp('chat');
      const text = chatEntry('thought', 'THINKING');
      const thought = (step.item.text || '').trim();
      if (!thought) { text.textContent = 'thinking privately…'; text.classList.add('private'); return; }
      await typeText(text, thought.length > 1500 ? thought.slice(0, 1500) + '…' : thought, { cps: 200, token });
      scrollChat();
    },

    async message(step, token) {
      await showApp('chat');
      const text = chatEntry('agent', (agent.status?.name || 'AGENT').toUpperCase());
      await typeText(text, step.item.text || '', { cps: 170, token });
      scrollChat();
    },

    async read(step, token) {
      const path = agentAbs(step.item.path);
      if (!path) return;
      let content = await readFile(path);
      if (content == null || token !== state.token) return;
      // A huge file opens as the region being read (a whole one would stall the editor).
      if (content.length > BIG_FILE) {
        const all = content.split('\n');
        const from = Math.max(0, (step.item.offset || 1) - 1);
        const to = Math.min(all.length, from + (step.item.limit || 200));
        content = all.slice(from, to).join('\n');
        step.item = { ...step.item, offset: 1, limit: to - from };
      }
      const model = await openInEditor(path, content, token);
      if (!model || token !== state.token) return;
      const count = model.getLineCount();
      const first = Math.min(Math.max(1, step.item.offset || 1), count);
      const last = Math.min(step.item.limit ? first + step.item.limit - 1 : count, count);
      const instance = ensureEditor();
      instance.revealLineNearTop(first, monacoRef.editor.ScrollType.Immediate);
      // The eye moves down the lines being read.
      const span = last - first + 1;
      const stepBy = Math.max(1, Math.ceil(span / (hurry ? 1 : 18)));
      for (let line = first; line <= last; line += stepBy) {
        if (token !== state.token) return;
        instance.setSelection(new monacoRef.Range(first, 1, line, model.getLineMaxColumn(line)));
        instance.revealLineInCenterIfOutsideViewport(line, monacoRef.editor.ScrollType.Smooth);
        await wait(40);
      }
      instance.setSelection(new monacoRef.Range(first, 1, last, model.getLineMaxColumn(last)));
      await wait(250);
      instance.setPosition({ lineNumber: last, column: 1 });
    },

    async edit(step, token) {
      const it = step.item;
      const path = agentAbs(it.path);
      if (!path) return;
      let now = await readFile(path);
      if (token !== state.token) return;
      touchFile(path, it.action === 'write' ? 'write' : 'edit');
      // A huge file: show just the region around the change.
      if (now != null && now.length > BIG_FILE) {
        const at = it.new ? now.indexOf(it.new) : -1;
        if (at < 0) return;
        const from = Math.max(0, now.lastIndexOf('\n', Math.max(0, at - 4000)));
        const to = now.indexOf('\n', Math.min(now.length, at + it.new.length + 4000));
        now = now.slice(from, to < 0 ? now.length : to);
      }

      // A new file, or a whole-file write: start empty and type it.
      if (it.action === 'write' || now == null) {
        const model = await openInEditor(path, '', token);
        if (!model) return;
        await typeInEditor(model, { lineNumber: 1, column: 1 }, now ?? (it.new || ''), token);
        return;
      }
      // Patches (Codex): replay hunk by hunk from the patch text.
      if (it.patch && !it.new) return ACTIONS.disk({ item: { path, hunks: patchHunks(it.patch, now) } }, token);

      const oldText = it.old || '', newText = it.new || '';
      const at = newText ? now.indexOf(newText) : -1;
      // The file as it was before this edit: the new text swapped back for the old.
      const before = at >= 0 ? now.slice(0, at) + oldText + now.slice(at + newText.length) : now;
      const model = await openInEditor(path, before, token);
      if (!model || token !== state.token) return;
      const instance = ensureEditor();
      const startOffset = at >= 0 ? at : 0;
      const start = model.getPositionAt(startOffset);
      const end = model.getPositionAt(startOffset + (at >= 0 ? oldText.length : 0));
      instance.revealPositionInCenter(start, monacoRef.editor.ScrollType.Smooth);
      await wait(350);
      const top = instance.getTopForPosition(start.lineNumber, 1) - instance.getScrollTop();
      await pointAt(instance.getDomNode(), { dx: 70, dy: Math.max(10, Math.min(300, top + 8)) });
      if (oldText && at >= 0) {
        // Select what's being replaced, then delete it.
        instance.setSelection(new monacoRef.Range(start.lineNumber, start.column, end.lineNumber, end.column));
        await wait(Math.min(900, 300 + oldText.length * 2));
        if (token !== state.token) return;
        model.applyEdits([{ range: new monacoRef.Range(start.lineNumber, start.column, end.lineNumber, end.column), text: '' }]);
        instance.setPosition(start);
        await wait(200);
      }
      if (at >= 0) await typeInEditor(model, start, newText, token);
      if (token === state.token && model.getValue() !== now) model.setValue(now);
    },

    async write(step, token) { return ACTIONS.edit(step, token); },

    /** Changes found on disk: rebuild the old file from the hunks, then replay each one. */
    async disk(step, token) {
      const { path, hunks = [] } = step.item;
      const now = await readFile(path);
      if (now == null || token !== state.token) return;
      if (now.length > BIG_FILE) { touchFile(path, 'edit'); return; }
      touchFile(path, 'edit');
      const lines = now.split('\n');
      // Undo the hunks from the bottom up to get the file as it was.
      const before = lines.slice();
      for (const h of [...hunks].sort((a, b) => b.start - a.start)) {
        before.splice(h.start - 1, h.count, ...(h.removed || []));
      }
      const model = await openInEditor(path, before.join('\n'), token);
      if (!model || token !== state.token) return;
      const instance = ensureEditor();
      // Replay top down: everything above a hunk is already in its new state, so each
      // hunk's start (a line number in the new file) is where its old lines sit now.
      for (const h of [...hunks].sort((a, b) => a.start - b.start).slice(0, 8)) {
        if (token !== state.token) return;
        const startLine = h.start;
        const removedCount = (h.removed || []).length;
        instance.revealLineInCenter(Math.min(startLine, model.getLineCount()), monacoRef.editor.ScrollType.Smooth);
        await wait(300);
        if (removedCount) {
          const endLine = startLine + removedCount;
          const range = endLine <= model.getLineCount()
            ? new monacoRef.Range(startLine, 1, endLine, 1)
            : new monacoRef.Range(startLine, 1, model.getLineCount(), model.getLineMaxColumn(model.getLineCount()));
          instance.setSelection(range);
          await wait(450);
          model.applyEdits([{ range, text: '' }]);
        }
        const added = lines.slice(h.start - 1, h.start - 1 + h.count);
        if (added.length) {
          const atEnd = startLine > model.getLineCount();
          const position = atEnd
            ? { lineNumber: model.getLineCount(), column: model.getLineMaxColumn(model.getLineCount()) }
            : { lineNumber: startLine, column: 1 };
          const text = atEnd ? '\n' + added.join('\n') : added.join('\n') + '\n';
          await typeInEditor(model, position, text, token);
        }
      }
      if (token === state.token && model.getValue() !== now) model.setValue(now);
    },

    async run(step, token) {
      await showApp('terminal');
      const cmd = (step.item.command || '').trim();
      termPrint(`${projectName()} ›`, 'prompt');
      const line = termPrint('', 'cmd');
      // The first line types out (up to a point); the rest appears as a paste would.
      const [firstLine, ...more] = cmd.split('\n');
      const typed = firstLine.length > 110 ? firstLine.slice(0, 110) : firstLine;
      await typeText(line, '$ ' + typed, { cps: 150, token });
      const tail = firstLine.slice(typed.length) + (more.length ? '\n' + more.slice(0, 8).join('\n') + (more.length > 8 ? '\n…' : '') : '');
      if (tail) line.append(tail);
      if (token !== state.token) return;
      const block = el('div', 'pov-term-block');
      termLines.append(block);
      const spinner = el('div', 'pov-term-line running');
      spinner.append(el('span', 'pov-spin'), ' running…');
      block.append(spinner);
      term.scrollTop = term.scrollHeight;
      // Output lands in this command's place whenever it arrives, even after the replay
      // has moved on, the way a real terminal fills in.
      const printOut = async (r) => {
        step.onResult = null;
        spinner.remove();
        const out = (r.text || '').replace(/\s+$/, '').split('\n').slice(-30);
        const live = state.playing === step && !hurry;
        for (const text of out) {
          block.append(el('div', `pov-term-line ${r.error ? 'err' : 'out'}`, text));
          if (live) { term.scrollTop = term.scrollHeight; await wait(18); }
        }
        block.append(el('div', `pov-term-line ${r.error ? 'fail' : 'ok'}`, r.error ? '✗ exited with an error' : '✓ done'));
        term.scrollTop = term.scrollHeight;
      };
      if (step.result) { await printOut(step.result); return; }
      step.onResult = (r) => printOut(r);
      // Wait briefly for quick commands; otherwise move on and let it fill in later.
      for (let i = 0; i < 12 && !step.result && !state.queue.length && token === state.token; i++) await wait(150);
    },

    async search(step, token) {
      await showApp('search');
      const pattern = step.item.pattern || step.item.query || step.item.description || '';
      await pointAt(searchBox, { click: true });
      searchResults.replaceChildren();
      await typeText(searchQuery, pattern, { cps: 60, token });
      const show = async (r) => {
        const groups = new Map();
        for (const line of (r.text || '').split('\n').filter(Boolean).slice(0, 60)) {
          const m = line.match(/^([^:\s]+):(\d+):(.*)$/);
          const file = m ? m[1] : line.trim();
          if (!groups.has(file)) groups.set(file, []);
          if (m) groups.get(file).push({ line: +m[2], text: m[3] });
        }
        let re = null;
        try { re = new RegExp(pattern.replace(/\\\|/g, '|'), 'i'); } catch {}
        let first = null;
        for (const [file, hits] of groups) {
          searchResults.append(el('div', 'pov-hit-file', file));
          const abs = agentAbs(file);
          if (abs && /\.[A-Za-z0-9]+$/.test(file)) { touchFile(abs, 'read'); first = first || { abs, hit: hits[0] }; }
          for (const hit of hits.slice(0, 5)) {
            const row = el('div', 'pov-hit');
            row.append(el('span', 'pov-hit-line', String(hit.line)));
            const text = el('span', 'pov-hit-text');
            const match = re && hit.text.match(re);
            if (match) {
              const i = hit.text.indexOf(match[0]);
              text.append(hit.text.slice(Math.max(0, i - 30), i), Object.assign(el('mark'), { textContent: match[0] }),
                hit.text.slice(i + match[0].length, i + match[0].length + 60));
            } else text.textContent = hit.text.trim().slice(0, 100);
            row.append(text);
            searchResults.append(row);
          }
          if (token === state.token) await wait(90);
        }
        if (!groups.size) searchResults.append(el('div', 'pov-hit-none', 'No results'));
        // Open the first match, with every match lit up.
        if (first && token === state.token && re) {
          await wait(600);
          const content = await readFile(first.abs);
          if (content == null || content.length > BIG_FILE) return;
          const model = await openInEditor(first.abs, content, token);
          if (!model) return;
          const matches = model.findMatches(re.source, false, true, false, null, false).slice(0, 200);
          const instance = ensureEditor();
          findDecorations = instance.createDecorationsCollection(
            matches.map(m => ({ range: m.range, options: { inlineClassName: 'pov-find-match' } })));
          if (matches[0]) {
            instance.setSelection(matches[0].range);
            instance.revealRangeInCenter(matches[0].range, monacoRef.editor.ScrollType.Smooth);
          }
        }
      };
      if (step.result) await show(step.result);
      else {
        step.onResult = (r) => { step.onResult = null; if (state.playing === step) show(r); };
        for (let i = 0; i < 10 && !step.result && !state.queue.length && token === state.token; i++) await wait(150);
      }
    },

    async web(step, token) {
      await showApp('browser');
      const raw = step.item.query || step.item.path || '';
      const url = /^https?:\/\//.test(raw) ? raw : `https://duckduckgo.com/?q=${encodeURIComponent(raw)}`;
      await pointAt(browserBar, { click: true, dx: 120 });
      await typeText(browserURL, url, { cps: 90, token });
      if (token !== state.token) return;
      browserProgress.classList.remove('done');
      browserView.querySelector('.pov-browser-empty')?.remove();
      browserView.dataset.url = url;
      browserView.dataset.loaded = '1';
      syncBrowser(url);
      await wait(1200);
      browserProgress.classList.add('done');
      await wait(state.queue.length ? 400 : 1500);
    },

    async todo(step) {
      const todos = step.item.todos || [];
      todoBox.classList.toggle('hidden', !todos.length);
      todoBox.replaceChildren(el('div', 'pov-side-head', 'PLAN'));
      todos.forEach((t, i) => {
        const row = el('div', `pov-plan ${t.status}`);
        row.style.setProperty('--i', i);
        row.append(el('span', 'pov-plan-box', t.status === 'completed' ? '✓' : t.status === 'in_progress' ? '▸' : ''),
          el('span', 'pov-plan-text', t.text));
        todoBox.append(row);
      });
      await pointAt(todoBox);
      await wait(900);
    },

    async agent(step, token) {
      await showApp('chat');
      const text = chatEntry('sub', '↳ SUB-AGENT');
      await typeText(text, step.item.description || step.item.query || 'working on a sub-task', { cps: 120, token });
      scrollChat();
    },

    async other(step, token) {
      await showApp('chat');
      const text = chatEntry('tool', `USED ${String(step.item.tool || 'a tool').toUpperCase()}`);
      const args = step.item.query || step.item.path || step.item.command || step.item.pattern || step.item.description || '';
      await typeText(text, args, { cps: 150, token });
      scrollChat();
    },
  };

  /** Hunks (with the file's current line numbers) from a Codex patch, found by content. */
  function patchHunks(patch, now) {
    const lines = now.split('\n');
    const hunks = [];
    let removed = [], added = [];
    const flush = () => {
      if (!removed.length && !added.length) return;
      const at = added.length ? lines.indexOf(added[0]) : -1;
      if (at >= 0) hunks.push({ start: at + 1, count: added.length, removed });
      removed = []; added = [];
    };
    for (const line of patch.split('\n')) {
      if (line.startsWith('+') && !line.startsWith('+++')) added.push(line.slice(1));
      else if (line.startsWith('-') && !line.startsWith('---')) removed.push(line.slice(1));
      else flush();
    }
    flush();
    return hunks;
  }

  // ---------- Timeline ----------

  function renderTimeline() {
    if (!timeline) return;
    timeline.replaceChildren();
    state.steps.slice(-400).forEach(s => { s.block = null; renderBlock(s); });
  }

  function renderBlock(step) {
    if (!timeline) return;
    let block = step.block;
    if (!block) {
      block = el('span', 'pov-block');
      block.onclick = () => replay(step);
      step.block = block;
      timeline.append(block);
      while (timeline.children.length > 400) timeline.firstChild.remove();
      timeline.scrollLeft = timeline.scrollWidth;
    }
    const [label, color] = KIND[step.kind] || KIND.other;
    block.style.setProperty('--k', `var(${color})`);
    block.classList.toggle('failed', !!step.result?.error);
    const it = step.item || {};
    const detail = it.path ? relative(agentAbs(it.path) || it.path) : (it.command || it.pattern || it.query || it.text || '').slice(0, 80);
    block.title = `${label}${detail ? ' · ' + detail : ''}`;
  }

  // ---------- Showing and hiding ----------

  function toggle(on = !state.on) {
    state.on = on;
    if (!stage) build();
    stage.classList.toggle('hidden', !on);
    $('pov-toggle')?.classList.toggle('on', on);
    document.body.classList.toggle('pov-active', on);
    syncBrowser();
    if (on) {
      renderTimeline();
      const last = state.steps[state.steps.length - 1];
      if (last && !state.busy) { state.queue = [last]; run(); }
    }
  }

  window.pov = { item, reset, status, diskChange, toggle, isOn: () => state.on };

  // Off by default: the editor follows the agent live (and splits for several agents).
  // AI POV opens only when its tab is clicked.
  const button = $('pov-toggle');
  if (button) button.onclick = () => toggle();
  try { localStorage.removeItem('pov'); } catch {}
})();
