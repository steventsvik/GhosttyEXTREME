// Backend: what a project runs on, drawn as one clear picture, and live.
//
// Detection reads the project itself (package.json, wrangler.toml/jsonc, supabase/, .vercel/,
// prisma/schema.prisma, env variable *names*, …), so it works offline and without logins.
// The Architecture view lays the pieces out left to right: Frontend → Compute (API routes,
// Workers, Edge Functions, servers) → Data (Postgres, Auth, Storage, D1, KV, R2, Redis…) →
// Services (Stripe, OpenAI, Resend…), with lines only where the code really connects them.
//
// Live data comes from the providers' own CLIs through the app (BackendProbe.swift), using
// their existing logins and read-only commands: Supabase project health, schema, row counts,
// RLS and migrations; Vercel deployments; Cloudflare Worker deployments, D1, KV and R2.
// The Database view draws the schema with its relations and RLS status, and every table,
// binding and service links to the code that uses it. When the agent edits something that
// belongs to a piece of the backend, that piece lights up, and it's flagged if what's
// deployed no longer matches (migrations not applied, commits not deployed).
//
// Polls only while the tab is showing. Uses helpers from app.js and map.js.

(() => {
  const SKIP = /(^|\/)(node_modules|\.git|\.next|\.open-next|dist|build|\.vercel\/output|\.wrangler|\.turbo|coverage|\.svelte-kit|\.output)(\/|$)/;

  // ---------- Providers ----------

  const SVG = {
    supabase: '<svg viewBox="0 0 24 24"><path fill="currentColor" d="M13.5 22.6c-.5.6-1.6.3-1.6-.5l-.2-9.6h6.6c1.2 0 1.9 1.4 1.1 2.3z"/><path fill="currentColor" opacity=".55" d="M10.5 1.4c.5-.6 1.6-.3 1.6.5l.1 9.6H5.7c-1.2 0-1.9-1.4-1.1-2.3z"/></svg>',
    cloudflare: '<svg viewBox="0 0 24 24"><path fill="currentColor" d="M16.5 17.5H5.2a.3.3 0 0 1-.3-.3c0-.1.1-.3.2-.3l11.7-.1c1.4-.1 2.9-1.2 3.4-2.6l.7-1.8.1-.2a7.6 7.6 0 0 0-14.6-.8 3.4 3.4 0 0 0-5.4 3.6A4.9 4.9 0 0 0 .1 17.6c0 .1.1.2.2.2h16.2zM19.3 11.6h-.4c-.1 0-.2.1-.2.2l-.4 1.2c-.4 1.3-1.6 2.2-3 2.3l-1 .1c-.1 0-.1.1-.1.2 0 .1 0 .1.1.1l.9.1h7.9c.1 0 .2-.1.2-.2.1-.4.2-.9.2-1.3a3.8 3.8 0 0 0-4.2-2.7z"/></svg>',
    vercel: '<svg viewBox="0 0 24 24"><path fill="currentColor" d="M12 3 23 21H1z"/></svg>',
  };
  const P = {
    supabase: ['Supabase', '#3ecf8e'], cloudflare: ['Cloudflare', '#f38020'], vercel: ['Vercel', '#ededed'],
    netlify: ['Netlify', '#32e6e2'], firebase: ['Firebase', '#ffca28'], prisma: ['Prisma', '#7f8cff'],
    postgres: ['PostgreSQL', '#6b9bd2'], neon: ['Neon', '#00e599'], planetscale: ['PlanetScale', '#ededed'],
    railway: ['Railway', '#c793ff'], render: ['Render', '#7f8cff'], 'aws-rds': ['AWS RDS', '#ff9900'], aws: ['AWS', '#ff9900'],
    upstash: ['Upstash', '#00e9a3'], redis: ['Redis', '#ff4438'], mongodb: ['MongoDB', '#47a248'],
    stripe: ['Stripe', '#8f86ff'], openai: ['OpenAI', '#10a37f'], anthropic: ['Anthropic', '#d97757'],
    gemini: ['Gemini', '#4285f4'], resend: ['Resend', '#ededed'], sendgrid: ['SendGrid', '#1a82e2'], clerk: ['Clerk', '#8c6cff'],
    sentry: ['Sentry', '#a78bfa'], posthog: ['PostHog', '#f9bd2b'], twilio: ['Twilio', '#f22f46'], github: ['GitHub', '#ededed'],
    slack: ['Slack', '#e01e5a'], discord: ['Discord', '#5865f2'], google: ['Google', '#4285f4'], pusher: ['Pusher', '#6d4aff'],
    lemonsqueezy: ['Lemon Squeezy', '#ffc233'], paypal: ['PayPal', '#3b7bbf'], shopify: ['Shopify', '#95bf47'],
    depop: ['Depop', '#ff2300'], ebay: ['eBay', '#e53238'], nextauth: ['Auth.js', '#b392f0'], auth: ['Auth', '#b392f0'],
    replicate: ['Replicate', '#ededed'], elevenlabs: ['ElevenLabs', '#ededed'], mapbox: ['Mapbox', '#4264fb'], algolia: ['Algolia', '#5468ff'],
    next: ['Next.js', '#ededed'], react: ['React', '#61dafb'], vite: ['Vite', '#bd34fe'], astro: ['Astro', '#ff5d01'],
    remix: ['Remix', '#ededed'], sveltekit: ['SvelteKit', '#ff3e00'], nuxt: ['Nuxt', '#00dc82'], vue: ['Vue', '#42b883'],
    expo: ['Expo', '#ededed'], angular: ['Angular', '#dd0031'], solid: ['Solid', '#4f88c6'], gatsby: ['Gatsby', '#663399'],
    express: ['Express', '#ededed'], fastify: ['Fastify', '#ededed'], hono: ['Hono', '#ff5b11'], koa: ['Koa', '#ededed'],
    nest: ['NestJS', '#e0234e'], fastapi: ['FastAPI', '#009688'], flask: ['Flask', '#ededed'], django: ['Django', '#44b78b'],
    docker: ['Docker', '#2496ed'], fly: ['Fly.io', '#8b5cf6'], local: ['Local', '#8c8374'], database: ['Database', '#6b9bd2'],
    site: ['Static site', '#deb86e'], images: ['Cloudflare Images', '#f38020'],
    generic: ['Service', '#8c8374'],
  };
  const pname = (id) => (P[id] || P.generic)[0];
  const pcolor = (id) => (P[id] || P.generic)[1];

  const FRAMEWORKS = [
    ['next', 'next'], ['nuxt', 'nuxt'], ['@remix-run/react', 'remix'], ['@sveltejs/kit', 'sveltekit'], ['astro', 'astro'],
    ['expo', 'expo'], ['@angular/core', 'angular'], ['gatsby', 'gatsby'], ['solid-js', 'solid'], ['vue', 'vue'],
    ['vite', 'vite'], ['react-scripts', 'react'], ['react', 'react'],
  ];
  const SERVERS = [['@nestjs/core', 'nest'], ['hono', 'hono'], ['express', 'express'], ['fastify', 'fastify'], ['koa', 'koa']];
  const SERVICE_PACKAGES = {
    stripe: 'stripe', openai: 'openai', '@anthropic-ai/sdk': 'anthropic', '@google/generative-ai': 'gemini', '@google/genai': 'gemini',
    resend: 'resend', '@sendgrid/mail': 'sendgrid', '@clerk/nextjs': 'clerk', '@clerk/clerk-react': 'clerk', '@sentry/nextjs': 'sentry',
    '@sentry/node': 'sentry', '@sentry/react': 'sentry', 'posthog-js': 'posthog', 'posthog-node': 'posthog', twilio: 'twilio',
    '@upstash/redis': 'upstash', ioredis: 'redis', redis: 'redis', mongodb: 'mongodb', mongoose: 'mongodb', firebase: 'firebase',
    'firebase-admin': 'firebase', 'next-auth': 'nextauth', '@auth/core': 'nextauth', replicate: 'replicate', 'mapbox-gl': 'mapbox',
    algoliasearch: 'algolia', pusher: 'pusher', '@octokit/rest': 'github', '@slack/web-api': 'slack', 'discord.js': 'discord',
  };
  const DATA_SERVICES = new Set(['upstash', 'redis', 'mongodb', 'firebase', 'neon', 'planetscale', 'railway', 'render', 'aws-rds', 'database', 'postgres', 'local']);
  const LANES = [
    ['client', 'Frontend', 'browser'], ['compute', 'Compute', 'server-process'],
    ['data', 'Data', 'database'], ['external', 'Services', 'plug'],
  ];

  // ---------- State ----------

  const B = {
    root: null, scanning: false, scannedAt: 0, comps: [], edges: [], byId: new Map(),
    refs: [], refsByFile: new Map(), tables: new Map(), // table -> [{ path, line }]
    live: {}, git: null,
    dbs: new Map(), dbSel: null, dbFilter: '', // databases for the Database view: id -> { label, provider, schema, source, error }
    view: 'arch', selected: null, visible: false, poll: 0, busy: 0,
    agent: new Map(), // comp id or table:name -> { files: Set, last }
  };
  /** The database shown in the Database view (its schema, where it came from, any error). */
  const curDB = () => B.dbs.get(B.dbSel) || [...B.dbs.values()][0] || null;
  Object.defineProperties(B, {
    schema: { get: () => curDB()?.schema || null },
    schemaSource: { get: () => curDB()?.source || null },
    schemaError: { get: () => curDB()?.error || null },
  });
  function dbEntry(id, init) {
    if (!B.dbs.has(id)) B.dbs.set(id, { id, schema: null, source: null, error: null, ...init });
    else if (init) Object.assign(B.dbs.get(id), init, { schema: B.dbs.get(id).schema, source: B.dbs.get(id).source });
    return B.dbs.get(id);
  }

  let wrap, top, stageEl, archEl, dbEl, svg, side, summaryEl, refreshBtn, updatedEl;

  // ---------- Small parsers ----------

  /** A small TOML reader: tables, arrays of tables, strings, numbers, booleans, arrays, inline tables. */
  function parseTOML(text) {
    const root = {};
    let current = root;
    const lines = text.split('\n');
    const stripComment = (line) => {
      let quote = null;
      for (let i = 0; i < line.length; i++) {
        const c = line[i];
        if (quote) { if (c === '\\') i++; else if (c === quote) quote = null; }
        else if (c === '"' || c === "'") quote = c;
        else if (c === '#') return line.slice(0, i);
      }
      return line;
    };
    const path = (s) => s.split('.').map(p => p.trim().replace(/^["']|["']$/g, ''));
    for (let i = 0; i < lines.length; i++) {
      let line = stripComment(lines[i]).trim();
      if (!line) continue;
      let m;
      if ((m = /^\[\[([^\]]+)\]\]$/.exec(line))) {
        const keys = path(m[1]);
        let obj = root;
        keys.slice(0, -1).forEach(k => { obj[k] = obj[k] ?? {}; obj = Array.isArray(obj[k]) ? obj[k][obj[k].length - 1] : obj[k]; });
        const last = keys[keys.length - 1];
        if (!Array.isArray(obj[last])) obj[last] = [];
        current = {};
        obj[last].push(current);
        continue;
      }
      if ((m = /^\[([^\]]+)\]$/.exec(line))) {
        let obj = root;
        for (const k of path(m[1])) { obj[k] = obj[k] ?? {}; obj = Array.isArray(obj[k]) ? obj[k][obj[k].length - 1] : obj[k]; }
        current = obj;
        continue;
      }
      const eq = line.indexOf('=');
      if (eq < 0) continue;
      const keys = path(line.slice(0, eq));
      let raw = line.slice(eq + 1).trim();
      // Multi-line arrays: read until the brackets balance.
      const balance = (s) => [...s].reduce((n, c) => n + (c === '[' || c === '{') - (c === ']' || c === '}'), 0);
      while (balance(raw) > 0 && i + 1 < lines.length) raw += ' ' + stripComment(lines[++i]).trim();
      let obj = current;
      keys.slice(0, -1).forEach(k => { obj[k] = obj[k] ?? {}; obj = obj[k]; });
      try { obj[keys[keys.length - 1]] = tomlValue(raw); } catch { /* skip what we can't read */ }
    }
    return root;
  }

  function tomlValue(src) {
    let i = 0;
    const ws = () => { while (i < src.length && /[\s,]/.test(src[i])) i++; };
    const value = () => {
      ws();
      const c = src[i];
      if (c === '"' || c === "'") {
        const triple = src.startsWith(c.repeat(3), i);
        const end = triple ? src.indexOf(c.repeat(3), i + 3) : (() => { let j = i + 1; while (j < src.length && src[j] !== c) { if (src[j] === '\\' && c === '"') j++; j++; } return j; })();
        const s = src.slice(i + (triple ? 3 : 1), end);
        i = end + (triple ? 3 : 1);
        return s;
      }
      if (c === '[') {
        i++;
        const out = [];
        for (ws(); src[i] !== ']' && i < src.length; ws()) out.push(value());
        i++;
        return out;
      }
      if (c === '{') {
        i++;
        const out = {};
        for (ws(); src[i] !== '}' && i < src.length; ws()) {
          const eq = src.indexOf('=', i);
          const key = src.slice(i, eq).trim().replace(/^["']|["']$/g, '');
          i = eq + 1;
          out[key] = value();
        }
        i++;
        return out;
      }
      const m = /^[^,\]}\s]+/.exec(src.slice(i));
      const word = m ? m[0] : '';
      i += word.length;
      if (word === 'true') return true;
      if (word === 'false') return false;
      return isNaN(Number(word)) ? word : Number(word);
    };
    return value();
  }

  /** JSON with comments and trailing commas (wrangler.jsonc, tsconfig). */
  function parseJSONC(text) {
    let out = '', quote = false;
    for (let i = 0; i < text.length; i++) {
      const c = text[i];
      if (quote) { out += c; if (c === '\\') out += text[++i]; else if (c === '"') quote = false; continue; }
      if (c === '"') { quote = true; out += c; continue; }
      if (c === '/' && text[i + 1] === '/') { while (i < text.length && text[i] !== '\n') i++; out += '\n'; continue; }
      if (c === '/' && text[i + 1] === '*') { i = text.indexOf('*/', i + 2) + 1; continue; }
      out += c;
    }
    return JSON.parse(out.replace(/,(\s*[}\]])/g, '$1'));
  }

  /** Tables from SQL migrations (offline fallback for the Database view). */
  function parseSQL(files) {
    const tables = new Map(), fks = [], rls = new Map(), policies = new Map();
    const clean = (n) => n.replace(/["`\[\]]/g, '').replace(/^public\./i, '');
    for (const { text } of files) {
      const sql = text.replace(/--[^\n]*/g, '');
      for (const m of sql.matchAll(/create\s+(?:unlogged\s+)?table\s+(?:if\s+not\s+exists\s+)?([\w."`\[\]]+)\s*\(([\s\S]*?)\)\s*(?:strict|without\s+rowid|partition\s+by[^;]*|inherits[^;]*)?\s*;/gi)) {
        const name = clean(m[1]);
        if (/^(auth|storage|extensions|realtime|graphql|pgsodium|vault|supabase_\w+)\./.test(name)) continue;
        const columns = [], pk = [];
        // Split on top-level commas.
        let depth = 0, cur = '';
        const parts = [];
        for (const c of m[2]) { if (c === '(') depth++; if (c === ')') depth--; if (c === ',' && depth === 0) { parts.push(cur); cur = ''; } else cur += c; }
        parts.push(cur);
        for (const part of parts.map(p => p.trim()).filter(Boolean)) {
          const pkm = /^(?:constraint\s+\S+\s+)?primary\s+key\s*\(([^)]+)\)/i.exec(part);
          if (pkm) { pk.push(...pkm[1].split(',').map(s => clean(s.trim()))); continue; }
          const fkm = /^(?:constraint\s+\S+\s+)?foreign\s+key\s*\(([^)]+)\)\s*references\s+([\w."]+)\s*(?:\(([^)]+)\))?/i.exec(part);
          if (fkm) { fks.push({ from: name, to: clean(fkm[2]), fromCol: clean(fkm[1].split(',')[0].trim()), toCol: fkm[3] ? clean(fkm[3].split(',')[0].trim()) : 'id' }); continue; }
          if (/^(constraint|unique|check|exclude)\b/i.test(part)) continue;
          const col = /^(["`\[]?[\w]+["`\]]?)\s+([\w\s[\]().,]+?)(?:\s+(?:not\s+null|null|default|primary|references|unique|check|generated|constraint|collate)\b|$)/i.exec(part);
          if (!col) continue;
          const colName = clean(col[1]);
          columns.push({ name: colName, type: col[2].trim().toLowerCase(), nullable: !/not\s+null|primary\s+key/i.test(part) });
          if (/primary\s+key/i.test(part)) pk.push(colName);
          const ref = /references\s+([\w."]+)\s*(?:\(([^)]+)\))?/i.exec(part);
          if (ref) fks.push({ from: name, to: clean(ref[1]), fromCol: colName, toCol: ref[2] ? clean(ref[2].trim()) : 'id' });
        }
        tables.set(name, { name, columns, pk, rls: false, policies: 0, rows: null });
      }
      for (const m of sql.matchAll(/alter\s+table\s+(?:only\s+)?(?:if\s+exists\s+)?([\w."]+)\s+enable\s+row\s+level\s+security/gi)) rls.set(clean(m[1]), true);
      for (const m of sql.matchAll(/create\s+policy\s+[\s\S]*?\son\s+([\w."]+)/gi)) policies.set(clean(m[1]), (policies.get(clean(m[1])) || 0) + 1);
      for (const m of sql.matchAll(/alter\s+table\s+(?:only\s+)?(?:if\s+exists\s+)?([\w."]+)\s+add\s+(?:constraint\s+\S+\s+)?foreign\s+key\s*\(([^)]+)\)\s*references\s+([\w."]+)\s*(?:\(([^)]+)\))?/gi)) {
        fks.push({ from: clean(m[1]), to: clean(m[3]), fromCol: clean(m[2].split(',')[0].trim()), toCol: m[4] ? clean(m[4].split(',')[0].trim()) : 'id' });
      }
      for (const m of sql.matchAll(/alter\s+table\s+(?:only\s+)?(?:if\s+exists\s+)?([\w."]+)\s+add\s+(?:column\s+)?(?:if\s+not\s+exists\s+)?("?\w+"?)\s+([\w\s[\]()]+?)(?:\s+(?:not|null|default|references)\b|;)/gi)) {
        const t = tables.get(clean(m[1]));
        if (t && !t.columns.some(c => c.name === clean(m[2]))) t.columns.push({ name: clean(m[2]), type: m[3].trim().toLowerCase(), nullable: true });
      }
    }
    for (const [name, t] of tables) { t.rls = !!rls.get(name); t.policies = policies.get(name) || 0; }
    // An unqualified reference means the same schema as the table that makes it.
    for (const f of fks) {
      if (!tables.has(f.to) && f.from.includes('.')) {
        const qualified = `${f.from.split('.')[0]}.${f.to}`;
        if (tables.has(qualified)) f.to = qualified;
      }
    }
    return { tables: [...tables.values()], fks: fks.filter(f => tables.has(f.to) && tables.has(f.from)), views: [], rpc: [], buckets: [] };
  }

  /** Prisma models as tables (offline fallback). */
  function parsePrisma(text) {
    const tables = [], fks = [];
    const models = [...text.matchAll(/model\s+(\w+)\s*\{([\s\S]*?)\n\}/g)];
    const names = new Set(models.map(m => m[1]));
    for (const [, name, body] of models) {
      const columns = [], pk = [];
      const mapped = /@@map\("([^"]+)"\)/.exec(body)?.[1];
      for (const line of body.split('\n').map(l => l.trim()).filter(l => l && !l.startsWith('//') && !l.startsWith('@@'))) {
        const [field, type] = line.split(/\s+/);
        if (!field || !type) continue;
        const base = type.replace(/[?[\]]/g, '');
        const rel = /@relation\([^)]*fields:\s*\[(\w+)[^\]]*\][^)]*references:\s*\[(\w+)/.exec(line);
        if (names.has(base)) { if (rel) fks.push({ from: mapped || name, to: base, fromCol: rel[1], toCol: rel[2] }); continue; }
        columns.push({ name: field, type: base.toLowerCase(), nullable: type.includes('?') });
        if (/@id\b/.test(line)) pk.push(field);
      }
      tables.push({ name: mapped || name, columns, pk, rls: null, policies: 0, rows: null });
    }
    // Relations name models; point them at mapped table names.
    const map = new Map(models.map(m => [m[1], /@@map\("([^"]+)"\)/.exec(m[2])?.[1] || m[1]]));
    fks.forEach(f => { f.to = map.get(f.to) || f.to; });
    return { tables, fks, views: [], rpc: [], buckets: [] };
  }

  /** One deployable environment of a wrangler config: its Worker name, domains and assets. */
  function workerEnv(key, e, base) {
    const routes = [].concat(e.routes || [], e.route ? [e.route] : []);
    const domains = routes.map(r => (typeof r === 'string' ? r : r.pattern) || '')
      .map(p => p.replace(/^https?:\/\//, '').replace(/^\*\.?/, '').split('/')[0]).filter(Boolean);
    return {
      key, name: e.name || (key ? `${base.name}-${key}` : base.name || 'worker'), domains: [...new Set(domains)],
      workersDev: e.workers_dev ?? (key ? false : !routes.length), assets: e.assets || (key ? null : base.assets) || base.assets || null,
    };
  }

  // ---------- Detection ----------

  const read = async (rel) => {
    const r = await fs('read', { path: `${B.root}/${rel}` }).catch(() => null);
    return r && !r.error && typeof r.content === 'string' ? r.content : null;
  };
  /** The config for `dir`: in it or the closest parent; else one in a direct child folder. */
  const isMainConfig = (x) => !x.rel || /(^|\/)wrangler\.(toml|jsonc?)$|\.vercel\/project\.json$/.test(x.rel);
  const nearest = (list, dir) => list.filter(x => under(dir, x.dir))
    .sort((a, b) => b.dir.length - a.dir.length || isMainConfig(b) - isMainConfig(a))[0]
    || list.filter(x => x.dir.startsWith(dir ? dir + '/' : '') && x.dir.split('/').length === (dir ? dir.split('/').length + 1 : 1))[0];
  const dirOf = (rel) => rel.includes('/') ? rel.slice(0, rel.lastIndexOf('/')) : '';
  const under = (rel, dir) => !dir || rel === dir || rel.startsWith(dir + '/');

  async function scan() {
    if (!state.root || B.scanning) return;
    B.scanning = true;
    B.root = state.root;
    renderTop();
    try {
      if (!state.files) state.files = await fs('files').catch(() => []);
      const files = (state.files || []).filter(f => !SKIP.test(f));
      const fileSet = new Set(files);
      const detect = await fs('backend', { action: 'detect' }).catch(() => ({}));
      B.detect = detect || {};
      const comps = [];
      const add = (c) => { comps.push(c); return c; };
      const services = new Map(); // id -> { via: Set, packages: Set }
      const service = (id, via) => {
        if (!services.has(id)) services.set(id, { via: new Set(), packages: new Set() });
        if (via) services.get(id).via.add(via);
        return services.get(id);
      };
      for (const s of detect?.services || []) service(s.id === 'database' ? (s.provider || 'database') : s.id, s.via).ref ??= s.ref;

      // Packages: frontends, servers, services.
      const pkgs = [];
      for (const rel of files.filter(f => /(^|\/)package\.json$/.test(f) && f.split('/').length <= 3)) {
        try { pkgs.push({ rel, dir: dirOf(rel), json: JSON.parse(await read(rel) || '{}') }); } catch { /* not JSON */ }
      }
      const deps = (p) => ({ ...p.json.dependencies, ...p.json.devDependencies });
      const anyDep = (name) => pkgs.some(p => deps(p)[name]);

      // Hosting config.
      const wranglerFiles = files.filter(f => /(^|\/)wrangler(\.[\w-]+)?\.(toml|jsonc?)$/.test(f) && f.split('/').length <= 3);
      const wranglers = [];
      for (const rel of wranglerFiles) {
        const text = await read(rel);
        if (!text) continue;
        try { wranglers.push({ rel, dir: dirOf(rel), cfg: rel.endsWith('.toml') ? parseTOML(text) : parseJSONC(text) }); } catch { /* unreadable */ }
      }
      const vercelLinks = [];
      for (const rel of files.filter(f => /(^|\/)\.vercel\/project\.json$/.test(f))) {
        try { vercelLinks.push({ rel, dir: dirOf(dirOf(rel)), cfg: JSON.parse(await read(rel) || '{}') }); } catch { /* skip */ }
      }
      // .vercel is usually gitignored, so `files` may not list it: look for it directly.
      for (const dir of new Set(['', ...pkgs.map(p => p.dir)])) {
        if (vercelLinks.some(v => v.dir === dir)) continue;
        const text = await read(`${dir ? dir + '/' : ''}.vercel/project.json`);
        if (text) try { vercelLinks.push({ rel: `${dir ? dir + '/' : ''}.vercel/project.json`, dir, cfg: JSON.parse(text) }); } catch { /* skip */ }
      }
      const has = (rel) => fileSet.has(rel);
      let vercelOff = false;
      try { vercelOff = JSON.parse(await read('vercel.json') || '{}')?.git?.deploymentEnabled === false; } catch { /* not JSON */ }
      const hostFor = (dir) => {
        const near = (list) => nearest(list, dir);
        const v = near(vercelLinks);
        const w = near(wranglers);
        if (v && w && vercelOff) return { provider: 'cloudflare', name: w.cfg.pages_build_output_dir ? 'Cloudflare Pages' : 'Cloudflare Workers', detail: w.cfg.name || '', link: w };
        if (v) return { provider: 'vercel', name: 'Vercel', detail: v.cfg.projectName || '', link: v };
        if (w) return { provider: 'cloudflare', name: w.cfg.pages_build_output_dir ? 'Cloudflare Pages' : 'Cloudflare Workers', detail: w.cfg.name || '', link: w };
        if (files.some(f => under(f, dir) && /(^|\/)vercel\.json$/.test(f))) return { provider: 'vercel', name: 'Vercel', detail: '' };
        if (has('netlify.toml')) return { provider: 'netlify', name: 'Netlify', detail: '' };
        if (has('firebase.json')) return { provider: 'firebase', name: 'Firebase Hosting', detail: '' };
        if (has('fly.toml')) return { provider: 'fly', name: 'Fly.io', detail: '' };
        if (files.some(f => /(^|\/)Dockerfile$/.test(f))) return { provider: 'docker', name: 'Container', detail: '' };
        return null;
      };

      // Frontend apps.
      for (const p of pkgs) {
        const d = deps(p);
        const fw = FRAMEWORKS.find(([dep]) => d[dep]);
        if (!fw) continue;
        const [, id] = fw;
        // A plain React/Vue dep inside a server package isn't an app.
        if ((id === 'react' || id === 'vue') && !d.vite && !d['react-scripts'] && !d['react-dom'] && !d.vue) continue;
        const host = hostFor(p.dir);
        const openNext = d['@opennextjs/cloudflare'] || files.some(f => under(f, p.dir) && /open-next\.config\.[jt]s$/.test(f));
        add({
          id: `app:${p.dir}`, lane: 'client', provider: id, dir: p.dir,
          title: p.json.name && !/^(app|web|frontend|client)$/.test(p.json.name) ? p.json.name : `${pname(id)} app`,
          subtitle: `${pname(id)}${d.typescript ? ' · TypeScript' : ''}`,
          host: openNext ? { provider: 'cloudflare', name: 'Cloudflare Workers (OpenNext)', detail: nearest(wranglers, p.dir)?.cfg?.name || '', link: nearest(wranglers, p.dir) } : host,
          evidence: [p.rel], kind: 'app',
        });
      }
      // Next.js API routes and pages/api.
      for (const app of comps.filter(c => c.kind === 'app')) {
        const routes = files.filter(f => under(f, app.dir) && (/(^|\/)app\/(.*\/)?api\/.*route\.[jt]sx?$/.test(f) || /(^|\/)pages\/api\/.+\.[jt]sx?$/.test(f)));
        const actions = [];
        if (routes.length) {
          add({
            id: `api:${app.dir}`, lane: 'compute', provider: app.provider, dir: app.dir, kind: 'routes', owner: app.id,
            title: 'API routes', subtitle: `${routes.length} route${routes.length === 1 ? '' : 's'} · ${app.host?.name || pname(app.provider)}`,
            routes: routes.map(f => ({ rel: f, url: '/' + f.replace(/^.*?(app|pages)\//, '').replace(/\/route\.[jt]sx?$|\.[jt]sx?$/, '').replace(/\/index$/, '').replace(/\(([^)]+)\)\//g, '') })),
            evidence: routes, host: app.host, actions,
          });
        }
      }
      // Servers (Express, Hono, Nest…), unless they're the Worker below.
      for (const p of pkgs) {
        const d = deps(p);
        const server = SERVERS.find(([dep]) => d[dep]);
        if (!server || wranglers.some(w => w.dir === p.dir)) continue;
        add({ id: `server:${p.dir}`, lane: 'compute', provider: server[1], dir: p.dir, kind: 'server',
              title: p.json.name || `${pname(server[1])} server`, subtitle: pname(server[1]), evidence: [p.rel], host: hostFor(p.dir) });
      }
      // Python servers.
      for (const rel of files.filter(f => /(^|\/)(requirements\.txt|pyproject\.toml)$/.test(f) && f.split('/').length <= 2)) {
        const text = (await read(rel) || '').toLowerCase();
        const id = ['fastapi', 'django', 'flask'].find(n => text.includes(n));
        if (id) add({ id: `server:${dirOf(rel)}:py`, lane: 'compute', provider: id, dir: dirOf(rel), kind: 'server',
                      title: `${pname(id)} server`, subtitle: 'Python', evidence: [rel], host: hostFor(dirOf(rel)) });
      }
      // Cloudflare Workers: one card per config, with its environments, sites and bindings.
      // Bindings to the same resource (one D1 database, one Hyperdrive, one queue) from
      // several Workers share a card, with a line from each Worker.
      const shared = new Map(); // resource key -> comp
      for (const w of wranglers) {
        const cfg = w.cfg;
        const openNext = /open-next/.test(cfg.main || '') || /open-next/.test(cfg.assets?.directory || '')
          || pkgs.some(p => p.dir === w.dir && deps(p)['@opennextjs/cloudflare']);
        // Named environments (production, preprod…) are what's deployed; when there are
        // some, the top level is usually just local development.
        const envs = Object.entries(cfg.env || {}).map(([key, e]) => workerEnv(key, e, cfg));
        const top = workerEnv('', cfg, cfg);
        const deployed = envs.length ? envs.sort((a, b) => (b.key === 'production') - (a.key === 'production')) : [top];
        const primary = deployed[0];
        const assets = primary.assets || top.assets;
        const assetsOnly = assets && (!cfg.main || /not-?found/i.test(cfg.main));
        // A site served by this Worker with no framework app found: the site itself is the frontend.
        let app = comps.find(c => c.kind === 'app' && c.host?.link === w);
        if (!app && assets && !openNext && !comps.some(c => c.kind === 'app' && c.dir === w.dir && c.host?.provider === 'cloudflare')) {
          const pkg = pkgs.find(p => p.dir === w.dir);
          app = add({
            id: `app:${w.rel}`, lane: 'client', provider: 'site', dir: w.dir, kind: 'app',
            title: pkg?.json?.name || primary.name, subtitle: assets.not_found_handling === 'single-page-application' ? 'Single-page app' : 'Static site',
            host: { provider: 'cloudflare', name: 'Cloudflare Workers', detail: primary.name, link: w }, evidence: [w.rel],
          });
        } else if (app && !app.host) {
          app.host = { provider: 'cloudflare', name: 'Cloudflare Workers', detail: primary.name, link: w };
        } else if (app?.host?.link === w) {
          app.host.detail = primary.name; // the deployed name (production), not a local placeholder
        }
        if (app) app.domains = deployed.flatMap(e => e.domains);
        const crons = cfg.triggers?.crons || [];
        const worker = add({
          id: `worker:${w.rel}`, lane: 'compute', provider: 'cloudflare', dir: w.dir, kind: 'worker',
          title: primary.name, cfg, main: cfg.main, owner: app?.id || null, config: w.rel.split('/').pop(), envs: deployed,
          subtitle: cfg.pages_build_output_dir ? 'Cloudflare Pages' : openNext ? 'Next.js on Workers (OpenNext)'
            : assetsOnly ? 'Serves the static site' : assets ? 'API + static site' : crons.length ? 'Scheduled Worker' : 'Cloudflare Worker',
          domains: deployed.flatMap(e => e.domains), workersDev: deployed.some(e => e.workersDev),
          crons, vars: Object.keys(cfg.vars || {}), accountId: cfg.account_id || null, observability: !!cfg.observability?.enabled,
          features: [
            ...(cfg.ratelimits?.length ? [`${cfg.ratelimits.length} rate limit${cfg.ratelimits.length === 1 ? '' : 's'}`] : []),
            ...(cfg.observability?.enabled ? ['logs on'] : []),
            ...(cfg.compatibility_flags?.includes('nodejs_compat') ? ['nodejs_compat'] : []),
          ],
          evidence: [w.rel],
        });
        // Every binding, from the top level and each environment.
        const sources = [['', cfg], ...Object.entries(cfg.env || {})];
        const bind = (type, title, icon, lane, key, label, list, env) => {
          for (const b of [].concat(list || [])) {
            const name = b.binding || b.name;
            if (!name) continue;
            const id = `${type}:${key(b) || `${w.rel}:${name}`}`;
            let comp = shared.get(id);
            if (!comp) {
              comp = add({ id, lane, provider: type === 'hyperdrive' ? 'postgres' : 'cloudflare', kind: type, binding: name,
                           bindings: [], workers: [], title: label(b) || name, subtitle: title, icon, info: b,
                           evidence: [w.rel], dir: w.dir, env, config: w.rel.split('/').pop() });
              shared.set(id, comp);
            }
            if (!comp.bindings.includes(name)) comp.bindings.push(name);
            if (!comp.workers.includes(worker.id)) comp.workers.push(worker.id);
            if (!comp.evidence.includes(w.rel)) comp.evidence.push(w.rel);
            comp.subtitle = `${title} · ${comp.bindings.map(n => `env.${n}`).join(', ')}`;
          }
        };
        for (const [env, c] of sources) {
          bind('d1', 'D1 database', 'database', 'data', b => b.database_id || b.database_name, b => b.database_name, c.d1_databases, env);
          bind('hyperdrive', 'Postgres via Hyperdrive', 'database', 'data', b => b.id, () => 'Postgres', c.hyperdrive, env);
          bind('kv', 'KV namespace', 'key', 'data', b => b.id, () => null, c.kv_namespaces, env);
          bind('r2', 'R2 bucket', 'archive', 'data', b => b.bucket_name, b => b.bucket_name, c.r2_buckets, env);
          bind('queue', 'Queue', 'list-ordered', 'data', b => b.queue, b => b.queue, c.queues?.producers, env);
          bind('do', 'Durable Object', 'symbol-class', 'data', b => `${b.script_name || primary.name}:${b.class_name}`, b => b.class_name, c.durable_objects?.bindings, env);
          bind('vectorize', 'Vectorize index', 'symbol-array', 'data', b => b.index_name, b => b.index_name, c.vectorize, env);
          bind('analytics', 'Analytics Engine', 'graph', 'data', b => b.dataset, b => b.dataset, c.analytics_engine_datasets, env);
          bind('workflow', 'Workflow', 'type-hierarchy', 'compute', b => b.name, b => b.name, c.workflows, env);
          if (c.ai?.binding) bind('ai', 'Workers AI', 'sparkle', 'external', () => 'workers-ai', () => 'Workers AI', [c.ai], env);
          if (c.images?.binding) bind('images', 'Cloudflare Images', 'file-media', 'external', () => 'images', () => 'Cloudflare Images', [c.images], env);
          if (c.browser?.binding) bind('browser', 'Browser Rendering', 'browser', 'external', () => 'browser', () => 'Browser Rendering', [c.browser], env);
          // Queues this Worker consumes.
          for (const q of c.queues?.consumers || []) {
            const id = `queue:${q.queue}`;
            let comp = shared.get(id);
            if (!comp) {
              comp = add({ id, lane: 'data', provider: 'cloudflare', kind: 'queue', binding: q.queue, bindings: [], workers: [],
                           title: q.queue, subtitle: 'Queue', icon: 'list-ordered', info: q, evidence: [w.rel], dir: w.dir });
              shared.set(id, comp);
            }
            (comp.consumers ||= []).push(worker.id);
          }
          // Service bindings: calls to other Workers.
          for (const sb of c.services || []) {
            if (!sb.service || sb.service === primary.name || sb.service === cfg.name) continue;
            (worker.calls ||= []).push({ binding: sb.binding, service: sb.service });
          }
        }
      }
      // Service bindings point at a Worker in this project, or at one elsewhere in the account.
      for (const worker of comps.filter(c => c.kind === 'worker')) {
        for (const call of worker.calls || []) {
          const target = comps.find(c => c.kind === 'worker' && (c.title === call.service || c.envs?.some(e => e.name === call.service)));
          if (target) { call.id = target.id; continue; }
          const id = `svcworker:${call.service}`;
          if (!comps.some(c => c.id === id)) add({ id, lane: 'compute', provider: 'cloudflare', kind: 'remote-worker', title: call.service,
                                                    subtitle: `Worker elsewhere · env.${call.binding}`, binding: call.binding, evidence: worker.evidence });
          call.id = id;
        }
      }
      // Supabase.
      const sbDir = files.some(f => f.startsWith('supabase/'));
      const sbUsed = sbDir || services.has('supabase') || anyDep('@supabase/supabase-js') || anyDep('@supabase/ssr');
      if (sbUsed) {
        let ref = services.get('supabase')?.ref || null;
        const linked = (await read('supabase/.temp/project-ref'))?.trim();
        if (linked && /^[a-z]{20}$/.test(linked)) ref = linked;
        try { const chosen = localStorage.getItem(`supabaseRef:${B.root}`); if (!ref && chosen) ref = chosen; } catch { /* no storage */ }
        const migrations = files.filter(f => /^supabase\/migrations\/.+\.sql$/.test(f)).sort();
        add({ id: 'supabase', lane: 'data', provider: 'supabase', kind: 'supabase', title: 'Supabase', ref,
              subtitle: ref ? `Postgres · Auth · Storage` : 'Project not identified yet', migrations,
              evidence: [...(sbDir ? ['supabase/config.toml'].filter(has) : []), ...migrations.slice(-3)],
              via: [...(services.get('supabase')?.via || [])] });
        const fns = [...new Set(files.filter(f => /^supabase\/functions\/[^_/][^/]*\/index\.[jt]s$/.test(f)).map(f => f.split('/')[2]))];
        if (fns.length) add({ id: 'sb-functions', lane: 'compute', provider: 'supabase', kind: 'edge-functions', title: 'Edge Functions',
                              subtitle: `${fns.length} function${fns.length === 1 ? '' : 's'} · Supabase`, functions: fns,
                              evidence: fns.map(f => files.find(x => x.startsWith(`supabase/functions/${f}/index.`))), dir: 'supabase/functions' });
        B.localSchemaFiles = migrations;
      }
      // Prisma.
      const prismaFile = files.find(f => /(^|\/)schema\.prisma$/.test(f));
      if (prismaFile) {
        const text = await read(prismaFile) || '';
        const provider = /datasource\s+\w+\s*\{[\s\S]*?provider\s*=\s*"(\w+)"/.exec(text)?.[1] || 'postgresql';
        const models = [...text.matchAll(/^model\s+(\w+)/gm)].length;
        if (!sbUsed || !/postgres/.test(provider)) {
          const db = [...services.keys()].find(k => DATA_SERVICES.has(k) && k !== 'local') || 'postgres';
          add({ id: 'prisma', lane: 'data', provider: db === 'postgres' ? 'prisma' : db, kind: 'prisma', title: `${provider === 'postgresql' ? 'PostgreSQL' : provider} via Prisma`,
                subtitle: `${models} model${models === 1 ? '' : 's'}${db !== 'postgres' ? ` · ${pname(db)}` : ''}`, evidence: [prismaFile], prisma: text });
          services.delete(db);
        } else {
          comps.find(c => c.id === 'supabase').prisma = text;
        }
      }
      // Firebase.
      if (has('firebase.json') || anyDep('firebase') || anyDep('firebase-admin')) {
        add({ id: 'firebase', lane: 'data', provider: 'firebase', kind: 'firebase', title: 'Firebase', subtitle: 'Firestore · Auth · Storage', evidence: ['firebase.json'].filter(has) });
        services.delete('firebase');
      }
      // Package-based services.
      for (const p of pkgs) for (const dep of Object.keys(deps(p))) if (SERVICE_PACKAGES[dep]) service(SERVICE_PACKAGES[dep]).packages.add(dep);
      services.delete('supabase'); services.delete('vercel'); services.delete('cloudflare'); services.delete('postgres');
      if (comps.some(c => c.kind === 'prisma')) services.delete('database');
      for (const [id, s] of services) {
        if (id === 'local') continue;
        const data = DATA_SERVICES.has(id);
        add({ id: `svc:${id}`, lane: data ? 'data' : 'external', provider: id, kind: 'service', title: pname(id),
              subtitle: [s.packages.size ? [...s.packages].join(', ') : '', s.via.size ? `${s.via.size} env var${s.via.size === 1 ? '' : 's'}` : ''].filter(Boolean).join(' · '),
              via: [...s.via], packages: [...s.packages], evidence: [] });
      }

      // Code keys: the strings that mean "this code uses that piece".
      for (const c of comps) c.keys = keysFor(c);
      const strings = [...new Set(comps.flatMap(c => c.keys))].slice(0, 150);
      const refs = strings.length ? await fs('backend', { action: 'refs', strings }).catch(() => []) : [];
      B.refs = Array.isArray(refs) ? refs.filter(r => !SKIP.test(r.path)) : [];

      B.comps = comps;
      B.byId = new Map(comps.map(c => [c.id, c]));
      B.files = files;
      registerDatabases(files);
      indexRefs();
      B.edges = buildEdges();
      B.scannedAt = Date.now();
      B.vercelLinks = vercelLinks;
      B.wranglers = wranglers;
    } finally {
      B.scanning = false;
    }
    render();
    refreshLive();
  }

  /** Every database the Database view can show, with the files its schema comes from. */
  function registerDatabases(files) {
    const keep = B.dbSel;
    const old = B.dbs;
    B.dbs = new Map();
    const carry = (id, init) => { const e = dbEntry(id, init); const prev = old.get(id); if (prev?.source === 'live') Object.assign(e, { schema: prev.schema, source: prev.source }); return e; };
    const used = new Set();
    const sb = B.byId.get('supabase');
    if (sb) { carry('supabase', { label: 'Supabase', provider: 'supabase', comp: 'supabase', files: sb.migrations, prisma: !sb.migrations.length ? sb.prisma : null }); sb.migrations.forEach(f => used.add(f)); }
    for (const c of B.comps.filter(c => c.kind === 'd1')) {
      const dir = `${c.dir ? c.dir + '/' : ''}${(c.info.migrations_dir || 'migrations').replace(/^\.\//, '')}`;
      const sql = files.filter(f => f.startsWith(dir + '/') && f.endsWith('.sql')).sort();
      sql.forEach(f => used.add(f));
      carry(c.id, { label: `D1 · ${c.title}`, provider: 'cloudflare', comp: c.id, files: sql });
    }
    const otherSQL = files.filter(f => f.endsWith('.sql') && !used.has(f) && /(^|\/)(migrations?|schema|db|sql|database)(\/|\.)/i.test(f)).sort();
    for (const c of B.comps.filter(c => c.kind === 'hyperdrive')) carry(c.id, { label: 'Postgres · Hyperdrive', provider: 'postgres', comp: c.id, files: otherSQL });
    const prisma = B.byId.get('prisma');
    if (prisma) carry('prisma', { label: prisma.title, provider: 'prisma', comp: 'prisma', prisma: prisma.prisma });
    if (!B.dbs.size && otherSQL.length) carry('sql', { label: 'Database (from SQL files)', provider: 'postgres', files: otherSQL });
    B.dbSel = B.dbs.has(keep) ? keep : [...B.dbs.keys()][0] || null;
  }

  const cronText = (c) => ({ '* * * * *': 'every minute', '0 * * * *': 'hourly', '0 0 * * *': 'daily', '0 0 * * 0': 'weekly' }[c]
    || (/^\*\/(\d+) \* \* \* \*$/.exec(c) ? `every ${/^\*\/(\d+)/.exec(c)[1]} min` : /^0 \*\/(\d+) \* \* \*$/.exec(c) ? `every ${/^0 \*\/(\d+)/.exec(c)[1]} h` : c));
  const workerOf = (c) => c.kind === 'worker' ? c
    : c.kind === 'app' && c.host?.provider === 'cloudflare' ? B.comps.find(x => x.kind === 'worker' && x.evidence[0] === c.host.link?.rel) : null;

  function keysFor(c) {
    switch (c.kind) {
      case 'supabase': return ['@supabase/supabase-js', '@supabase/ssr', 'createServerClient(', 'createBrowserClient(', '.from(\'', '.from("', '.rpc(\'', '.rpc("', 'supabase.auth.', '.storage.from(', 'createClient(process.env.NEXT_PUBLIC_SUPABASE', 'SUPABASE_URL'];
      case 'd1': case 'kv': case 'r2': case 'queue': case 'do': case 'hyperdrive': case 'vectorize': case 'analytics':
      case 'workflow': case 'ai': case 'images': case 'browser':
        return (c.bindings || [c.binding]).flatMap(b => [`env.${b}`, `env["${b}"]`, `env?.${b}`]);
      case 'prisma': return ['@prisma/client', 'prisma.'];
      case 'firebase': return ['firebase/firestore', 'firebase-admin', 'getFirestore('];
      case 'service': return [...c.via, ...c.packages.flatMap(p => [`'${p}'`, `"${p}"`])];
      default: return [];
    }
  }

  /** Which piece of the app a file belongs to, for drawing who-talks-to-what. */
  function ownerOf(rel) {
    let best = null, bestScore = -1;
    for (const c of B.comps) {
      let score = -1;
      if (c.kind === 'routes' && c.routes.some(r => r.rel === rel)) score = 100;
      else if (c.kind === 'edge-functions' && rel.startsWith('supabase/functions/')) score = 90;
      else if (c.kind === 'worker' && c.main && rel === `${c.dir ? c.dir + '/' : ''}${c.main.replace(/^\.\//, '')}`) score = 95;
      else if (c.kind === 'worker' && c.main && !/open-next|not-?found/i.test(c.main) && c.config && /^wrangler\.(toml|jsonc?)$/.test(c.config) && under(rel, dirOf(`${c.dir ? c.dir + '/' : ''}${c.main.replace(/^\.\//, '')}`))) score = 80;
      else if (c.kind === 'server' && under(rel, c.dir)) score = 50 + c.dir.length;
      else if (c.kind === 'app' && under(rel, c.dir)) score = 10 + c.dir.length;
      if (score > bestScore) { best = c; bestScore = score; }
    }
    return best;
  }

  function indexRefs() {
    B.refsByFile = new Map();
    B.tables = new Map();
    B.compRefs = new Map();
    const keyOwners = new Map();
    for (const c of B.comps) for (const k of c.keys || []) { if (!keyOwners.has(k)) keyOwners.set(k, []); keyOwners.get(k).push(c.id); }
    for (const r of B.refs) {
      const owners = keyOwners.get(r.match) || [];
      for (const id of owners) {
        if (!B.compRefs.has(id)) B.compRefs.set(id, []);
        B.compRefs.get(id).push(r);
        if (!B.refsByFile.has(r.path)) B.refsByFile.set(r.path, []);
        const comp = B.byId.get(id);
        B.refsByFile.get(r.path).push({ id, label: comp.title, kind: comp.subtitle?.split(' · ')[0] || pname(comp.provider), icon: comp.icon || iconFor(comp), line: r.line });
      }
      // Supabase tables, functions and buckets by name.
      for (const m of r.text.matchAll(/\.(from|rpc)\(\s*['"`]([\w-]+)['"`]/g)) {
        const isBucket = /storage\s*\.from\(/.test(r.text);
        const key = isBucket ? `bucket:${m[2]}` : m[1] === 'rpc' ? `rpc:${m[2]}` : `table:${m[2]}`;
        if (!B.tables.has(key)) B.tables.set(key, []);
        if (!B.tables.get(key).some(x => x.path === r.path && x.line === r.line)) B.tables.get(key).push({ path: r.path, line: r.line, text: r.text });
        if (!B.refsByFile.has(r.path)) B.refsByFile.set(r.path, []);
        const list = B.refsByFile.get(r.path);
        if (!list.some(x => x.id === key)) list.push({ id: key, label: m[2], kind: isBucket ? 'Storage bucket' : m[1] === 'rpc' ? 'Database function' : 'Table', icon: isBucket ? 'archive' : m[1] === 'rpc' ? 'symbol-method' : 'table', line: r.line });
      }
    }
  }

  function iconFor(c) {
    return { app: 'browser', routes: 'symbol-namespace', server: 'server-process', worker: 'zap', 'edge-functions': 'zap',
             supabase: 'database', prisma: 'database', firebase: 'flame', service: c.lane === 'data' ? 'database' : 'plug' }[c.kind] || c.icon || 'circle-filled';
  }

  function buildEdges() {
    const edges = new Map();
    const link = (from, to, count = 1, assumed = false) => {
      if (!from || !to || from === to) return;
      const key = `${from}>${to}`;
      const e = edges.get(key) || { from, to, count: 0, assumed };
      e.count += count;
      e.assumed = e.assumed && assumed;
      edges.set(key, e);
    };
    const comps = B.comps;
    // Frontend → its compute.
    for (const c of comps) {
      if (c.kind === 'routes') link(c.owner, c.id);
      if (c.kind === 'worker' && c.owner) link(c.owner, c.id);
      // Bindings belong to their Workers (as configured, so not "assumed").
      for (const w of c.workers || []) link(w, c.id, 0, false);
      for (const w of c.consumers || []) link(c.id, w, 0, false);
      for (const call of c.calls || []) link(c.id, call.id, 0, false);
    }
    // Everything else from where the code really uses it.
    for (const [id, refs] of B.compRefs || []) {
      const byOwner = new Map();
      for (const r of refs) {
        const owner = ownerOf(r.path);
        if (owner) byOwner.set(owner.id, (byOwner.get(owner.id) || 0) + 1);
      }
      for (const [owner, n] of byOwner) {
        // Bindings are reached through their Worker.
        const comp = B.byId.get(id);
        if (comp.workers?.length && B.byId.get(owner)?.kind === 'app') comp.workers.forEach(w => link(w, id, n));
        else link(owner, id, n);
      }
    }
    // A data piece nothing connects to yet: from the first compute (or app), dashed.
    const firstCompute = comps.find(c => c.lane === 'compute') || comps.find(c => c.lane === 'client');
    for (const c of comps.filter(c => c.lane === 'data' || c.lane === 'external')) {
      if (![...edges.values()].some(e => e.to === c.id)) link(firstCompute?.id, c.id, 0, true);
    }
    for (const c of comps.filter(c => c.lane === 'compute')) {
      if (![...edges.values()].some(e => e.to === c.id)) link(comps.find(x => x.lane === 'client')?.id, c.id, 0, true);
    }
    return [...edges.values()];
  }

  // ---------- Live data ----------

  const rowsOf = (res) => {
    let j = res?.json;
    if (j && !Array.isArray(j) && typeof j === 'object') j = j.rows || j.data || j.result || j.results || j;
    return Array.isArray(j) ? j : j ? [j] : [];
  };
  const dataOf = (res) => {
    const row = rowsOf(res)[0];
    if (!row) return null;
    let v = row.data ?? Object.values(row)[0];
    if (typeof v === 'string') { try { v = JSON.parse(v); } catch { /* text */ } }
    return v;
  };
  const errorOf = (res) => res?.error ? String(res.error) : null;

  async function call(action, args = {}) {
    B.busy++;
    renderTop();
    try { return await fs('backend', { action, ...args }); }
    catch (e) { return { error: String(e) }; }
    finally { B.busy--; renderTop(); }
  }

  let liveRunning = false;
  async function refreshLive(force) {
    if (!B.comps.length || liveRunning || !B.visible) return;
    liveRunning = true;
    try {
      const jobs = [];
      jobs.push(call('gitState').then(r => { B.git = r; }));
      const sb = B.byId.get('supabase');
      if (sb && B.detect?.tools?.supabase) {
        jobs.push(call('supabaseProjects').then(r => {
          const list = rowsOf(r);
          B.live.supabaseProjects = r?.error ? null : list;
          B.live.supabaseProjectsError = errorOf(r);
          if (sb.ref) B.live.supabase = list.find(p => p.ref === sb.ref || p.id === sb.ref) || null;
        }));
        if (sb.ref) {
          jobs.push(call('supabaseSchema', { ref: sb.ref }).then(r => {
            const data = dataOf(r);
            const db = dbEntry('supabase');
            if (data?.tables) { db.schema = data; db.source = 'live'; db.error = null; }
            else db.error = errorOf(r) || 'No schema returned';
          }));
          jobs.push(call('supabaseMigrations', { ref: sb.ref }).then(r => { const d = dataOf(r); B.live.migrations = Array.isArray(d) ? d : null; }));
          jobs.push(call('supabaseStats', { ref: sb.ref }).then(r => {
            const d = dataOf(r);
            if (d) {
              const prev = B.live.stats;
              B.live.stats = d;
              // Tables written to since the last poll pulse in the Database view.
              B.live.hotTables = new Set();
              if (prev?.writes) for (const [t, n] of Object.entries(d.writes || {})) if (n > (prev.writes[t] || 0)) B.live.hotTables.add(t);
            }
          }));
          if (B.byId.get('sb-functions') || force) {
            jobs.push(call('supabaseFunctions', { ref: sb.ref }).then(r => { B.live.functions = rowsOf(r); }));
          }
        }
      }
      if (B.detect?.tools?.vercel) {
        for (const v of B.vercelLinks || []) {
          jobs.push(call('vercelDeploys', { dir: v.dir }).then(r => {
            B.live.vercel = B.live.vercel || {};
            const name = v.cfg.projectName;
            const all = r?.json?.deployments || rowsOf(r);
            B.live.vercel[v.dir] = r?.error ? { error: errorOf(r), stale: !!r.stale }
              : { deployments: all.filter(d => !name || d.name === name).slice(0, 20) };
            if (r?.stale) { v.stale = true; rehost(); }
          }));
        }
      }
      if (B.detect?.tools?.wrangler) {
        B.live.workers = B.live.workers || {};
        for (const c of B.comps.filter(c => c.kind === 'worker')) {
          for (const env of c.envs) {
            jobs.push(call('wrangler', { what: 'deployments', dir: c.dir, config: c.config, env: env.key }).then(r => {
              B.live.workers[`${c.id}|${env.key}`] = r?.error ? { error: errorOf(r) } : { deployments: rowsOf(r) };
            }));
          }
        }
        const firstWith = (key) => B.comps.find(c => c.kind === key);
        const d1 = firstWith('d1'), kv = firstWith('kv'), r2 = firstWith('r2');
        if (d1) jobs.push(call('wrangler', { what: 'd1', dir: d1.dir }).then(r => { B.live.d1 = r?.error ? { error: errorOf(r) } : rowsOf(r); }));
        if (kv) jobs.push(call('wrangler', { what: 'kv', dir: kv.dir }).then(r => { B.live.kv = r?.error ? { error: errorOf(r) } : rowsOf(r); }));
        if (r2) jobs.push(call('wrangler', { what: 'r2', dir: r2.dir }).then(r => {
          B.live.r2 = r?.error ? { error: errorOf(r) } : (r?.text || '').split('\n').map(l => /^name:\s*(\S+)/.exec(l)?.[1]).filter(Boolean);
        }));
        // Each D1 database: its live tables, and migrations not applied yet.
        for (const c of B.comps.filter(c => c.kind === 'd1' && c.info.database_name)) {
          const args = { dir: c.dir, config: c.config, env: c.env || '', database: c.info.database_name };
          jobs.push(call('wrangler', { what: 'd1Schema', ...args }).then(r => {
            const db = dbEntry(c.id);
            const rows = rowsOf(r)[0]?.results || rowsOf(r);
            const sql = rows.map(x => x.sql).filter(Boolean);
            if (r?.error || !sql.length) { db.error = errorOf(r) || (rows.length ? null : 'No tables yet'); return; }
            const parsed = parseSQL([{ text: sql.map(x => x.replace(/;?\s*$/, ';')).join('\n') }]);
            parsed.tables.forEach(t => { t.rls = null; });
            db.schema = parsed; db.source = 'live'; db.error = null;
          }));
          if (c.info.migrations_dir || B.files?.some(f => under(f, `${c.dir ? c.dir + '/' : ''}migrations`) && f.endsWith('.sql'))) {
            jobs.push(call('wrangler', { what: 'd1Migrations', ...args }).then(r => {
              if (r?.error) { c.pending = null; c.pendingError = errorOf(r); return; }
              const text = r?.text || JSON.stringify(r?.json || '');
              c.pending = /no migrations to apply/i.test(text) ? [] : [...new Set(text.match(/[\w-]+\.sql/g) || [])];
            }));
          }
        }
      }
      // Offline schema from migrations or Prisma while the live one loads (or if there isn't one).
      jobs.push(loadLocalSchemas());
      // Re-render as each answer lands.
      jobs.forEach(j => j.then(() => renderSoon()));
      await Promise.allSettled(jobs);
      B.liveAt = Date.now();
    } finally {
      liveRunning = false;
      render();
    }
  }

  /** A stale Vercel link (the project is gone): host the app on what's left, e.g. Cloudflare. */
  function rehost() {
    for (const c of B.comps.filter(c => c.kind === 'app' && c.host?.provider === 'vercel')) {
      const link = c.host.link;
      if (!link?.stale) continue;
      const w = nearest(B.wranglers || [], c.dir);
      c.host = w ? { provider: 'cloudflare', name: w.cfg.pages_build_output_dir ? 'Cloudflare Pages' : 'Cloudflare Workers', detail: w.cfg.name || '', link: w }
                 : { provider: 'vercel', name: 'Vercel (link is stale)', detail: link.cfg.projectName || '', link };
    }
    renderSoon();
  }

  /** Schemas from the project's own files: SQL migrations (Supabase, D1, plain Postgres) or Prisma. */
  async function loadLocalSchemas() {
    const fromFiles = async (rels) => {
      const files = [];
      for (const rel of rels.slice(-250)) { const text = await read(rel); if (text) files.push({ rel, text }); }
      return parseSQL(files);
    };
    for (const db of B.dbs.values()) {
      if (db.source === 'live' || db.loadedLocal || !db.files?.length && !db.prisma) continue;
      db.loadedLocal = true;
      const parsed = db.prisma ? parsePrisma(db.prisma) : await fromFiles(db.files);
      if (db.source === 'live' || !parsed.tables.length) continue;
      if (db.provider === 'cloudflare') parsed.tables.forEach(t => { t.rls = null; }); // SQLite has no RLS
      db.schema = parsed;
      db.source = db.prisma ? 'prisma' : 'migrations';
    }
  }

  // ---------- Status, drift and agent awareness ----------

  const ago = (time) => {
    if (!time) return '';
    const s = Math.round((Date.now() - time) / 1000);
    if (s < 60) return 'just now';
    if (s < 3600) return `${Math.round(s / 60)}m ago`;
    if (s < 86400) return `${Math.round(s / 3600)}h ago`;
    return `${Math.round(s / 86400)}d ago`;
  };
  const num = (n) => n == null ? '–' : n >= 1e6 ? `${(n / 1e6).toFixed(1)}M` : n >= 1e3 ? `${(n / 1e3).toFixed(1)}k` : String(n);
  const bytes = (n) => n == null ? '' : n >= 1e9 ? `${(n / 1e9).toFixed(1)} GB` : n >= 1e6 ? `${(n / 1e6).toFixed(1)} MB` : `${Math.round(n / 1e3)} kB`;

  /** [label, tone] for a card: ok, warn, err, off, busy. */
  function statusOf(c) {
    const L = B.live;
    if (c.kind === 'supabase') {
      if (!c.ref) return ['Pick project', 'warn'];
      if (!B.detect?.tools?.supabase) return ['CLI not installed', 'off'];
      if (L.supabaseProjectsError) return ['Not signed in', 'off'];
      const p = L.supabase;
      if (!p) return [L.supabaseProjects ? 'Not in your account' : 'Checking…', L.supabaseProjects ? 'warn' : 'busy'];
      if (/HEALTHY/.test(p.status)) return ['Healthy', 'ok'];
      if (/INACTIVE|PAUSED/.test(p.status)) return ['Paused', 'warn'];
      return [p.status.replace(/_/g, ' ').toLowerCase(), 'warn'];
    }
    const vercel = vercelFor(c);
    if (vercel) {
      if (vercel.error) return ['Not linked', 'off'];
      const prod = vercel.deployments?.find(d => d.target === 'production') || vercel.deployments?.[0];
      if (!prod) return ['No deploys', 'off'];
      return [{ READY: 'Live', ERROR: 'Failed', BUILDING: 'Building', QUEUED: 'Queued', CANCELED: 'Canceled', INITIALIZING: 'Starting' }[prod.state] || prod.state,
              { READY: 'ok', ERROR: 'err', BUILDING: 'busy', QUEUED: 'busy', INITIALIZING: 'busy' }[prod.state] || 'warn'];
    }
    const worker = workerFor(c);
    if (worker) {
      if (worker.error) return [/login|auth/i.test(worker.error) ? 'Not signed in' : 'Unavailable', 'off'];
      return worker.deployments?.length ? ['Deployed', 'ok'] : ['Never deployed', 'warn'];
    }
    if (c.kind === 'd1') {
      if (!B.live.d1) return ['', 'none'];
      if (B.live.d1.error) return ['Unavailable', 'off'];
      return B.live.d1.some?.(d => d.uuid === c.info.database_id || d.name === c.info.database_name) ? ['Exists', 'ok'] : ['Not found', 'err'];
    }
    if (c.kind === 'kv') {
      if (!B.live.kv || B.live.kv.error) return ['', 'none'];
      return B.live.kv.some?.(k => k.id === c.info.id) ? ['Exists', 'ok'] : ['Not found', 'err'];
    }
    if (c.kind === 'r2') {
      if (!B.live.r2 || B.live.r2.error) return ['', 'none'];
      return B.live.r2.includes?.(c.info.bucket_name) ? ['Exists', 'ok'] : ['Not found', 'err'];
    }
    if (c.lane === 'client' && !c.host) return ['Local', 'off'];
    return ['', 'none'];
  }

  function vercelFor(c) {
    if (!B.live.vercel) return null;
    if (c.host?.provider !== 'vercel' && c.kind !== 'app') return null;
    const link = c.host?.link;
    return link && c.kind === 'app' && c.host?.provider === 'vercel' && B.vercelLinks?.includes(link) ? B.live.vercel[link.dir] : null;
  }
  /** Live deploys of a Worker's main environment (production when it has one). */
  function workerFor(c, envKey) {
    const w = workerOf(c);
    if (!B.live.workers || !w) return null;
    return B.live.workers[`${w.id}|${envKey ?? w.envs[0].key}`] || null;
  }
  const lastDeploy = (live) => (live?.deployments || []).map(x => Date.parse(x.created_on || x.createdOn || x.created_at || 0)).filter(Boolean).sort((a, b) => b - a)[0] || null;

  /** What's out of step between the code and what's deployed. */
  function driftOf(c) {
    const out = [];
    if (c.kind === 'supabase' && c.migrations?.length && B.live.migrations) {
      const remote = new Set(B.live.migrations.map(m => String(m.version)));
      const local = c.migrations.map(f => f.split('/').pop().split('_')[0]);
      const pending = local.filter(v => !remote.has(v));
      if (pending.length) out.push({ tone: 'warn', text: `${pending.length} migration${pending.length === 1 ? '' : 's'} not applied`, detail: pending });
      const extra = [...remote].filter(v => !local.includes(v));
      if (extra.length) out.push({ tone: 'off', text: `${extra.length} remote-only migration${extra.length === 1 ? '' : 's'}` });
    }
    const vercel = vercelFor(c);
    if (vercel?.deployments && B.git?.head) {
      const prod = vercel.deployments.find(d => d.target === 'production' && d.state === 'READY');
      const sha = prod?.meta?.githubCommitSha;
      if (sha && !B.git.head.startsWith(sha.slice(0, 7))) out.push({ tone: 'warn', text: 'Production is behind your code', detail: [`Live: ${sha.slice(0, 7)} ${prod.meta.githubCommitMessage?.split('\n')[0] || ''}`, `Local: ${B.git.head.slice(0, 7)}`] });
    }
    if (c.kind === 'd1' && c.pending?.length) out.push({ tone: 'warn', text: `${c.pending.length} migration${c.pending.length === 1 ? '' : 's'} not applied`, detail: c.pending });
    if (c.kind === 'worker' || (c.kind === 'app' && workerOf(c))) {
      const deployed = lastDeploy(workerFor(c));
      if (deployed && B.git?.committed && B.git.committed > deployed + 60000) {
        out.push({ tone: 'warn', text: 'Newer commits than the last deploy', detail: [`Deployed ${ago(deployed)} · last commit ${ago(B.git.committed)}`] });
      }
    }
    const dirtyHere = (B.git?.dirty || []).filter(l => {
      const rel = l.slice(3).replace(/^"|"$/g, '');
      return (c.evidence || []).some(e => e === rel) || (c.kind === 'supabase' && rel.startsWith('supabase/')) ||
             ((c.kind === 'worker' || c.kind === 'routes' || c.kind === 'app') && under(rel, c.dir || '') && c.dir);
    });
    if (dirtyHere.length && c.kind !== 'app') out.push({ tone: 'off', text: `${dirtyHere.length} uncommitted change${dirtyHere.length === 1 ? '' : 's'}` });
    const touch = B.agent.get(c.id);
    const deployedAt = deployTime(c);
    if (touch && deployedAt && touch.last > deployedAt && (c.kind === 'worker' || c.kind === 'routes' || c.kind === 'edge-functions')) {
      out.push({ tone: 'warn', text: 'Edited since the last deploy' });
    }
    return out;
  }

  function deployTime(c) {
    const d = lastDeploy(workerFor(c));
    if (d) return d;
    const v = vercelFor(c) || (c.owner && vercelFor(B.byId.get(c.owner)));
    return v?.deployments?.find(x => x.target === 'production')?.createdAt || null;
  }

  function metricsOf(c) {
    const L = B.live;
    const m = [];
    if (c.kind === 'supabase') {
      if (L.supabase?.region) m.push(L.supabase.region);
      const sbs = B.dbs.get('supabase');
      if (sbs?.schema && sbs.source === 'live') {
        m.push(`${sbs.schema.tables.length} tables`);
        if (sbs.schema.users != null) m.push(`${num(sbs.schema.users)} users`);
        if (sbs.schema.size) m.push(bytes(sbs.schema.size));
      } else if (c.migrations?.length) m.push(`${c.migrations.length} migrations`);
      if (L.stats?.connections != null) m.push(`${L.stats.connections} conn`);
    } else if (c.kind === 'routes') {
      m.push(c.routes.slice(0, 3).map(r => r.url).join('  '));
    } else if (c.kind === 'worker') {
      const last = lastDeploy(workerFor(c));
      if (last) m.push(`deployed ${ago(last)}`);
      if (c.domains?.length) m.push(c.domains[0] + (c.domains.length > 1 ? ` +${c.domains.length - 1}` : ''));
      else if (c.workersDev) m.push('workers.dev');
      if (c.envs.length > 1 || c.envs[0].key) m.push(c.envs.map(e => e.key || 'default').join(' / '));
      if (c.crons?.length) m.push(`cron ${c.crons.map(cronText).join(', ')}`);
    } else if (c.kind === 'app' && c.domains?.length) {
      m.push(c.domains[0] + (c.domains.length > 1 ? ` +${c.domains.length - 1}` : ''));
      const last = lastDeploy(workerFor(c));
      if (last) m.push(`deployed ${ago(last)}`);
    } else if (c.kind === 'hyperdrive') {
      const db = B.dbs.get(c.id);
      if (db?.schema) m.push(`${db.schema.tables.length} tables${db.source === 'migrations' ? ' (from migrations)' : ''}`);
    } else if (c.kind === 'app') {
      const v = vercelFor(c);
      const prod = v?.deployments?.find(d => d.target === 'production');
      if (prod) m.push(`${ago(prod.createdAt)}`);
      const errors = v?.deployments?.filter(d => d.state === 'ERROR').length;
      if (errors) m.push(`${errors} failed of last ${v.deployments.length}`);
    } else if (c.kind === 'edge-functions') {
      m.push(c.functions.slice(0, 3).join(', '));
    } else if (c.kind === 'd1') {
      const d = Array.isArray(L.d1) && L.d1.find(x => x.uuid === c.info.database_id || x.name === c.info.database_name);
      const db = B.dbs.get(c.id);
      if (db?.schema) m.push(`${db.schema.tables.length} tables`);
      else if (d?.num_tables != null) m.push(`${d.num_tables} tables`);
      if (d?.file_size) m.push(bytes(d.file_size));
    }
    const refs = B.compRefs?.get(c.id)?.length;
    if (refs) m.push(`${new Set(B.compRefs.get(c.id).map(r => r.path)).size} files use it`);
    return m.filter(Boolean);
  }

  /** The agent edited a file: light up the pieces it belongs to. */
  function agentTouched(abs, kind) {
    if (!B.root || !abs) return;
    const root = canonical(B.root).toLowerCase();
    const path = canonical(abs);
    if (!path.toLowerCase().startsWith(root + '/')) return;
    const rel = path.slice(root.length + 1);
    const hits = new Set();
    for (const c of B.comps) {
      if ((c.evidence || []).includes(rel)) hits.add(c.id);
      if (c.kind === 'supabase' && rel.startsWith('supabase/')) hits.add(c.id);
      if (c.kind === 'edge-functions' && rel.startsWith('supabase/functions/')) hits.add(c.id);
    }
    const owner = ownerOf(rel);
    if (owner && owner.kind !== 'app') hits.add(owner.id);
    for (const r of B.refsByFile.get(rel) || []) hits.add(r.id);
    const now = Date.now();
    for (const id of hits) {
      const entry = B.agent.get(id) || { files: new Set(), last: 0 };
      entry.files.add(rel);
      entry.last = now;
      B.agent.set(id, entry);
    }
    // Config or schema changed: look again soon (code links too).
    clearTimeout(agentTouched.timer);
    const config = /(^|\/)(package\.json|wrangler\.(toml|jsonc?)|schema\.prisma|vercel\.json|\.env[^/]*)$|^supabase\//.test(rel);
    agentTouched.timer = setTimeout(() => { if (config) scan(); else { refreshRefs(); } }, config ? 2500 : 6000);
    if (hits.size) renderSoon();
  }

  async function refreshRefs() {
    const strings = [...new Set(B.comps.flatMap(c => c.keys || []))].slice(0, 150);
    if (!strings.length) return;
    const refs = await fs('backend', { action: 'refs', strings }).catch(() => null);
    if (!Array.isArray(refs)) return;
    B.refs = refs.filter(r => !SKIP.test(r.path));
    indexRefs();
    B.edges = buildEdges();
    renderSoon();
  }

  // ---------- Rendering ----------

  let renderTimer = 0;
  function renderSoon() { clearTimeout(renderTimer); renderTimer = setTimeout(render, 120); }

  function logo(provider, size = 22) {
    const box = el('span', 'be-logo');
    box.style.setProperty('--b', pcolor(provider));
    box.style.width = box.style.height = `${size}px`;
    if (SVG[provider]) box.innerHTML = SVG[provider];
    else box.append(el('b', null, pname(provider).replace(/[^A-Za-z0-9]/g, '').slice(0, provider === 'next' ? 1 : 2)));
    return box;
  }

  function renderTop() {
    if (!top) return;
    refreshBtn?.classList.toggle('spinning', B.busy > 0 || B.scanning);
    if (updatedEl) updatedEl.textContent = B.scanning ? 'Scanning project…' : B.busy ? 'Checking live status…' : B.liveAt ? `Updated ${ago(B.liveAt)}` : '';
  }

  function summary() {
    const app = B.comps.find(c => c.lane === 'client');
    const parts = [];
    if (app) parts.push(`${pname(app.provider)}${app.host ? ` on ${app.host.name.replace(/ \(.*\)$/, '')}` : ''}`);
    const data = B.comps.filter(c => c.lane === 'data');
    const sb = B.byId.get('supabase');
    if (sb) parts.push(`Supabase${B.live.supabase?.region ? ` ${B.live.supabase.region}` : ''}`);
    const cf = data.filter(c => c.provider === 'cloudflare');
    if (cf.length) parts.push(`${cf.length} Cloudflare binding${cf.length === 1 ? '' : 's'}`);
    const other = data.filter(c => c.provider !== 'cloudflare' && c.id !== 'supabase');
    other.forEach(c => parts.push(c.title));
    const ext = B.comps.filter(c => c.lane === 'external').length;
    if (ext) parts.push(`${ext} service${ext === 1 ? '' : 's'}`);
    return parts.join(' · ');
  }

  function render() {
    if (!wrap || !B.visible) return;
    renderTop();
    if (summaryEl) summaryEl.textContent = B.comps.length ? summary() : '';
    wrap.querySelectorAll('.be-view button').forEach(b => b.classList.toggle('on', b.dataset.view === B.view));
    archEl.classList.toggle('hidden', B.view !== 'arch');
    dbEl.classList.toggle('hidden', B.view !== 'db');
    if (B.view === 'arch') renderArch(); else renderDB();
    renderSide();
  }

  function card(c) {
    const node = el('div', 'be-card');
    node.dataset.id = c.id;
    node.style.setProperty('--b', pcolor(c.host?.provider && c.lane === 'client' ? c.provider : c.provider));
    if (B.selected === c.id) node.classList.add('selected');
    const head = el('div', 'be-card-head');
    head.append(logo(c.provider));
    const titles = el('div', 'be-titles');
    titles.append(el('div', 'be-title', c.title), el('div', 'be-sub', c.subtitle || ''));
    head.append(titles);
    const [label, tone] = statusOf(c);
    if (label) head.append(el('span', `be-status ${tone}`, label));
    node.append(head);
    if (c.host && c.lane === 'client') {
      const host = el('div', 'be-host');
      host.append(logo(c.host.provider, 14), `${c.host.name}${c.host.detail ? ` · ${c.host.detail}` : ''}`);
      node.append(host);
    }
    const metrics = metricsOf(c);
    if (metrics.length) node.append(el('div', 'be-metrics', metrics.join(' · ')));
    const badges = el('div', 'be-badges');
    for (const d of driftOf(c)) badges.append(el('span', `be-badge ${d.tone}`, d.text));
    const touch = B.agent.get(c.id);
    if (touch) {
      const b = el('span', 'be-badge agent', `✎ ${agentName()} · ${touch.files.size} file${touch.files.size === 1 ? '' : 's'} · ${ago(touch.last)}`);
      badges.append(b);
      if (Date.now() - touch.last < 6000) node.classList.add('pulse');
    }
    if (badges.childElementCount) node.append(badges);
    node.onclick = () => { B.selected = B.selected === c.id ? null : c.id; render(); };
    return node;
  }

  function renderArch() {
    archEl.replaceChildren();
    if (!state.root) {
      const e = el('div', 'be-empty');
      e.append(el('div', 'be-empty-title', 'No project folder open'), el('div', null, 'Open the code editor from a terminal that’s inside a project, and its backend shows up here.'));
      archEl.append(e);
      return;
    }
    if (B.scanning && !B.comps.length) { archEl.append(el('div', 'be-empty', 'Looking at the project…')); return; }
    if (!B.comps.length) {
      const e = el('div', 'be-empty');
      e.append(el('div', 'be-empty-title', 'No backend found in this project'),
               el('div', null, 'GhosttyEXTREME looks for Supabase, Cloudflare (wrangler), Vercel, Prisma, Firebase, server frameworks and the services your env variables point at.'));
      archEl.append(e);
      return;
    }
    svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
    svg.classList.add('be-wires');
    archEl.append(svg);
    const grid = el('div', 'be-lanes');
    // Too narrow for the lanes side by side: stack them, flowing top to bottom.
    const used = LANES.filter(([lane]) => B.comps.some(c => c.lane === lane)).length;
    grid.classList.toggle('stacked', stageEl.clientWidth < used * 236 + (used - 1) * 46 + 36);
    for (const [lane, name, icon] of LANES) {
      const comps = B.comps.filter(c => c.lane === lane);
      if (!comps.length) continue;
      const col = el('div', 'be-lane');
      const h = el('div', 'be-lane-title');
      h.append(el('i', `codicon codicon-${icon}`), name, el('span', 'be-count', String(comps.length)));
      col.append(h);
      comps.forEach(c => col.append(card(c)));
      grid.append(col);
    }
    archEl.append(grid);
    requestAnimationFrame(drawWires);
  }

  function drawWires() {
    if (!svg || !archEl.isConnected || B.view !== 'arch') return;
    const base = archEl.getBoundingClientRect();
    svg.setAttribute('width', archEl.scrollWidth);
    svg.setAttribute('height', archEl.scrollHeight);
    svg.replaceChildren();
    const boxOf = (id) => {
      const n = archEl.querySelector(`.be-card[data-id="${CSS.escape(id)}"]`);
      if (!n) return null;
      const r = n.getBoundingClientRect();
      const t = r.top - base.top + archEl.scrollTop;
      return { l: r.left - base.left + archEl.scrollLeft, r: r.right - base.left + archEl.scrollLeft,
               y: t + Math.min(24, r.height / 2), t, b: t + r.height, cx: (r.left + r.right) / 2 - base.left + archEl.scrollLeft };
    };
    const ns = 'http://www.w3.org/2000/svg';
    for (const e of B.edges) {
      const a = boxOf(e.from), b = boxOf(e.to);
      if (!a || !b) continue;
      let d;
      if (b.t >= a.b - 4 && !(b.l >= a.r - 4)) {
        // Stacked: from the bottom of one card to the top of the next.
        const dy = Math.max(24, (b.t - a.b) / 2);
        d = `M${a.cx},${a.b} C${a.cx},${a.b + dy} ${b.cx},${b.t - dy} ${b.cx},${b.t}`;
      } else {
        const forward = b.l >= a.r - 4;
        const x1 = forward ? a.r : a.l, x2 = forward ? b.l : b.r;
        const dx = Math.max(40, Math.abs(x2 - x1) / 2) * (forward ? 1 : -1);
        d = `M${x1},${a.y} C${x1 + dx},${a.y} ${x2 - dx},${b.y} ${x2},${b.y}`;
      }
      const to = B.byId.get(e.to);
      const [, tone] = statusOf(to);
      const active = B.selected && (e.from === B.selected || e.to === B.selected);
      const path = document.createElementNS(ns, 'path');
      path.setAttribute('d', d);
      path.setAttribute('class', `be-wire ${e.assumed ? 'assumed' : ''} ${tone === 'err' ? 'err' : ''} ${active ? 'active' : ''} ${B.selected && !active ? 'faded' : ''}`);
      path.style.setProperty('--b', pcolor(to.provider));
      const title = document.createElementNS(ns, 'title');
      title.textContent = e.assumed ? `${B.byId.get(e.from)?.title} → ${to.title} (not seen in code yet)`
                                    : `${B.byId.get(e.from)?.title} → ${to.title}${e.count ? ` · ${e.count} reference${e.count === 1 ? '' : 's'} in code` : ''}`;
      path.append(title);
      svg.append(path);
      // A pulse travelling along live connections.
      if (!e.assumed && tone !== 'err' && tone !== 'off') {
        const dot = document.createElementNS(ns, 'circle');
        dot.setAttribute('r', active ? 3 : 2.2);
        dot.setAttribute('class', 'be-pulse');
        dot.style.setProperty('--b', pcolor(to.provider));
        const motion = document.createElementNS(ns, 'animateMotion');
        motion.setAttribute('dur', `${2.4 + (e.from.length % 5) * 0.3}s`);
        motion.setAttribute('repeatCount', 'indefinite');
        motion.setAttribute('path', d);
        dot.append(motion);
        svg.append(dot);
      }
    }
  }

  // ----- Database view -----

  function renderDB() {
    dbEl.replaceChildren();
    // Until you pick one, show a database that has a schema.
    if (!B.dbPicked && !curDB()?.schema) {
      const withSchema = [...B.dbs.values()].find(d => d.schema);
      if (withSchema) B.dbSel = withSchema.id;
    }
    const db = curDB();
    const schema = db?.schema;
    const sb = B.byId.get('supabase');
    const bar = el('div', 'be-dbbar');
    // One chip per database: Supabase, each D1, Postgres behind Hyperdrive, Prisma…
    if (B.dbs.size > 1) {
      const pick = el('div', 'be-dbpick');
      for (const d of B.dbs.values()) {
        const b = el('button', d.id === db?.id ? 'on' : '');
        b.append(logo(d.provider === 'postgres' ? 'postgres' : d.provider, 14), d.label);
        if (d.schema) b.append(el('span', 'n', String(d.schema.tables.length)));
        b.onclick = () => { B.dbSel = d.id; B.dbPicked = true; B.selected = null; B.dbFilter = ''; render(); };
        pick.append(b);
      }
      bar.append(pick);
    }
    if (schema) {
      const src = el('span', `be-src ${db.source}`);
      src.textContent = db.source === 'live' ? `Live · ${db.provider === 'supabase' ? `Supabase${B.live.supabase?.name ? ` · ${B.live.supabase.name}` : ''}` : db.label}`
        : db.source === 'prisma' ? 'From Prisma schema (local)' : `From ${db.files?.length || ''} migration${db.files?.length === 1 ? '' : 's'} (local)`;
      bar.append(src);
      const postgres = db.provider === 'supabase' || db.provider === 'postgres';
      const noRls = schema.tables.filter(t => t.rls === false);
      bar.append(el('span', 'be-dbstat', `${schema.tables.length} tables`), el('span', 'be-dbstat', `${schema.fks.length} relations`));
      if (postgres && db.source !== 'prisma') {
        bar.append(el('span', `be-dbstat ${noRls.length ? 'warn' : 'ok'}`, noRls.length ? `${noRls.length} without RLS` : 'RLS on every table'));
      }
      if (schema.buckets?.length) bar.append(el('span', 'be-dbstat', `${schema.buckets.length} storage bucket${schema.buckets.length === 1 ? '' : 's'}`));
      if (db.error && db.source !== 'live') bar.append(el('span', 'be-dbstat off', `Live schema unavailable: ${db.error.split('\n')[0].slice(0, 80)}`));
      // Big schemas: search, and pick a Postgres schema (core, public…).
      const schemas = [...new Set(schema.tables.map(t => t.name.includes('.') ? t.name.split('.')[0] : 'public'))];
      if (schema.tables.length > 12) {
        const input = el('input', 'be-dbsearch');
        input.placeholder = `Search ${schema.tables.length} tables…`;
        input.value = B.dbFilter;
        input.oninput = () => { B.dbFilter = input.value; clearTimeout(input.t); input.t = setTimeout(() => { render(); const i = dbEl.querySelector('.be-dbsearch'); i?.focus(); i?.setSelectionRange(i.value.length, i.value.length); }, 180); };
        bar.append(input);
      }
      if (schemas.length > 1) for (const name of schemas) {
        const chip = el('button', `be-schemachip ${B.dbFilter === `${name}.` ? 'on' : ''}`, name);
        chip.onclick = () => { B.dbFilter = B.dbFilter === `${name}.` ? '' : `${name}.`; render(); };
        bar.append(chip);
      }
    }
    dbEl.append(bar);
    if (!schema) {
      const e = el('div', 'be-empty');
      if (!B.dbs.size) e.append(el('div', 'be-empty-title', 'No database found'), el('div', null, 'Supabase projects, Cloudflare D1, Postgres (Hyperdrive) with SQL migrations, and Prisma schemas show up here.'));
      else if (db.id === 'supabase' && sb && !sb.ref) e.append(el('div', 'be-empty-title', 'Which Supabase project is this?'), projectPicker());
      else e.append(el('div', 'be-empty-title', B.busy ? 'Loading the schema…' : 'No schema yet'),
                    el('div', null, db.error ? `${db.label}: ${db.error.slice(0, 220)}` : db.files?.length === 0 && db.provider === 'postgres' ? 'No SQL migrations found for this database.' : 'Waiting for the database.'));
      dbEl.append(e);
      return;
    }
    const canvas = el('div', 'be-er');
    const wires = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
    wires.classList.add('be-wires');
    canvas.append(wires);
    // Columns by depth: referenced tables on the left, the tables that point at them to the right.
    const q = B.dbFilter.toLowerCase();
    const match = (t) => !q || (q.endsWith('.') ? (t.name.includes('.') ? t.name.split('.')[0] + '.' : 'public.') === q
      : t.name.toLowerCase().includes(q) || t.columns.some(c => c.name.toLowerCase().includes(q)));
    // A search also keeps the tables directly related to what matched.
    const hits = new Set(schema.tables.filter(match).map(t => t.name));
    if (q && !q.endsWith('.')) for (const f of schema.fks) { if (hits.has(f.from)) hits.add(f.to); }
    const tables = schema.tables.filter(t => hits.has(t.name));
    const byName = new Map(tables.map(t => [t.name, t]));
    const depth = new Map();
    const depthOf = (name, seen = new Set()) => {
      if (depth.has(name)) return depth.get(name);
      if (seen.has(name)) return 0;
      seen.add(name);
      const parents = schema.fks.filter(f => f.from === name && f.to !== name && byName.has(f.to));
      const d = parents.length ? 1 + Math.max(...parents.map(f => depthOf(f.to, seen))) : 0;
      depth.set(name, d);
      return d;
    };
    tables.forEach(t => depthOf(t.name));
    const columns = [];
    for (const t of tables) (columns[Math.min(depth.get(t.name), 7)] ||= []).push(t);
    const grid = el('div', 'be-er-cols');
    const hot = B.live.hotTables || new Set();
    for (const col of columns.filter(Boolean)) {
      const c = el('div', 'be-er-col');
      col.sort((a, b) => (B.tables.get(`table:${b.name}`)?.length || 0) - (B.tables.get(`table:${a.name}`)?.length || 0) || a.name.localeCompare(b.name));
      for (const t of col) c.append(tableCard(t, schema, hot));
      grid.append(c);
    }
    canvas.append(grid);
    dbEl.append(canvas);
    requestAnimationFrame(() => drawFKs(canvas, wires, schema));
  }

  function tableCard(t, schema, hot) {
    const node = el('div', 'be-table');
    node.dataset.table = t.name;
    const id = `table:${t.name}`;
    if (B.selected === id) node.classList.add('selected');
    if (hot.has(t.name)) node.classList.add('hot');
    if (B.agent.get(id) && Date.now() - B.agent.get(id).last < 6000) node.classList.add('pulse');
    const head = el('div', 'be-table-head');
    head.append(el('i', 'codicon codicon-table'), el('span', 'be-table-name', t.name));
    if (t.rows != null) head.append(el('span', 'be-rows', `${num(t.rows)} rows`));
    node.append(head);
    const flags = el('div', 'be-table-flags');
    if (t.rls === true) flags.append(el('span', 'be-flag ok', `RLS · ${t.policies} polic${t.policies === 1 ? 'y' : 'ies'}`));
    else if (t.rls === false) flags.append(el('span', 'be-flag err', 'No RLS'));
    const uses = B.tables.get(id);
    if (uses?.length) flags.append(el('span', 'be-flag', `used in ${new Set(uses.map(u => u.path)).size} file${new Set(uses.map(u => u.path)).size === 1 ? '' : 's'}`));
    if (B.agent.get(id)) flags.append(el('span', 'be-flag agent', `✎ ${ago(B.agent.get(id).last)}`));
    if (hot.has(t.name)) flags.append(el('span', 'be-flag live', 'writes now'));
    if (flags.childElementCount) node.append(flags);
    const fkCols = new Set(schema.fks.filter(f => f.from === t.name).map(f => f.fromCol));
    const pk = new Set(t.pk || []);
    const cols = t.columns || [];
    const max = B.selected === id ? 40 : 7;
    for (const col of cols.slice(0, max)) {
      const row = el('div', 'be-col');
      row.dataset.col = col.name;
      row.append(el('i', `codicon codicon-${pk.has(col.name) ? 'key' : fkCols.has(col.name) ? 'link' : 'circle-small'}`),
                 el('span', 'be-col-name', col.name), el('span', 'be-col-type', shortType(col.type)));
      if (pk.has(col.name)) row.classList.add('pk');
      if (fkCols.has(col.name)) row.classList.add('fk');
      node.append(row);
    }
    if (cols.length > max) node.append(el('div', 'be-col more', `+${cols.length - max} more columns`));
    node.onclick = () => { B.selected = B.selected === id ? null : id; render(); };
    return node;
  }

  const shortType = (t) => (t || '').replace('timestamp with time zone', 'timestamptz').replace('character varying', 'varchar')
    .replace('double precision', 'float8').replace(/\(\d+\)/, '').slice(0, 18);

  function drawFKs(canvas, wires, schema) {
    const base = canvas.getBoundingClientRect();
    wires.setAttribute('width', canvas.scrollWidth);
    wires.setAttribute('height', canvas.scrollHeight);
    wires.replaceChildren();
    wires.classList.toggle('dense', schema.fks.length > 40);
    const ns = 'http://www.w3.org/2000/svg';
    const rect = (n) => { const r = n.getBoundingClientRect(); return { l: r.left - base.left + canvas.scrollLeft, r: r.right - base.left + canvas.scrollLeft, t: r.top - base.top + canvas.scrollTop, h: r.height }; };
    for (const f of schema.fks) {
      const from = canvas.querySelector(`.be-table[data-table="${CSS.escape(f.from)}"]`);
      const to = canvas.querySelector(`.be-table[data-table="${CSS.escape(f.to)}"]`);
      if (!from || !to) continue;
      const fromRow = from.querySelector(`.be-col[data-col="${CSS.escape(f.fromCol || '')}"]`) || from.querySelector('.be-table-head');
      const toRow = to.querySelector(`.be-col[data-col="${CSS.escape(f.toCol || '')}"]`) || to.querySelector('.be-table-head');
      const a = rect(fromRow), b = rect(toRow);
      const leftward = b.r <= a.l + 4;
      const x1 = leftward ? a.l : a.r, x2 = leftward ? b.r : b.l;
      const y1 = a.t + a.h / 2, y2 = b.t + b.h / 2;
      const dx = Math.max(30, Math.abs(x2 - x1) / 2) * (leftward ? -1 : 1);
      const path = document.createElementNS(ns, 'path');
      path.setAttribute('d', `M${x1},${y1} C${x1 + dx},${y1} ${x2 - dx},${y2} ${x2},${y2}`);
      const active = B.selected === `table:${f.from}` || B.selected === `table:${f.to}`;
      path.setAttribute('class', `be-fk ${active ? 'active' : ''} ${B.selected?.startsWith('table:') && !active ? 'faded' : ''}`);
      const title = document.createElementNS(ns, 'title');
      title.textContent = `${f.from}.${f.fromCol} → ${f.to}.${f.toCol}`;
      path.append(title);
      wires.append(path);
      const end = document.createElementNS(ns, 'circle');
      end.setAttribute('cx', x2); end.setAttribute('cy', y2); end.setAttribute('r', 2.6);
      end.setAttribute('class', `be-fk-end ${active ? 'active' : ''}`);
      wires.append(end);
    }
  }

  function projectPicker() {
    const box = el('div', 'be-picker');
    const list = B.live.supabaseProjects;
    if (!B.detect?.tools?.supabase) {
      box.append(el('div', null, 'Install the Supabase CLI (brew install supabase/tap/supabase) and run supabase login to see it live.'));
      return box;
    }
    if (!list) {
      box.append(el('div', null, B.live.supabaseProjectsError ? `Supabase CLI: ${B.live.supabaseProjectsError.slice(0, 160)} — run supabase login in a terminal.` : 'Loading your Supabase projects…'));
      return box;
    }
    box.append(el('div', 'be-dim', 'Pick the project this code uses (remembered for this folder):'));
    for (const p of list) {
      const b = el('button', 'be-pick');
      b.append(logo('supabase', 16), el('span', null, p.name), el('span', 'be-dim', `${p.region} · ${String(p.status).replace(/_/g, ' ').toLowerCase()}`));
      b.onclick = () => {
        try { localStorage.setItem(`supabaseRef:${B.root}`, p.ref || p.id); } catch { /* no storage */ }
        const sb = B.byId.get('supabase');
        sb.ref = p.ref || p.id;
        sb.subtitle = 'Postgres · Auth · Storage';
        B.live.supabase = p;
        refreshLive(true);
        render();
      };
      box.append(b);
    }
    return box;
  }

  // ----- Details drawer -----

  function section(title, count) {
    const s = el('div', 'side-section');
    const h = el('div', 'side-title', title);
    if (count != null) h.append(el('span', 'side-count', String(count)));
    s.append(h);
    return s;
  }
  const kv = (k, v) => { const r = el('div', 'be-kv'); r.append(el('span', 'k', k), el('span', 'v', v)); return r; };

  function codeList(refs, max = 14) {
    const box = el('div');
    const byFile = new Map();
    for (const r of refs) { if (!byFile.has(r.path)) byFile.set(r.path, []); byFile.get(r.path).push(r); }
    [...byFile.entries()].slice(0, max).forEach(([path, list]) => {
      const row = el('div', 'side-row link');
      row.append(iconEl(path.split('/').pop()), el('span', 'side-name', path.split('/').pop()), el('span', 'side-dim', path.includes('/') ? dirOf(path) : ''),
                 el('span', 'side-dim', `:${list[0].line}${list.length > 1 ? ` +${list.length - 1}` : ''}`));
      row.title = `${list[0].text?.trim() || path}\nClick to open · ⌥-click to show on the code map`;
      row.onclick = (e) => {
        if (e.altKey) { window.starmap?.reveal(path); return; }
        openPickedAt(`${B.root}/${path}`, list[0].line);
      };
      box.append(row);
    });
    if (byFile.size > max) box.append(el('div', 'side-dim-text', `+${byFile.size - max} more files`));
    return box;
  }

  /** A Cloudflare dashboard page, in the project's own account when its config names it. */
  function cfDash(c, page) {
    const account = (c.workers || [c.id]).map(id => B.byId.get(id)?.accountId || B.byId.get(id)?.cfg?.account_id).find(Boolean)
      || B.comps.find(x => x.accountId)?.accountId;
    return account ? `https://dash.cloudflare.com/${account}/${page}` : `https://dash.cloudflare.com/?to=/:account/${page}`;
  }

  function dashButton(text, url) {
    const b = el('button', 'side-btn');
    b.append(el('i', 'codicon codicon-link-external'), text);
    b.onclick = () => fs('backend', { action: 'openURL', url });
    return b;
  }

  function renderSide() {
    if (!side) return;
    const id = B.selected;
    side.classList.toggle('open', !!id);
    if (!id) { side.replaceChildren(); requestAnimationFrame(redrawWires); return; }
    const scroll = side.querySelector('.side-body')?.scrollTop || 0;
    const parts = id.startsWith('table:') ? tableSide(id.slice(6)) : id.startsWith('bucket:') || id.startsWith('rpc:') ? nameSide(id) : compSide(B.byId.get(id));
    if (!parts) { B.selected = null; side.replaceChildren(); return; }
    side.replaceChildren(...parts);
    const body = side.querySelector('.side-body');
    if (body) body.scrollTop = scroll;
    requestAnimationFrame(redrawWires);
  }

  function redrawWires() {
    if (B.view === 'arch') drawWires();
    else { const c = dbEl.querySelector('.be-er'); if (c && B.schema) drawFKs(c, c.querySelector('svg'), B.schema); }
  }

  function sideHead(icon, title, path, chips) {
    const head = el('div', 'side-head');
    const h = el('div', 'side-heading');
    h.append(icon, el('span', 'side-file', title));
    const close = el('i', 'codicon codicon-close side-close');
    close.title = 'Close (Esc)';
    close.onclick = () => { B.selected = null; render(); };
    h.append(close);
    head.append(h);
    if (path) head.append(el('div', 'side-path', path));
    if (chips?.length) { const c = el('div', 'side-chips'); chips.forEach(x => c.append(x)); head.append(c); }
    return head;
  }
  const chip = (text, tone) => el('span', `side-chip ${tone || ''}`, text);

  function compSide(c) {
    if (!c) return null;
    const [label, tone] = statusOf(c);
    const chips = [chip(`${pname(c.provider)}`)];
    if (label) chips.push(chip(label, { ok: 'new', warn: 'edit', err: 'err' }[tone] || ''));
    const parts = [sideHead(logo(c.provider, 20), c.title, c.subtitle, chips)];
    const actions = el('div', 'side-actions');
    const body = el('div', 'side-body');
    const L = B.live;

    // Overview.
    const over = section('Overview');
    if (c.kind === 'supabase') {
      const p = L.supabase;
      if (c.ref) over.append(kv('Project', p?.name || c.ref), kv('Ref', c.ref));
      if (p?.region) over.append(kv('Region', p.region));
      if (p?.database?.version) over.append(kv('Postgres', p.database.version));
      const sbs = B.dbs.get('supabase')?.schema;
      if (sbs?.users != null) over.append(kv('Auth users', num(sbs.users)));
      if (sbs?.size) over.append(kv('Database size', bytes(sbs.size)));
      if (L.stats) over.append(kv('Connections', `${L.stats.connections} (${L.stats.active} active)`), kv('Cache hit', `${L.stats.cacheHit ?? '–'}%`));
      if (c.ref) {
        actions.append(dashButton('Dashboard', `https://supabase.com/dashboard/project/${c.ref}`));
        actions.append(dashButton('Table editor', `https://supabase.com/dashboard/project/${c.ref}/editor`));
        actions.append(dashButton('Logs', `https://supabase.com/dashboard/project/${c.ref}/logs/explorer`));
      }
      const db = el('button', 'side-btn primary');
      db.append(el('i', 'codicon codicon-table'), 'Database view');
      db.onclick = () => { B.view = 'db'; B.dbSel = 'supabase'; B.selected = null; render(); };
      actions.prepend(db);
      if (!c.ref || !L.supabase) over.append(projectPicker());
    } else if (c.kind === 'worker') {
      if (c.main) over.append(kv('Entry', c.main));
      over.append(kv('Config', c.config));
      if (c.cfg?.compatibility_date) over.append(kv('Compatibility', c.cfg.compatibility_date));
      if (c.crons?.length) over.append(kv('Schedule', c.crons.map(x => `${cronText(x)} (${x})`).join(', ')));
      if (c.features?.length) over.append(kv('Features', c.features.join(', ')));
      if (c.vars?.length) over.append(kv('Vars', c.vars.join(', ')));
      for (const site of c.domains || []) actions.append(dashButton(site, `https://${site}`));
      actions.append(dashButton('Cloudflare', cfDash(c, `workers/services/view/${encodeURIComponent(c.title)}/production`)));
      // Each environment: its Worker name, where it's served, and its latest deploy.
      const envs = section('Environments', c.envs.length);
      for (const env of c.envs) {
        const live = workerFor(c, env.key);
        const last = lastDeploy(live);
        const row = el('div', 'side-row');
        row.append(el('span', `be-dot ${live?.error ? 'off' : last ? 'ok' : live ? 'warn' : 'off'}`), el('span', 'side-name', env.key || 'default'),
                   el('span', 'side-dim mono', env.name),
                   el('span', 'side-dim', live?.error ? 'unavailable' : last ? `deployed ${ago(last)}` : live ? 'never deployed' : ''));
        envs.append(row);
        if (env.domains.length) envs.append(el('div', 'side-dim-text mono', `   ${env.domains.join(', ')}`));
        else if (env.workersDev) envs.append(el('div', 'side-dim-text mono', '   workers.dev'));
      }
      body.append(envs);
      if (c.calls?.length) {
        const calls = section('Calls other Workers', c.calls.length);
        c.calls.forEach(x => calls.append(kv(`env.${x.binding}`, x.service)));
        body.append(calls);
      }
    } else if (c.kind === 'app') {
      for (const site of c.domains || []) actions.append(dashButton(site, `https://${site}`));
      over.append(kv('Framework', pname(c.provider)));
      over.append(kv('Hosted on', c.host ? `${c.host.name}${c.host.detail ? ` (${c.host.detail})` : ''}` : 'Not detected (local only)'));
      if (c.dir) over.append(kv('Folder', c.dir));
      const v = vercelFor(c);
      const prod = v?.deployments?.find(d => d.target === 'production' && d.state === 'READY');
      if (prod?.url && !c.domains?.length) actions.append(dashButton('Open site', `https://${prod.url}`));
      if (prod?.inspectorUrl) actions.append(dashButton('Vercel', prod.inspectorUrl));
    } else if (c.kind === 'routes') {
      over.append(kv('Routes', String(c.routes.length)));
    } else if (c.provider === 'cloudflare' || c.kind === 'hyperdrive') {
      over.append(kv(c.bindings?.length > 1 ? 'Bindings' : 'Binding', (c.bindings || [c.binding]).map(b => `env.${b}`).join(', ')));
      if (c.workers?.length) over.append(kv('Workers', c.workers.map(id => B.byId.get(id)?.title).join(', ')));
      if (c.consumers?.length) over.append(kv('Consumed by', c.consumers.map(id => B.byId.get(id)?.title).join(', ')));
      for (const [k, v] of Object.entries(c.info || {})) if (!['binding', 'name'].includes(k) && typeof v !== 'object') over.append(kv(k.replace(/_/g, ' '), String(v)));
      const page = { d1: 'workers/d1', kv: 'workers/kv/namespaces', r2: 'r2/overview', queue: 'workers/queues', do: 'workers/durable-objects',
                     hyperdrive: 'workers/hyperdrive', vectorize: 'ai/vectorize', images: 'images', workflow: 'workers/workflows', ai: 'ai/workers-ai' }[c.kind];
      if (page) actions.append(dashButton('Cloudflare', cfDash(c, page)));
      if (B.dbs.has(c.id)) {
        const db = el('button', 'side-btn primary');
        db.append(el('i', 'codicon codicon-table'), 'Database view');
        db.onclick = () => { B.view = 'db'; B.dbSel = c.id; B.selected = null; render(); };
        actions.prepend(db);
      }
      if (c.kind === 'd1' && c.pendingError) over.append(kv('Migrations', `couldn't check: ${c.pendingError.split('\n')[0].slice(0, 80)}`));
    } else if (c.kind === 'edge-functions') {
      const live = new Map((L.functions || []).map(f => [f.slug || f.name, f]));
      for (const f of c.functions) {
        const lf = live.get(f);
        over.append(kv(f, lf ? `v${lf.version} · ${String(lf.status).toLowerCase()} · ${ago(Date.parse(lf.updated_at) || lf.updated_at)}` : L.functions ? 'not deployed' : ''));
      }
    } else if (c.kind === 'service' || c.kind === 'prisma' || c.kind === 'firebase') {
      if (c.packages?.length) over.append(kv('Packages', c.packages.join(', ')));
      if (c.via?.length) over.append(kv('Env vars', c.via.join(', ')));
    }
    if (over.childElementCount > 1) body.append(over);
    if (actions.childElementCount) parts.push(actions);

    // Live: deployments.
    const v = vercelFor(c);
    if (v?.deployments?.length) {
      const s = section('Deployments', v.deployments.length);
      for (const d of v.deployments.slice(0, 8)) {
        const row = el('div', 'side-row link be-deploy');
        const t = { READY: 'ok', ERROR: 'err', BUILDING: 'busy', QUEUED: 'busy', CANCELED: 'off' }[d.state] || 'off';
        row.append(el('span', `be-dot ${t}`), el('span', 'side-name', d.meta?.githubCommitMessage?.split('\n')[0] || d.url),
                   el('span', 'side-dim', `${d.target === 'production' ? 'prod' : 'preview'} · ${ago(d.createdAt)}`));
        row.title = `${d.state} · ${d.url}`;
        row.onclick = () => fs('backend', { action: 'openURL', url: d.inspectorUrl || `https://${d.url}` });
        s.append(row);
      }
      body.append(s);
    } else if (v?.error) {
      const s = section('Deployments');
      s.append(el('div', 'side-dim-text', `Vercel CLI: ${v.error.slice(0, 200)}`));
      body.append(s);
    }
    const w = workerFor(c);
    if (w?.deployments?.length) {
      const s = section('Deployments', w.deployments.length);
      const list = w.deployments.slice().sort((a, b) => Date.parse(b.created_on || 0) - Date.parse(a.created_on || 0));
      for (const d of list.slice(0, 8)) {
        const row = el('div', 'side-row');
        row.append(el('span', 'be-dot ok'), el('span', 'side-name', d.annotations?.['workers/message'] || d.source || 'Deployment'),
                   el('span', 'side-dim', `${d.author_email ? d.author_email.split('@')[0] + ' · ' : ''}${ago(Date.parse(d.created_on))}`));
        s.append(row);
      }
      body.append(s);
    } else if (w?.error) {
      const s = section('Deployments');
      s.append(el('div', 'side-dim-text', `wrangler: ${w.error.slice(0, 200)}${/login|auth|token/i.test(w.error) ? ' — run npx wrangler login in a terminal.' : ''}`));
      body.append(s);
    }

    // Drift.
    const drift = driftOf(c);
    if (drift.length) {
      const s = section('Out of sync');
      for (const d of drift) {
        s.append(el('div', `be-drift ${d.tone}`, d.text));
        (d.detail || []).slice(0, 6).forEach(x => s.append(el('div', 'side-dim-text mono', x)));
      }
      body.append(s);
    }

    // Agent activity here.
    const touch = B.agent.get(c.id);
    if (touch) {
      const s = section(`${agentName()} changed here`, touch.files.size);
      s.append(codeList([...touch.files].map(path => ({ path, line: 1 }))));
      body.append(s);
    }

    // Supabase: tables at a glance.
    const ownDB = B.dbs.get(c.id)?.schema;
    if (ownDB?.tables?.length) {
      const s = section('Tables', ownDB.tables.length);
      for (const t of ownDB.tables.slice().sort((a, b) => (b.rows || 0) - (a.rows || 0) || a.name.localeCompare(b.name)).slice(0, 10)) {
        const row = el('div', 'side-row link');
        row.append(el('i', 'codicon codicon-table'), el('span', 'side-name', t.name), el('span', 'side-dim', t.rows != null ? `${num(t.rows)} rows` : ''));
        if (t.rls === false) row.append(el('span', 'side-flag err', 'no RLS'));
        row.onclick = () => { B.view = 'db'; B.dbSel = c.id; B.selected = `table:${t.name}`; render(); };
        s.append(row);
      }
      body.append(s);
      if (ownDB.buckets?.length) {
        const b = section('Storage buckets', ownDB.buckets.length);
        ownDB.buckets.forEach(x => b.append(kv(x.name, x.public ? 'public' : 'private')));
        body.append(b);
      }
    }
    // API routes list.
    if (c.kind === 'routes') {
      const s = section('Routes', c.routes.length);
      c.routes.slice(0, 30).forEach(r => {
        const row = el('div', 'side-row link');
        row.append(el('i', 'codicon codicon-symbol-namespace'), el('span', 'side-name mono', r.url));
        row.onclick = () => openPickedAt(`${B.root}/${r.rel}`, 1);
        s.append(row);
      });
      body.append(s);
    }

    // Code that uses it.
    const refs = B.compRefs?.get(c.id) || [];
    const used = section('Used in code', new Set(refs.map(r => r.path)).size);
    if (refs.length) used.append(codeList(refs));
    else used.append(el('div', 'side-dim-text', c.lane === 'client' ? 'This is the app itself.' : 'No references found in the code yet.'));
    body.append(used);

    // Config files.
    const evidence = (c.evidence || []).filter(Boolean);
    if (evidence.length) {
      const s = section('Defined in', evidence.length);
      s.append(codeList(evidence.map(path => ({ path, line: 1 }))));
      body.append(s);
    }
    parts.push(body);
    return parts;
  }

  function tableSide(name) {
    const t = B.schema?.tables.find(x => x.name === name);
    if (!t) return null;
    const chips = [];
    if (t.rls === true) chips.push(chip(`RLS on · ${t.policies} polic${t.policies === 1 ? 'y' : 'ies'}`, 'new'));
    else if (t.rls === false) chips.push(chip('RLS off', 'err'));
    if (t.rows != null) chips.push(chip(`${num(t.rows)} rows`));
    const parts = [sideHead(el('i', 'codicon codicon-table'), name, `public.${name}`, chips)];
    const sb = B.byId.get('supabase');
    if (sb?.ref) {
      const actions = el('div', 'side-actions');
      actions.append(dashButton('Open in Supabase', `https://supabase.com/dashboard/project/${sb.ref}/editor`));
      parts.push(actions);
    }
    const body = el('div', 'side-body');
    if (t.rls === false && B.schemaSource !== 'prisma') {
      const warn = el('div', 'side-note err');
      warn.textContent = curDB()?.provider === 'supabase'
        ? 'Row Level Security is off. Through Supabase’s API, anyone with your public anon key can read and change every row of this table. Turn RLS on and add policies for who may access what.'
        : 'Row Level Security is off for this table, so any role that can reach it sees every row. If other tables rely on RLS to keep tenants apart, this one doesn’t.';
      body.append(warn);
    } else if (t.rls === true && !t.policies) {
      const warn = el('div', 'side-note');
      warn.textContent = 'RLS is on with no policies, so the API can’t read or write this table at all (only the service role can).';
      body.append(warn);
    }
    const stats = B.live.stats;
    if (stats?.writes?.[name] != null || stats?.reads?.[name] != null) {
      const s = section('Activity');
      s.append(kv('Writes (since stats reset)', num(stats.writes?.[name])), kv('Scans', num(stats.reads?.[name])));
      if (B.live.hotTables?.has(name)) s.append(el('div', 'be-drift ok', 'Being written to right now'));
      body.append(s);
    }
    const cols = section('Columns', t.columns.length);
    const pk = new Set(t.pk || []);
    const fkCols = new Map(B.schema.fks.filter(f => f.from === name).map(f => [f.fromCol, f]));
    for (const c of t.columns) {
      const row = el('div', 'side-row');
      row.append(el('i', `codicon codicon-${pk.has(c.name) ? 'key' : fkCols.has(c.name) ? 'link' : 'circle-small'}`), el('span', 'side-name', c.name),
                 el('span', 'side-dim mono', `${c.type}${c.nullable ? '' : ' · not null'}`));
      if (fkCols.has(c.name)) {
        const f = fkCols.get(c.name);
        const to = el('span', 'side-flag link', `→ ${f.to}`);
        to.onclick = (e) => { e.stopPropagation(); B.selected = `table:${f.to}`; render(); };
        row.append(to);
      }
      cols.append(row);
    }
    body.append(cols);
    const inbound = B.schema.fks.filter(f => f.to === name);
    if (inbound.length) {
      const s = section('Referenced by', inbound.length);
      inbound.forEach(f => {
        const row = el('div', 'side-row link');
        row.append(el('i', 'codicon codicon-table'), el('span', 'side-name', f.from), el('span', 'side-dim', `.${f.fromCol}`));
        row.onclick = () => { B.selected = `table:${f.from}`; render(); };
        s.append(row);
      });
      body.append(s);
    }
    const uses = B.tables.get(`table:${name}`) || [];
    const s = section('Used in code', new Set(uses.map(u => u.path)).size);
    if (uses.length) s.append(codeList(uses)); else s.append(el('div', 'side-dim-text', `No .from('${name}') calls found.`));
    body.append(s);
    const touch = B.agent.get(`table:${name}`);
    if (touch) {
      const a = section(`${agentName()} changed code using it`, touch.files.size);
      a.append(codeList([...touch.files].map(path => ({ path, line: 1 }))));
      body.append(a);
    }
    parts.push(body);
    return parts;
  }

  function nameSide(id) {
    const [kind, name] = id.split(':');
    const uses = B.tables.get(id) || [];
    const parts = [sideHead(el('i', `codicon codicon-${kind === 'bucket' ? 'archive' : 'symbol-method'}`), name,
                            kind === 'bucket' ? 'Storage bucket' : 'Database function (rpc)', [])];
    const body = el('div', 'side-body');
    const s = section('Used in code', new Set(uses.map(u => u.path)).size);
    s.append(codeList(uses));
    body.append(s);
    parts.push(body);
    return parts;
  }

  // ---------- Building the view ----------

  function build() {
    wrap = el('div');
    wrap.id = 'agent-backend';
    top = el('div', 'be-top');
    const views = el('div', 'be-view');
    for (const [v, icon, name] of [['arch', 'type-hierarchy', 'Architecture'], ['db', 'table', 'Database']]) {
      const b = el('button');
      b.dataset.view = v;
      b.append(el('i', `codicon codicon-${icon}`), name);
      b.onclick = () => { B.view = v; B.selected = null; render(); };
      views.append(b);
    }
    summaryEl = el('div', 'be-summary');
    updatedEl = el('span', 'be-updated');
    refreshBtn = el('button', 'be-refresh');
    refreshBtn.append(el('i', 'codicon codicon-refresh'));
    refreshBtn.title = 'Scan the project again and refresh live status';
    refreshBtn.onclick = () => { B.live = {}; scan(); };
    top.append(views, summaryEl, updatedEl, refreshBtn);
    const main = el('div', 'be-main');
    stageEl = el('div', 'be-stage');
    archEl = el('div', 'be-arch');
    dbEl = el('div', 'be-db hidden');
    stageEl.append(archEl, dbEl);
    side = el('div', 'map-side be-side');
    main.append(stageEl, side);
    wrap.append(top, main);
    $('agent-feed').before(wrap);
    new ResizeObserver(() => requestAnimationFrame(() => {
      const grid = archEl.querySelector('.be-lanes');
      if (grid) {
        const used = grid.children.length;
        const stack = stageEl.clientWidth < used * 236 + (used - 1) * 46 + 36;
        if (stack !== grid.classList.contains('stacked')) grid.classList.toggle('stacked', stack);
      }
      redrawWires();
    })).observe(stageEl);
    addEventListener('keydown', (e) => {
      if (e.key === 'Escape' && B.selected && B.visible && !editor?.hasTextFocus()) { B.selected = null; render(); }
    });
  }

  // ---------- Hooks ----------

  window.backend = {
    shown(visible) {
      const was = B.visible;
      B.visible = visible;
      clearInterval(B.poll);
      if (!visible) return;
      if (B.root !== state.root || !B.scannedAt) scan();
      else { render(); if (!was && Date.now() - (B.liveAt || 0) > 30000) refreshLive(); }
      // Poll while showing: faster while something is building.
      B.poll = setInterval(() => {
        const building = Object.values(B.live.vercel || {}).some(v => v.deployments?.some(d => /BUILDING|QUEUED|INITIALIZING/.test(d.state)));
        if (building || Date.now() - (B.liveAt || 0) > 60000) refreshLive();
        else renderTop();
      }, 15000);
    },
    folder() {
      B.root = state.root; B.comps = []; B.byId = new Map(); B.edges = []; B.live = {}; B.dbs = new Map(); B.dbSel = null; B.dbFilter = '';
      B.refs = []; B.refsByFile = new Map(); B.tables = new Map(); B.agent.clear(); B.selected = null; B.scannedAt = 0;
      if (B.visible) scan();
    },
    agentTouched,
    /** Backend pieces a project file uses, for the code map's sidebar. */
    linksFor(rel) {
      if (!B.scannedAt && state.root && !B.scanning) scan();
      return B.refsByFile.get(rel) || [];
    },
    /** Shows a piece (or table) from elsewhere, e.g. the code map's sidebar. */
    reveal(id) {
      $('agent').querySelector('.agent-mode button[data-mode="backend"]')?.click();
      B.view = id.startsWith('table:') ? 'db' : 'arch';
      B.selected = id;
      render();
    },
  };

  build();
  // The panel may have opened on this tab before this script loaded.
  if ($('agent').classList.contains('backend-mode')) window.backend.shown(true);
})();
