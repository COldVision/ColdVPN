import 'dart:convert';
import 'dart:io';

import 'server_installer.dart';
import 'l10n.dart';

/// Хранилище данных для входа на серверы (пароль или SSH-ключ).
///
/// Файл шифруется средствами Windows (DPAPI) под текущего пользователя:
/// прочитать его можно только на этом компьютере и только под этой учётной
/// записью. Сам пароль в командную строку не попадает — он передаётся
/// вспомогательному процессу через стандартный ввод.
class SecretStore {
  SecretStore(this.file);

  final File file;

  static bool get supported => Platform.isWindows;

  static const _prelude = r"$ErrorActionPreference='Stop'; "
      'Add-Type -AssemblyName System.Security; '
      r'$d=[Convert]::FromBase64String([Console]::In.ReadToEnd().Trim()); '
      r'$s=[Security.Cryptography.DataProtectionScope]::CurrentUser; ';

  /// Шифрует или расшифровывает данные. На входе и на выходе — base64.
  static Future<String> _dpapi(String action, String input) async {
    final process = await Process.start('powershell', [
      '-NoProfile',
      '-NonInteractive',
      '-Command',
      '$_prelude'
          '\$r=[Security.Cryptography.ProtectedData]::$action(\$d,\$null,\$s); '
          '[Console]::Out.Write([Convert]::ToBase64String(\$r))',
    ]);
    process.stdin.write(input);
    await process.stdin.close();
    final output = process.stdout.transform(ascii.decoder).join();
    final errors = process.stderr.transform(systemEncoding.decoder).join();
    final code = await process.exitCode.timeout(const Duration(seconds: 30));
    final text = (await output).trim();
    if (code != 0 || text.isEmpty) {
      throw tr('защита данных Windows вернула ошибку: {0}', [(await errors).trim()]);
    }
    return text;
  }

  /// Сохранённые данные для входа: адрес сервера → данные. Если файла нет
  /// или его не удалось расшифровать, возвращается пустой набор.
  Future<Map<String, InstallRequest>> load() async {
    final result = <String, InstallRequest>{};
    if (!supported || !file.existsSync()) return result;
    try {
      final plain = await _dpapi('Unprotect', (await file.readAsString()).trim());
      final json = jsonDecode(utf8.decode(base64.decode(plain)));
      for (final item in json as List) {
        final map = item as Map<String, dynamic>;
        final request = InstallRequest(
          host: map['host'] as String,
          sshPort: map['sshPort'] as int? ?? 22,
          username: map['username'] as String? ?? 'root',
          password: map['password'] as String?,
          privateKeyPem: map['privateKeyPem'] as String?,
        );
        result[request.host] = request;
      }
    } catch (_) {
      // Файл от другой учётной записи или повреждён: данные придётся ввести
      // заново.
    }
    return result;
  }

  /// Записывает данные для входа; пустой набор удаляет файл.
  Future<void> save(Map<String, InstallRequest> credentials) async {
    if (!supported) return;
    if (credentials.isEmpty) {
      if (file.existsSync()) await file.delete();
      return;
    }
    final json = jsonEncode([
      for (final r in credentials.values)
        {
          'host': r.host,
          'sshPort': r.sshPort,
          'username': r.username,
          'password': r.password,
          'privateKeyPem': r.privateKeyPem,
        },
    ]);
    final sealed = await _dpapi('Protect', base64.encode(utf8.encode(json)));
    await file.parent.create(recursive: true);
    await file.writeAsString(sealed);
  }
}
