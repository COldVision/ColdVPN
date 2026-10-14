import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'app_state.dart';
import 'dns_proxy.dart' show DomainMatcher;
import 'l10n.dart';
import 'route_input.dart';
import 'ui/settings_tab.dart' show appVersion;

/// Связь с расширением для браузера: маленький HTTP-сервер на 127.0.0.1.
///
/// Каждый запрос, кроме `/api/hello`, должен нести код из настроек
/// приложения в заголовке `X-ColdVPN-Key` — иначе управлять VPN могла бы
/// любая программа или страница на компьютере.
class BrowserApi {
  BrowserApi(this.state);

  static const port = 47321;

  final AppState state;
  HttpServer? _server;

  Future<void> start() async {
    try {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
      _server = server;
      server.listen((request) => unawaited(_handle(request)));
    } catch (e) {
      state.addLog(tr('Связь с расширением браузера недоступна (порт {0} '
          'занят): {1}', [port, e]));
    }
  }

  Future<void> stop() async => _server?.close(force: true);

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    try {
      // Запросы с чужих страниц, подставивших адрес 127.0.0.1 под своё
      // имя, отсекаются по заголовку Host.
      final host = request.headers.host ?? '';
      if (host != '127.0.0.1' && host != 'localhost') {
        return _reply(response, 403, {'error': 'host'});
      }
      // Ответы читает только расширение (его адрес chrome-extension://…).
      final origin = request.headers.value('origin') ?? '';
      if (origin.startsWith('chrome-extension://')) {
        response.headers
          ..set('Access-Control-Allow-Origin', origin)
          ..set('Access-Control-Allow-Headers', 'Content-Type, X-ColdVPN-Key')
          ..set('Access-Control-Allow-Methods', 'GET, POST');
      }
      if (request.method == 'OPTIONS') {
        response.statusCode = 204;
        return response.close();
      }
      final path = request.uri.path;
      if (path == '/api/hello') {
        return _reply(response, 200, {'app': 'ColdVPN', 'version': appVersion});
      }
      if (request.headers.value('x-coldvpn-key') != state.browserKey) {
        return _reply(response, 401, {'error': 'key'});
      }
      final body = request.method == 'POST'
          ? jsonDecode(await utf8.decoder.bind(request).join()) as Map
          : const {};
      switch ('${request.method} $path') {
        case 'GET /api/status':
          return _reply(response, 200, _status());
        case 'GET /api/domains':
          return _reply(response, 200, {'domains': state.browserDomains});
        case 'GET /api/site':
          return _reply(response, 200, _site(request.uri.queryParameters['host'] ?? ''));
        case 'POST /api/browser':
          state.browserRequest('${body['client']}', body['on'] == true);
          return _reply(response, 200, _status());
        case 'POST /api/toggle':
          state.toggleService('${body['id']}', body['on'] == true);
          return _reply(response, 200, {'ok': true});
        case 'POST /api/add':
          final domain = '${body['domain']}'.trim();
          final lines = parseRouteText(domain);
          if (domain.isEmpty || !lines.any((l) => l.accepted)) {
            return _reply(response, 400, {'error': tr('Это не похоже на домен.')});
          }
          final name = '${body['name']}'.trim();
          final wanted = '${body['section']}';
          final section = state.sections.any((s) => s.id == wanted)
              ? wanted
              : state.sections.isNotEmpty
                  ? state.sections.first.id
                  : state.saveSection(name: tr('Прочее'), icon: 'globe');
          state.saveResource(
            name: name.isEmpty ? domain : name,
            section: section,
            lines: lines,
            enable: true,
          );
          return _reply(response, 200, _site(domain));
      }
      return _reply(response, 404, {'error': 'unknown'});
    } catch (e) {
      return _reply(response, 500, {'error': '$e'});
    }
  }

  Map<String, Object?> _status() {
    final domains = state.browserDomains;
    final server = state.current;
    return {
      'lang': appLang,
      'browser': state.browserStatus.name,
      'error': state.browserError,
      'system': state.status.name,
      'all': state.settings.fullTunnel,
      'proxyPort': AppState.browserProxyPort,
      // Расширение перекачивает список доменов только когда он изменился.
      'domainsRev': '${domains.length}:${Object.hashAll(domains)}',
      'server': server == null
          ? null
          : {'name': server.name, 'place': server.place},
    };
  }

  /// Ресурс, в списке которого есть сайт [host], и разделы для добавления.
  Map<String, Object?> _site(String host) {
    final name = host.toLowerCase().replaceFirst(RegExp(r'^www\.'), '');
    Map<String, Object?>? found;
    for (final s in state.services) {
      if (!DomainMatcher(s.domains, s.keywords).matches(name)) continue;
      found = {
        'id': s.id,
        'name': s.name,
        'section': state.sectionOf(s.id)?.title ?? '',
        'on': state.enabled.contains(s.id),
      };
      break;
    }
    return {
      'host': name,
      'resource': found,
      'sections': [
        for (final s in state.sections) {'id': s.id, 'name': s.title},
      ],
    };
  }

  Future<void> _reply(HttpResponse response, int code, Object body) async {
    response
      ..statusCode = code
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(body));
    await response.close();
  }
}
