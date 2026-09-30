#if os(macOS)
import Foundation

/// The script Visual Fix runs in the previewed page. It reports what's under the pointer
/// and what was clicked (with the details an agent needs to find it in the code), and where
/// the chosen and pinned elements are as the page scrolls or reloads. All of the drawing is
/// done natively over the page; the only thing it changes in the page is the cursor.
enum VisualFixProbe {
    static let source = #"""
(() => {
  if (window.__gxFix) return;
  const post = (message) => { try { window.webkit.messageHandlers.gxFix.postMessage(message); } catch (e) {} };
  let picking = false, hoverEl = null, selectedEl = null, frame = 0, lastRects = '';
  const pins = new Map();

  const style = document.createElement('style');
  style.textContent = 'html.__gxfix-picking, html.__gxfix-picking * { cursor: crosshair !important; }';
  (document.head || document.documentElement).appendChild(style);

  const esc = (s) => (window.CSS && CSS.escape) ? CSS.escape(s) : s;
  const usefulClass = (c) => c.length < 32 && !/[:\[\]\/!@]/.test(c) && !/^(css-|sc-|jsx-|svelte-|__)/.test(c);

  function selectorOf(el) {
    const parts = [];
    for (let node = el; node && node.nodeType === 1 && parts.length < 6; node = node.parentElement) {
      if (node.id && !/^\d/.test(node.id)) { parts.unshift('#' + esc(node.id)); break; }
      let part = node.tagName.toLowerCase();
      const classes = [...node.classList].filter(usefulClass).slice(0, 2);
      if (classes.length) part += '.' + classes.map(esc).join('.');
      const parent = node.parentElement;
      if (parent) {
        const same = [...parent.children].filter((c) => c.tagName === node.tagName);
        if (same.length > 1) part += ':nth-of-type(' + (same.indexOf(node) + 1) + ')';
      }
      parts.unshift(part);
      if (node.tagName === 'BODY') break;
    }
    return parts.join(' > ');
  }

  // Which component renders it, and where, in development builds.
  function framework(el) {
    const out = { components: [], source: null };
    const key = Object.keys(el).find((k) => k.startsWith('__reactFiber$') || k.startsWith('__reactInternalInstance$'));
    if (key) {
      for (let fiber = el[key]; fiber && out.components.length < 4; fiber = fiber.return) {
        const type = fiber.type;
        if (typeof type === 'function' || (type && typeof type === 'object')) {
          const name = type.displayName || type.name || (type.render && (type.render.displayName || type.render.name))
            || (type.type && type.type.name);
          if (name && !out.components.includes(name) && !/^(Anonymous|_c\d*)$/.test(name)) out.components.push(name);
        }
        if (!out.source && fiber._debugSource) {
          out.source = { file: fiber._debugSource.fileName, line: fiber._debugSource.lineNumber };
        }
      }
    }
    for (let node = el; node; node = node.parentElement) {
      if (!node.__vueParentComponent) continue;
      for (let vue = node.__vueParentComponent, i = 0; vue && i < 4; vue = vue.parent, i++) {
        const type = vue.type || {};
        const name = type.name || type.__name || (type.__file || '').split('/').pop().replace(/\.vue$/, '');
        if (name && !out.components.includes(name)) out.components.push(name);
        if (!out.source && type.__file) out.source = { file: type.__file };
      }
      break;
    }
    for (let node = el; node && !out.source; node = node.parentElement) {
      const meta = node.__svelte_meta;
      if (meta && meta.loc) out.source = { file: meta.loc.file, line: meta.loc.line + 1 };
    }
    return out;
  }

  const rectOf = (el) => {
    if (!el || !el.isConnected) return null;
    const r = el.getBoundingClientRect();
    return { x: r.left, y: r.top, w: r.width, h: r.height };
  };

  function label(el) {
    const tag = el.tagName.toLowerCase();
    const cls = [...el.classList].filter(usefulClass)[0];
    const r = el.getBoundingClientRect();
    return (el.id ? tag + '#' + el.id : cls ? tag + '.' + cls : tag) + '  ' + Math.round(r.width) + '×' + Math.round(r.height);
  }

  function describe(el) {
    const cs = getComputedStyle(el);
    const text = (el.innerText || el.value || el.alt || el.getAttribute('aria-label') || el.getAttribute('placeholder') || '')
      .trim().replace(/\s+/g, ' ').slice(0, 90);
    const attrs = {};
    for (const name of ['id', 'class', 'href', 'src', 'type', 'role', 'aria-label', 'data-testid', 'name']) {
      const value = el.getAttribute(name);
      if (value) attrs[name] = value.slice(0, 160);
    }
    const found = framework(el);
    return {
      tag: el.tagName.toLowerCase(), text, attrs, selector: selectorOf(el), label: label(el), rect: rectOf(el),
      components: found.components, source: found.source,
      styles: {
        size: Math.round(el.getBoundingClientRect().width) + '×' + Math.round(el.getBoundingClientRect().height),
        font: cs.fontSize + ' ' + cs.fontWeight + ' ' + cs.fontFamily.split(',')[0].replace(/["']/g, ''),
        color: cs.color, background: cs.backgroundColor, padding: cs.padding, margin: cs.margin,
        display: cs.display, radius: cs.borderRadius,
      },
      page: { url: location.href, title: document.title, width: innerWidth, height: innerHeight },
    };
  }

  const pick = (e) => document.elementFromPoint(e.clientX, e.clientY);
  const block = (e) => { if (!picking) return; e.preventDefault(); e.stopPropagation(); e.stopImmediatePropagation(); };

  function select(el) {
    selectedEl = el;
    post({ type: 'select', info: describe(el) });
  }

  document.addEventListener('mousemove', (e) => {
    if (!picking) return;
    const el = pick(e);
    if (!el || el === hoverEl) return;
    hoverEl = el;
    post({ type: 'hover', label: label(el), rect: rectOf(el) });
  }, true);
  document.addEventListener('mouseout', (e) => {
    if (picking && !e.relatedTarget) { hoverEl = null; post({ type: 'hover', rect: null }); }
  }, true);
  for (const type of ['mousedown', 'mouseup', 'pointerdown', 'pointerup', 'dblclick', 'contextmenu', 'auxclick']) {
    document.addEventListener(type, block, true);
  }
  document.addEventListener('click', (e) => {
    if (!picking) return;
    block(e);
    const el = pick(e);
    if (el) select(el);
  }, true);
  document.addEventListener('keydown', (e) => { if (e.key === 'Escape') post({ type: 'escape' }); }, true);

  // Positions of the hovered, chosen and pinned elements, whenever they may have moved.
  function tick() {
    frame = 0;
    const pinRects = {};
    for (const [id, selector] of pins) {
      let el = null;
      try { el = document.querySelector(selector); } catch (e) {}
      pinRects[id] = rectOf(el);
    }
    const rects = { hover: picking ? rectOf(hoverEl) : null, selected: rectOf(selectedEl), pins: pinRects };
    const json = JSON.stringify(rects);
    if (json === lastRects) return;
    lastRects = json;
    post({ type: 'rects', ...rects });
  }
  const schedule = () => { if (!frame) frame = requestAnimationFrame(tick); };
  addEventListener('scroll', schedule, true);
  addEventListener('resize', schedule);
  setInterval(schedule, 500);

  window.__gxFix = {
    setPicking(on) {
      picking = on;
      document.documentElement.classList.toggle('__gxfix-picking', on);
      if (!on) { hoverEl = null; post({ type: 'hover', rect: null }); }
      schedule();
    },
    parent() {
      if (selectedEl && selectedEl.parentElement && selectedEl.parentElement !== document.documentElement) select(selectedEl.parentElement);
    },
    clear() { selectedEl = null; lastRects = ''; schedule(); },
    pin(id, selector) { pins.set(id, selector); lastRects = ''; schedule(); },
    unpin(id) { pins.delete(id); lastRects = ''; schedule(); },
    reveal(selector) {
      let el = null;
      try { el = document.querySelector(selector); } catch (e) {}
      if (el) el.scrollIntoView({ block: 'center', behavior: 'smooth' });
      return !!el;
    },
    saveScroll() { try { sessionStorage.setItem('__gxfix-scroll', String(scrollY)); } catch (e) {} },
  };
  try {
    const y = sessionStorage.getItem('__gxfix-scroll');
    if (y) { sessionStorage.removeItem('__gxfix-scroll'); scrollTo(0, Number(y)); }
  } catch (e) {}
  post({ type: 'ready', title: document.title, url: location.href });
})();
"""#
}
#endif
