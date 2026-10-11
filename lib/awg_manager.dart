import 'dart:async';
import 'dart:io';

import 'awg_config.dart';
import 'l10n.dart';

class TunnelException implements Exception {
  TunnelException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Состояние туннеля по данным `awg show`.
class TunnelStats {
  const TunnelStats({this.lastHandshake, this.received = 0, this.sent = 0});

  final DateTime? lastHandshake;
  final int received;
  final int sent;
}

/// Управляет туннелем AmneziaWG на Windows через официальный клиент:
/// туннель работает как служба Windows, которую клиент ставит по конфигу.
class AwgManager {
  AwgManager(this.dir, {required this.onLog});

  static const _clientVersion = '2.0.1';
  static const _msiUrl =
      'https://github.com/amnezia-vpn/amneziawg-windows-client/releases/download/'
      '$_clientVersion/amneziawg-amd64-$_clientVersion.msi';

  /// Папка приложения, где лежит конфиг туннеля.
  final Directory dir;
  final void Function(String line) onLog;

  String get _installDir {
    final programFiles =
        Platform.environment['ProgramW6432'] ??
        Platform.environment['ProgramFiles'] ??
        r'C:\Program Files';
    return '$programFiles\\AmneziaWG';
  }

  File get _client => File('$_installDir\\amneziawg.exe');
  File get _awg => File('$_installDir\\awg.exe');
  File get _conf => File('${dir.path}\\$tunnelName.conf');

  bool get isInstalled => _client.existsSync() && _awg.existsSync();

  /// Проверяет, что приложение запущено от имени администратора: без этого
  /// нельзя установить службу туннеля.
  static Future<bool> isElevated() async {
    if (!Platform.isWindows) return true;
    try {
      final result = await Process.run('net', ['session']);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  /// Ставит официальный клиент AmneziaWG, если его ещё нет.
  Future<void> ensureInstalled() async {
    if (isInstalled) return;
    await dir.create(recursive: true);
    onLog(tr('Скачиваю клиент AmneziaWG {0} (около 3,5 МБ)…', [_clientVersion]));
    final msi = File('${dir.path}\\amneziawg.msi');
    final http = HttpClient()..connectionTimeout = const Duration(seconds: 20);
    try {
      final request = await http.getUrl(Uri.parse(_msiUrl));
      final response = await request.close();
      if (response.statusCode != 200) {
        throw TunnelException(tr('GitHub ответил кодом {0}', [response.statusCode]));
      }
      await response.pipe(msi.openWrite());
    } on TunnelException {
      rethrow;
    } catch (e) {
      throw TunnelException(
        tr('Не удалось скачать клиент AmneziaWG: {0}\n'
        'Его можно установить вручную: {1}', [e, _msiUrl]),
      );
    } finally {
      http.close(force: true);
    }

    onLog(tr('Устанавливаю клиент AmneziaWG…'));
    final install = await Process.run('msiexec', [
      '/i',
      msi.path,
      '/qn',
      '/norestart',
      'DO_NOT_LAUNCH=1',
    ]);
    // 3010 — установка прошла, но Windows просит перезагрузку.
    if ((install.exitCode != 0 && install.exitCode != 3010) || !isInstalled) {
      throw TunnelException(
        tr('Установка клиента AmneziaWG не удалась (код {0}). '
        'Установите его вручную: {1}', [install.exitCode, _msiUrl]),
      );
    }
    try {
      await msi.delete();
    } catch (_) {}
    onLog(tr('Клиент AmneziaWG установлен.'));
  }

  /// Поднимает туннель с указанным конфигом (прежний при этом снимается).
  Future<void> start(String conf) async {
    await stop();
    await dir.create(recursive: true);
    await _conf.writeAsString(conf);
    final result = await Process.run(
      _client.path,
      ['/installtunnelservice', _conf.path],
    );
    if (result.exitCode != 0) {
      throw TunnelException(
        tr('Служба туннеля не запустилась (код {0}): '
        '{1}', [result.exitCode, '${result.stdout}${result.stderr}'.trim()]),
      );
    }
  }

  /// Снимает туннель. Безопасно вызывать, даже если он не установлен.
  Future<void> stop() async {
    if (!_client.existsSync()) return;
    try {
      await Process.run(_client.path, ['/uninstalltunnelservice', tunnelName]);
    } catch (_) {}
    // Служба удаляется не мгновенно; ждём, пока исчезнет.
    for (var i = 0; i < 20; i++) {
      if (!await isRunning()) break;
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    try {
      if (_conf.existsSync()) await _conf.delete();
    } catch (_) {}
  }

  /// Снимает туннель, оставшийся от сборок с прежним названием приложения.
  Future<void> removeLegacyTunnel() async {
    if (!_client.existsSync()) return;
    try {
      final query = await Process.run(
        'sc',
        ['query', 'AmneziaWGTunnel\$$legacyTunnelName'],
      );
      if (query.exitCode != 0) return;
      await Process.run(
        _client.path,
        ['/uninstalltunnelservice', legacyTunnelName],
      );
    } catch (_) {}
  }

  /// Сколько адресов и диапазонов туннель сейчас согласен пересылать.
  /// null — туннель не поднят.
  Future<int?> allowedIpCount() async {
    try {
      final result =
          await Process.run(_awg.path, ['show', tunnelName, 'allowed-ips']);
      if (result.exitCode != 0) return null;
      final parts = '${result.stdout}'.trim().split(RegExp(r'\s+'));
      // Первое слово — ключ сервера, дальше адреса.
      return parts.length <= 1 ? 0 : parts.length - 1;
    } catch (_) {
      return null;
    }
  }

  /// Существует ли сейчас служба туннеля.
  Future<bool> isRunning() async {
    try {
      final result =
          await Process.run('sc', ['query', 'AmneziaWGTunnel\$$tunnelName']);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  /// Читает время последнего рукопожатия и счётчики трафика.
  /// null — туннель не поднят.
  Future<TunnelStats?> stats() async {
    try {
      // Формат строк: «ключ<TAB>время» и «ключ<TAB>получено<TAB>отправлено».
      final handshakes = await Process.run(
        _awg.path,
        ['show', tunnelName, 'latest-handshakes'],
      );
      if (handshakes.exitCode != 0) return null;
      final transfer =
          await Process.run(_awg.path, ['show', tunnelName, 'transfer']);

      List<String> firstRow(Object? output) {
        final line = '$output'.trim().split('\n').first.trim();
        return line.isEmpty ? const [] : line.split(RegExp(r'\s+'));
      }

      final h = firstRow(handshakes.stdout);
      final t = firstRow(transfer.stdout);
      final seconds = h.length >= 2 ? int.tryParse(h[1]) ?? 0 : 0;
      return TunnelStats(
        lastHandshake: seconds > 0
            ? DateTime.fromMillisecondsSinceEpoch(seconds * 1000)
            : null,
        received: t.length >= 3 ? int.tryParse(t[1]) ?? 0 : 0,
        sent: t.length >= 3 ? int.tryParse(t[2]) ?? 0 : 0,
      );
    } catch (_) {
      return null;
    }
  }

  /// Ждёт первого рукопожатия с сервером.
  Future<bool> waitForHandshake(Duration timeout) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final current = await stats();
      if (current?.lastHandshake != null) return true;
      await Future<void>.delayed(const Duration(milliseconds: 700));
    }
    return false;
  }

  static const _ruleTag = 'SplitVPN';

  /// Делает адаптер туннеля самым приоритетным, чтобы Windows спрашивала
  /// имена в первую очередь у DNS-посредника приложения, и сбрасывает кэш
  /// имён, чтобы программы спросили их заново.
  Future<void> preferTunnelDns() async {
    await Process.run('netsh', [
      'interface', 'ipv4', 'set', 'interface', tunnelName, 'metric=1', //
    ]);
    await Process.run('ipconfig', ['/flushdns']);
  }

  /// Убирает правила разрешения имён (NRPT), которые добавляла одна из
  /// прежних сборок приложения. Сейчас такие правила не создаются.
  static Future<void> clearDomainRules() async {
    if (!Platform.isWindows) return;
    try {
      await Process.run('powershell', [
        '-NoProfile',
        '-Command',
        "Get-DnsClientNrptRule | Where-Object { \$_.Comment -eq '$_ruleTag' } | "
            'Remove-DnsClientNrptRule -Force; Clear-DnsClientCache',
      ]).timeout(const Duration(seconds: 40));
    } catch (_) {}
  }

  /// Назначает адаптеру туннеля DNS-серверы в указанном порядке.
  Future<void> setTunnelDns(List<String> servers) async {
    if (servers.isEmpty) return;
    await Process.run('netsh', [
      'interface', 'ipv4', 'set', 'dnsservers', 'name=$tunnelName', //
      'source=static', 'address=${servers.first}', 'register=none',
      'validate=no',
    ]);
    for (var i = 1; i < servers.length; i++) {
      await Process.run('netsh', [
        'interface', 'ipv4', 'add', 'dnsservers', 'name=$tunnelName', //
        'address=${servers[i]}', 'index=${i + 1}', 'validate=no',
      ]);
    }
    await Process.run('ipconfig', ['/flushdns']);
  }

  /// DNS-серверы системы (IPv4), которыми она пользовалась до туннеля.
  static Future<List<String>> systemDnsServers() async {
    final found = <String>[];
    bool usable(String ip) =>
        RegExp(r'^\d+\.\d+\.\d+\.\d+$').hasMatch(ip) &&
        !ip.startsWith('127.') &&
        !ip.startsWith('169.254.') &&
        !found.contains(ip);
    Future<void> collect(String script) async {
      try {
        final result = await Process.run(
          'powershell',
          ['-NoProfile', '-Command', script],
        ).timeout(const Duration(seconds: 15));
        for (final part in '${result.stdout}'.split(RegExp(r'[\s,]+'))) {
          if (usable(part.trim())) found.add(part.trim());
        }
      } catch (_) {}
    }

    await collect(
      "(Get-DnsClientServerAddress -AddressFamily IPv4 | "
      "Where-Object { \$_.InterfaceAlias -ne '$tunnelName' } | "
      "ForEach-Object { \$_.ServerAddresses }) -join ','",
    );
    if (found.isEmpty) {
      // Часто DNS раздаёт сам роутер — он же шлюз по умолчанию.
      await collect(
        "(Get-NetRoute -DestinationPrefix '0.0.0.0/0' | "
        "Sort-Object RouteMetric | Select-Object -First 1).NextHop",
      );
    }
    if (found.isEmpty) found.addAll(['77.88.8.8', '8.8.8.8']);
    return found;
  }

  /// Направляет в туннель отдельные адреса у уже работающего туннеля.
  ///
  /// [allowedIpsConf] — конфиг для `awg addconf` с полным списком адресов
  /// (туннель должен согласиться их пересылать), [addresses] — новые адреса,
  /// для которых нужно добавить маршруты Windows.
  Future<void> routeAddresses(
    String allowedIpsConf,
    List<String> addresses,
  ) async {
    if (addresses.isEmpty) return;
    final update = File('${dir.path}\\allowed.conf');
    await update.writeAsString(allowedIpsConf);
    await Process.run(_awg.path, ['addconf', tunnelName, update.path]);

    final script = File('${dir.path}\\routes.txt');
    await script.writeAsString([
      for (final ip in addresses)
        'interface ipv4 add route prefix=$ip/32 interface="$tunnelName" '
            'store=active',
      '',
    ].join('\r\n'));
    await Process.run('netsh', ['-f', script.path]);
  }

  /// Последние строки журнала клиента AmneziaWG.
  Future<List<String>> clientLog({int lines = 60}) async {
    if (!_client.existsSync()) {
      return [
        tr('Клиент AmneziaWG ещё не установлен: он ставится при первом нажатии '
            '«Подключить».'),
      ];
    }
    try {
      final result = await Process.run(_client.path, ['/dumplog'])
          .timeout(const Duration(seconds: 10));
      final all = '${result.stdout}'
          .split('\n')
          .map((l) => l.trimRight())
          .where((l) => l.isNotEmpty)
          .toList();
      return all.length > lines ? all.sublist(all.length - lines) : all;
    } catch (e) {
      return [tr('Не удалось прочитать журнал клиента: {0}', [e])];
    }
  }
}
