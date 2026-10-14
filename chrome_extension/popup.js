const TEXT = {
  ru: {
    connectedTo: '{0}', noServer: 'Сервер не добавлен', notFound: 'Приложение не найдено', needCode: 'Нужен код',
    offTitle: 'Приложение ColdVPN не запущено',
    offText: 'Расширение работает вместе с приложением на этом компьютере. Запустите ColdVPN — расширение подключится само.',
    retry: 'Проверить снова', retryAgain: 'Всё ещё не найдено — проверить снова',
    pairTitle: 'Введите код из приложения',
    pairText: 'ColdVPN → «Настройки» → «Расширение для браузера». Код нужен один раз.',
    pairError: 'Код не подошёл. Проверьте его в приложении.', pairSave: 'Подключить', paired: 'Расширение подключено к ColdVPN',
    vpnOn: 'VPN включён', vpnOff: 'VPN выключен', vpnBusy: 'Включаю VPN…', vpnFail: 'Не удалось включить VPN', failNote: 'Подробности — в приложении, вкладка «Журнал»', slowNote: 'Поднимаю туннель — это занимает до 20 секунд',
    noteAll: 'Через VPN — все сайты', noteFav: 'Через VPN — избранные сайты: {0}', noteOff: 'Нажмите, чтобы включить',
    modeAll: 'Все сайты', modeFav: 'Избранные',
    favTitle: 'Избранные сайты', countFav: 'Включено {0} из {1}', countAll: 'Работает на весь браузер',
    empty: 'Список пуст. Откройте сайт и добавьте его кнопкой ниже.',
    addFav: 'Добавить текущий сайт в избранное', inFav: 'Уже в избранном', noSite: 'На этой вкладке нет сайта',
    addApp: 'Добавить сайт в приложение', inApp: 'Уже есть в приложении',
    favAdded: '{0} добавлен в избранное', favAlready: '«{0}» уже в избранном', favRemoved: '«{0}» удалён из избранного', saved: 'Изменения сохранены',
    ctxEdit: 'Изменить…', ctxEditPlain: 'Изменить', ctxOpen: 'Открыть в новой вкладке', ctxDelete: 'Удалить из избранного',
    turnOn: 'Включить', turnOff: 'Выключить',
    favSite: 'Избранный сайт', editNote: 'Название и домены', keep: 'Не удалять', delete: 'Удалить', confirm: 'Удалить «{0}» из избранного?',
    editTitle: 'Изменить сайт', name: 'Название', domains: 'Домены, по одному в строке', domainsNote: 'Каждый домен — вместе с поддоменами.',
    cancel: 'Отмена', save: 'Сохранить', add: 'Добавить',
    appTitle: 'Добавить сайт в приложение', appNote: 'Домен {0} со всеми поддоменами станет ресурсом ColdVPN — его можно включать в приложении для всей системы.',
    resName: 'Название ресурса', section: 'Раздел', appAdded: 'Ресурс «{0}» добавлен в раздел «{1}»', appHas: '{0} уже есть в ресурсах ColdVPN',
    locked: '{0}, заблокировано: VPN на весь браузер', actions: 'Действия с сайтом «{0}»', drag: 'Зажмите и перетащите, чтобы изменить порядок. Правая кнопка — меню',
  },
  en: {
    connectedTo: '{0}', noServer: 'No server added', notFound: 'App not found', needCode: 'Code needed',
    offTitle: 'The ColdVPN app is not running',
    offText: 'The extension works together with the app on this computer. Start ColdVPN and the extension connects by itself.',
    retry: 'Check again', retryAgain: 'Still not found — check again',
    pairTitle: 'Enter the code from the app',
    pairText: 'ColdVPN → Settings → Browser extension. The code is needed once.',
    pairError: 'The code did not match. Check it in the app.', pairSave: 'Connect', paired: 'The extension is connected to ColdVPN',
    vpnOn: 'VPN is on', vpnOff: 'VPN is off', vpnBusy: 'Turning the VPN on…', vpnFail: 'Could not turn the VPN on', failNote: 'Details are on the Log tab of the app', slowNote: 'Bringing up the tunnel takes up to 20 seconds',
    noteAll: 'Through the VPN: all sites', noteFav: 'Through the VPN: favourite sites: {0}', noteOff: 'Press to turn on',
    modeAll: 'All sites', modeFav: 'Favourites',
    favTitle: 'Favourite sites', countFav: '{0} of {1} on', countAll: 'Works for the whole browser',
    empty: 'The list is empty. Open a site and add it with the button below.',
    addFav: 'Add the current site to favourites', inFav: 'Already in favourites', noSite: 'There is no site in this tab',
    addApp: 'Add the site to the app', inApp: 'Already in the app',
    favAdded: '{0} added to favourites', favAlready: '“{0}” is already in favourites', favRemoved: '“{0}” removed from favourites', saved: 'Changes saved',
    ctxEdit: 'Edit…', ctxEditPlain: 'Edit', ctxOpen: 'Open in a new tab', ctxDelete: 'Remove from favourites',
    turnOn: 'Turn on', turnOff: 'Turn off',
    favSite: 'Favourite site', editNote: 'Name and domains', keep: 'Keep', delete: 'Remove', confirm: 'Remove “{0}” from favourites?',
    editTitle: 'Edit site', name: 'Name', domains: 'Domains, one per line', domainsNote: 'Each domain includes its subdomains.',
    cancel: 'Cancel', save: 'Save', add: 'Add',
    appTitle: 'Add the site to the app', appNote: 'The domain {0} with all subdomains becomes a ColdVPN resource — it can be turned on in the app for the whole system.',
    resName: 'Resource name', section: 'Section', appAdded: 'Resource “{0}” added to the section “{1}”', appHas: '{0} is already in the ColdVPN resources',
    locked: '{0}, locked: VPN for the whole browser', actions: 'Actions for “{0}”', drag: 'Hold and drag to reorder. Right-click for the menu',
  },
};
let lang = navigator.language.toLowerCase().startsWith('ru') ? 'ru' : 'en';
const t = (key, ...args) => (TEXT[lang][key] || key).replace(/\{(\d)\}/g, (_, i) => args[i] ?? '');
const $ = (id) => document.getElementById(id);
const ICON = {
  grip: '<svg width="14" height="14" viewBox="0 0 24 24" fill="currentColor"><circle cx="9" cy="6" r="1.7"/><circle cx="15" cy="6" r="1.7"/><circle cx="9" cy="12" r="1.7"/><circle cx="15" cy="12" r="1.7"/><circle cx="9" cy="18" r="1.7"/><circle cx="15" cy="18" r="1.7"/></svg>',
  more: '<svg width="16" height="16" viewBox="0 0 24 24" fill="currentColor"><circle cx="12" cy="5" r="1.8"/><circle cx="12" cy="12" r="1.8"/><circle cx="12" cy="19" r="1.8"/></svg>',
  lock: '<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><rect x="5" y="11" width="14" height="10" rx="2"/><path d="M8 11V7a4 4 0 0 1 8 0v4"/></svg>',
};

let st = { on: false, mode: 'fav', favs: [] };
let status = null;
let host = '';
let site = null; // ответ приложения про текущий сайт
let view = '';
let menuId = null;
let dragId = null;
let retried = false;

function translate() {
  document.documentElement.lang = lang;
  for (const el of document.querySelectorAll('[data-t]')) el.textContent = t(el.dataset.t);
}

function show(name) {
  if (view === name) return;
  view = name;
  for (const id of ['offline', 'pair', 'main']) $(id).hidden = id !== name;
}

function setCollapsed(el, shut) { el.classList.toggle('shut', shut); }

let toastTimer;
function toast(text) {
  const el = $('toast');
  el.textContent = text;
  el.classList.add('show');
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => el.classList.remove('show'), 2200);
}

async function save(patch) {
  Object.assign(st, patch);
  await chrome.storage.local.set(patch);
}

const hostIn = (f) => !!host && f.domains.some((d) => host === d || host.endsWith('.' + d));
const titleCase = (s) => s.charAt(0).toUpperCase() + s.slice(1);

async function currentHost() {
  try {
    const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
    const url = new URL(tab?.url || '');
    if (url.protocol === 'http:' || url.protocol === 'https:') return cleanDomain(url.hostname);
  } catch (e) {}
  return '';
}

// ------------------------------------------------------------------ render

function render() {
  const fav = st.mode === 'fav';
  // Приложение сообщило об ошибке — показываем её, а не бесконечное «Включаю».
  const failed = st.on && status && status.browser === 'off' && !!status.error;
  const busy = st.on && status && status.browser !== 'on' && !failed;
  const power = $('power');
  power.classList.toggle('on', st.on && !busy && !failed);
  power.classList.toggle('busy', !!busy);
  power.classList.toggle('failed', !!failed);
  power.setAttribute('aria-checked', String(st.on));
  $('powerTitle').textContent = !st.on ? t('vpnOff') : failed ? t('vpnFail') : busy ? t('vpnBusy') : t('vpnOn');
  const enabled = st.favs.filter((f) => f.on).length;
  $('powerNote').textContent = !st.on ? t('noteOff')
    : failed ? status.error
    : busy ? t('slowNote')
    : fav ? t('noteFav', enabled) : t('noteAll');
  $('powerNote').title = failed ? t('failNote') : '';

  const seg = document.querySelector('.segments');
  seg.classList.toggle('fav', fav);
  for (const b of seg.querySelectorAll('button')) b.setAttribute('aria-checked', String(b.dataset.mode === st.mode));
  $('favCount').textContent = fav ? t('countFav', enabled, st.favs.length) : t('countAll');

  renderList();

  const inFav = st.favs.some(hostIn);
  const favBtn = $('addFav');
  favBtn.classList.toggle('done', inFav || !host);
  $('addFavTitle').textContent = !host ? t('noSite') : inFav ? t('inFav') : t('addFav');
  $('addFavHost').textContent = host;
  $('addFavHost').hidden = !host;
  const inApp = !!site?.resource;
  const appBtn = $('addApp');
  appBtn.hidden = !host;
  appBtn.classList.toggle('done', inApp);
  $('addAppTitle').textContent = inApp ? t('inApp') : t('addApp');
}

function renderList() {
  const list = $('list');
  const fav = st.mode === 'fav';
  $('empty').hidden = st.favs.length > 0;
  const rows = new Map([...list.children].map((el) => [el.dataset.id, el]));
  const keep = new Set();
  st.favs.forEach((f, index) => {
    keep.add(f.id);
    let row = rows.get(f.id);
    if (!row) {
      row = document.createElement('div');
      row.className = 'row';
      row.setAttribute('role', 'listitem');
      row.draggable = true;
      row.dataset.id = f.id;
      // Перетаскивают всю строку, меню — правой кнопкой мыши.
      row.innerHTML = '<span class="row-text"><span class="row-name"></span><span class="row-meta"></span></span>' +
        '<button class="toggle" role="switch" draggable="false"></button>';
      row.querySelector('.toggle').addEventListener('click', () => toggleFav(row.dataset.id));
      row.addEventListener('contextmenu', (e) => { e.preventDefault(); openCtx(row.dataset.id, e.clientX, e.clientY); });
      row.addEventListener('dragstart', (e) => { dragId = row.dataset.id; e.dataTransfer.effectAllowed = 'move'; e.dataTransfer.setData('text/plain', dragId); requestAnimationFrame(() => row.classList.add('dragging')); });
      row.addEventListener('dragend', () => { row.classList.remove('dragging'); if (dragId) { dragId = null; save({ favs: st.favs }); } });
      row.addEventListener('dragover', (e) => {
        if (!dragId || dragId === row.dataset.id) return;
        e.preventDefault();
        const from = st.favs.findIndex((x) => x.id === dragId);
        const to = st.favs.findIndex((x) => x.id === row.dataset.id);
        const item = st.favs.splice(from, 1)[0];
        st.favs.splice(to, 0, item);
        renderList();
      });
      row.addEventListener('drop', (e) => e.preventDefault());
    }
    const lit = st.on && (!fav || f.on);
    row.classList.toggle('lit', lit);
    row.classList.toggle('current', hostIn(f));
    row.title = t('drag');
    row.querySelector('.row-name').textContent = f.name;
    row.querySelector('.row-meta').textContent = f.domains[0] + (f.domains.length > 1 ? ' +' + (f.domains.length - 1) : '');
    const toggle = row.querySelector('.toggle');
    const locked = !fav;
    toggle.setAttribute('aria-checked', String(locked || f.on));
    toggle.setAttribute('aria-label', locked ? t('locked', f.name) : f.name);
    toggle.setAttribute('aria-disabled', String(locked));
    const wanted = locked ? 'lock' + (st.on ? '-lit' : '') : 'switch';
    if (toggle.dataset.kind !== wanted) {
      toggle.dataset.kind = wanted;
      toggle.innerHTML = locked ? '<span class="lock' + (st.on ? ' lit' : '') + '">' + ICON.lock + '</span>' : '<span class="switch"><i></i></span>';
    }
    if (list.children[index] !== row) list.insertBefore(row, list.children[index] || null);
  });
  for (const [id, el] of rows) if (!keep.has(id)) el.remove();
}

// ------------------------------------------------------------------ actions

async function toggleFav(id) {
  if (st.mode !== 'fav') return;
  await save({ favs: st.favs.map((f) => (f.id === id ? { ...f, on: !f.on } : f)) });
  render();
}

async function removeFav(id) {
  const f = st.favs.find((x) => x.id === id);
  const row = document.querySelector('.row[data-id="' + id + '"]');
  if (row) { row.classList.add('leaving'); await new Promise((r) => setTimeout(r, 200)); }
  await save({ favs: st.favs.filter((x) => x.id !== id) });
  render();
  if (f) toast(t('favRemoved', f.name));
}

function openCtx(id, x, y) {
  menuId = id;
  const f = st.favs.find((v) => v.id === id);
  $('ctxToggle').hidden = st.mode !== 'fav';
  $('ctxToggle').textContent = f.on ? t('turnOff') : t('turnOn');
  const layer = $('ctxLayer');
  layer.hidden = false;
  const menu = $('ctx');
  const w = 210, h = menu.offsetHeight || 170;
  menu.style.left = Math.min(x, document.body.clientWidth - w - 6) + 'px';
  menu.style.top = Math.min(y, document.documentElement.scrollHeight - h - 6) + 'px';
}
function closeCtx() { $('ctxLayer').hidden = true; }

function openSheet(which) {
  for (const id of ['sheetMenu', 'sheetEdit', 'sheetApp']) $(id).hidden = id !== which;
  const layer = $('sheetLayer');
  layer.hidden = false;
  requestAnimationFrame(() => layer.classList.add('open'));
}
function closeSheet() {
  const layer = $('sheetLayer');
  layer.classList.remove('open');
  setTimeout(() => { if (!layer.classList.contains('open')) layer.hidden = true; }, 300);
}

function openMenu(id) {
  menuId = id;
  const f = st.favs.find((v) => v.id === id);
  $('menuTitle').textContent = f.name;
  $('confirmText').textContent = t('confirm', f.name);
  setCollapsed($('confirm'), true);
  $('askDelete').hidden = false;
  openSheet('sheetMenu');
}

function openEdit(id) {
  menuId = id;
  const f = st.favs.find((v) => v.id === id);
  $('edName').value = f.name;
  $('edDomains').value = f.domains.join('\n');
  openSheet('sheetEdit');
  setTimeout(() => $('edName').focus(), 300);
}

async function act(action) {
  closeCtx();
  const f = st.favs.find((v) => v.id === menuId);
  if (!f) return;
  if (action === 'edit') openEdit(f.id);
  if (action === 'toggle') toggleFav(f.id);
  if (action === 'open') chrome.tabs.create({ url: 'https://' + f.domains[0] });
  if (action === 'delete') { openMenu(f.id); $('askDelete').hidden = true; setCollapsed($('confirm'), false); }
}

// ------------------------------------------------------------------ sync

async function refresh() {
  const result = await chrome.runtime.sendMessage({ type: 'sync' }).catch(() => null);
  if (result?.status?.lang && result.status.lang !== lang) { lang = result.status.lang; translate(); }
  if (!result || result.state === 'offline' || result.state === 'error') {
    $('appState').textContent = t('notFound'); $('appState').className = 'app-state bad';
    show('offline');
    return;
  }
  if (result.state === 'key') {
    $('appState').textContent = t('needCode'); $('appState').className = 'app-state bad';
    show('pair');
    return;
  }
  status = result.status;
  const server = status.server;
  $('appState').textContent = server ? [server.name, server.place].filter(Boolean).join(' · ') : t('noServer');
  $('appState').className = 'app-state';
  show('main');
  render();
}

async function loadSite() {
  host = await currentHost();
  site = host ? await api('/site?host=' + encodeURIComponent(host)).catch(() => null) : null;
  if (view === 'main') render();
}

// ------------------------------------------------------------------ events

$('power').addEventListener('click', async () => { await save({ on: !st.on }); render(); refresh(); });
for (const b of document.querySelectorAll('.segments button')) {
  b.addEventListener('click', async () => { await save({ mode: b.dataset.mode }); render(); });
}
$('addFav').addEventListener('click', async () => {
  if (!host) return;
  const existing = st.favs.find(hostIn);
  if (existing) { toast(t('favAlready', existing.name)); return; }
  const f = { id: 'f' + Date.now().toString(36), name: titleCase(host.split('.')[0]), domains: [host], on: true };
  await save({ favs: [f, ...st.favs] });
  render();
  $('list').scrollTop = 0;
  toast(t('favAdded', host));
});
$('addApp').addEventListener('click', () => {
  if (!host) return;
  if (site?.resource) { toast(t('appHas', host)); return; }
  $('appName').value = titleCase(host.split('.')[0]);
  $('appNote').textContent = t('appNote', host);
  const select = $('appSection');
  select.textContent = '';
  for (const s of site?.sections || []) {
    const o = document.createElement('option');
    o.value = s.id; o.textContent = s.name;
    select.append(o);
  }
  if ((site?.sections || []).some((s) => s.id === 'other')) select.value = 'other';
  setCollapsed($('appError'), true);
  openSheet('sheetApp');
});
$('saveApp').addEventListener('click', async () => {
  try {
    const sectionName = $('appSection').selectedOptions[0]?.textContent || '';
    site = await api('/add', { name: $('appName').value, section: $('appSection').value, domain: host });
    closeSheet();
    render();
    toast(t('appAdded', $('appName').value || host, sectionName));
  } catch (e) {
    $('appError').textContent = e.message;
    setCollapsed($('appError'), false);
  }
});
$('saveEdit').addEventListener('click', async () => {
  const domains = [...new Set($('edDomains').value.split('\n').map(cleanDomain).filter((d) => d.includes('.')))];
  if (!domains.length) { $('edDomains').focus(); return; }
  await save({ favs: st.favs.map((f) => (f.id === menuId ? { ...f, name: $('edName').value.trim() || domains[0], domains } : f)) });
  closeSheet();
  render();
  toast(t('saved'));
});
$('askDelete').addEventListener('click', () => { $('askDelete').hidden = true; setCollapsed($('confirm'), false); });
$('cancelDelete').addEventListener('click', () => { setCollapsed($('confirm'), true); $('askDelete').hidden = false; });
$('doDelete').addEventListener('click', () => { closeSheet(); removeFav(menuId); });
document.querySelector('#sheetMenu [data-act="edit"]').addEventListener('click', () => openEdit(menuId));
for (const b of document.querySelectorAll('[data-close]')) b.addEventListener('click', closeSheet);
$('sheetLayer').addEventListener('click', (e) => { if (e.target === $('sheetLayer')) closeSheet(); });
$('ctxLayer').addEventListener('click', (e) => { if (e.target === $('ctxLayer')) closeCtx(); });
$('ctxLayer').addEventListener('contextmenu', (e) => { e.preventDefault(); closeCtx(); });
for (const b of document.querySelectorAll('#ctx button')) b.addEventListener('click', () => act(b.dataset.act));
document.addEventListener('keydown', (e) => { if (e.key === 'Escape') { closeCtx(); closeSheet(); } });

$('retry').addEventListener('click', async () => {
  await refresh();
  if (view === 'offline') { retried = true; $('retry').textContent = t('retryAgain'); }
});
$('pairSave').addEventListener('click', async () => {
  await chrome.storage.local.set({ key: $('key').value.trim().toUpperCase() });
  const result = await chrome.runtime.sendMessage({ type: 'sync' });
  if (result?.state === 'key') { setCollapsed($('pairError'), false); return; }
  setCollapsed($('pairError'), true);
  await refresh();
  await loadSite();
  toast(t('paired'));
});
$('key').addEventListener('keydown', (e) => { if (e.key === 'Enter') $('pairSave').click(); });
$('key').addEventListener('input', () => setCollapsed($('pairError'), true));

(async () => {
  st = await settings();
  translate();
  setCollapsed($('pairError'), true);
  setCollapsed($('confirm'), true);
  setCollapsed($('appError'), true);
  await refresh();
  await loadSite();
  // Пока окно открыто — следим за состоянием приложения.
  setInterval(() => { if ($('sheetLayer').hidden && $('ctxLayer').hidden && !dragId) refresh(); }, 2500);
})();
