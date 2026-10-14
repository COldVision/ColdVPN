import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'dns_proxy.dart' show parseDnsAddresses;

/// Узнаёт адреса имён через туннель: запрос к DNS-серверу уходит с адреса
/// компьютера в туннеле, поэтому подменить ответ по дороге провайдер не
/// может.
class TunnelResolver {
  TunnelResolver({required this.source, required this.server});

  /// Адрес компьютера в туннеле, например `10.66.77.2`.
  String source;

  /// DNS-сервер, адрес которого идёт через туннель.
  String server;

  final _cache = <String, (List<String>, DateTime)>{};
  final _random = Random();

  Future<List<String>> lookup(String name) async {
    final key = name.toLowerCase();
    final cached = _cache[key];
    if (cached != null && DateTime.now().isBefore(cached.$2)) return cached.$1;
    for (var attempt = 0; attempt < 2; attempt++) {
      final found = await _ask(key, const Duration(seconds: 3));
      if (found.isNotEmpty) {
        if (_cache.length > 2000) _cache.clear();
        _cache[key] = (found, DateTime.now().add(const Duration(minutes: 2)));
        return found;
      }
    }
    return const [];
  }

  Future<List<String>> _ask(String name, Duration timeout) async {
    final id = _random.nextInt(0xFFFF);
    final query = BytesBuilder()
      ..add([id >> 8, id & 0xFF, 0x01, 0x00, 0, 1, 0, 0, 0, 0, 0, 0]);
    for (final label in name.split('.')) {
      if (label.isEmpty) continue;
      final bytes = label.codeUnits;
      if (bytes.length > 63 || bytes.any((b) => b > 127)) return const [];
      query
        ..addByte(bytes.length)
        ..add(bytes);
    }
    query.add([0, 0, 1, 0, 1]); // конец имени, тип A, класс IN

    RawDatagramSocket? socket;
    try {
      socket = await RawDatagramSocket.bind(InternetAddress(source), 0);
      final done = Completer<List<String>>();
      socket.listen((event) {
        if (event != RawSocketEvent.read || done.isCompleted) return;
        final packet = socket!.receive();
        if (packet == null || packet.data.length < 2) return;
        if (((packet.data[0] << 8) | packet.data[1]) != id) return;
        done.complete(parseDnsAddresses(Uint8List.fromList(packet.data)));
      });
      socket.send(query.toBytes(), InternetAddress(server), 53);
      return await done.future.timeout(timeout, onTimeout: () => const []);
    } catch (_) {
      return const [];
    } finally {
      socket?.close();
    }
  }
}

/// SOCKS5-прокси на 127.0.0.1 для браузера. Соединения к сайтам он
/// открывает с адреса компьютера в туннеле, поэтому они идут через VPN, а
/// остальные программы его не используют и ходят напрямую.
class SocksProxy {
  SocksProxy._(this._server, this.resolver, this.log);

  static Future<SocksProxy> start({
    required int port,
    required TunnelResolver resolver,
    required void Function(String line) log,
  }) async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, port);
    final proxy = SocksProxy._(server, resolver, log);
    server.listen(proxy._accept, onError: (_) {});
    return proxy;
  }

  final ServerSocket _server;
  final TunnelResolver resolver;
  final void Function(String line) log;
  final _open = <Socket>{};

  /// Сколько соединений браузера сейчас идёт через прокси.
  int get connections => _open.length;

  Future<void> stop() async {
    await _server.close();
    for (final socket in _open.toList()) {
      socket.destroy();
    }
    _open.clear();
  }

  void _accept(Socket client) {
    _open.add(client);
    final buffer = BytesBuilder(copy: false);
    var stage = 0; // 0 — приветствие, 1 — запрос, 2 — передача данных
    Socket? upstream;
    late StreamSubscription<Uint8List> sub;

    void close() {
      _open.remove(client);
      upstream?.destroy();
      client.destroy();
    }

    Future<void> open(String host, int port, Uint8List rest) async {
      sub.pause();
      try {
        String address = host;
        if (InternetAddress.tryParse(host) == null) {
          final found = await resolver.lookup(host);
          if (found.isEmpty) throw 'не найден адрес $host';
          address = found.first;
        }
        final remote = await Socket.connect(
          address,
          port,
          sourceAddress: resolver.source,
          timeout: const Duration(seconds: 12),
        );
        upstream = remote;
        remote.setOption(SocketOption.tcpNoDelay, true);
        client.add([5, 0, 0, 1, 0, 0, 0, 0, 0, 0]);
        if (rest.isNotEmpty) remote.add(rest);
        stage = 2;
        // Ответы сайта — браузеру; поток сам притормаживает, если браузер
        // не успевает читать.
        unawaited(client
            .addStream(remote)
            .then((_) => close(), onError: (_) => close()));
        sub.resume();
      } catch (_) {
        try {
          client.add([5, 4, 0, 1, 0, 0, 0, 0, 0, 0]); // узел недоступен
        } catch (_) {}
        close();
      }
    }

    sub = client.listen(
      (data) {
        if (stage == 3) return; // поток на паузе, сюда не попадаем
        if (stage == 2) {
          try {
            upstream?.add(data);
          } catch (_) {
            close();
          }
          return;
        }
        buffer.add(data);
        final bytes = buffer.toBytes();
        if (stage == 0) {
          if (bytes.length < 2) return;
          if (bytes[0] != 5) return close();
          final need = 2 + bytes[1];
          if (bytes.length < need) return;
          client.add([5, 0]); // без пароля: прокси слушает только 127.0.0.1
          stage = 1;
          buffer.clear();
          if (bytes.length > need) buffer.add(bytes.sublist(need));
          if (buffer.isEmpty) return;
        }
        final request = buffer.toBytes();
        if (request.length < 5) return;
        if (request[0] != 5 || request[1] != 1) {
          // Поддерживается только CONNECT.
          client.add([5, 7, 0, 1, 0, 0, 0, 0, 0, 0]);
          return close();
        }
        late final String host;
        late final int end;
        switch (request[3]) {
          case 1: // IPv4
            if (request.length < 10) return;
            host = request.sublist(4, 8).join('.');
            end = 8;
            break;
          case 3: // имя
            final length = request[4];
            if (request.length < 5 + length + 2) return;
            host = String.fromCharCodes(request.sublist(5, 5 + length));
            end = 5 + length;
            break;
          default: // IPv6 через туннель не идёт
            client.add([5, 8, 0, 1, 0, 0, 0, 0, 0, 0]);
            return close();
        }
        final port = (request[end] << 8) | request[end + 1];
        buffer.clear();
        stage = 3; // ждём соединения с сайтом
        unawaited(open(host, port, request.sublist(end + 2)));
      },
      onDone: close,
      onError: (_) => close(),
      cancelOnError: true,
    );
  }
}
