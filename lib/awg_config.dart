import 'models.dart';

/// Имя туннеля: так называются сетевой адаптер и служба Windows.
const tunnelName = 'ColdVPN';

/// Имя туннеля в прежних сборках: его служба снимается при запуске.
const legacyTunnelName = 'SplitVPN';

/// Адрес, который всегда идёт через туннель. По нему приложение проверяет,
/// что трафик реально проходит через сервер, и через него же спрашивает
/// DNS для сервисов из списка (это публичный DNS Cloudflare).
const probeAddress = '1.0.0.1';

/// Порядок параметров маскировки в конфиге (остальные идут следом).
const _obfuscationOrder = [
  'Jc', 'Jmin', 'Jmax', 'S1', 'S2', 'S3', 'S4', 'H1', 'H2', 'H3', 'H4', //
];

/// Ключи секции [Interface], которые являются параметрами маскировки или
/// тонкой настройки AmneziaWG и переносятся в профиль как есть.
final _obfuscationKey = RegExp(
  r'^(jc|jmin|jmax|s[1-4]|h[1-4]|i[1-5]|headerprotectionkey|'
  r'contentpaddingaddition|rekeyaftertime|rekeytimeout|rejectaftertime|'
  r'keepalivetimeout|maxhandshakeattempts|randomtrailers|disablecookies)$',
);

final _androidKey = RegExp(r'^(jc|jmin|jmax|s[1-4]|h[1-4]|i[1-5])$');

/// Приводит диапазон к его началу: `1.2.3.4/24` → `1.2.3.0/24`. Android
/// не принимает маршрут, у которого заданы биты после маски.
String alignCidr(String cidr) {
  final slash = cidr.indexOf('/');
  if (slash < 0) return cidr;
  final base = _ipv4ToInt(cidr.substring(0, slash));
  final bits = int.tryParse(cidr.substring(slash + 1));
  if (base == null || bits == null || bits < 0 || bits > 32) return cidr;
  final mask = bits == 0 ? 0 : (0xFFFFFFFF << (32 - bits)) & 0xFFFFFFFF;
  final v = base & mask;
  return '${(v >> 24) & 255}.${(v >> 16) & 255}.${(v >> 8) & 255}.'
      '${v & 255}/$bits';
}

/// Собирает конфигурацию туннеля для клиента.
///
/// В AllowedIPs попадают только [cidrs]: Windows добавит маршруты ровно для
/// них, а всё остальное пойдёт мимо VPN напрямую через провайдера.
///
/// [dns] — адрес локального DNS-посредника приложения; если задан, Windows
/// спрашивает имена у него, и приложение добавляет маршруты по доменам.
String buildClientConf(
  ServerProfile server,
  Iterable<String> cidrs, {
  String? dns,
  List<String> includedApps = const [],
  bool androidOnly = false,
}) {
  final routes = allowedIps(cidrs);
  // Библиотека туннеля для Android отвергает конфиг с незнакомыми ей
  // ключами, поэтому туда идут только известные параметры маскировки.
  bool accepted(String key) =>
      !androidOnly || _androidKey.hasMatch(key.toLowerCase());
  final params = <String>[
    for (final key in _obfuscationOrder)
      if (server.obfuscation[key] != null) '$key = ${server.obfuscation[key]}',
    for (final entry in server.obfuscation.entries)
      if (!_obfuscationOrder.contains(entry.key) && accepted(entry.key))
        '${entry.key} = ${entry.value}',
  ];
  final endpoint =
      server.host.contains(':') ? '[${server.host}]' : server.host;
  return [
    '[Interface]',
    'PrivateKey = ${server.clientPrivateKey}',
    'Address = ${server.clientAddress}/32',
    'MTU = 1280',
    if (dns != null) 'DNS = $dns',
    // Только на Android: через VPN идут лишь перечисленные приложения.
    if (includedApps.isNotEmpty)
      'IncludedApplications = ${includedApps.join(', ')}',
    ...params,
    '',
    '[Peer]',
    'PublicKey = ${server.serverPublicKey}',
    if (server.presharedKey.isNotEmpty) 'PresharedKey = ${server.presharedKey}',
    'Endpoint = $endpoint:${server.port}',
    'AllowedIPs = ${routes.join(', ')}',
    'PersistentKeepalive = 25',
    '',
  ].join('\r\n');
}

/// Полный отсортированный список для AllowedIPs: диапазоны сервисов,
/// проверочный адрес и адреса, найденные по доменам.
List<String> allowedIps(Iterable<String> cidrs) =>
    {...cidrs, '$probeAddress/32'}.toList()..sort();

/// Конфиг для `awg addconf`: обновляет у работающего туннеля список
/// адресов, которые разрешено отправлять серверу.
String buildAllowedIpsUpdate(ServerProfile server, Iterable<String> cidrs) {
  return [
    '[Peer]',
    'PublicKey = ${server.serverPublicKey}',
    'AllowedIPs = ${allowedIps(cidrs).join(', ')}',
    '',
  ].join('\r\n');
}

int? _ipv4ToInt(String ip) {
  final parts = ip.split('.');
  if (parts.length != 4) return null;
  var value = 0;
  for (final part in parts) {
    final n = int.tryParse(part);
    if (n == null || n < 0 || n > 255) return null;
    value = (value << 8) | n;
  }
  return value;
}

/// Быстрая проверка «адрес уже покрыт одним из диапазонов».
class CidrSet {
  CidrSet(Iterable<String> cidrs) {
    for (final cidr in cidrs) {
      final slash = cidr.indexOf('/');
      final base = _ipv4ToInt(slash < 0 ? cidr : cidr.substring(0, slash));
      final bits = slash < 0 ? 32 : int.tryParse(cidr.substring(slash + 1));
      if (base == null || bits == null || bits < 0 || bits > 32) continue;
      final mask = bits == 0 ? 0 : (0xFFFFFFFF << (32 - bits)) & 0xFFFFFFFF;
      (_byMask[mask] ??= <int>{}).add(base & mask);
    }
  }

  final Map<int, Set<int>> _byMask = {};

  bool contains(String ip) {
    final value = _ipv4ToInt(ip);
    if (value == null) return false;
    for (final entry in _byMask.entries) {
      if (entry.value.contains(value & entry.key)) return true;
    }
    return false;
  }
}

/// Собирает диапазоны всех включённых сервисов.
Set<String> collectCidrs(
  Iterable<ServiceEntry> services,
  Set<String> enabledIds,
) {
  return {
    for (final s in services)
      if (enabledIds.contains(s.id)) ...s.ips,
  };
}

/// Разбирает готовый конфиг AmneziaWG (`.conf`), например выданный
/// приложением Amnezia. Возвращает null, если в тексте не хватает
/// обязательных полей. AllowedIPs и DNS из конфига игнорируются: маршруты
/// задаются переключателями сервисов.
ServerProfile? parseClientConf(String text) {
  var section = '';
  final interface = <String, String>{};
  final peer = <String, String>{};
  final obfuscation = <String, String>{};

  for (final raw in text.split('\n')) {
    final line = raw.split('#').first.trim();
    if (line.isEmpty) continue;
    if (line.startsWith('[') && line.endsWith(']')) {
      // Берём только первую секцию [Peer].
      final name = line.substring(1, line.length - 1).trim().toLowerCase();
      section = (name == 'peer' && peer.isNotEmpty) ? 'skip' : name;
      continue;
    }
    final eq = line.indexOf('=');
    if (eq <= 0) continue;
    final key = line.substring(0, eq).trim();
    final value = line.substring(eq + 1).trim();
    if (section == 'interface') {
      if (_obfuscationKey.hasMatch(key.toLowerCase())) {
        obfuscation[key] = value;
      } else {
        interface[key.toLowerCase()] = value;
      }
    } else if (section == 'peer') {
      peer[key.toLowerCase()] = value;
    }
  }

  final endpoint = peer['endpoint'] ?? '';
  final colon = endpoint.lastIndexOf(':');
  final port = colon > 0 ? int.tryParse(endpoint.substring(colon + 1)) : null;
  var host = colon > 0 ? endpoint.substring(0, colon) : '';
  if (host.startsWith('[') && host.endsWith(']')) {
    host = host.substring(1, host.length - 1);
  }

  // Из адресов интерфейса берём первый IPv4 без маски.
  final address = (interface['address'] ?? '')
      .split(',')
      .map((a) => a.trim().split('/').first)
      .firstWhere((a) => a.contains('.') && !a.contains(':'), orElse: () => '');

  final privateKey = interface['privatekey'] ?? '';
  final publicKey = peer['publickey'] ?? '';
  if (host.isEmpty ||
      port == null ||
      address.isEmpty ||
      privateKey.isEmpty ||
      publicKey.isEmpty) {
    return null;
  }
  return ServerProfile(
    host: host,
    port: port,
    serverPublicKey: publicKey,
    clientPrivateKey: privateKey,
    presharedKey: peer['presharedkey'] ?? '',
    clientAddress: address,
    obfuscation: obfuscation,
  );
}
