import 'l10n.dart';

/// Сервис из списка: один переключатель в интерфейсе.
class ServiceEntry {
  const ServiceEntry({
    required this.id,
    required this.name,
    required this.ips,
    required this.domains,
    this.keywords = const [],
  });

  final String id;
  final String name;

  /// Диапазоны IPv4 в виде CIDR, например `104.16.0.0/16`.
  final List<String> ips;

  /// Домены сервиса (вместе со всеми поддоменами): их адреса добавляются
  /// в туннель на лету, когда программа спрашивает имя у DNS.
  final List<String> domains;

  /// Подстроки: имя с такой подстрокой тоже относится к сервису.
  final List<String> keywords;

  /// Строки для поля ввода при правке: домены, затем адреса.
  String get text => [
        ...domains,
        for (final ip in ips) ip.endsWith('/32') ? ip.split('/').first : ip,
      ].join('\n');

  factory ServiceEntry.fromJson(Map<String, dynamic> json) {
    return ServiceEntry(
      id: json['id'] as String,
      name: json['name'] as String,
      ips: (json['ips'] as List<dynamic>? ?? const []).cast<String>(),
      domains: (json['domains'] as List<dynamic>? ?? const []).cast<String>(),
      keywords: (json['keywords'] as List<dynamic>? ?? const []).cast<String>(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'ips': ips,
        'domains': domains,
        'keywords': keywords,
      };
}

/// Данные подключения к серверу AmneziaWG для этого устройства.
class ServerProfile {
  const ServerProfile({
    required this.host,
    required this.port,
    required this.serverPublicKey,
    required this.clientPrivateKey,
    required this.presharedKey,
    required this.clientAddress,
    required this.obfuscation,
  });

  final String host;

  /// UDP-порт сервера.
  final int port;
  final String serverPublicKey;
  final String clientPrivateKey;

  /// Может быть пустым, если сервер его не использует.
  final String presharedKey;

  /// Адрес устройства внутри туннеля, например `10.66.77.2`.
  final String clientAddress;

  /// Параметры маскировки AmneziaWG (Jc, Jmin, Jmax, S1, S2, H1–H4 и
  /// другие, если они были в импортированном конфиге), в исходном написании.
  final Map<String, String> obfuscation;

  Map<String, dynamic> toJson() => {
        'host': host,
        'port': port,
        'serverPublicKey': serverPublicKey,
        'clientPrivateKey': clientPrivateKey,
        'presharedKey': presharedKey,
        'clientAddress': clientAddress,
        'obfuscation': obfuscation,
      };

  factory ServerProfile.fromJson(Map<String, dynamic> json) {
    return ServerProfile(
      host: json['host'] as String,
      port: json['port'] as int,
      serverPublicKey: json['serverPublicKey'] as String,
      clientPrivateKey: json['clientPrivateKey'] as String,
      presharedKey: json['presharedKey'] as String? ?? '',
      clientAddress: json['clientAddress'] as String,
      obfuscation: (json['obfuscation'] as Map<String, dynamic>? ?? const {})
          .map((key, value) => MapEntry(key, '$value')),
    );
  }
}

/// Сохранённый сервер: данные подключения плюс то, что видит пользователь.
class SavedServer {
  const SavedServer({
    required this.id,
    required this.name,
    required this.profile,
    this.country = '',
    this.city = '',
    this.countryCode = '',
  });

  final String id;
  final String name;
  final ServerProfile profile;
  final String country;
  final String city;

  /// Двухбуквенный код страны, например `SE`. Пусто — неизвестно.
  final String countryCode;

  /// Сервер настроен этим приложением (а не импортирован чужим конфигом):
  /// у него наша внутренняя сеть. Только на таком сервере приложение может
  /// выпускать отдельные ключи.
  bool get managed => profile.clientAddress.startsWith('10.66.77.');

  /// «Страна, Город» или то, что из этого известно.
  String get place =>
      [country, city].where((part) => part.isNotEmpty).join(', ');

  SavedServer copyWith({
    String? name,
    String? country,
    String? city,
    String? countryCode,
  }) {
    return SavedServer(
      id: id,
      name: name ?? this.name,
      profile: profile,
      country: country ?? this.country,
      city: city ?? this.city,
      countryCode: countryCode ?? this.countryCode,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'profile': profile.toJson(),
        'country': country,
        'city': city,
        'countryCode': countryCode,
      };

  factory SavedServer.fromJson(Map<String, dynamic> json) {
    return SavedServer(
      id: json['id'] as String,
      name: json['name'] as String? ?? tr('Сервер'),
      profile: ServerProfile.fromJson(json['profile'] as Map<String, dynamic>),
      country: json['country'] as String? ?? '',
      city: json['city'] as String? ?? '',
      countryCode: json['countryCode'] as String? ?? '',
    );
  }
}

/// Раздел на вкладке «Сервисы».
class Section {
  Section({required this.id, required this.name, required this.icon});

  final String id;
  String name;

  /// Ключ значка из `sectionIcons`.
  String icon;

  /// Название для показа: стандартные разделы переводятся, свои — как есть.
  String get title => tr(name);

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'icon': icon};

  factory Section.fromJson(Map<String, dynamic> json) => Section(
        id: json['id'] as String,
        name: json['name'] as String? ?? tr('Раздел'),
        icon: json['icon'] as String? ?? 'star',
      );
}

/// Ресурс: строка с переключателем на вкладке «Сервисы».
///
/// У ресурса, пришедшего из каталога ([id] совпадает с сервисом каталога),
/// здесь хранятся только правки пользователя: что он дописал и что убрал.
/// Сам список берётся из каталога, поэтому продолжает обновляться.
class Resource {
  Resource({
    required this.id,
    required this.name,
    required this.section,
    this.domains = const [],
    this.ips = const [],
    this.removed = const [],
  });

  final String id;
  String name;

  /// Идентификатор раздела, в котором показан ресурс.
  String section;

  /// Свои домены и адреса (CIDR). У ресурса из каталога — добавленные
  /// к его списку.
  final List<String> domains;
  final List<String> ips;

  /// Домены и адреса каталога, которые пользователь убрал.
  final List<String> removed;

  /// Итоговый список: каталог ([base]) с правками пользователя.
  ServiceEntry toService(ServiceEntry? base) {
    if (base == null) {
      return ServiceEntry(id: id, name: name, ips: ips, domains: domains);
    }
    final gone = removed.toSet();
    return ServiceEntry(
      id: id,
      name: name,
      ips: {...base.ips.where((v) => !gone.contains(v)), ...ips}.toList(),
      domains: {...base.domains.where((v) => !gone.contains(v)), ...domains}
          .toList(),
      keywords: base.keywords,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'section': section,
        'domains': domains,
        'ips': ips,
        'removed': removed,
      };

  /// Читает и запись прежних сборок о «своём маршруте» (без раздела).
  factory Resource.fromJson(Map<String, dynamic> json) {
    List<String> list(String key) =>
        (json[key] as List<dynamic>? ?? const []).cast<String>();
    return Resource(
      id: json['id'] as String,
      name: json['name'] as String? ?? tr('Ресурс'),
      section: json['section'] as String? ?? '',
      domains: list('domains'),
      ips: list('ips'),
      removed: list('removed'),
    );
  }
}

/// Настройки с вкладки «Настройки».
class AppSettings {
  AppSettings({
    this.connectOnStart = true,
    this.wasOn = false,
    this.domainRouting = true,
    this.ipv4Only = true,
    this.dns = '1.0.0.1',
    this.fullTunnel = false,
    this.appMode = false,
    this.closeToTray = true,
    this.language = '',
    this.autoUpdateLists = true,
  });

  /// Подключаться при запуске, если в прошлый раз VPN был включён.
  bool connectOnStart;

  /// Был ли VPN включён, когда приложение закрывали.
  bool wasOn;

  /// Добавлять адреса сервисов на лету через DNS.
  bool domainRouting;

  /// Для сервисов из списка отдавать только адреса IPv4.
  bool ipv4Only;

  /// DNS-сервер, у которого через туннель спрашиваются имена сервисов.
  String dns;

  /// Через VPN идёт весь трафик, а не только включённые сервисы.
  bool fullTunnel;

  /// Только на Android: через VPN идут выбранные приложения целиком, а не
  /// сервисы по спискам адресов.
  bool appMode;

  /// При закрытии окна прятать приложение в трей, а не выходить.
  bool closeToTray;

  /// Язык интерфейса: `ru`, `en` или пусто — как в системе.
  String language;

  /// Раз в неделю обновлять списки сервисов из репозиториев.
  bool autoUpdateLists;

  Map<String, dynamic> toJson() => {
        'connectOnStart': connectOnStart,
        'wasOn': wasOn,
        'domainRouting': domainRouting,
        'ipv4Only': ipv4Only,
        'dns': dns,
        'fullTunnel': fullTunnel,
        'appMode': appMode,
        'closeToTray': closeToTray,
        'language': language,
        'autoUpdateLists': autoUpdateLists,
      };

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    return AppSettings(
      connectOnStart: json['connectOnStart'] as bool? ?? true,
      wasOn: json['wasOn'] as bool? ?? false,
      domainRouting: json['domainRouting'] as bool? ?? true,
      ipv4Only: json['ipv4Only'] as bool? ?? true,
      dns: json['dns'] as String? ?? '1.0.0.1',
      fullTunnel: json['fullTunnel'] as bool? ?? false,
      appMode: json['appMode'] as bool? ?? false,
      closeToTray: json['closeToTray'] as bool? ?? true,
      language: json['language'] as String? ?? '',
      autoUpdateLists: json['autoUpdateLists'] as bool? ?? true,
    );
  }
}

enum LogKind { info, ok, warn, route }

/// Запись для вкладки «События».
class LogEvent {
  const LogEvent(this.time, this.kind, this.text);

  final String time;
  final LogKind kind;
  final String text;
}

enum CheckState { wait, run, ok, warn, fail, skip }

/// Один шаг диагностики.
class CheckStep {
  CheckStep(this.title);

  final String title;
  CheckState state = CheckState.wait;
  String note = tr('в очереди');
}
