import 'package:flutter/services.dart';

import 'awg_manager.dart' show TunnelStats;

/// Приложение, установленное на телефоне.
class AndroidApp {
  const AndroidApp(this.package, this.label);

  final String package;
  final String label;
}

/// Туннель AmneziaWG на Android. Сама работа идёт в Kotlin
/// (android/…/MainActivity.kt) через библиотеку amneziawg-android; здесь —
/// только вызовы.
class AndroidTunnel {
  static const _channel = MethodChannel('coldvpn/tunnel');

  /// Спрашивает у пользователя разрешение создавать VPN-подключение, если
  /// оно ещё не выдано. false — пользователь отказал.
  static Future<bool> prepare() async =>
      await _channel.invokeMethod<bool>('prepare') ?? false;

  /// Поднимает туннель с указанным конфигом (прежний при этом снимается).
  static Future<void> start(String conf) =>
      _channel.invokeMethod<void>('start', {'conf': conf});

  static Future<void> stop() => _channel.invokeMethod<void>('stop');

  static Future<bool> isUp() async {
    try {
      return await _channel.invokeMethod<bool>('isUp') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Время последнего рукопожатия и счётчики трафика; null — туннель не поднят.
  static Future<TunnelStats?> stats() async {
    try {
      final map = await _channel.invokeMapMethod<String, dynamic>('stats');
      if (map == null) return null;
      final handshake = (map['handshake'] as num?)?.toInt() ?? 0;
      return TunnelStats(
        lastHandshake: handshake > 0
            ? DateTime.fromMillisecondsSinceEpoch(handshake)
            : null,
        received: (map['rx'] as num?)?.toInt() ?? 0,
        sent: (map['tx'] as num?)?.toInt() ?? 0,
      );
    } catch (_) {
      return null;
    }
  }

  /// Приложения, у которых есть значок на рабочем столе, по алфавиту.
  static Future<List<AndroidApp>> apps() async {
    final list = await _channel.invokeListMethod<dynamic>('apps') ?? const [];
    return [
      for (final item in list)
        if (item is Map)
          AndroidApp('${item['package']}', '${item['label']}'),
    ];
  }

  /// Открывает ссылку в браузере телефона. false — открыть нечем.
  static Future<bool> openUrl(String url) async {
    try {
      return await _channel.invokeMethod<bool>('openUrl', {'url': url}) ??
          false;
    } catch (_) {
      return false;
    }
  }
}
