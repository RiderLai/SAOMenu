(() => {
  'use strict';

  // Geometry (px). R = icon radius, STEP = distance between icon centers.
  const R = 30, STEP = 76, PANEL_W = 236, GAP = 26, PGAP = 22, PAD = 16;

  const ICONS = window.SAO_ICONS;

  const stage = document.getElementById('stage');
  const toastEl = document.getElementById('toast');
  const clamp = (v, lo, hi) => Math.min(Math.max(v, lo), hi);
  const el = (tag, cls, parent) => {
    const e = document.createElement(tag);
    if (cls) e.className = cls;
    if (parent) parent.appendChild(e);
    return e;
  };

  // ---------- state ----------
  // Level 0 is the icon column; level k >= 1 is the k-th list panel.
  // path[k] = index selected at level k. panels[k-1] = DOM of level k.
  let config = { menu: [] };
  let isOpen = false, closing = false;
  let ax = 0, ay = 0;
  let path = [];
  let focus = { level: 0, idx: -1 };
  let column = null;
  let panels = [];

  function send(msg) {
    try {
      return window.webkit.messageHandlers.sao.postMessage(msg);
    } catch (e) {
      return Promise.resolve({ ok: true }); // running in a plain browser
    }
  }

  // ---------- sound (played natively by the app) ----------
  function sfx(name) {
    if (config.sound !== false) send({ cmd: 'sfx', name });
  }

  // ---------- helpers ----------
  function glyph(name, parent) {
    const g = el('span', 'glyph', parent);
    if (ICONS[name]) g.innerHTML = `<svg viewBox="0 0 24 24">${ICONS[name]}</svg>`;
    else g.textContent = [...String(name || '')].slice(0, 2).join('');
    return g;
  }

  // Real icons for app entries, fetched from the app once and cached.
  const appIcons = new Map();
  function useAppIcon(node, holder) {
    const a = node.action;
    if (node.icon || !a || a.type !== 'app' || !a.app) return;
    if (!appIcons.has(a.app)) {
      appIcons.set(a.app, Promise.resolve(send({ cmd: 'icon', app: a.app })).catch(() => null));
    }
    appIcons.get(a.app).then((res) => {
      if (!res || !res.icon || !holder.isConnected) return;
      holder.textContent = '';
      holder.classList.add('app');
      el('img', '', holder).src = res.icon;
    });
  }

  function rowIcon(node) {
    if (node.icon) return node.icon;
    if (node.items && node.items.length) return 'list';
    const a = node.action || {};
    if (a.type === 'quit') return 'logout';
    if (a.type === 'settings') return 'gear';
    if (a.type === 'url') return 'globe';
    if (a.type === 'terminal') return 'terminal';
    if (a.type === 'app') return 'grid';
    const base = String(a.path || '').split('/').pop();
    if (base.endsWith('.app')) return 'grid';
    return /\.[A-Za-z0-9]{1,8}$/.test(base) ? 'file' : 'folder';
  }

  function actionText(a) {
    return a ? a.path || a.url || a.command || a.app || '' : '';
  }

  function depthOf(items) {
    let d = 0;
    for (const n of items || []) {
      if (n.items && n.items.length) d = Math.max(d, 1 + depthOf(n.items));
    }
    return d;
  }

  function itemsAt(level) {
    let items = config.menu || [];
    for (let k = 0; k < level; k++) items = (items[path[k]] || {}).items || [];
    return items;
  }

  function elsAt(level) {
    if (level === 0) return column ? [...column.children] : [];
    const p = panels[level - 1];
    return p ? [...p.querySelectorAll('.row')] : [];
  }

  function refresh() {
    for (let level = 0; level <= panels.length; level++) {
      elsAt(level).forEach((e, i) => {
        e.classList.toggle('selected', path[level] === i);
        e.classList.toggle('focus', focus.level === level && focus.idx === i);
      });
    }
  }

  function trimPanels(level) {
    while (panels.length > level) panels.pop().remove();
  }

  function shiftColumn() {
    const n = (config.menu || []).length;
    const off = path.length ? path[0] * STEP : ((n - 1) * STEP) / 2;
    column.style.transform = `translateY(${-off}px)`;
  }

  let toastTimer = 0;
  function toast(msg) {
    toastEl.textContent = msg;
    toastEl.classList.add('show');
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => toastEl.classList.remove('show'), 3500);
  }

  // ---------- open / close ----------
  function reset() {
    if (dialog) dialog.done(false);
    stage.querySelectorAll('.column, .panel, .dialog-wrap').forEach((e) => e.remove());
    stage.classList.remove('open', 'closing');
    clearTimeout(toastTimer);
    toastEl.classList.remove('show');
    column = null;
    panels = [];
    path = [];
    focus = { level: 0, idx: -1 };
    isOpen = false;
    closing = false;
  }

  function open(x, y) {
    reset();
    const menu = config.menu || [];
    const n = menu.length;
    const W = innerWidth, H = innerHeight;

    // (ax, ay) is the anchor: the selected icon always slides to this point,
    // so keep enough room for the column to shift fully up or down.
    const span = Math.max(0, n - 1) * STEP + R + PAD;
    ay = 2 * span <= H ? clamp(y, span, H - span) : H / 2;
    const totalW = 2 * R + GAP + depthOf(menu) * (PANEL_W + PGAP);
    ax = clamp(x - R, PAD, Math.max(PAD, W - totalW - PAD));

    column = el('div', 'column', stage);
    column.style.left = ax + 'px';
    column.style.top = ay + 'px';
    menu.forEach((node, i) => {
      const ic = el('div', 'icon', column);
      ic.style.top = i * STEP - R + 'px';
      ic.style.setProperty('--i', i);
      ic.style.setProperty('--ri', n - 1 - i);
      glyph(node.icon || 'star', ic);
      useAppIcon(node, ic);
      ic.addEventListener('click', (e) => {
        e.stopPropagation();
        focus = { level: 0, idx: i };
        select(0, i, { toggle: true });
      });
    });
    shiftColumn();

    isOpen = true;
    requestAnimationFrame(() => stage.classList.add('open'));
    sfx('open');
    if (!n) toast('菜单为空，请在配置文件的 menu 里添加条目');
  }

  function close() {
    if (outroRunning) return;
    if (introState) return endIntro(false);
    if (dialog) dialog.done(false);
    if (!isOpen || closing) return;
    closing = true;
    sfx('close');
    stage.classList.remove('open');
    stage.classList.add('closing');
    const n = column ? column.children.length : 0;
    setTimeout(() => {
      reset();
      // let the emptied stage paint before the window goes away
      setTimeout(() => send({ cmd: 'hide' }), 50);
    }, 190 + n * 18);
  }

  // ---------- panels ----------
  function openPanel(level, node, targetY) {
    const p = el('div', 'panel', stage);
    p.style.left = ax + 2 * R + GAP + (level - 1) * (PANEL_W + PGAP) + 'px';
    el('header', '', p).textContent = node.label || '';
    const rows = el('div', 'rows', p);
    node.items.forEach((child, i) => {
      const r = el('div', 'row', rows);
      const ico = el('span', 'ico', r);
      glyph(rowIcon(child), ico);
      useAppIcon(child, ico);
      el('span', 'lbl', r).textContent =
        child.label || actionText(child.action) || '—';
      if (child.items && child.items.length) el('span', 'chev', r).textContent = '›';
      r.addEventListener('mouseenter', () => {
        if (focus.level !== level || focus.idx !== i) {
          focus = { level, idx: i };
          refresh();
          sfx('move');
        }
      });
      r.addEventListener('click', (e) => {
        e.stopPropagation();
        focus = { level, idx: i };
        select(level, i);
      });
    });
    // a child panel points at a row; scrolling would leave it pointing at nothing
    rows.addEventListener('scroll', () => {
      if (path.length > level) {
        path = path.slice(0, level);
        trimPanels(level);
        refresh();
      }
    });
    p.addEventListener('click', (e) => e.stopPropagation());

    const h = p.offsetHeight;
    const top = clamp(targetY - h / 2, PAD, Math.max(PAD, innerHeight - h - PAD));
    p.style.top = top + 'px';
    p.style.setProperty('--py', clamp(targetY - top, 16, h - 16) + 'px');
    p._top = top;
    panels.push(p);
  }

  function rowCenter(level, idx) {
    const p = panels[level - 1];
    const r = elsAt(level)[idx];
    const rows = p.querySelector('.rows');
    return p._top + r.offsetTop - rows.scrollTop + r.offsetHeight / 2;
  }

  function collapse() {
    const prev = path[0];
    path = [];
    trimPanels(0);
    shiftColumn();
    focus = { level: 0, idx: prev === undefined ? -1 : prev };
    refresh();
    sfx('back');
  }

  /** Select item idx at a level: opens its sub-panel, or runs its action. */
  function select(level, idx, opt = {}) {
    const { run = true, enter = false, toggle = false } = opt;
    const node = itemsAt(level)[idx];
    if (!node) return;
    if (toggle && level === 0 && path[0] === idx) return collapse();

    const hasItems = node.items && node.items.length;
    if (!hasItems && level > 0) {
      // leaf row: keep the open path as is, just fire
      path = path.slice(0, level);
      trimPanels(level);
    } else {
      path = path.slice(0, level);
      path.push(idx);
      trimPanels(level);
      if (level === 0) shiftColumn();
    }

    if (hasItems) {
      openPanel(level + 1, node, level === 0 ? ay : rowCenter(level, idx));
      if (enter) focus = { level: level + 1, idx: 0 };
      sfx('select');
    } else if (run) {
      if (node.action) runAction(node, elsAt(level)[idx]);
      else toast('这一项还没有配置 action');
    }
    refresh();
  }

  async function runAction(node, target) {
    const a = node.action;
    const isQuit = a.type === 'quit';
    if (isQuit || a.confirm) {
      const msg = typeof a.confirm === 'string' ? a.confirm
        : isQuit ? '确定要登出并退出 SAO Menu 吗？'
        : `确定要执行「${node.label || actionText(a)}」吗？`;
      const yes = await confirmDialog(isQuit ? 'LOG OUT' : 'CONFIRM', msg);
      if (!yes || !isOpen || closing) return;
    }
    if (isQuit) return outro();
    let res;
    try {
      // If the app is stuck behind a system permission prompt, don't keep the
      // overlay up waiting for it: treat a slow reply as started.
      res = await Promise.race([
        send({ cmd: 'run', action: node.action }),
        new Promise((done) => setTimeout(() => done({ ok: true }), 500)),
      ]);
    } catch (e) {
      res = { ok: false, error: String(e) };
    }
    if (res && res.ok) {
      if (target) target.classList.add('fired');
      sfx('launch');
      setTimeout(close, 240);
    } else {
      if (target) {
        target.classList.add('error');
        setTimeout(() => target.classList.remove('error'), 700);
      }
      sfx('error');
      toast((res && res.error) || '执行失败');
    }
  }

  // ---------- input ----------
  stage.addEventListener('mousedown', (e) => {
    if (e.target === stage || e.target.id === 'dim') close();
  });
  document.addEventListener('contextmenu', (e) => e.preventDefault());

  document.addEventListener('keydown', (e) => {
    if (introState) {
      e.preventDefault();
      return endIntro(true); // any key skips the launch sequence
    }
    if (outroRunning) return e.preventDefault();
    if (dialog) {
      const key = e.key.toLowerCase();
      if (key === 'enter' || key === ' ') dialog.done(dialog.choice);
      else if (key === 'y') dialog.done(true);
      else if (key === 'escape' || key === 'n' || key === 'backspace') dialog.done(false);
      else if (key.startsWith('arrow') || key === 'tab') {
        dialog.choice = !dialog.choice;
        dialog.paint();
        sfx('move');
      }
      return e.preventDefault();
    }
    if (!isOpen || closing) return;
    const k = e.key;
    const L = focus.level;
    let handled = true;

    if (k === 'Escape') {
      close();
    } else if (k === 'ArrowDown' || k === 'ArrowUp') {
      const items = itemsAt(L);
      if (items.length) {
        const d = k === 'ArrowDown' ? 1 : -1;
        const i = focus.idx < 0
          ? (d > 0 ? 0 : items.length - 1)
          : (focus.idx + d + items.length) % items.length;
        focus = { level: L, idx: i };
        if (L === 0) {
          select(0, i, { run: false });
        } else {
          if (path.length > L) {
            path = path.slice(0, L);
            trimPanels(L);
          }
          refresh();
          elsAt(L)[i].scrollIntoView({ block: 'nearest' });
          sfx('move');
        }
      }
    } else if (k === 'ArrowRight' || k === 'Enter' || k === ' ') {
      const run = k !== 'ArrowRight';
      if (focus.idx < 0) {
        focus = { level: 0, idx: 0 };
        select(0, 0, { run: false });
      } else if (L === 0 && path[0] === focus.idx && panels.length) {
        focus = { level: 1, idx: 0 };
        refresh();
        sfx('move');
      } else {
        select(L, focus.idx, { run, enter: true });
      }
    } else if (k === 'ArrowLeft' || k === 'Backspace') {
      if (L > 0) {
        path = path.slice(0, L);
        trimPanels(L);
        focus = { level: L - 1, idx: path[L - 1] };
        refresh();
        sfx('back');
      } else if (path.length) {
        collapse();
      } else {
        close();
      }
    } else {
      handled = false;
    }
    if (handled) e.preventDefault();
  });

  window.addEventListener('error', (e) => {
    send({ cmd: 'log', msg: `${e.message} @ ${e.filename}:${e.lineno}` });
  });

  // ---------- launch sequence ----------
  // Light tunnel -> sense checks -> log in -> welcome -> back to the desktop,
  // where the menu drops in. Any key or click skips it.
  const SENSES = ['Touch', 'Sight', 'Hearing', 'Taste', 'Smell'];
  let introState = null;

  /**
   * Light streaks on a canvas behind root's content. paramsAt(seconds) returns
   * { speed, alpha, blue }; positive speed rushes outward, negative converges.
   */
  function streakField(root, paramsAt) {
    const cv = document.createElement('canvas');
    root.prepend(cv);
    const W = innerWidth, H = innerHeight, dpr = devicePixelRatio || 1;
    cv.width = W * dpr;
    cv.height = H * dpr;
    const g = cv.getContext('2d');
    const cx = W / 2, cy = H / 2, maxR = Math.hypot(W, H) / 2;
    const streaks = Array.from({ length: 280 }, () => ({
      a: Math.random() * Math.PI * 2,
      p: Math.random(),
      hue: Math.random() * 360,
      w: 1 + Math.random() * 2.5,
      len: 0.15 + Math.random() * 0.4,
    }));
    const t0 = performance.now();
    let last = t0, raf = 0, stopped = false;
    function frame(now) {
      if (stopped) return;
      const dt = Math.min(0.05, (now - last) / 1000);
      last = now;
      const { speed, alpha, blue = false } = paramsAt((now - t0) / 1000);
      g.setTransform(dpr, 0, 0, dpr, 0, 0);
      g.clearRect(0, 0, W, H);
      g.lineCap = 'round';
      for (const s of streaks) {
        s.p += dt * speed * (0.6 + s.w * 0.2);
        if (s.p > 1 || s.p < 0) {
          s.p -= Math.floor(s.p);
          s.a = Math.random() * Math.PI * 2;
        }
        const r1 = maxR * s.p ** 3;
        const r2 = r1 * (1 + s.len) + 4;
        const c = Math.cos(s.a), sn = Math.sin(s.a);
        g.lineWidth = s.w * (0.5 + s.p * 4);
        const hue = blue ? 190 + (s.hue % 40) : s.hue;
        g.strokeStyle = `hsla(${hue}, 95%, 58%, ${alpha * (0.3 + s.p)})`;
        g.beginPath();
        g.moveTo(cx + c * r1, cy + sn * r1);
        g.lineTo(cx + c * r2, cy + sn * r2);
        g.stroke();
      }
      raf = requestAnimationFrame(frame);
    }
    raf = requestAnimationFrame(frame);
    return {
      stop() {
        stopped = true;
        cancelAnimationFrame(raf);
      },
    };
  }

  // ---------- confirm dialog ----------
  // Round blue "yes" and red "no" buttons. Enter / Y confirms, Esc / N cancels.
  let dialog = null;

  function confirmDialog(title, message) {
    return new Promise((resolve) => {
      const wrap = el('div', 'dialog-wrap', stage);
      const box = el('div', 'dialog', wrap);
      el('header', '', box).textContent = title;
      el('div', 'msg', box).textContent = message;
      const btns = el('div', 'btns', box);
      const yes = el('div', 'btn yes', btns), no = el('div', 'btn no', btns);
      yes.innerHTML = '<svg viewBox="0 0 24 24"><circle cx="12" cy="12" r="7"/></svg>';
      no.innerHTML = '<svg viewBox="0 0 24 24"><path d="M6 6l12 12M18 6L6 18"/></svg>';
      const d = (dialog = {
        choice: true,
        paint() {
          yes.classList.toggle('focus', d.choice);
          no.classList.toggle('focus', !d.choice);
        },
        done(value) {
          if (dialog !== d) return;
          dialog = null;
          wrap.classList.add('out');
          setTimeout(() => wrap.remove(), 180);
          sfx(value ? 'select' : 'back');
          resolve(value);
        },
      });
      yes.addEventListener('click', () => d.done(true));
      no.addEventListener('click', () => d.done(false));
      wrap.addEventListener('mousedown', (e) => {
        e.stopPropagation();
        if (e.target === wrap) d.done(false);
      });
      wrap.addEventListener('click', (e) => e.stopPropagation());
      d.paint();
      sfx('select');
    });
  }

  // ---------- log out sequence ----------
  // Light converges back to the center, then the view switches off like a
  // screen and the app quits.
  let outroRunning = false;

  function outro() {
    outroRunning = true;
    stage.classList.remove('open');
    stage.classList.add('closing');
    const root = el('div', 'intro', stage);
    requestAnimationFrame(() => root.classList.add('in'));
    const fx = streakField(root, (t) => ({
      speed: -(0.5 + t * 1.4),
      alpha: clamp(t / 0.4, 0, 1),
      blue: true,
    }));
    const label = el('div', 'welcome', root);
    label.textContent = 'LOG OUT';
    sfx('logout');
    setTimeout(() => label.classList.add('in'), 350);
    setTimeout(() => {
      stage.querySelectorAll('.column, .panel').forEach((e) => e.remove());
      root.classList.add('off');
    }, 1750);
    setTimeout(() => {
      fx.stop();
      send({ cmd: 'run', action: { type: 'quit' } });
    }, 2350);
  }

  function endIntro(openMenu) {
    const st = introState;
    if (!st) return;
    introState = null;
    st.timers.forEach(clearTimeout);
    if (st.fx) st.fx.stop();
    if (openMenu) {
      st.root.classList.add('out');
      setTimeout(() => st.root.remove(), 600);
      open(st.x, st.y);
    } else {
      st.root.remove();
      setTimeout(() => send({ cmd: 'hide' }), 50);
    }
  }

  function intro(user, x, y) {
    reset();
    if (introState) endIntro(false);
    if (config.intro === false) return open(x, y);

    const root = el('div', 'intro', stage);
    const st = (introState = { root, timers: [], fx: null, x, y });
    const at = (sec, fn) => st.timers.push(setTimeout(fn, sec * 1000));
    root.addEventListener('mousedown', (e) => {
      e.stopPropagation();
      endIntro(true);
    });
    requestAnimationFrame(() => root.classList.add('in'));

    st.fx = streakField(root, (t) => {
      if (t < 2.4) return { speed: 0.25 + t * t * 0.5, alpha: clamp((t - 0.25) / 0.4, 0, 1) };
      if (t < 4.1) return { speed: 0.3, alpha: 0.3 };
      if (t < 6.7) return { speed: 0.08, alpha: clamp(0.3 - (t - 4.1) * 0.6, 0, 0.3) };
      return { speed: 3.2, alpha: clamp((t - 6.7) / 0.2, 0, 1), blue: true };
    });
    at(0.15, () => sfx('dive'));

    // --- sense checks ---
    const senses = el('div', 'senses', root);
    SENSES.forEach((name, i) => {
      const s = el('div', 'sense', senses);
      el('div', 'ring', s).textContent = 'OK';
      el('div', 'name', s).textContent = name;
      at(2.2 + i * 0.3, () => s.classList.add('in'));
      at(2.42 + i * 0.3, () => { s.classList.add('ok'); sfx('tick'); });
    });
    at(3.9, () => senses.classList.add('fly'));

    // --- log in ---
    const login = el('div', 'login', root);
    el('div', 'title', login).textContent = 'LOG IN';
    const field = (label) => {
      const row = el('div', 'field', login);
      el('span', 'key', row).textContent = label;
      return el('span', 'val', row);
    };
    const account = field('ACCOUNT'), password = field('PASSWORD');
    const status = el('div', 'status', login);
    status.textContent = 'AUTHENTICATING…';
    at(4.15, () => login.classList.add('in'));
    const name = [...String(user || 'player')].slice(0, 20);
    name.forEach((ch, i) => at(4.4 + (i * 0.45) / name.length, () => { account.textContent += ch; }));
    for (let i = 0; i < 8; i++) at(4.9 + i * 0.045, () => { password.textContent += '●'; });
    at(5.35, () => { login.classList.add('ok'); status.textContent = 'LOGIN SUCCESSFUL'; sfx('select'); });
    at(5.85, () => login.classList.add('fly'));

    // --- welcome, then back to reality ---
    const welcome = el('div', 'welcome', root);
    welcome.textContent = config.welcome || 'Welcome to Sword Art Online!';
    at(5.95, () => { welcome.classList.add('in'); sfx('welcome'); });
    at(6.7, () => sfx('warp'));
    at(6.95, () => welcome.classList.add('fly'));
    at(7.3, () => endIntro(true));
  }

  window.SAO = {
    intro,
    open,
    close,
    toast,
    setConfig(c) { config = c || { menu: [] }; },
  };
  send({ cmd: 'ready' });
})();
