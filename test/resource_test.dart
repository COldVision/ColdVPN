import 'package:flutter_test/flutter_test.dart';
import 'package:split_vpn/models.dart';

void main() {
  const base = ServiceEntry(
    id: 'demo',
    name: 'Demo',
    ips: ['1.2.3.0/24', '5.6.7.8/32'],
    domains: ['a.example', 'b.example'],
  );

  test('правки накладываются на список каталога', () {
    final r = Resource(
      id: 'demo',
      name: 'Моё имя',
      section: 's',
      domains: ['c.example', 'a.example'],
      ips: ['9.9.9.9/32'],
      removed: ['b.example', '1.2.3.0/24'],
    );
    final s = r.toService(base);
    expect(s.name, 'Моё имя');
    expect(s.domains, ['a.example', 'c.example']);
    expect(s.ips, ['5.6.7.8/32', '9.9.9.9/32']);
    expect(s.text, 'a.example\nc.example\n5.6.7.8\n9.9.9.9');
  });

  test('свой ресурс и запись прежней сборки', () {
    final r = Resource.fromJson({
      'id': 'custom-1',
      'name': 'Портал',
      'domains': ['portal.example'],
      'ips': ['203.0.113.0/24'],
    });
    expect(r.section, '');
    expect(r.toService(null).ips, ['203.0.113.0/24']);
    expect(Resource.fromJson(r.toJson()).domains, ['portal.example']);
  });
}
