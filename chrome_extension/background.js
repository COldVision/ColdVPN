importScripts('common.js');

// Signature of what is in the browser proxy settings now; 'none' — nothing of ours.
let applied = null;

async function current() {
  if (applied === null) {
    const { applied: saved } = await chrome.storage.session.get('applied');
    applied = saved ?? 'none';
  }
  return applied;
}

async function remember(value) {
  applied = value;
  await chrome.storage.session.set({ applied: value });
}

async function clearProxy() {
  if ((await current()) === 'none') return;
  await chrome.proxy.settings.clear({ scope: 'regular' });
  await remember('none');
}

async function applyProxy(mode, favs, port) {
  const all = mode === 'all';
  const domains = all ? [] : favDomains(favs);
  const signature = JSON.stringify([all, port, domains]);
  if ((await current()) === signature) return;
  if (!all && domains.length === 0) {
    await clearProxy();
    return;
  }
  await chrome.proxy.settings.set({
    value: { mode: 'pac_script', pacScript: { data: pacScript(domains, port, all) } },
    scope: 'regular',
  });
  await remember(signature);
}

function badge(text, color) {
  chrome.action.setBadgeText({ text });
  if (color) chrome.action.setBadgeBackgroundColor({ color });
}

// Tells the app whether this browser wants the VPN (it also serves as a
// heartbeat: a closed browser stops asking and the app turns its VPN off)
// and brings the proxy settings in line with the answer.
let running = null;
function sync() {
  running = (running || Promise.resolve()).then(syncNow, syncNow);
  return running;
}

async function syncNow() {
  const { on, mode, favs } = await settings();
  let status;
  try {
    status = await api('/browser', { client: await clientId(), on });
  } catch (e) {
    await clearProxy();
    badge(on ? '!' : '', '#c0303c');
    return { state: e.code === 'key' ? 'key' : 'offline' };
  }
  if (on && status.browser === 'on') {
    await applyProxy(mode, favs, status.proxyPort);
    badge('ON', '#1f9f90');
  } else {
    await clearProxy();
    badge(on ? '…' : '', '#6366f1');
  }
  return { state: 'ok', status };
}

chrome.runtime.onInstalled.addListener(() => {
  chrome.alarms.create('sync', { periodInMinutes: 0.5 });
  sync();
});
chrome.runtime.onStartup.addListener(() => {
  chrome.alarms.create('sync', { periodInMinutes: 0.5 });
  sync();
});
chrome.alarms.onAlarm.addListener(() => sync());
chrome.storage.onChanged.addListener((changes, area) => {
  if (area === 'local' && (changes.on || changes.mode || changes.favs || changes.key)) sync();
});
chrome.runtime.onMessage.addListener((message, _sender, reply) => {
  if (message?.type === 'sync') {
    sync().then(reply, (e) => reply({ state: 'error', error: String(e) }));
    return true;
  }
  return false;
});
chrome.proxy.onProxyError.addListener((details) => console.warn('ColdVPN proxy:', details.error));
