import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

/// Проверяет, относится ли имя к одному из включённых сервисов.
class DomainMatcher {
  DomainMatcher(Iterable<String> domains, Iterable<String> keywords)
      : _domains = {for (final d in domains) d.toLowerCase()},
        _keywords = [for (final k in keywords) k.toLowerCase()];

  final Set<String> _domains;
  final List<String> _keywords;

  bool get isEmpty => _domains.isEmpty && _keywords.isEmpty;

  /// Совпадает само имя или любой его родительский домен из списка.
  bool matches(String name) {
    var host = name.toLowerCase();
    if (host.endsWith('.')) host = host.substring(0, host.length - 1);
    if (host.isEmpty) return false;
    var rest = host;
    while (true) {
      if (_domains.contains(rest)) return true;
      final dot = rest.indexOf('.');
      if (dot < 0) break;
      rest = rest.substring(dot + 1);
    }
    for (final keyword in _keywords) {
      if (host.contains(keyword)) return true;
    }
    return false;
  }
}

/// Вопрос из DNS-запроса.
class DnsQuestion {
  const DnsQuestion(this.name, this.type, this.end);

  final String name;

  /// Тип записи: 1 — A, 28 — AAAA, 65 — HTTPS.
  final int type;

  /// Смещение первого байта после вопроса.
  final int end;
}

const dnsTypeA = 1;
const dnsTypeAaaa = 28;
const dnsTypeHttps = 65;

/// Читает имя по смещению [offset]; возвращает имя и смещение после него
/// в исходном месте (сжатые ссылки раскрываются, но на смещение не влияют).
(String, int)? _readName(Uint8List data, int offset) {
  final labels = <String>[];
  var pos = offset;
  int? after;
  var jumps = 0;
  while (true) {
    if (pos >= data.length) return null;
    final len = data[pos];
    if (len == 0) {
      pos++;
      break;
    }
    if (len & 0xC0 == 0xC0) {
      if (pos + 1 >= data.length || ++jumps > 16) return null;
      after ??= pos + 2;
      pos = ((len & 0x3F) << 8) | data[pos + 1];
      continue;
    }
    if (len > 63 || pos + 1 + len > data.length) return null;
    labels.add(String.fromCharCodes(data, pos + 1, pos + 1 + len));
    pos += 1 + len;
  }
  return (labels.join('.'), after ?? pos);
}

/// Разбирает первый вопрос запроса или ответа. null — пакет не разобрался.
DnsQuestion? parseDnsQuestion(Uint8List data) {
  if (data.length < 17) return null;
  final questions = (data[4] << 8) | data[5];
  if (questions < 1) return null;
  final name = _readName(data, 12);
  if (name == null) return null;
  final (text, next) = name;
  if (next + 4 > data.length) return null;
  return DnsQuestion(text, (data[next] << 8) | data[next + 1], next + 4);
}

/// Достаёт из ответа все адреса IPv4 (записи A).
List<String> parseDnsAddresses(Uint8List data) {
  final result = <String>[];
  if (data.length < 12) return result;
  final questions = (data[4] << 8) | data[5];
  final answers = (data[6] << 8) | data[7];
  var pos = 12;
  for (var i = 0; i < questions; i++) {
    final name = _readName(data, pos);
    if (name == null) return result;
    pos = name.$2 + 4;
  }
  for (var i = 0; i < answers; i++) {
    final name = _readName(data, pos);
    if (name == null) return result;
    pos = name.$2;
    if (pos + 10 > data.length) return result;
    final type = (data[pos] << 8) | data[pos + 1];
    final length = (data[pos + 8] << 8) | data[pos + 9];
    pos += 10;
    if (pos + length > data.length) return result;
    if (type == dnsTypeA && length == 4) {
      result.add('${data[pos]}.${data[pos + 1]}.${data[pos + 2]}.${data[pos + 3]}');
    }
    pos += length;
  }
  return result;
}

/// Строит на запрос ответ «записей нет» (успех с пустым списком).
Uint8List buildEmptyDnsAnswer(Uint8List query, DnsQuestion question) {
  final response = Uint8List.fromList(query.sublist(0, question.end));
  response[2] = 0x80 | (query[2] & 0x79); // ответ, тот же код операции и RD
  response[3] = 0x80; // рекурсия доступна, ошибки нет
  response[4] = 0;
  response[5] = 1; // один вопрос
  for (var i = 6; i < 12; i++) {
    response[i] = 0; // ни ответов, ни дополнительных записей
  }
  return response;
}

/// Локальный DNS-посредник для маршрутизации по доменам.
///
/// Windows спрашивает у него имена. Если имя относится к включённому
/// сервису, посредник узнаёт его адреса, сообщает их через [onAddresses]
/// (приложение добавляет для них маршруты в туннель) и только после этого
/// отдаёт ответ программе. Остальные запросы просто пересылаются обычному
/// DNS системы.
class DnsProxy {
  DnsProxy({
    required this.matcher,
    required this.directUpstreams,
    required this.tunnelUpstream,
    required this.onAddresses,
    required this.log,
    this.ipv4Only = true,
  });

  /// Для имён из списка не отдавать адреса IPv6: списки и туннель работают
  /// по IPv4, а по IPv6 трафик ушёл бы мимо VPN.
  final bool ipv4Only;

  /// Адрес, на котором слушает посредник. Отдельный адрес из 127.0.0.0/8,
  /// чтобы не конфликтовать с другими локальными DNS на 127.0.0.1.
  static const listenAddress = '127.66.77.1';

  final DomainMatcher matcher;

  /// Обычные DNS-серверы системы (в обход туннеля).
  final List<String> directUpstreams;

  /// DNS-сервер, запросы к которому идут через туннель: его ответы не
  /// подменяются провайдером.
  final String tunnelUpstream;

  final Future<void> Function(String name, List<String> addresses) onAddresses;
  final void Function(String line) log;

  RawDatagramSocket? _udp;
  RawDatagramSocket? _extraUdp;
  ServerSocket? _tcp;

  /// Сколько запросов пришло всего и сколько из них — по спискам сервисов.
  int total = 0;
  int matched = 0;

  /// Запросы по спискам, на которые не ответил ни один DNS-сервер.
  int unanswered = 0;

  /// Запросы, на которые DNS через туннель не успел ответить вовремя.
  int tunnelLate = 0;
  int _detailed = 0;

  Future<void> start() async {
    final address = InternetAddress(listenAddress);
    final udp = await RawDatagramSocket.bind(address, 53);
    _udp = udp;
    _serve(udp);
    // DNS по TCP нужен редко (очень длинные ответы); пересылаем как есть.
    try {
      final tcp = await ServerSocket.bind(address, 53);
      _tcp = tcp;
      tcp.listen(_relayTcp, onError: (_) {});
    } catch (e) {
      log('DNS по TCP недоступен: $e');
    }
  }

  void _serve(RawDatagramSocket udp) {
    udp.listen((event) {
      if (event != RawSocketEvent.read) return;
      while (true) {
        final datagram = udp.receive();
        if (datagram == null) break;
        _handleUdp(udp, datagram);
      }
    });
  }

  /// Начинает дополнительно слушать на [address] — собственном адресе
  /// компьютера в туннеле. Запрос и ответ тогда идут между одним и тем же
  /// адресом, и Windows принимает ответ без оговорок. Адрес появляется
  /// только после запуска туннеля, поэтому делается несколько попыток.
  Future<bool> listenAlso(String address) async {
    for (var attempt = 0; attempt < 12; attempt++) {
      try {
        final udp = await RawDatagramSocket.bind(InternetAddress(address), 53);
        _extraUdp = udp;
        _serve(udp);
        return true;
      } catch (_) {
        await Future<void>.delayed(const Duration(milliseconds: 400));
      }
    }
    return false;
  }

  Future<void> stop() async {
    _udp?.close();
    _udp = null;
    _extraUdp?.close();
    _extraUdp = null;
    await _tcp?.close();
    _tcp = null;
  }

  Future<void> _handleUdp(RawDatagramSocket udp, Datagram datagram) async {
    try {
      final response = await _resolve(
        datagram.data,
        '${datagram.address.address} → ${udp.address.address}',
      );
      if (response != null) udp.send(response, datagram.address, datagram.port);
    } catch (_) {
      // Сбой одного запроса не должен останавливать посредника.
    }
  }

  Future<Uint8List?> _resolve(Uint8List query, String path) async {
    total++;
    final question = parseDnsQuestion(query);
    if (question == null || !matcher.matches(question.name)) {
      return _exchange(query, directUpstreams, const Duration(seconds: 2));
    }
    matched++;

    // Для сервисов из списка отдаём только IPv4: списки и туннель работают
    // по IPv4, а по IPv6 трафик ушёл бы мимо VPN.
    if (question.type == dnsTypeAaaa || question.type == dnsTypeHttps) {
      if (ipv4Only) return buildEmptyDnsAnswer(query, question);
      return _exchange(query, directUpstreams, const Duration(seconds: 2));
    }

    // Спрашиваем и через туннель, и напрямую: программа может получить
    // любой из ответов, поэтому маршруты нужны для адресов из обоих.
    final watch = Stopwatch()..start();
    final viaTunnel =
        _exchange(query, [tunnelUpstream], const Duration(seconds: 3));
    final direct = await _exchange(
      query,
      directUpstreams,
      const Duration(seconds: 2),
    );
    // Ответ через туннель ждём недолго: если он запаздывает, отвечаем тем,
    // что есть, а его адреса добавим в туннель, когда он придёт.
    final tunnelAnswer = await viaTunnel.timeout(
      Duration(milliseconds: direct == null ? 3000 : 600),
      onTimeout: () => null,
    );
    if (tunnelAnswer == null) {
      tunnelLate++;
      unawaited(viaTunnel.then((late) async {
        if (late == null) return;
        final addresses = parseDnsAddresses(late);
        if (addresses.isNotEmpty) await onAddresses(question.name, addresses);
      }).catchError((_) {}));
    }

    final addresses = <String>{
      if (tunnelAnswer != null) ...parseDnsAddresses(tunnelAnswer),
      if (direct != null) ...parseDnsAddresses(direct),
    };
    if (addresses.isNotEmpty) {
      await onAddresses(question.name, addresses.toList());
    }
    final answer = tunnelAnswer ?? direct;
    if (answer == null) unanswered++;
    if (_detailed < 40) {
      _detailed++;
      log('DNS: ${question.name} — адресов ${addresses.length}, через туннель '
          '${tunnelAnswer == null ? 'нет ответа' : 'ответ'}, напрямую '
          '${direct == null ? 'нет ответа' : 'ответ'}, '
          '${watch.elapsedMilliseconds} мс, запрос $path');
    }
    return answer;
  }

  /// Отправляет запрос серверам по очереди и возвращает первый ответ.
  Future<Uint8List?> _exchange(
    Uint8List query,
    List<String> servers,
    Duration timeout,
  ) async {
    for (final server in servers) {
      RawDatagramSocket? socket;
      try {
        socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
        final done = Completer<Uint8List?>();
        final current = socket;
        current.listen((event) {
          if (event != RawSocketEvent.read) return;
          final datagram = current.receive();
          if (datagram == null || done.isCompleted) return;
          final data = datagram.data;
          // Ответ узнаём по идентификатору запроса в первых двух байтах.
          if (data.length >= 12 && data[0] == query[0] && data[1] == query[1]) {
            done.complete(data);
          }
        });
        current.send(query, InternetAddress(server), 53);
        final response =
            await done.future.timeout(timeout, onTimeout: () => null);
        if (response != null) return response;
      } catch (_) {
        // Пробуем следующий сервер.
      } finally {
        socket?.close();
      }
    }
    return null;
  }

  Future<void> _relayTcp(Socket client) async {
    Socket? upstream;
    try {
      final server =
          directUpstreams.isNotEmpty ? directUpstreams.first : tunnelUpstream;
      upstream = await Socket.connect(
        server,
        53,
        timeout: const Duration(seconds: 3),
      );
      final target = upstream;
      target.listen(client.add, onDone: client.destroy, onError: (_) {
        client.destroy();
      });
      client.listen(target.add, onDone: target.destroy, onError: (_) {
        target.destroy();
      });
    } catch (_) {
      client.destroy();
      upstream?.destroy();
    }
  }
}
