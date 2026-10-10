#!/usr/bin/env python3
"""Собирает assets/services.json.

IP-диапазоны берутся из репозитория RockBlack-VPN/ip-address, домены — из
v2fly/domain-list-community. Какие сервисы попадают в приложение и из чего
они собираются, описано в assets/selection.json.

Запуск:
  python3 tool/build_services.py <клон ip-address> <клон domain-list-community> assets/services.json
"""
import ipaddress, json, re, sys
from pathlib import Path

ROUTE = re.compile(r'route\s+add\s+(\d+\.\d+\.\d+\.\d+)\s+mask\s+(\d+\.\d+\.\d+\.\d+)', re.I)
# Локальные и служебные сети никогда не должны уходить в туннель.
RESERVED = [ipaddress.ip_network(x) for x in (
    '0.0.0.0/8', '10.0.0.0/8', '100.64.0.0/10', '127.0.0.0/8', '169.254.0.0/16',
    '172.16.0.0/12', '192.168.0.0/16', '224.0.0.0/3')]
DOMAIN = re.compile(r'^(?:[a-z0-9_-]+\.)+[a-z0-9-]{2,}$', re.I)


def parse(path):
    nets, doms = [], []
    for line in path.read_text(encoding='utf-8-sig', errors='replace').splitlines():
        m = ROUTE.search(line)
        if m:
            try:
                net = ipaddress.ip_network(f'{m[1]}/{m[2]}', strict=False)
                if not any(net.overlaps(r) for r in RESERVED):
                    nets.append(net)
            except ValueError:
                pass
            continue
        s = line.split('#')[0].strip().lower().lstrip('.')
        if s and DOMAIN.match(s):
            doms.append(s)
    return nets, doms


def read_v2fly(data_dir, name, seen=None):
    """Читает список v2fly вместе с вложенными include.

    Возвращает (домены, ключевые слова). Запись без префикса и `domain:` —
    домен со всеми поддоменами; `full:` — точное имя (здесь тоже трактуется
    как домен с поддоменами); `keyword:` — подстрока. `regexp:` и записи с
    пометкой @ads пропускаются.
    """
    seen = seen if seen is not None else set()
    if name in seen:
        return set(), set()
    seen.add(name)
    path = Path(data_dir) / name
    if not path.is_file():
        sys.exit(f'нет списка v2fly: {name}')
    domains, keywords = set(), set()
    for raw in path.read_text(encoding='utf-8').splitlines():
        line = raw.split('#')[0].strip()
        if not line:
            continue
        parts = line.split()
        entry, attrs = parts[0], parts[1:]
        if entry.startswith('include:'):
            d, k = read_v2fly(data_dir, entry[len('include:'):], seen)
            domains |= d; keywords |= k
            continue
        if '@ads' in attrs or entry.startswith('regexp:'):
            continue
        if entry.startswith('keyword:'):
            keywords.add(entry[len('keyword:'):].lower())
            continue
        for prefix in ('domain:', 'full:'):
            if entry.startswith(prefix):
                entry = entry[len(prefix):]
        entry = entry.lower().strip('.')
        if DOMAIN.match(entry):
            domains.add(entry)
    return domains, keywords


def minimize(domains):
    """Убирает домены, уже покрытые более коротким доменом из того же списка."""
    result = set()
    for d in sorted(domains, key=lambda x: x.count('.')):
        labels = d.split('.')
        if not any('.'.join(labels[i:]) in result for i in range(1, len(labels))):
            result.add(d)
    return result


def main(src, v2fly, out):
    root = Path(src)
    sel = json.loads((Path(__file__).parent.parent / 'assets' / 'selection.json').read_text(encoding='utf-8'))
    exclude = set(sel.get('exclude_files', []))
    result = []
    for item in sel['services']:
        nets, sources = set(), []
        for src_path in item['from']:
            p = root / src_path
            if not p.exists():
                sys.exit(f'нет в репозитории: {src_path}')
            files = [p] if p.is_file() else sorted(f for f in p.rglob('*') if f.is_file())
            for f in files:
                rel = f.relative_to(root).as_posix()
                if rel in exclude:
                    continue
                n, _ = parse(f)
                nets.update(n); sources.append(rel)
        doms = {d.lower() for d in item.get('domains', [])}
        keywords = set()
        for name in item.get('v2fly', []):
            d, k = read_v2fly(Path(v2fly) / 'data', name)
            doms |= d; keywords |= k
            sources.append(f'v2fly:{name}')
        doms = minimize(doms)
        if not nets and not doms:
            sys.exit(f'пустой сервис: {item["name"]}')
        result.append({
            'id': re.sub(r'[^a-z0-9]+', '-', item['name'].lower()).strip('-'),
            'name': item['name'],
            'domains': sorted(doms),
            'keywords': sorted(keywords),
            'ips': [str(n) for n in ipaddress.collapse_addresses(nets)],
            'sources': sources,
        })
    Path(out).write_text(json.dumps({'source': ['https://github.com/RockBlack-VPN/ip-address',
                                                'https://github.com/v2fly/domain-list-community'],
                                     'services': result}, ensure_ascii=False, indent=1), encoding='utf-8')
    return result


if __name__ == '__main__':
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    for s in main(sys.argv[1], sys.argv[2], sys.argv[3]):
        print(f"{s['name']:22} ip:{len(s['ips']):5}  домены:{len(s['domains']):4}  ключевые слова:{len(s['keywords'])}")
