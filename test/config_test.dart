import 'package:flutter_test/flutter_test.dart';
import 'dart:typed_data';

import 'package:split_vpn/awg_config.dart';
import 'package:split_vpn/dns_proxy.dart';
import 'package:split_vpn/models.dart';

void main() {
  const server = ServerProfile(
    host: '203.0.113.10',
    port: 41000,
    serverPublicKey: 'SERVERPUBLICKEYSERVERPUBLICKEYSERVERPUBLIC0=',
    clientPrivateKey: 'CLIENTPRIVATEKEYCLIENTPRIVATEKEYCLIENTPRIV0=',
    presharedKey: 'PRESHAREDKEYPRESHAREDKEYPRESHAREDKEYPRESHA0=',
    clientAddress: '10.66.77.2',
    obfuscation: {'Jc': '5', 'Jmin': '10', 'Jmax': '60', 'S1': '40', 'S2': '90',
      'H1': '11', 'H2': '22', 'H3': '33', 'H4': '44'},
  );

  test('в маршруты попадают только включённые сервисы', () {
    const services = [
      ServiceEntry(id: 'a', name: 'A', ips: ['1.1.1.0/24', '2.2.2.0/24'], domains: []),
      ServiceEntry(id: 'b', name: 'B', ips: ['2.2.2.0/24', '3.3.3.0/24'], domains: []),
      ServiceEntry(id: 'c', name: 'C', ips: ['4.4.4.0/24'], domains: []),
    ];
    final cidrs = collectCidrs(services, {'a', 'b'});
    expect(cidrs, {'1.1.1.0/24', '2.2.2.0/24', '3.3.3.0/24'});

    final conf = buildClientConf(server, cidrs);
    expect(conf, contains('AllowedIPs = 1.0.0.1/32, 1.1.1.0/24, 2.2.2.0/24, 3.3.3.0/24'));
    expect(conf, isNot(contains('4.4.4.0/24')));
    expect(conf, isNot(contains('DNS')));
    expect(conf, contains('Endpoint = 203.0.113.10:41000'));
    expect(conf, contains('Jc = 5'));
    expect(conf, contains('H4 = 44'));
  });

  test('собранный конфиг разбирается обратно в тот же профиль', () {
    final parsed = parseClientConf(buildClientConf(server, const ['8.8.8.0/24']));
    expect(parsed, isNotNull);
    expect(parsed!.toJson(), server.toJson());
  });

  test('конфиг приложения Amnezia разбирается', () {
    final parsed = parseClientConf('''
[Interface]
Address = 10.8.1.5/32, fd00::5/128
DNS = 1.1.1.1, 1.0.0.1
PrivateKey = AAAA=
Jc = 4
Jmin = 10
Jmax = 50
S1 = 100
S2 = 60
H1 = 1
H2 = 2
H3 = 3
H4 = 4
I1 = <b 0xdeadbeef>

[Peer]
PublicKey = BBBB=
PresharedKey = CCCC=
AllowedIPs = 0.0.0.0/0, ::/0
Endpoint = vpn.example.com:39547
PersistentKeepalive = 25
''');
    expect(parsed, isNotNull);
    expect(parsed!.host, 'vpn.example.com');
    expect(parsed.port, 39547);
    expect(parsed.clientAddress, '10.8.1.5');
    expect(parsed.clientPrivateKey, 'AAAA=');
    expect(parsed.obfuscation['S1'], '100');
    expect(parsed.obfuscation['I1'], '<b 0xdeadbeef>');
  });

  test('неполный конфиг отклоняется', () {
    expect(parseClientConf('[Interface]\nPrivateKey = AAAA=\n'), isNull);
    expect(parseClientConf('просто текст'), isNull);
  });

  test('домен сопоставляется вместе с поддоменами', () {
    final matcher = DomainMatcher(['discord.media', 'x.com'], ['keyword']);
    expect(matcher.matches('discord.media'), isTrue);
    expect(matcher.matches('russia1234.Discord.Media.'), isTrue);
    expect(matcher.matches('notdiscord.media'), isFalse);
    expect(matcher.matches('max.com'), isFalse);
    expect(matcher.matches('has-keyword-inside.net'), isTrue);
  });

  test('диапазоны покрывают адрес', () {
    final set = CidrSet(['104.16.0.0/13', '8.8.8.8/32']);
    expect(set.contains('104.16.5.9'), isTrue);
    expect(set.contains('104.24.0.1'), isFalse);
    expect(set.contains('8.8.8.8'), isTrue);
    expect(set.contains('8.8.8.9'), isFalse);
  });

  test('DNS: вопрос и адреса читаются из пакета со сжатием имён', () {
    List<int> name(String n) => [
          for (final label in n.split('.')) ...[label.length, ...label.codeUnits],
          0,
        ];
    final query = Uint8List.fromList([
      0x12, 0x34, 0x01, 0x00, 0, 1, 0, 0, 0, 0, 0, 0, //
      ...name('voice.discord.media'), 0, 1, 0, 1,
    ]);
    final question = parseDnsQuestion(query)!;
    expect(question.name, 'voice.discord.media');
    expect(question.type, dnsTypeA);
    expect(question.end, query.length);

    final answer = Uint8List.fromList([
      0x12, 0x34, 0x81, 0x80, 0, 1, 0, 2, 0, 0, 0, 0, //
      ...name('voice.discord.media'), 0, 1, 0, 1,
      0xC0, 0x0C, 0, 1, 0, 1, 0, 0, 0, 60, 0, 4, 66, 22, 1, 2,
      0xC0, 0x0C, 0, 1, 0, 1, 0, 0, 0, 60, 0, 4, 66, 22, 1, 3,
    ]);
    expect(parseDnsAddresses(answer), ['66.22.1.2', '66.22.1.3']);

    final empty = buildEmptyDnsAnswer(query, question);
    expect(empty.length, query.length);
    expect(empty[2] & 0x80, 0x80);
    expect(parseDnsAddresses(empty), isEmpty);
  });
}
