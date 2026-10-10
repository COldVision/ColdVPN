import 'dart:async';
import 'dart:convert';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'models.dart';

/// Что пользователь ввёл на экране настройки сервера.
class InstallRequest {
  const InstallRequest({
    required this.host,
    required this.sshPort,
    required this.username,
    this.password,
    this.privateKeyPem,
    this.vpnPort = 0,
    this.device = 'windows',
    this.resetKeys = false,
  });

  final String host;
  final int sshPort;
  final String username;
  final String? password;
  final String? privateKeyPem;

  /// UDP-порт AmneziaWG; 0 — сервер выберет сам и запомнит.
  final int vpnPort;

  /// Имя устройства: у каждого свой ключ и адрес в туннеле.
  final String device;
  final bool resetKeys;
}

class InstallException implements Exception {
  InstallException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Заходит на сервер по SSH и выполняет там скрипт из ресурсов приложения.
/// Каждая строка вывода передаётся в [onLine].
Future<void> _runRemoteScript(
  InstallRequest request,
  String asset,
  String env,
  void Function(String line) status,
  void Function(String line) onLine,
) async {
  // Скрипт обязан уйти на сервер с переводами строк Unix.
  final script = (await rootBundle.loadString(asset)).replaceAll('\r', '');
  final encoded = base64.encode(utf8.encode(script));

  status('Подключаюсь к ${request.host}:${request.sshPort}…');
  final SSHSocket socket;
  try {
    socket = await SSHSocket.connect(
      request.host,
      request.sshPort,
      timeout: const Duration(seconds: 15),
    );
  } catch (e) {
    throw InstallException(
      'Сервер не отвечает по SSH (${request.host}:${request.sshPort}): $e',
    );
  }

  List<SSHKeyPair>? identities;
  final pem = request.privateKeyPem?.trim() ?? '';
  if (pem.isNotEmpty) {
    try {
      identities = SSHKeyPair.fromPem(pem);
    } catch (e) {
      socket.close();
      throw InstallException('Не удалось прочитать SSH-ключ: $e');
    }
  }
  final password = request.password ?? '';

  final client = SSHClient(
    socket,
    username: request.username,
    identities: identities,
    onPasswordRequest: password.isEmpty ? null : () => password,
    onUserInfoRequest: password.isEmpty
        ? null
        : (info) => [for (final _ in info.prompts) password],
  );

  try {
    try {
      await client.authenticated;
    } catch (e) {
      throw InstallException('Сервер не принял логин или пароль: $e');
    }
    status('Вход выполнен.');

    // Скрипт сначала сохраняется во временный файл и запускается из него.
    // Если отдать его bash через stdin, любая команда внутри, читающая
    // stdin (например, docker run -i), «съест» остаток скрипта.
    final runner =
        request.username == 'root' ? 'env $env bash' : 'sudo -n env $env bash';
    final session = await client.execute(
      'F=\$(mktemp /tmp/svpn.XXXXXX) && echo $encoded | base64 -d > "\$F" && '
      '{ $runner "\$F" </dev/null 2>&1; R=\$?; rm -f "\$F"; exit \$R; }',
    );

    final lines = session.stdout
        .cast<List<int>>()
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter());
    await for (final line in lines) {
      onLine(line);
    }
    await session.done;
  } finally {
    client.close();
  }
}

/// Ставит AmneziaWG на сервер и возвращает данные подключения.
///
/// Пароль и ключ здесь используются только для работы по SSH; хранением
/// занимается SecretStore.
Future<ServerProfile> installServer(
  InstallRequest request,
  void Function(String line) log, {
  void Function(String line, {required bool problem})? important,
}) async {
  final result = <String, String>{};
  String? error;
  var done = false;

  final env = 'SVPN_PORT=${request.vpnPort} SVPN_DEVICE=${request.device} '
      'SVPN_RESET=${request.resetKeys ? 1 : 0}';
  await _runRemoteScript(request, 'assets/install_awg.sh', env, log, (line) {
    if (line.startsWith('SVPN_RESULT ')) {
      final pair = line.substring('SVPN_RESULT '.length);
      final eq = pair.indexOf('=');
      if (eq > 0) result[pair.substring(0, eq)] = pair.substring(eq + 1);
    } else if (line.startsWith('SVPN_ERROR: ')) {
      error = line.substring('SVPN_ERROR: '.length);
      log('Ошибка: $error');
    } else if (line.startsWith('SVPN_WARN: ')) {
      final text = 'Внимание: ${line.substring('SVPN_WARN: '.length)}';
      log(text);
      important?.call(text, problem: true);
    } else if (line.startsWith('SVPN_SELFTEST ')) {
      final ok = line.startsWith('SVPN_SELFTEST ok');
      final detail = line
          .substring(ok ? 'SVPN_SELFTEST ok'.length : 'SVPN_SELFTEST fail'.length)
          .trim();
      final text = ok
          ? 'Самопроверка на сервере пройдена $detail.'
          : 'Самопроверка на сервере НЕ пройдена $detail.';
      log(text);
      important?.call(text, problem: !ok);
    } else if (line == 'SVPN_DONE') {
      done = true;
    } else if (line.trim().isNotEmpty) {
      log(line);
    }
  });

  if (error != null) throw InstallException(error!);
  if (!done) {
    throw InstallException(
      request.username == 'root'
          ? 'Установка прервалась, подробности в журнале выше.'
          : 'Установка прервалась. Пользователю ${request.username} нужен '
              'sudo без пароля — проще всего войти под root.',
    );
  }

  const names = {
    'jc': 'Jc', 'jmin': 'Jmin', 'jmax': 'Jmax', 's1': 'S1', 's2': 'S2', //
    'h1': 'H1', 'h2': 'H2', 'h3': 'H3', 'h4': 'H4',
  };
  final profile = ServerProfile(
    host: request.host,
    port: int.tryParse(result['port'] ?? '') ?? 0,
    serverPublicKey: result['server_public_key'] ?? '',
    clientPrivateKey: result['client_private_key'] ?? '',
    presharedKey: result['preshared_key'] ?? '',
    clientAddress: result['client_address'] ?? '',
    obfuscation: {
      for (final entry in names.entries)
        if ((result[entry.key] ?? '').isNotEmpty) entry.value: result[entry.key]!,
    },
  );
  if (profile.port == 0 ||
      profile.serverPublicKey.isEmpty ||
      profile.clientPrivateKey.isEmpty ||
      profile.clientAddress.isEmpty) {
    throw InstallException('Сервер не вернул данные подключения.');
  }
  log('Готово: AmneziaWG установлен и запущен.');
  return profile;
}

/// Собирает с сервера диагностику: состояние AmneziaWG и исходящие соединения.
/// На сервере ничего не меняет.
Future<List<String>> diagnoseServer(InstallRequest request) async {
  final lines = <String>[];
  await _runRemoteScript(
    request,
    'assets/diagnose.sh',
    'SVPN_DIAG=1',
    (_) {},
    (line) {
      if (line != 'SVPN_DONE') lines.add(line);
    },
  );
  return lines;
}
