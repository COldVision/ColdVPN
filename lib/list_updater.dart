import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'models.dart';

/// Обновление списков сервисов прямо из исходных репозиториев: диапазоны IP
/// берутся из RockBlack-VPN/ip-address, домены — из
/// v2fly/domain-list-community. Какие сервисы из чего собираются, описано в
/// assets/selection.json. Логика повторяет tool/build_services.py.
const ipListRepo = 'RockBlack-VPN/ip-address';
const domainListRepo = 'v2fly/domain-list-community';

final _route = RegExp(
  r'route\s+add\s+(\d+\.\d+\.\d+\.\d+)\s+mask\s+(\d+\.\d+\.\d+\.\d+)',
  caseSensitive: false,
);
final _domain = RegExp(r'^(?:[a-z0-9_-]+\.)+[a-z0-9-]{2,}$');

/// Локальные и служебные сети никогда не должны уходить в туннель:
/// пары «начало, конец» диапазона.
final List<List<int>> _reserved = [
  for (final cidr in const [
    '0.0.0.0/8', '10.0.0.0/8', '100.64.0.0/10', '127.0.0.0/8', //
    '169.254.0.0/16', '172.16.0.0/12', '192.168.0.0/16', '224.0.0.0/3',
  ])
    _cidrRange(cidr)!,
];

int? _parseIp(String text) {
  final parts = text.split('.');
  if (parts.length != 4) return null;
  var value = 0;
  for (final part in parts) {
    final n = int.tryParse(part);
    if (n == null || n < 0 || n > 255) return null;
    value = value * 256 + n;
  }
  return value;
}

String _formatIp(int value) => [
      (value >> 24) & 255,
      (value >> 16) & 255,
      (value >> 8) & 255,
      value & 255,
    ].join('.');

List<int>? _cidrRange(String cidr) {
  final slash = cidr.indexOf('/');
  final ip = _parseIp(cidr.substring(0, slash));
  final bits = int.tryParse(cidr.substring(slash + 1));
  if (ip == null || bits == null || bits < 0 || bits > 32) return null;
  final size = 1 << (32 - bits);
  final start = ip - ip % size;
  return [start, start + size - 1];
}

/// Диапазон по адресу и маске вида 255.255.255.0. null — маска некорректна.
List<int>? _maskRange(String address, String mask) {
  final ip = _parseIp(address);
  final m = _parseIp(mask);
  if (ip == null || m == null) return null;
  final inverse = 0xFFFFFFFF - m;
  // У правильной маски единицы идут подряд слева, то есть обратная маска
  // плюс один — степень двойки.
  if ((inverse & (inverse + 1)) != 0) return null;
  final start = ip - ip % (inverse + 1);
  return [start, start + inverse];
}

bool _isReserved(List<int> range) =>
    _reserved.any((r) => range[0] <= r[1] && range[1] >= r[0]);

/// Диапазоны из файла маршрутов (`route add … mask …`).
List<List<int>> parseRouteFile(String text) {
  final result = <List<int>>[];
  for (final line in text.split('\n')) {
    final match = _route.firstMatch(line);
    if (match == null) continue;
    final range = _maskRange(match.group(1)!, match.group(2)!);
    if (range != null && !_isReserved(range)) result.add(range);
  }
  return result;
}

/// Сливает пересекающиеся и соседние диапазоны и записывает результат
/// наименьшим числом блоков CIDR, по возрастанию адресов.
List<String> collapseRanges(List<List<int>> ranges) {
  if (ranges.isEmpty) return const [];
  final sorted = [...ranges]..sort((a, b) => a[0].compareTo(b[0]));
  final merged = <List<int>>[
    [sorted.first[0], sorted.first[1]],
  ];
  for (final range in sorted.skip(1)) {
    final last = merged.last;
    if (range[0] <= last[1] + 1) {
      if (range[1] > last[1]) last[1] = range[1];
    } else {
      merged.add([range[0], range[1]]);
    }
  }
  final result = <String>[];
  for (final range in merged) {
    var start = range[0];
    final end = range[1];
    while (start <= end) {
      // Самый крупный блок, который начинается с этого адреса…
      var size = start == 0 ? 0x100000000 : start & -start;
      // …и не выходит за конец диапазона.
      while (size > end - start + 1) {
        size ~/= 2;
      }
      result.add('${_formatIp(start)}/${33 - size.bitLength}');
      start += size;
    }
  }
  return result;
}

/// Список v2fly вместе с вложенными include. Запись без префикса и с
/// `domain:` или `full:` — домен с поддоменами, `keyword:` — подстрока;
/// `regexp:` и записи с пометкой @ads пропускаются.
void readDomainList(
  Map<String, String> lists,
  String name,
  Set<String> domains,
  Set<String> keywords,
  Set<String> seen,
  List<String> problems,
) {
  if (!seen.add(name)) return;
  final text = lists[name];
  if (text == null) {
    problems.add('нет списка доменов «$name»');
    return;
  }
  for (final raw in text.split('\n')) {
    final line = raw.split('#').first.trim();
    if (line.isEmpty) continue;
    final parts = line.split(RegExp(r'\s+'));
    var entry = parts.first;
    if (entry.startsWith('include:')) {
      readDomainList(
        lists,
        entry.substring('include:'.length),
        domains,
        keywords,
        seen,
        problems,
      );
      continue;
    }
    if (parts.skip(1).contains('@ads') || entry.startsWith('regexp:')) continue;
    if (entry.startsWith('keyword:')) {
      keywords.add(entry.substring('keyword:'.length).toLowerCase());
      continue;
    }
    for (final prefix in const ['domain:', 'full:']) {
      if (entry.startsWith(prefix)) entry = entry.substring(prefix.length);
    }
    entry = entry.toLowerCase().replaceAll(RegExp(r'^\.+|\.+$'), '');
    if (_domain.hasMatch(entry)) domains.add(entry);
  }
}

/// Убирает домены, уже покрытые более коротким доменом из того же набора.
Set<String> minimizeDomains(Set<String> domains) {
  final ordered = domains.toList()
    ..sort((a, b) => '.'.allMatches(a).length - '.'.allMatches(b).length);
  final result = <String>{};
  for (final domain in ordered) {
    final labels = domain.split('.');
    var covered = false;
    for (var i = 1; i < labels.length && !covered; i++) {
      covered = result.contains(labels.sublist(i).join('.'));
    }
    if (!covered) result.add(domain);
  }
  return result;
}

String serviceIdOf(String name) => name
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
    .replaceAll(RegExp(r'^-+|-+$'), '');

/// Собирает сервисы из содержимого двух репозиториев.
///
/// [ipFiles] — файлы ip-address (путь → текст), [domainLists] — списки
/// v2fly (имя → текст). Сервис, для которого ничего не нашлось, в результат
/// не попадает, а причина дописывается в [problems].
List<ServiceEntry> buildServices(
  Map<String, dynamic> selection,
  Map<String, String> ipFiles,
  Map<String, String> domainLists,
  List<String> problems,
) {
  final exclude =
      (selection['exclude_files'] as List? ?? const []).cast<String>().toSet();
  final result = <ServiceEntry>[];
  for (final raw in selection['services'] as List) {
    final item = raw as Map<String, dynamic>;
    final name = item['name'] as String;

    final ranges = <List<int>>[];
    for (final source in (item['from'] as List? ?? const []).cast<String>()) {
      final paths = ipFiles.keys
          .where((p) => p == source || p.startsWith('$source/'))
          .where((p) => !exclude.contains(p))
          .toList();
      if (paths.isEmpty) {
        problems.add('$name: в репозитории больше нет «$source»');
        continue;
      }
      for (final path in paths) {
        ranges.addAll(parseRouteFile(ipFiles[path]!));
      }
    }

    final domains = {
      for (final d in (item['domains'] as List? ?? const []).cast<String>())
        d.toLowerCase(),
    };
    final keywords = <String>{};
    for (final list in (item['v2fly'] as List? ?? const []).cast<String>()) {
      readDomainList(domainLists, list, domains, keywords, {}, problems);
    }

    if (ranges.isEmpty && domains.isEmpty) {
      problems.add('$name: не найдено ни адресов, ни доменов');
      continue;
    }
    result.add(ServiceEntry(
      id: serviceIdOf(name),
      name: name,
      ips: collapseRanges(ranges),
      domains: minimizeDomains(domains).toList()..sort(),
      keywords: keywords.toList()..sort(),
    ));
  }
  return result;
}

/// Скачивает репозиторий архивом и возвращает его текстовые файлы
/// (путь внутри репозитория → текст). [keep] отбирает нужные пути.
Future<Map<String, String>> _downloadRepo(
  String repo,
  bool Function(String path) keep,
) async {
  final http = HttpClient()..connectionTimeout = const Duration(seconds: 15);
  try {
    final request = await http
        .getUrl(Uri.parse('https://github.com/$repo/archive/HEAD.zip'));
    final response = await request.close().timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      throw 'GitHub ответил кодом ${response.statusCode} для $repo';
    }
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in response.timeout(const Duration(seconds: 30))) {
      bytes.add(chunk);
      if (bytes.length > 60 * 1024 * 1024) {
        throw 'архив $repo неожиданно большой';
      }
    }
    final archive = ZipDecoder().decodeBytes(bytes.takeBytes());
    final files = <String, String>{};
    for (final file in archive.files) {
      if (!file.isFile) continue;
      // Первая папка в архиве — «имя-ветка», она не часть пути.
      final slash = file.name.indexOf('/');
      if (slash < 0) continue;
      final path = file.name.substring(slash + 1);
      if (!keep(path)) continue;
      var text = utf8.decode(
        Uint8List.fromList(file.content as List<int>),
        allowMalformed: true,
      );
      if (text.startsWith('\uFEFF')) text = text.substring(1);
      files[path] = text.replaceAll('\r', '');
    }
    return files;
  } finally {
    http.close(force: true);
  }
}

class ListUpdate {
  const ListUpdate(this.services, this.problems);

  final List<ServiceEntry> services;
  final List<String> problems;
}

/// Скачивает оба репозитория и собирает из них сервисы по [selection].
Future<ListUpdate> downloadServices(Map<String, dynamic> selection) async {
  final ipFiles = await _downloadRepo(ipListRepo, (path) => true);
  final dataFiles =
      await _downloadRepo(domainListRepo, (path) => path.startsWith('data/'));
  final domainLists = {
    for (final entry in dataFiles.entries)
      entry.key.substring('data/'.length): entry.value,
  };
  final problems = <String>[];
  final services = buildServices(selection, ipFiles, domainLists, problems);
  return ListUpdate(services, problems);
}
