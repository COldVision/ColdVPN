import 'l10n.dart';

/// Разбор того, что пользователь ввёл на экране «Свой маршрут».
enum RouteLineKind { domain, network, address, duplicate, error }

class RouteLine {
  const RouteLine(this.kind, this.value, this.note);

  final RouteLineKind kind;

  /// Приведённое значение: домен без схемы и пути, адрес или диапазон.
  final String value;
  final String note;

  bool get accepted =>
      kind == RouteLineKind.domain ||
      kind == RouteLineKind.network ||
      kind == RouteLineKind.address;
}

final _scheme = RegExp(r'^[a-z][a-z0-9+.-]*://');
final _ipv4 =
    RegExp(r'^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})(?:/(\d{1,2}))?$');
final _ipv6Like = RegExp(r'^[0-9a-f:./]+$');
final _domain = RegExp(
  r'^([a-z0-9а-яё]([a-z0-9а-яё-]{0,61}[a-z0-9а-яё])?\.)+[a-zа-яё][a-z0-9а-яё-]+$',
);

/// Разбирает одну строку: домен, адрес, диапазон или ошибка.
RouteLine parseRouteLine(String raw) {
  final source = raw.trim();
  var v = source.toLowerCase();
  var fromLink = false;
  if (_scheme.hasMatch(v)) {
    v = v.replaceFirst(_scheme, '');
    fromLink = true;
  }

  final ip = _ipv4.firstMatch(v);
  if (ip != null) {
    final octets = [for (var i = 1; i <= 4; i++) int.parse(ip.group(i)!)];
    if (octets.any((o) => o > 255)) {
      return RouteLine(RouteLineKind.error, source,
          tr('пропущено: число в адресе больше 255'));
    }
    final address = octets.join('.');
    final mask = ip.group(5);
    if (mask == null || mask == '32') {
      return RouteLine(RouteLineKind.address, address, tr('один адрес'));
    }
    final bits = int.parse(mask);
    if (bits > 32) {
      return RouteLine(RouteLineKind.error, source,
          tr('пропущено: маска должна быть от 0 до 32'));
    }
    if (bits < 5) {
      return RouteLine(RouteLineKind.error, source,
          tr('пропущено: слишком широкий диапазон, минимум /5'));
    }
    return RouteLine(
        RouteLineKind.network, '$address/$bits', tr('{0} адресов', [1 << (32 - bits)]));
  }

  if (v.split(':').length > 2 && _ipv6Like.hasMatch(v)) {
    return RouteLine(
        RouteLineKind.error, source, tr('пропущено: IPv6 пока не поддерживается'));
  }

  final hadPath = v.contains(RegExp(r'[/?#]'));
  v = v
      .split(RegExp(r'[/?#]'))
      .first
      .replaceFirst(RegExp(r':\d+$'), '')
      .replaceFirst(RegExp(r'^\*\.'), '')
      .replaceFirst(RegExp(r'\.$'), '');
  if (v.length > 253 || !_domain.hasMatch(v)) {
    return RouteLine(
        RouteLineKind.error, source, tr('пропущено: не похоже на домен или IP'));
  }
  return RouteLine(
    RouteLineKind.domain,
    v,
    (fromLink || hadPath) ? tr('домен из ссылки, с поддоменами') : tr('с поддоменами'),
  );
}

/// Разбирает весь текст: пустые строки и строки с `#` в начале пропускаются,
/// повторы помечаются.
List<RouteLine> parseRouteText(String text) {
  final seen = <String>{};
  final result = <RouteLine>[];
  for (final raw in text.split('\n')) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    final parsed = parseRouteLine(line);
    if (parsed.accepted && !seen.add(parsed.value)) {
      result.add(RouteLine(RouteLineKind.duplicate, parsed.value,
          tr('повтор — будет пропущен')));
    } else {
      result.add(parsed);
    }
  }
  return result;
}

/// Русское склонение: `plural(2, 'домен', 'домена', 'доменов')`.
String plural(int n, String one, String few, String many) {
  // В английском форм две; слова сюда приходят уже переведёнными.
  if (appLang != 'ru') return n == 1 ? '$n $one' : '$n $many';
  final mod10 = n % 10;
  final mod100 = n % 100;
  if (mod10 == 1 && mod100 != 11) return '$n $one';
  if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) {
    return '$n $few';
  }
  return '$n $many';
}
