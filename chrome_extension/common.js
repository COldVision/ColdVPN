// Shared by the background worker and the popup.
const API = 'http://127.0.0.1:47321/api';

async function api(path, body) {
  const { key = '' } = await chrome.storage.local.get('key');
  let response;
  try {
    response = await fetch(API + path, {
      method: body ? 'POST' : 'GET',
      headers: { 'Content-Type': 'application/json', 'X-ColdVPN-Key': key },
      body: body ? JSON.stringify(body) : undefined,
    });
  } catch (e) {
    const error = new Error('offline');
    error.code = 'offline';
    throw error;
  }
  if (response.status === 401) {
    const error = new Error('key');
    error.code = 'key';
    throw error;
  }
  const data = await response.json().catch(() => ({}));
  if (!response.ok) throw new Error(data.error || String(response.status));
  return data;
}

async function clientId() {
  let { client } = await chrome.storage.local.get('client');
  if (!client) {
    client = crypto.randomUUID();
    await chrome.storage.local.set({ client });
  }
  return client;
}

// Extension settings: on/off, mode ('all' | 'fav') and the favourites.
async function settings() {
  const { on = false, mode = 'fav', favs = [] } = await chrome.storage.local.get(['on', 'mode', 'favs']);
  return { on, mode, favs };
}

// Domains that go through the VPN in favourites mode.
function favDomains(favs) {
  const set = new Set();
  for (const f of favs) if (f.on) for (const d of f.domains) set.add(d);
  return [...set].sort();
}

// PAC script: chosen domains (or every site in "all" mode) go to the app's
// SOCKS5 proxy, everything else goes directly. Local addresses never do.
function pacScript(domains, port, all) {
  const map = {};
  for (const d of domains) map[d] = 1;
  return 'var D=' + JSON.stringify(map) + ',A=' + (all ? 'true' : 'false') +
    ',P="SOCKS5 127.0.0.1:' + port + '";\n' +
    'function FindProxyForURL(u,h){h=h.toLowerCase();' +
    'if(isPlainHostName(h)||h==="localhost"||/^(127\\.|10\\.|192\\.168\\.|169\\.254\\.)/.test(h)' +
    '||/^172\\.(1[6-9]|2\\d|3[01])\\./.test(h))return "DIRECT";' +
    'if(A)return P;' +
    'for(var x=h;;){if(Object.prototype.hasOwnProperty.call(D,x))return P;' +
    'var i=x.indexOf(".");if(i<0)return "DIRECT";x=x.substring(i+1);}}';
}

// "https://www.youtube.com/watch" or "WWW.YouTube.com" -> "youtube.com".
function cleanDomain(text) {
  return String(text).trim().toLowerCase()
    .replace(/^[a-z][a-z0-9+.-]*:\/\//, '')
    .replace(/[/?#:].*$/, '')
    .replace(/^\*\./, '')
    .replace(/^www\./, '')
    .replace(/\.$/, '');
}
