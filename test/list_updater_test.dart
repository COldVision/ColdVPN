import 'package:flutter_test/flutter_test.dart';

import 'package:split_vpn/list_updater.dart';

void main() {
  test('маршруты из файла: маски, служебные сети, слияние', () {
    final ranges = parseRouteFile('''
route add 104.16.0.0 mask 255.255.0.0 0.0.0.0
ROUTE ADD 104.17.0.0 MASK 255.255.0.0 0.0.0.0
route add 192.168.1.0 mask 255.255.255.0 0.0.0.0
route add 8.8.8.8 mask 255.255.255.255 0.0.0.0
route add 1.2.3.0 mask 255.0.255.0 0.0.0.0
просто строка
''');
    // Локальная сеть и неправильная маска отброшены.
    expect(ranges.length, 3);
    expect(collapseRanges(ranges), ['8.8.8.8/32', '104.16.0.0/15']);
  });

  test('список доменов: include, keyword, @ads и regexp', () {
    final domains = <String>{};
    final keywords = <String>{};
    final problems = <String>[];
    readDomainList(
      {
        'main': 'example.com\nfull:www.example.com\ninclude:extra\n'
            'keyword:Exa\nregexp:^x\$\nads.example.net @ads\n# комментарий\n',
        'extra': 'domain:Other.org\ninclude:main\ninclude:missing\n',
      },
      'main',
      domains,
      keywords,
      {},
      problems,
    );
    expect(domains, {'example.com', 'www.example.com', 'other.org'});
    expect(keywords, {'exa'});
    expect(problems.length, 1);
    expect(minimizeDomains(domains), {'example.com', 'other.org'});
  });

  test('сервис собирается из обоих источников', () {
    final problems = <String>[];
    final services = buildServices(
      {
        'exclude_files': ['Global/Demo/skip.bat'],
        'services': [
          {
            'name': 'Demo / Test',
            'from': ['Global/Demo'],
            'v2fly': ['demo'],
          },
          {
            'name': 'Empty',
            'from': ['Global/Nothing'],
          },
        ],
      },
      {
        'Global/Demo/a.bat': 'route add 5.5.5.0 mask 255.255.255.0 0.0.0.0',
        'Global/Demo/skip.bat': 'route add 6.6.6.0 mask 255.255.255.0 0.0.0.0',
        'Global/Demolition/b.bat': 'route add 7.7.7.0 mask 255.255.255.0 0.0.0.0',
      },
      {'demo': 'demo.example\nsub.demo.example\n'},
      problems,
    );
    expect(services.length, 1);
    expect(services.first.id, 'demo-test');
    expect(services.first.ips, ['5.5.5.0/24']);
    expect(services.first.domains, ['demo.example']);
    expect(problems.length, 2);
  });
}
