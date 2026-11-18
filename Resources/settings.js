(() => {
  'use strict';

  const ICONS = window.SAO_ICONS;
  const $ = (id) => document.getElementById(id);
  const send = (msg) => {
    try {
      return window.webkit.messageHandlers.settings.postMessage(msg);
    } catch (e) {
      return Promise.resolve({}); // plain browser
    }
  };

  // What an entry does. "menu" means it holds sub-items instead of an action.
  const TYPES = [
    ['menu', '子菜单'],
    ['open', '打开文件 / 文件夹'],
    ['app', '打开应用'],
    ['url', '打开网页'],
    ['terminal', '终端命令'],
    ['system', '系统功能'],
    ['settings', '打开本设置窗口'],
    ['quit', '退出程序'],
  ];
  // [name, label, hint] for the "system" action
  const SYSTEM = [
    ['lock', '锁定屏幕', '立即锁定 Mac，需要密码或 Touch ID 才能解锁。'],
    ['screensaver', '启动屏幕保护程序', ''],
    ['displaySleep', '关闭显示器', '只让显示器睡眠，电脑继续运行。'],
    ['sleep', '睡眠', '让 Mac 进入睡眠。'],
    ['screenshot', '截图', '打开系统的截图工具栏，可以截图或录屏。'],
    ['darkMode', '切换深色 / 浅色模式', '第一次使用时系统会询问是否允许 SAO Menu 控制 “System Events”，需要点允许。'],
    ['mute', '静音 / 取消静音', ''],
    ['missionControl', '调度中心', '显示所有打开的窗口和桌面。'],
    ['emptyTrash', '清倒废纸篓', '删除后无法恢复，建议勾选下面的二次确认。第一次使用时需要允许 SAO Menu 控制 “访达”。'],
    ['restart', '重新启动…', '弹出系统自己的确认框，可以在那里取消。'],
    ['shutdown', '关机…', '弹出系统自己的确认框，可以在那里取消。'],
    ['logout', '退出登录…', '退出当前 macOS 用户，会弹出系统自己的确认框。'],
  ];
  const SYSTEM_ICONS = { lock: 'lock', sleep: 'moon', displaySleep: 'desktop', screensaver: 'star', screenshot: 'camera', darkMode: 'moon', mute: 'volume', emptyTrash: 'trash', missionControl: 'grid', restart: 'refresh', shutdown: 'power', logout: 'logout' };
  const NEW_ACTION = {
    open: { type: 'open', path: '~' },
    app: { type: 'app', app: '' },
    url: { type: 'url', url: 'https://' },
    terminal: { type: 'terminal', cwd: '~', command: '' },
    system: { type: 'system', name: 'lock' },
    settings: { type: 'settings' },
    quit: { type: 'quit' },
  };

  let cfg = null;
  let trusted = false; // Accessibility permission, needed to fully intercept the mouse gesture
  let defaults = '{}';
  let sel = 'general'; // 'general' or an index path into cfg.menu
  let armed = null; // which destructive button is waiting for a second click

  // ---------- dom helpers ----------
  function h(tag, props, ...kids) {
    const e = document.createElement(tag);
    for (const [k, v] of Object.entries(props || {})) {
      if (k === 'class') e.className = v;
      else if (k.startsWith('on')) e.addEventListener(k.slice(2), v);
      else if (v === true) e.setAttribute(k, '');
      else if (v !== false && v != null) e.setAttribute(k, v);
    }
    for (const kid of kids.flat()) if (kid != null && kid !== false) e.append(kid);
    return e;
  }

  function glyph(name) {
    const g = h('span', { class: 'glyph' });
    if (ICONS[name]) g.innerHTML = `<svg viewBox="0 0 24 24">${ICONS[name]}</svg>`;
    else g.textContent = [...String(name || '')].slice(0, 2).join('');
    return g;
  }

  // ---------- model helpers ----------
  const isPath = (v) => Array.isArray(v);
  const same = (a, b) => isPath(a) && isPath(b) && a.join() === b.join();
  const typeOf = (node) => (node.action ? node.action.type || 'open' : 'menu');

  function listAt(path) {
    let list = cfg.menu;
    for (const i of path) list = list[i].items;
    return list;
  }
  const nodeAt = (path) => listAt(path.slice(0, -1))[path[path.length - 1]];

  // mirrors the menu's own choice when an entry has no explicit icon
  function iconOf(node, top) {
    if (node.icon) return node.icon;
    if (top) return 'star';
    if (node.items) return 'list';
    const a = node.action || {};
    if (a.type === 'quit') return 'logout';
    if (a.type === 'lock') return 'lock';
    if (a.type === 'system') return SYSTEM_ICONS[a.name] || 'gear';
    if (a.type === 'settings') return 'gear';
    if (a.type === 'url') return 'globe';
    if (a.type === 'terminal') return 'terminal';
    if (a.type === 'app') return 'grid';
    const base = String(a.path || '').split('/').pop();
    if (base.endsWith('.app')) return 'grid';
    return /\.[A-Za-z0-9]{1,8}$/.test(base) ? 'file' : 'folder';
  }

  // ---------- saving ----------
  let saveTimer = 0;
  function setStatus(text, cls) {
    $('status').textContent = text;
    $('status').className = cls || '';
  }
  function changed(treeToo) {
    if (treeToo) renderTree();
    setStatus('正在保存…');
    clearTimeout(saveTimer);
    saveTimer = setTimeout(save, 350);
  }
  async function save() {
    clearTimeout(saveTimer);
    let res;
    try {
      res = await send({ cmd: 'save', text: JSON.stringify(cfg, null, 2) + '\n' });
    } catch (e) {
      res = { ok: false, error: String(e) };
    }
    if (!res || res.ok === false) setStatus((res && res.error) || '保存失败', 'bad');
    else if (res.warning) setStatus(res.warning, 'bad');
    else setStatus('已保存，下次呼出菜单生效', 'ok');
  }

  // ---------- sidebar ----------
  function select(next) {
    sel = next;
    armed = null;
    render();
  }

  function renderTree() {
    const tree = $('tree');
    const scroll = tree.scrollTop;
    tree.textContent = '';
    tree.append(
      h('div', { class: 'trow' + (sel === 'general' ? ' sel' : ''), onclick: () => select('general') },
        glyph('gear'), h('span', { class: 'tl' }, '通用设置')),
      h('div', { class: 'thead' }, '菜单'));
    const walk = (items, base) => items.forEach((node, i) => {
      const path = base.concat(i);
      const row = h('div', {
        class: 'trow' + (base.length ? '' : ' top') + (same(sel, path) ? ' sel' : ''),
        style: `padding-left:${10 + base.length * 20}px`,
        onclick: () => { if (!justDragged) select(path); },
        onmousedown: (e) => startDrag(e, path, row),
      },
        glyph(iconOf(node, !base.length)),
        h('span', { class: 'tl' }, node.label || '（未命名）'),
        node.items ? h('span', { class: 'tc' }, String(node.items.length)) : null);
      row._path = path;
      tree.append(row);
      if (node.items) walk(node.items, path);
    });
    walk(cfg.menu, []);
    tree.scrollTop = scroll;
    const current = tree.querySelector('.sel');
    if (current) current.scrollIntoView({ block: 'nearest' });

    const on = isPath(sel);
    const node = on ? nodeAt(sel) : null;
    const idx = on ? sel[sel.length - 1] : -1;
    $('addChild').disabled = !(node && node.items);
    $('up').disabled = !on || idx === 0;
    $('down').disabled = !on || idx === listAt(sel.slice(0, -1)).length - 1;
    $('del').disabled = !on;
    $('del').textContent = armed === 'del' ? '确认删除' : '删除';
    $('del').classList.toggle('armed', armed === 'del');
    $('restore').textContent = armed === 'restore' ? '确认恢复默认' : '恢复默认配置';
    $('restore').classList.toggle('armed', armed === 'restore');
  }

  // ---------- drag to reorder ----------
  // Drag a row onto another: its upper part drops before it, its lower part
  // after it, and the middle of a submenu row drops into that submenu. Works
  // across levels and across top-level icons.
  let justDragged = false;

  function startDrag(down, from, row) {
    if (down.button !== 0) return;
    const tree = $('tree');
    const node = nodeAt(from);
    let active = false, drop = null, ghost = null;
    const line = h('div', { class: 'dropline' });
    const rows = () => [...tree.querySelectorAll('.trow')].filter((r) => r._path);
    const inside = (p) => from.every((v, i) => p[i] === v); // p is the dragged row or below it

    const clear = () => {
      line.remove();
      tree.querySelectorAll('.drop-into').forEach((r) => r.classList.remove('drop-into'));
    };
    const onMove = (e) => {
      if (!active) {
        if (Math.hypot(e.clientX - down.clientX, e.clientY - down.clientY) < 5) return;
        active = true;
        row.classList.add('dragging');
        document.body.classList.add('drag-on');
        ghost = h('div', { class: 'dragghost' }, node.label || '（未命名）');
        document.body.append(ghost);
      }
      ghost.style.left = e.clientX + 12 + 'px';
      ghost.style.top = e.clientY + 8 + 'px';
      const box = tree.getBoundingClientRect();
      if (e.clientY < box.top + 26) tree.scrollTop -= 10;
      else if (e.clientY > box.bottom - 26) tree.scrollTop += 10;

      clear();
      drop = null;
      const all = rows();
      let target = all.find((r) => {
        const b = r.getBoundingClientRect();
        return e.clientY >= b.top && e.clientY < b.bottom;
      });
      // below the last row: append at the top level
      if (!target && all.length && e.clientY >= all[all.length - 1].getBoundingClientRect().bottom
          && e.clientX >= box.left && e.clientX <= box.right) {
        target = all.find((r) => r._path.length === 1 && r._path[0] === cfg.menu.length - 1);
        if (target && !inside(target._path)) drop = { target, where: 'after' };
      } else if (target && !inside(target._path)) {
        const b = target.getBoundingClientRect();
        const t = (e.clientY - b.top) / b.height;
        const folder = !!nodeAt(target._path).items;
        const where = folder ? (t < 0.28 ? 'before' : t > 0.72 ? 'after' : 'into') : (t < 0.5 ? 'before' : 'after');
        drop = { target, where };
      }
      if (!drop) return;
      if (drop.where === 'into') return drop.target.classList.add('drop-into');
      // "after" a submenu means after everything inside it
      let edge = drop.target;
      if (drop.where === 'after') {
        const p = drop.target._path;
        all.forEach((r) => { if (p.every((v, i) => r._path[i] === v)) edge = r; });
      }
      const eb = edge.getBoundingClientRect();
      line.style.top = (drop.where === 'before' ? eb.top : eb.bottom) - box.top + tree.scrollTop - 1 + 'px';
      line.style.left = 10 + (drop.target._path.length - 1) * 20 + 'px';
      tree.append(line);
    };
    const onUp = () => {
      document.removeEventListener('mousemove', onMove);
      document.removeEventListener('mouseup', onUp);
      if (!active) return;
      clear();
      if (ghost) ghost.remove();
      row.classList.remove('dragging');
      document.body.classList.remove('drag-on');
      justDragged = true; // swallow the click that follows this mouseup
      setTimeout(() => { justDragged = false; }, 0);
      if (!drop) return;
      const targetNode = nodeAt(drop.target._path);
      const destList = drop.where === 'into' ? targetNode.items : listAt(drop.target._path.slice(0, -1));
      const srcList = listAt(from.slice(0, -1));
      srcList.splice(from[from.length - 1], 1);
      if (drop.where === 'into') destList.push(node);
      else destList.splice(destList.indexOf(targetNode) + (drop.where === 'after' ? 1 : 0), 0, node);
      const find = (items, base) => {
        for (let i = 0; i < items.length; i++) {
          if (items[i] === node) return base.concat(i);
          const deep = items[i].items && find(items[i].items, base.concat(i));
          if (deep) return deep;
        }
        return null;
      };
      sel = find(cfg.menu, []) || 'general';
      armed = null;
      render();
      changed();
    };
    document.addEventListener('mousemove', onMove);
    document.addEventListener('mouseup', onUp);
  }

  $('add').onclick = () => {
    if (isPath(sel)) {
      const parent = sel.slice(0, -1), at = sel[sel.length - 1] + 1;
      listAt(parent).splice(at, 0, parent.length
        ? { label: '新项目', action: { ...NEW_ACTION.open } }
        : { icon: 'star', label: 'NEW', items: [] });
      sel = parent.concat(at);
    } else {
      cfg.menu.push({ icon: 'star', label: 'NEW', items: [] });
      sel = [cfg.menu.length - 1];
    }
    armed = null;
    render();
    changed();
  };
  $('addChild').onclick = () => {
    const node = nodeAt(sel);
    node.items.push({ label: '新项目', action: { ...NEW_ACTION.open } });
    sel = sel.concat(node.items.length - 1);
    armed = null;
    render();
    changed();
  };
  function move(delta) {
    const list = listAt(sel.slice(0, -1)), i = sel[sel.length - 1];
    [list[i], list[i + delta]] = [list[i + delta], list[i]];
    sel = sel.slice(0, -1).concat(i + delta);
    armed = null;
    render();
    changed();
  }
  $('up').onclick = () => move(-1);
  $('down').onclick = () => move(1);
  $('del').onclick = () => {
    const node = nodeAt(sel);
    if (node.items && node.items.length && armed !== 'del') {
      armed = 'del'; // has children: ask for a second click
      return renderTree();
    }
    const parent = sel.slice(0, -1), list = listAt(parent), i = sel[sel.length - 1];
    list.splice(i, 1);
    sel = list.length ? parent.concat(Math.min(i, list.length - 1)) : parent.length ? parent : 'general';
    armed = null;
    render();
    changed();
  };

  // ---------- form pieces ----------
  const field = (label, ...ctl) =>
    h('div', { class: 'field' }, h('label', {}, label), h('div', { class: 'ctl' }, ...ctl));

  /** Text input bound to obj[key]; an empty value removes the key. */
  function text(obj, key, opt = {}) {
    const input = h(opt.multiline ? 'textarea' : 'input', {
      type: opt.multiline ? null : 'text',
      placeholder: opt.placeholder,
      spellcheck: 'false',
      oninput: () => {
        if (input.value === '' && !opt.keepEmpty) delete obj[key];
        else obj[key] = input.value;
        changed(opt.tree);
      },
    });
    input.value = obj[key] == null ? '' : obj[key];
    return input;
  }

  function pick(label, kind, obj, key, input, tree) {
    return h('button', {
      onclick: async () => {
        const res = await send({ cmd: 'pick', kind });
        if (!res || !res.path) return;
        obj[key] = res.path;
        input.value = res.path;
        changed(tree);
      },
    }, label);
  }

  function check(label, value, onchange) {
    const box = h('input', { type: 'checkbox', checked: value, onchange: () => onchange(box.checked) });
    return h('label', { class: 'check' }, box, label);
  }

  function appField(label, action, hint) {
    const input = text(action, 'app', { placeholder: hint, tree: true });
    return field(label, input, pick('选择…', 'app', action, 'app', input, true));
  }

  function iconField(node, top) {
    const custom = h('input', {
      type: 'text',
      placeholder: '或输入 emoji / 文字',
      style: 'flex:none;width:170px',
      oninput: () => {
        if (custom.value) node.icon = custom.value;
        else delete node.icon;
        changed(true);
        paint();
      },
    });
    const grid = h('div', { class: 'icons' });
    const cell = (name, content, title) => h('button', {
      class: 'pick', title, 'data-name': name,
      onclick: () => {
        if (name) node.icon = name;
        else delete node.icon;
        custom.value = '';
        changed(true);
        paint();
      },
    }, content);
    grid.append(cell('', '自动', top ? '默认图标' : '按动作类型自动选择'));
    for (const name of Object.keys(ICONS)) grid.append(cell(name, glyph(name), name));
    function paint() {
      for (const b of grid.children) b.classList.toggle('on', (node.icon || '') === b.dataset.name);
    }
    if (node.icon && !ICONS[node.icon]) custom.value = node.icon;
    paint();
    return field('图标', grid, custom);
  }

  // ---------- entry form ----------
  function renderNode(form, path) {
    const node = nodeAt(path);
    const top = path.length === 1;
    const type = typeOf(node);
    $('title').textContent = (top ? '图标：' : '') + (node.label || '（未命名）');

    const label = text(node, 'label', { placeholder: top ? '显示在面板标题上' : '显示的名称', tree: true });
    label.addEventListener('input', () => {
      $('title').textContent = (top ? '图标：' : '') + (node.label || '（未命名）');
    });
    form.append(field('名称', label), iconField(node, top));

    const kids = (node.items || []).length;
    const typeSel = h('select', {
      disabled: kids > 0,
      onchange: () => {
        const t = typeSel.value;
        if (t === 'menu') {
          delete node.action;
          node.items = [];
        } else {
          delete node.items;
          node.action = { ...NEW_ACTION[t] };
        }
        render();
        changed();
      },
    }, TYPES.map(([v, name]) => h('option', { value: v }, name)));
    typeSel.value = TYPES.some(([v]) => v === type) ? type : 'open';
    form.append(field('类型', typeSel,
      kids ? h('span', { class: 'hint' }, `有 ${kids} 个子项，删除它们之后才能改成其他类型。`) : null));

    const a = node.action;
    if (type === 'menu') {
      form.append(field('', h('span', { class: 'hint' },
        '点开后展开一个面板。用左下角的「＋ 子项」往里面添加内容。')));
      return;
    }
    if (type === 'open') {
      const p = text(a, 'path', { placeholder: '~/Documents', keepEmpty: true, tree: true });
      form.append(
        field('路径', p, pick('选择文件', 'file', a, 'path', p, true), pick('选择文件夹', 'dir', a, 'path', p, true)),
        appField('用此应用打开', a, '留空则用默认应用'));
    } else if (type === 'app') {
      form.append(appField('应用', a, '应用名、路径或 bundle id，如 Music'));
      form.append(field('', h('span', { class: 'hint' }, '不指定图标（选「自动」）时，菜单里显示应用自己的图标。')));
    } else if (type === 'url') {
      form.append(
        field('网址', text(a, 'url', { placeholder: 'https://example.com', keepEmpty: true, tree: true })),
        appField('浏览器', a, '留空则用默认浏览器'));
    } else if (type === 'terminal') {
      const cwd = text(a, 'cwd', { placeholder: '~' });
      form.append(
        field('目录', cwd, pick('选择…', 'dir', a, 'cwd', cwd)),
        field('命令', text(a, 'command', { multiline: true, placeholder: '留空则只打开终端；可以写多行', tree: true })),
        appField('终端应用', a, '留空则用系统自带的终端，可填 iTerm 等'));
    } else if (type === 'quit') {
      form.append(field('', h('span', { class: 'hint' }, '弹出确认框，确认后播放登出动画并退出 SAO Menu。')));
      return;
    } else if (type === 'settings') {
      form.append(field('', h('span', { class: 'hint' }, '打开这个设置窗口。')));
      return;
    } else if (type === 'system') {
      const hint = h('span', { class: 'hint' });
      const box = h('select', {
        onchange: () => {
          a.name = box.value;
          render();
          changed();
        },
      }, SYSTEM.map(([v, name]) => h('option', { value: v }, name)));
      const cur = SYSTEM.find(([v]) => v === a.name) || SYSTEM[0];
      box.value = cur[0];
      hint.textContent = cur[2];
      form.append(field('功能', box));
      if (cur[2]) form.append(field('', hint));
    }

    // optional confirmation before running
    const msg = h('input', {
      type: 'text',
      placeholder: '确认框里的提示（可留空）',
      oninput: () => {
        a.confirm = msg.value || true;
        changed();
      },
    });
    msg.value = typeof a.confirm === 'string' ? a.confirm : '';
    msg.hidden = !a.confirm;
    form.append(h('div', { class: 'sep' }), field('二次确认',
      check('执行前先弹出确认框', !!a.confirm, (on) => {
        if (on) a.confirm = msg.value || true;
        else delete a.confirm;
        msg.hidden = !on;
        changed();
      }), msg));
  }

  // ---------- general form ----------
  const MOD_NAMES = { cmd: '⌘', command: '⌘', alt: '⌥', option: '⌥', opt: '⌥', ctrl: '⌃', control: '⌃', shift: '⇧' };
  const prettyHotkey = (s) => String(s || '').split('+').map((p) => {
    const k = p.trim().toLowerCase();
    return MOD_NAMES[k] || (k.length === 1 ? k.toUpperCase() : k.replace(/^\w/, (c) => c.toUpperCase()));
  }).join(' ');
  const CODE_KEYS = {
    Space: 'space', Backquote: '`', Minus: '-', Equal: '=', BracketLeft: '[', BracketRight: ']',
    Semicolon: ';', Quote: "'", Comma: ',', Period: '.', Slash: '/', Backslash: '\\',
    Enter: 'return', Tab: 'tab',
  };

  function hotkeyButton() {
    let recording = false;
    const btn = h('button', { class: 'hotkey' });
    const paint = () => {
      btn.textContent = recording ? '请按下新的快捷键…' : prettyHotkey(cfg.hotkey || 'alt+s');
      btn.classList.toggle('rec', recording);
    };
    const stop = () => {
      if (!recording) return;
      recording = false;
      send({ cmd: 'hotkey', suspend: false });
      paint();
    };
    btn.onclick = () => {
      if (recording) return stop();
      recording = true;
      send({ cmd: 'hotkey', suspend: true }); // so the current hotkey doesn't fire meanwhile
      paint();
    };
    btn.onblur = stop;
    btn.onkeydown = (e) => {
      if (!recording) return;
      e.preventDefault();
      e.stopPropagation();
      if (e.key === 'Escape') return stop();
      let key = CODE_KEYS[e.code];
      const m = /^(?:Key([A-Z])|Digit(\d)|(F\d{1,2}))$/.exec(e.code);
      if (m) key = (m[1] || m[2] || m[3]).toLowerCase();
      if (!key) return; // a modifier on its own, or an unsupported key
      const mods = [e.ctrlKey && 'ctrl', e.altKey && 'alt', e.shiftKey && 'shift', e.metaKey && 'cmd'].filter(Boolean);
      if (!mods.length && !/^f\d+$/.test(key)) {
        return setStatus('快捷键需要带上 ⌘ ⌥ ⌃ ⇧ 中的至少一个', 'bad');
      }
      cfg.hotkey = mods.concat(key).join('+');
      recording = false;
      paint();
      save(); // saving re-registers the hotkey
    };
    paint();
    return btn;
  }

  function mouseSelect() {
    const options = [['off', '关闭'], ['right', '按住右键向下划'], ['both', '同时按住左右键向下划']];
    const box = h('select', {
      onchange: () => {
        cfg.mouseGesture = box.value;
        changed();
      },
    }, options.map(([v, name]) => h('option', { value: v }, name)));
    const current = cfg.mouseGesture === true ? 'both' : cfg.mouseGesture; // true: older configs
    box.value = options.some(([v]) => v === current) ? current : 'off';
    return box;
  }

  function trackpadSelect() {
    const options = [['off', '关闭'], ['tap4', '四指轻点（推荐）'], ['tap5', '五指轻点'], ['tap3', '三指轻点']];
    const box = h('select', {
      onchange: () => {
        cfg.trackpad = box.value;
        changed();
      },
    }, options.map(([v, name]) => h('option', { value: v }, name)));
    box.value = options.some(([v]) => v === cfg.trackpad) ? cfg.trackpad : 'off';
    return box;
  }

  function renderGeneral(form) {
    $('title').textContent = '通用设置';
    const vol = h('input', {
      type: 'range', min: '0', max: '1', step: '0.05',
      oninput: () => {
        cfg.volume = Number(vol.value);
        volText.textContent = Math.round(cfg.volume * 100) + '%';
        changed();
      },
    });
    vol.value = cfg.volume == null ? 0.7 : cfg.volume;
    const volText = h('span', { class: 'hint', style: 'flex-basis:auto' }, Math.round(vol.value * 100) + '%');

    const num = (key, def, min, max) => {
      const box = h('input', {
        type: 'number', min: String(min), max: String(max), step: '1', style: 'width:70px;flex:none',
        onchange: () => {
          const v = Math.min(max, Math.max(min, Math.round(Number(box.value)) || def));
          box.value = v;
          cfg[key] = v;
          changed();
        },
      });
      box.value = cfg[key] == null ? def : cfg[key];
      return box;
    };

    form.append(
      field('呼出热键', hotkeyButton(), h('span', { class: 'hint' }, '点击按钮后按下新的组合键，Esc 取消。')),
      field('鼠标手势', mouseSelect(),
        h('span', { class: 'hint' }, trusted
          ? '已获得「辅助功能」权限：手势不会传给下面的应用。右键模式下，普通右键菜单会在松开按键时弹出。'
          : '没有「辅助功能」权限时只能旁观：手势能触发，但下面的应用会同时弹出右键菜单，右键模式尤其明显。授权后自动切换。'),
        trusted ? null : h('button', { onclick: () => send({ cmd: 'axPrompt' }) }, '去授权…')),
      field('触控板手势', trackpadSelect(),
        h('span', { class: 'hint' }, '轻点不会和系统的滑动、捏合手势冲突，再点一次收起菜单。如果系统开启了「三指轻点查询」，不要选三指。')),
      h('div', { class: 'sep' }),
      field('子菜单行数', num('maxRows', 7, 2, 20),
        h('span', { class: 'hint' }, '一个子菜单最多同时显示几项；超过的可以滚动，边缘的选项会渐渐淡出。')),
      field('背景模糊', num('blur', 6, 0, 40),
        h('span', { class: 'hint' }, '菜单呼出时背后画面的模糊程度，0 为关闭。')),
      h('div', { class: 'sep' }),
      field('音效', check('播放音效', cfg.sound !== false, (on) => { cfg.sound = on; changed(); })),
      field('音量', vol, volText),
      h('div', { class: 'sep' }),
      field('启动动画', check('启动时播放登录动画', cfg.intro !== false, (on) => { cfg.intro = on; changed(); })),
      field('欢迎语', text(cfg, 'welcome', { placeholder: 'Welcome to Sword Art Online!' })),
      h('div', { class: 'sep' }),
      field('', h('span', { class: 'hint' },
        '在左侧选择菜单项进行编辑。最外层的每一项是一个圆形图标，里面可以嵌套多层子菜单。修改会自动保存，打开本窗口时的配置备份在 config.backup.json。')));
  }

  // ---------- render ----------
  function render() {
    if (!cfg) return;
    if (isPath(sel)) {
      try {
        if (!nodeAt(sel)) sel = 'general';
      } catch (e) {
        sel = 'general';
      }
    }
    renderTree();
    const form = $('form');
    form.textContent = '';
    if (isPath(sel)) renderNode(form, sel);
    else renderGeneral(form);
  }

  function showError(message) {
    $('app').hidden = !!message;
    $('app').style.display = message ? 'none' : '';
    $('error').hidden = !message;
    $('errorText').textContent = message || '';
  }

  function adopt(textValue) {
    const parsed = JSON.parse(textValue);
    if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) {
      throw new Error('配置的最外层必须是一个 JSON 对象');
    }
    if (!Array.isArray(parsed.menu)) parsed.menu = [];
    // every entry is either a submenu or an action; normalise anything else
    const fix = (items) => items.forEach((n) => {
      if (Array.isArray(n.items)) fix(n.items);
      else if (!n.action) n.items = [];
    });
    fix(parsed.menu);
    cfg = parsed;
  }

  async function load() {
    const res = await send({ cmd: 'load' });
    defaults = (res && res.defaults) || '{}';
    trusted = !!(res && res.trusted);
    try {
      adopt((res && res.text) || '');
      showError(null);
      setStatus('');
      sel = 'general';
      armed = null;
      render();
    } catch (e) {
      cfg = null;
      showError(`config.json 解析失败：${e.message}`);
    }
  }

  function restoreDefaults() {
    adopt(defaults);
    showError(null);
    sel = 'general';
    armed = null;
    render();
    save();
  }

  $('preview').onclick = () => send({ cmd: 'preview' });
  $('openFile').onclick = () => send({ cmd: 'openFile' });
  $('errOpen').onclick = () => send({ cmd: 'openFile' });
  $('errRestore').onclick = restoreDefaults;
  $('restore').onclick = () => {
    if (armed !== 'restore') {
      armed = 'restore';
      return renderTree();
    }
    restoreDefaults();
  };
  document.addEventListener('contextmenu', (e) => {
    if (!/^(INPUT|TEXTAREA)$/.test(e.target.tagName)) e.preventDefault();
  });

  window.Settings = { reload: load };
  load();
})();
