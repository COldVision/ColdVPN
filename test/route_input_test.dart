import 'package:flutter_test/flutter_test.dart';

import 'package:split_vpn/l10n.dart';
import 'package:split_vpn/route_input.dart';

void main() {
  // Тексты проверяются по-русски, каким бы ни был язык системы.
  setUp(() => appLang = 'ru');

  test('строки своего маршрута распознаются', () {
    expect(parseRouteLine('portal.example.com').kind, RouteLineKind.domain);
    final link = parseRouteLine('https://Wiki.Example.org/start?x=1');
    expect(link.kind, RouteLineKind.domain);
    expect(link.value, 'wiki.example.org');
    expect(parseRouteLine('*.foo.com').value, 'foo.com');
    expect(parseRouteLine('сайт.рф').kind, RouteLineKind.domain);

    final net = parseRouteLine('203.0.113.0/24');
    expect(net.kind, RouteLineKind.network);
    expect(net.note, '256 адресов');
    expect(parseRouteLine('198.51.100.7').kind, RouteLineKind.address);
    expect(parseRouteLine('198.51.100.7/32').kind, RouteLineKind.address);

    for (final bad in ['300.1.1.1', 'exa mple', 'localhost', '2001:db8::1',
        '10.0.0.0/4', '1.2.3.4/40']) {
      expect(parseRouteLine(bad).kind, RouteLineKind.error, reason: bad);
    }
  });

  test('повторы и пустые строки в тексте маршрута', () {
    final lines = parseRouteText('a.com\n\n# заметка\nhttp://a.com/x\n1.2.3.4\n');
    expect(lines.map((l) => l.kind), [
      RouteLineKind.domain,
      RouteLineKind.duplicate,
      RouteLineKind.address,
    ]);
  });

  test('склонение числительных', () {
    expect(plural(1, 'домен', 'домена', 'доменов'), '1 домен');
    expect(plural(3, 'домен', 'домена', 'доменов'), '3 домена');
    expect(plural(11, 'домен', 'домена', 'доменов'), '11 доменов');
    expect(plural(25, 'домен', 'домена', 'доменов'), '25 доменов');
  });

  test('английский: перевод, подстановки и две формы числа', () {
    appLang = 'en';
    expect(tr('Включено {0} из {1}', [2, 5]), 'On: 2 of 5');
    expect(tr('строки без перевода остаются как есть'),
        'строки без перевода остаются как есть');
    expect(plural(1, 'domain', 'domains', 'domains'), '1 domain');
    expect(plural(21, 'domain', 'domains', 'domains'), '21 domains');
    expect(trLoose('ошибка туннеля: X'), 'tunnel error: X');
    expect(parseRouteLine('1.2.3.0/24').note, '256 addresses');
  });
}
