import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException, rootBundle;
import 'package:path_provider/path_provider.dart';

import 'android_tunnel.dart';
import 'awg_config.dart';
import 'awg_manager.dart';
import 'catalog.dart';
import 'dns_proxy.dart';
import 'list_updater.dart';
import 'models.dart';
import 'route_input.dart';
import 'secret_store.dart';
import 'socks_proxy.dart';
import 'server_installer.dart';
import 'l10n.dart';

enum VpnStatus { off, connecting, on }

/// Имя задачи планировщика Windows для автозапуска.
const _autostartTask = 'ColdVPN';

/// Состояние приложения: серверы, переключатели сервисов и подключение.
class AppState extends ChangeNotifier {
  AppState._(
    this._stateFile,
    this._listsFile,
    this.builtin,
    Directory tunnelDir,
  ) {
    _tunnel = AwgManager(tunnelDir, onLog: addLog);
    // Начальный набор разделов; сохранённые настройки читаются следом.
    _apply(const {});
  }

  final File _stateFile;

  /// Списки сервисов, обновлённые из репозиториев (если обновлялись).
  final File _listsFile;

  /// Когда списки обновлялись последний раз. null — используются встроенные.
  DateTime? listsUpdatedAt;
  bool updatingLists = false;
  late final AwgManager _tunnel;
  Timer? _restartTimer;
  Timer? _statsTimer;
  int _run = 0;

  // Маршрутизация по доменам.
  DnsProxy? _dns;
  Timer? _routeKeeper;
  Future<void> _routeQueue = Future.value();
  CidrSet _staticRanges = CidrSet(const []);
  Set<String> _activeCidrs = {};
  final Set<String> _routed = {};
  int _routeLogCount = 0;

  /// Адреса, найденные по доменам: адрес → имя, по которому он найден.
  /// Сохраняются между запусками, чтобы после переподключения сервисы
  /// работали сразу, не дожидаясь новых запросов к DNS.
  final Map<String, String> _learned = {};

  /// Сколько адресов сейчас направлено в туннель по доменам.
  int get domainRouteCount => _routed.length;

  /// Каталог: списки сервисов, которые обновляются из репозиториев.
  final List<ServiceEntry> builtin;

  /// Разделы вкладки «Сервисы» в порядке показа.
  final List<Section> sections = [];

  /// Ресурсы всех разделов. Порядок в разделе — порядок в этом списке.
  final List<Resource> resources = [];

  /// Сервисы каталога, которые пользователь удалил: обновление списков
  /// не должно возвращать их обратно.
  final Set<String> deleted = {};

  /// Ресурсы с итоговыми списками адресов, в порядке [resources].
  List<ServiceEntry> services = const [];

  final Set<String> enabled = {};

  final List<SavedServer> servers = [];
  String? selectedServerId;

  final AppSettings settings = AppSettings();
  bool autostart = false;

  /// Полный журнал строками — для вкладки «Подробно».
  final List<String> events = [];

  /// Важные события — для вкладки «События». Новые в конце.
  final List<LogEvent> feed = [];

  VpnStatus status = VpnStatus.off;
  String? error;
  bool elevated = true;

  /// Под каким адресом сайты видят устройство через туннель.
  String? exitAddress;

  // Показатели туннеля, обновляются раз в две секунды.
  double downRate = 0;
  double upRate = 0;
  int received = 0;
  int sent = 0;
  DateTime? lastHandshake;
  int _lastRx = 0;
  int _lastTx = 0;
  DateTime? _lastSample;

  /// Данные для входа на серверы (по адресу): нужны, чтобы выпускать
  /// отдельные ключи и снимать диагностику без повторного ввода пароля.
  /// Сохраняются на диск в зашифрованном виде, см. [SecretStore].
  final Map<String, InstallRequest> credentials = {};
  SecretStore? _secrets;

  /// Запоминает данные для входа на сервер. [persist] = false — только до
  /// закрытия приложения.
  Future<void> rememberCredentials(
    InstallRequest request, {
    bool persist = true,
  }) async {
    credentials[request.host] = request;
    if (persist) {
      _memoryOnly.remove(request.host);
      await _saveSecrets();
    } else {
      // Раньше для этого сервера пароль мог быть сохранён — убираем его.
      await _saveSecrets(except: request.host);
    }
    notifyListeners();
  }

  Future<void> forgetCredentials(String host) async {
    credentials.remove(host);
    await _saveSecrets();
    notifyListeners();
  }

  final Set<String> _memoryOnly = {};

  Future<void> _saveSecrets({String? except}) async {
    if (except != null) _memoryOnly.add(except);
    final store = _secrets;
    if (store == null) return;
    try {
      await store.save({
        for (final entry in credentials.entries)
          if (!_memoryOnly.contains(entry.key)) entry.key: entry.value,
      });
    } catch (e) {
      addLog(tr('Не удалось сохранить пароль сервера: {0}', [e]));
    }
  }

  // Диагностика.
  List<CheckStep> checks = [];
  bool checking = false;
  String checkSummary = '';
  String checkAdvice = '';

  /// Подключение пока реализовано только для Windows.
  bool get platformSupported => Platform.isWindows || Platform.isAndroid;

  bool get isAndroid => Platform.isAndroid;

  /// Только на Android: приложения телефона и те из них, что идут через VPN.
  List<AndroidApp> apps = const [];
  final Set<String> enabledApps = {};
  bool loadingApps = false;

  /// Режим «по приложениям» действует только на Android.
  bool get appMode => Platform.isAndroid && settings.appMode;

  Future<void> loadApps() async {
    if (!Platform.isAndroid || loadingApps) return;
    loadingApps = true;
    notifyListeners();
    try {
      apps = await AndroidTunnel.apps();
    } catch (e) {
      addLog(tr('Не удалось получить список приложений: {0}', [e]));
    } finally {
      loadingApps = false;
      notifyListeners();
    }
  }

  void toggleApp(String package, bool on) {
    on ? enabledApps.add(package) : enabledApps.remove(package);
    notifyListeners();
    unawaited(_save());
    if (status == VpnStatus.off || !appMode || settings.fullTunnel) return;
    _restartTimer?.cancel();
    _restartTimer = Timer(const Duration(milliseconds: 1200), () {
      if (canConnect) {
        connect();
      } else {
        disconnect();
      }
    });
  }

  Future<TunnelStats?> _tunnelStats() =>
      Platform.isAndroid ? AndroidTunnel.stats() : _tunnel.stats();

  Future<void> _tunnelStop() async {
    if (Platform.isAndroid) {
      try {
        await AndroidTunnel.stop();
      } catch (_) {}
    } else {
      await _tunnel.stop();
    }
  }

  SavedServer? get current {
    for (final s in servers) {
      if (s.id == selectedServerId) return s;
    }
    return servers.isEmpty ? null : servers.first;
  }

  ServerProfile? get server => current?.profile;

  /// Есть ли что направлять в туннель.
  bool get canConnect =>
      settings.fullTunnel ||
      (appMode ? enabledApps.isNotEmpty : enabled.isNotEmpty);

  int get enabledRangeCount => collectCidrs(services, enabled).length;

  String get logText => events.join('\n');

  int get builtinDomainCount =>
      builtin.fold(0, (sum, s) => sum + s.domains.length);

  static Future<AppState> load() async {
    final raw = await rootBundle.loadString('assets/services.json');
    final list = (jsonDecode(raw) as Map<String, dynamic>)['services'] as List;
    final services = [
      for (final item in list)
        ServiceEntry.fromJson(item as Map<String, dynamic>),
    ];

    final support = await getApplicationSupportDirectory();
    final sep = Platform.pathSeparator;
    final listsFile = File('${support.path}${sep}services.json');
    // Списки, обновлённые из репозиториев, важнее встроенных.
    DateTime? updatedAt;
    try {
      if (listsFile.existsSync()) {
        final saved =
            jsonDecode(await listsFile.readAsString()) as Map<String, dynamic>;
        final fresh = [
          for (final item in saved['services'] as List)
            ServiceEntry.fromJson(item as Map<String, dynamic>),
        ];
        if (fresh.isNotEmpty) {
          // Заменяем по одному: сервис, появившийся в новой версии
          // приложения, не должен пропасть из-за старого файла.
          final byId = {for (final s in fresh) s.id: s};
          for (var i = 0; i < services.length; i++) {
            final newer = byId.remove(services[i].id);
            if (newer != null) services[i] = newer;
          }
          // Остальное в файле — сервисы, которых в этой версии уже нет.
          updatedAt = DateTime.tryParse('${saved['updatedAt']}');
        }
      }
    } catch (_) {
      // Файл повреждён — остаёмся на встроенных списках.
    }
    final state = AppState._(
      File('${support.path}${sep}state.json'),
      listsFile,
      services,
      Directory('${support.path}${sep}awg'),
    );
    state.listsUpdatedAt = updatedAt;
    await state._read();
    if (SecretStore.supported) {
      final secrets = SecretStore(File('${support.path}${sep}credentials.bin'));
      state._secrets = secrets;
      state.credentials.addAll(await secrets.load());
    }
    state.elevated = await AwgManager.isElevated();
    // Туннель мог остаться от прошлого запуска, если приложение закрыли
    // аварийно: снимаем его, чтобы состояние на экране было честным.
    if (Platform.isWindows && state.elevated) {
      await state._tunnel.removeLegacyTunnel();
      await state._tunnel.stop();
      // И правила DNS, которые создавала прежняя сборка: без работающего
      // приложения они оставляют имена сервисов без ответа.
      await AwgManager.clearDomainRules();
    }
    if (Platform.isAndroid && await AndroidTunnel.isUp()) {
      // На Android туннель живёт дольше окна приложения: если он поднят,
      // показываем это честно.
      state.status = VpnStatus.on;
      state._startStats();
    }
    if (Platform.isWindows) {
      state.autostart = await _autostartEnabled();
      // Задача автозапуска от прежней сборки запускала приложение с окном —
      // пересоздаём её, чтобы оно стартовало свёрнутым в трей.
      if (state.autostart && state.elevated && await _autostartOutdated()) {
        await state.setAutostart(true);
      }
    }
    return state;
  }

  void _rebuildServices() {
    final base = {for (final s in builtin) s.id: s};
    services = [for (final r in resources) r.toService(base[r.id])];
  }

  /// Раздел, куда попадает ресурс, оставшийся без своего.
  String _fallbackSection() {
    if (sections.isEmpty) {
      sections.add(Section(id: otherGroupId, name: 'Прочее', icon: 'globe'));
    }
    return sections.any((s) => s.id == otherGroupId)
        ? otherGroupId
        : sections.last.id;
  }

  /// Добавляет ресурсы для сервисов каталога, которых ещё нет в разделах
  /// (первый запуск, новый сервис в каталоге), и пристраивает ресурсы,
  /// раздел которых пропал.
  void _addMissing() {
    bool exists(String id) => sections.any((s) => s.id == id);
    for (final r in resources) {
      if (!exists(r.section)) r.section = _fallbackSection();
    }
    final have = {for (final r in resources) r.id};
    final home = {
      for (final g in serviceGroups)
        for (final id in g.serviceIds) id: g.id,
    };
    final ordered = [
      for (final id in home.keys) ...builtin.where((s) => s.id == id),
      ...builtin.where((s) => !home.containsKey(s.id)),
    ];
    // Раздел, появившийся в новой версии приложения (ни одного его ресурса
    // у пользователя ещё не было), добавляется вместе с ресурсами.
    for (final g in serviceGroups) {
      if (exists(g.id) ||
          g.serviceIds.any((id) => have.contains(id) || deleted.contains(id)) ||
          !g.serviceIds.any((id) => builtin.any((s) => s.id == id))) {
        continue;
      }
      sections.add(Section(id: g.id, name: g.label, icon: g.icon));
    }
    for (final s in ordered) {
      if (have.contains(s.id) || deleted.contains(s.id)) continue;
      final section = home[s.id] ?? otherGroupId;
      resources.add(Resource(
        id: s.id,
        name: s.name,
        section: exists(section) ? section : _fallbackSection(),
      ));
    }
  }

  Future<void> _read() async {
    if (!_stateFile.existsSync()) return;
    try {
      _apply(
        jsonDecode(await _stateFile.readAsString()) as Map<String, dynamic>,
      );
    } catch (e) {
      addLog(tr('Не удалось прочитать сохранённые настройки: {0}', [e]));
      _apply(const {});
    }
  }

  /// Заменяет всё состояние приложения тем, что записано в [json].
  void _apply(Map<String, dynamic> json) {
    sections.clear();
    resources.clear();
    deleted.clear();
    enabled.clear();
    enabledApps.clear();
    _learned.clear();
    servers.clear();
    enabledApps.addAll((json['apps'] as List? ?? const []).cast<String>());

    if (json['sections'] is List) {
      for (final item in json['sections'] as List) {
        sections.add(Section.fromJson(item as Map<String, dynamic>));
      }
      for (final item in json['resources'] as List? ?? const []) {
        resources.add(Resource.fromJson(item as Map<String, dynamic>));
      }
      deleted.addAll((json['deleted'] as List? ?? const []).cast<String>());
    } else {
      // Первый запуск или настройки прежней сборки: начальный набор
      // разделов в сохранённом порядке, свои маршруты — отдельным разделом.
      for (final item in json['customRoutes'] as List? ?? const []) {
        resources.add(Resource.fromJson(item as Map<String, dynamic>)
          ..section = customGroupId);
      }
      final groups = [
        for (final g in serviceGroups)
          Section(id: g.id, name: g.label, icon: g.icon),
        if (resources.isNotEmpty)
          Section(id: customGroupId, name: 'Мои маршруты', icon: 'route'),
      ];
      final order = (json['groupOrder'] as List? ?? const []).cast<String>();
      sections
        ..addAll([
          for (final id in order) ...groups.where((g) => g.id == id),
        ])
        ..addAll(groups.where((g) => !order.contains(g.id)));
    }
    resources.removeWhere((r) => retiredServices.contains(r.id));
    _addMissing();
    _rebuildServices();

    final known = {for (final s in services) s.id};
    enabled.addAll(
      (json['enabled'] as List? ?? const [])
          .cast<String>()
          .where(known.contains),
    );
    final learned = json['learned'];
    if (learned is Map<String, dynamic>) {
      learned.forEach((ip, name) => _learned[ip] = '$name');
    }

    for (final item in json['servers'] as List? ?? const []) {
      servers.add(SavedServer.fromJson(item as Map<String, dynamic>));
    }
    // Прежние сборки хранили один сервер в поле `server`.
    final old = json['server'];
    if (servers.isEmpty &&
        old is Map<String, dynamic> &&
        old['clientPrivateKey'] is String) {
      servers.add(SavedServer(
        id: _newId('srv'),
        name: tr('Основной'),
        profile: ServerProfile.fromJson(old),
      ));
    }
    selectedServerId = json['selectedServer'] as String?;

    final saved = json['settings'];
    final s = saved is Map<String, dynamic>
        ? AppSettings.fromJson(saved)
        : AppSettings();
    settings
      ..connectOnStart = s.connectOnStart
      ..wasOn = s.wasOn
      ..domainRouting = s.domainRouting
      ..ipv4Only = s.ipv4Only
      ..fullTunnel = s.fullTunnel
      ..appMode = s.appMode
      ..closeToTray = s.closeToTray
      ..startInTray = s.startInTray
      ..language = s.language
      ..browserKey = s.browserKey
      ..autoUpdateLists = s.autoUpdateLists
      ..dns = s.dns;
    // Пустое значение — язык ещё не выбирали: берётся язык системы.
    appLang = settings.language.isEmpty ? systemLang() : settings.language;
  }

  Map<String, dynamic> _snapshot({bool withLearned = true}) => {
        'enabled': enabled.toList(),
        'servers': [for (final s in servers) s.toJson()],
        'selectedServer': selectedServerId,
        'sections': [for (final s in sections) s.toJson()],
        'resources': [for (final r in resources) r.toJson()],
        'deleted': deleted.toList(),
        'apps': enabledApps.toList(),
        'settings': settings.toJson(),
        if (withLearned) 'learned': _learned,
      };

  Future<void> _save() async {
    try {
      await _stateFile.parent.create(recursive: true);
      await _stateFile.writeAsString(jsonEncode(_snapshot()));
    } catch (e) {
      debugPrint(tr('Не удалось сохранить настройки: {0}', [e]));
    }
  }

  // -------------------------------------------------- перенос и сброс

  /// Текст файла настроек для переноса на другое устройство. В нём есть
  /// ключи серверов, поэтому файл нужно хранить как пароль.
  String exportSettings() => const JsonEncoder.withIndent(' ').convert({
        'app': 'ColdVPN',
        ..._snapshot(withLearned: false),
      });

  /// Заменяет настройки содержимым файла, сохранённого [exportSettings].
  /// Возвращает текст ошибки или null, если всё получилось.
  Future<String?> importSettings(String text) async {
    Object? json;
    try {
      json = jsonDecode(text);
    } catch (_) {
      return tr('Это не файл настроек ColdVPN.');
    }
    if (json is! Map<String, dynamic> ||
        json['app'] != 'ColdVPN' ||
        json['servers'] is! List) {
      return tr('Это не файл настроек ColdVPN.');
    }
    if (status != VpnStatus.off) await disconnect();
    final backup = _snapshot();
    try {
      _apply(json);
    } catch (e) {
      // Файл оказался испорчен на середине — возвращаем то, что было.
      _apply(backup);
      notifyListeners();
      return tr('Файл настроек повреждён: {0}', [e]);
    }
    settings.wasOn = false;
    await _save();
    addLog(tr('Настройки загружены из файла: серверов {0}, '
        'разделов {1}, ресурсов {2}.', [servers.length, sections.length, resources.length]));
    return null;
  }

  /// Возвращает приложение к начальному состоянию. Серверы при этом
  /// остаются настроенными — удаляются только записи о них.
  Future<void> resetAll() async {
    if (status != VpnStatus.off) await disconnect();
    _apply(const {});
    credentials.clear();
    _memoryOnly.clear();
    await _saveSecrets();
    await _save();
    addLog(tr('Настройки сброшены.'));
  }

  // ------------------------------------------------------ списки сервисов

  /// Обновляет списки сервисов из репозиториев. Сервис, для которого
  /// ничего не скачалось, остаётся с прежним списком.
  /// Возвращает короткий итог для показа пользователю.
  Future<String> updateLists() async {
    if (updatingLists) return tr('Обновление уже идёт');
    updatingLists = true;
    notifyListeners();
    try {
      final selection = jsonDecode(
        await rootBundle.loadString('assets/selection.json'),
      ) as Map<String, dynamic>;
      final update = await downloadServices(selection);
      for (final problem in update.problems) {
        addLog(tr('Списки: {0}', [problem]));
      }
      if (update.services.isEmpty) {
        throw tr('из репозиториев не удалось собрать ни одного сервиса');
      }
      final fresh = {for (final s in update.services) s.id: s};
      var changed = 0;
      for (var i = 0; i < builtin.length; i++) {
        final old = builtin[i];
        final now = fresh.remove(old.id);
        // Новый список без адресов при непустом старом — признак сбоя в
        // источнике, а не того, что у сервиса не осталось адресов.
        if (now == null || (now.ips.isEmpty && old.ips.isNotEmpty)) continue;
        if (now.ips.length != old.ips.length ||
            now.domains.length != old.domains.length ||
            now.ips.join() != old.ips.join() ||
            now.domains.join() != old.domains.join()) {
          changed++;
        }
        builtin[i] = now;
      }
      builtin.addAll(fresh.values);
      changed += fresh.length;
      listsUpdatedAt = DateTime.now();
      await _listsFile.parent.create(recursive: true);
      await _listsFile.writeAsString(jsonEncode({
        'updatedAt': listsUpdatedAt!.toIso8601String(),
        'services': [for (final s in builtin) s.toJson()],
      }));
      _addMissing();
      _rebuildServices();
      unawaited(_save());
      final summary = changed == 0
          ? tr('Списки актуальны, изменений нет')
          : tr('Списки обновлены, изменилось сервисов: {0}', [changed]);
      addLog('$summary.');
      if (changed > 0 &&
          status != VpnStatus.off &&
          !settings.fullTunnel &&
          !appMode) {
        unawaited(connect());
      }
      return summary;
    } catch (e) {
      addLog(tr('Не удалось обновить списки сервисов: {0}', [e]));
      return tr('Не удалось обновить списки. Подробности в журнале');
    } finally {
      updatingLists = false;
      notifyListeners();
    }
  }

  /// Вызывается после запуска: раз в неделю обновляет списки сам.
  void autoUpdateLists() {
    if (!settings.autoUpdateLists) return;
    final last = listsUpdatedAt;
    if (last != null && DateTime.now().difference(last).inDays < 7) return;
    // Даём приложению и сети время на запуск и подключение.
    Timer(const Duration(seconds: 30), () {
      if (!updatingLists) unawaited(updateLists());
    });
  }

  String _newId(String prefix) =>
      '$prefix-${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';

  // ---------------------------------------------------------------- журнал

  static String _clock() {
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(now.hour)}:${two(now.minute)}:${two(now.second)}';
  }

  static LogKind _kindOf(String line) {
    final low = line.toLowerCase();
    // Записи журнала бывают на обоих языках, признаки — тоже.
    if (line.startsWith('По домену') || line.startsWith('By domain')) {
      return LogKind.route;
    }
    const bad = [
      'не удалось', 'ошибка', 'внимание', 'не прошл', 'не ответил', //
      'недоступн', 'не пройдена', 'не разрешилось', 'прервалась',
      'could not', 'error', 'warning', 'failed', 'did not respond', //
      'unavailable', 'not passed', 'interrupted',
    ];
    if (bad.any(low.contains)) return LogKind.warn;
    if (line.startsWith('Подключено') ||
        line.startsWith('Рукопожатие') ||
        low.contains('пройдена') ||
        low.contains('настроен') ||
        line.startsWith('Connected') ||
        line.startsWith('Handshake') ||
        low.contains('passed') ||
        low.contains('configured')) {
      return LogKind.ok;
    }
    return LogKind.info;
  }

  void addLog(String line) {
    final time = _clock();
    events.add('$time  $line');
    // Подробности по каждому запросу DNS — только в полном журнале.
    if (!line.startsWith('DNS: ')) {
      feed.add(LogEvent(time, _kindOf(line), line));
      if (feed.length > 300) feed.removeRange(0, feed.length - 300);
    }
    _trim();
    notifyListeners();
  }

  void _addBlock(String title, List<String> lines) {
    events.add('--- $title ---');
    events.addAll(lines);
    events.add(tr('--- конец: {0} ---', [title]));
    _trim();
    notifyListeners();
  }

  void _trim() {
    if (events.length > 800) events.removeRange(0, events.length - 800);
  }

  // --------------------------------------------------------------- серверы

  /// Добавляет сервер и делает его выбранным.
  Future<SavedServer> addServer(ServerProfile profile, {String? name}) async {
    if (status != VpnStatus.off) await disconnect();
    final entry = SavedServer(
      id: _newId('srv'),
      name: (name == null || name.trim().isEmpty)
          ? (servers.isEmpty ? tr('Основной') : tr('Сервер {0}', [servers.length + 1]))
          : name.trim(),
      profile: profile,
    );
    servers.add(entry);
    selectedServerId = entry.id;
    await _save();
    notifyListeners();
    unawaited(_lookupLocation(entry.id));
    return entry;
  }

  /// Заменяет данные подключения у сервера с тем же адресом (повторная
  /// установка) или добавляет новый.
  Future<SavedServer> addOrReplaceServer(ServerProfile profile) async {
    final index = servers.indexWhere((s) => s.profile.host == profile.host);
    if (index < 0) return addServer(profile);
    if (status != VpnStatus.off) await disconnect();
    final old = servers[index];
    final entry = SavedServer(
      id: old.id,
      name: old.name,
      profile: profile,
      country: old.country,
      city: old.city,
      countryCode: old.countryCode,
    );
    servers[index] = entry;
    selectedServerId = entry.id;
    await _save();
    notifyListeners();
    return entry;
  }

  Future<void> selectServer(String id) async {
    if (id == current?.id) return;
    final wasOn = status != VpnStatus.off;
    selectedServerId = id;
    if (wasOn) {
      await disconnect(remember: false);
    } else if (browserOn) {
      // Туннель для браузера переезжает на новый сервер.
      await _closeBrowserPath();
      browserStatus = VpnStatus.off;
      unawaited(_resumeBrowser());
    }
    await _save();
    notifyListeners();
    if (wasOn && canConnect) unawaited(connect());
  }

  Future<void> updateServer(
    String id, {
    required String name,
    required String country,
    required String city,
  }) async {
    final index = servers.indexWhere((s) => s.id == id);
    if (index < 0) return;
    final old = servers[index];
    servers[index] = old.copyWith(
      name: name.trim().isEmpty ? old.name : name.trim(),
      country: country.trim(),
      city: city.trim(),
      // Код страны относится к найденной стране: если её поменяли вручную,
      // он больше не подходит.
      countryCode: country.trim() == old.country ? old.countryCode : '',
    );
    await _save();
    notifyListeners();
  }

  Future<void> deleteServer(String id) async {
    final wasCurrent = current?.id == id;
    if (wasCurrent && status != VpnStatus.off) await disconnect();
    final removed = servers.where((s) => s.id == id).toList();
    servers.removeWhere((s) => s.id == id);
    // Пароль удалённого сервера больше не нужен.
    for (final s in removed) {
      if (!servers.any((other) => other.profile.host == s.profile.host) &&
          credentials.remove(s.profile.host) != null) {
        await _saveSecrets();
      }
    }
    if (wasCurrent) {
      selectedServerId = servers.isEmpty ? null : servers.first.id;
    }
    await _save();
    notifyListeners();
  }

  /// Конфиг сервера для передачи на другое устройство или другу.
  String exportConf(SavedServer entry) => _shareConf(entry.profile);

  String _shareConf(ServerProfile profile) =>
      buildClientConf(profile, const ['0.0.0.0/0'], dns: '1.1.1.1');

  /// Есть ли данные для входа на сервер — с ними можно выпустить отдельный
  /// ключ.
  bool canIssueKey(SavedServer entry) =>
      credentials.containsKey(entry.profile.host);

  /// Выпускает на сервере ключ для ещё одного устройства и возвращает
  /// готовый конфиг. С ним можно подключаться одновременно с этим
  /// устройством.
  Future<String> issueDeviceConf(SavedServer entry) async {
    final creds = credentials[entry.profile.host];
    if (creds == null) throw tr('Нет данных для входа на сервер.');
    final device =
        'shared-${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}';
    final profile = await installServer(
      InstallRequest(
        host: creds.host,
        sshPort: creds.sshPort,
        username: creds.username,
        password: creds.password,
        privateKeyPem: creds.privateKeyPem,
        vpnPort: entry.profile.port,
        device: device,
      ),
      (_) {},
    );
    addLog(tr('На сервере {0} выпущен отдельный ключ '
        '«{1}» для другого устройства.', [entry.profile.host, device]));
    return _shareConf(profile);
  }

  /// Узнаёт страну и город сервера по его адресу. Один запрос к открытому
  /// сервису ip-api.com; если он не ответил, место остаётся пустым и его
  /// можно вписать вручную.
  Future<void> _lookupLocation(String id) async {
    final index = servers.indexWhere((s) => s.id == id);
    if (index < 0) return;
    final host = servers[index].profile.host;
    final http = HttpClient()..connectionTimeout = const Duration(seconds: 6);
    try {
      final request = await http.getUrl(Uri.parse(
        'http://ip-api.com/json/$host?fields=status,country,countryCode,city'
        '&lang=$appLang',
      ));
      final response = await request.close().timeout(const Duration(seconds: 6));
      final body = await response
          .transform(const Utf8Decoder(allowMalformed: true))
          .join()
          .timeout(const Duration(seconds: 6));
      final json = jsonDecode(body);
      if (json is! Map<String, dynamic> || json['status'] != 'success') return;
      final now = servers.indexWhere((s) => s.id == id);
      if (now < 0) return;
      servers[now] = servers[now].copyWith(
        country: '${json['country'] ?? ''}',
        city: '${json['city'] ?? ''}',
        countryCode: '${json['countryCode'] ?? ''}',
      );
      await _save();
      notifyListeners();
    } catch (_) {
      // Не страшно: место можно указать вручную.
    } finally {
      http.close(force: true);
    }
  }

  // ------------------------------------------------------ сервисы и группы

  void toggleService(String id, bool on) {
    on ? enabled.add(id) : enabled.remove(id);
    _afterSelectionChange();
  }

  void setMany(Iterable<String> ids, bool on) {
    on ? enabled.addAll(ids) : enabled.removeAll(ids.toSet());
    _afterSelectionChange();
  }

  /// Ресурсы раздела в том порядке, в каком они показаны.
  List<ServiceEntry> servicesOf(String sectionId) {
    final ids = {
      for (final r in resources)
        if (r.section == sectionId) r.id,
    };
    return [
      for (final s in services)
        if (ids.contains(s.id)) s,
    ];
  }

  /// Раздел, в котором лежит ресурс.
  Section? sectionOf(String resourceId) {
    for (final r in resources) {
      if (r.id != resourceId) continue;
      for (final s in sections) {
        if (s.id == r.section) return s;
      }
    }
    return null;
  }

  void moveGroup(int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex--;
    final section = sections.removeAt(oldIndex);
    sections.insert(newIndex.clamp(0, sections.length).toInt(), section);
    notifyListeners();
    unawaited(_save());
  }

  /// Создаёт раздел ([id] == null) или меняет его название и значок.
  /// Возвращает идентификатор раздела.
  String saveSection({String? id, required String name, required String icon}) {
    final title = name.trim().isEmpty ? tr('Новый раздел') : name.trim();
    var sid = id;
    if (sid == null) {
      sid = _newId('sec');
      sections.add(Section(id: sid, name: title, icon: icon));
    } else {
      for (final s in sections) {
        if (s.id != sid) continue;
        // Стандартное название показано в переводе: если его не меняли,
        // оно остаётся исходным и продолжает переводиться.
        if (title != s.title) s.name = title;
        s.icon = icon;
      }
    }
    notifyListeners();
    unawaited(_save());
    return sid;
  }

  /// Удаляет раздел. Его ресурсы переезжают в [moveTo], а если он не
  /// задан — удаляются вместе с разделом.
  void deleteSection(String id, {String? moveTo}) {
    for (final r in resources.where((r) => r.section == id).toList()) {
      if (moveTo != null) {
        r.section = moveTo;
      } else {
        _forget(r);
      }
    }
    sections.removeWhere((s) => s.id == id);
    _rebuildServices();
    _afterSelectionChange();
  }

  /// Перетаскивание: ставит ресурс в раздел [sectionId] перед ресурсом
  /// [before], а если он не задан — в конец раздела.
  void placeResource(String id, String sectionId, {String? before}) {
    if (id == before) return;
    final from = resources.indexWhere((r) => r.id == id);
    if (from < 0 || !sections.any((s) => s.id == sectionId)) return;
    final resource = resources.removeAt(from)..section = sectionId;
    final at =
        before == null ? -1 : resources.indexWhere((r) => r.id == before);
    // Порядок в разделе — порядок в общем списке, поэтому «в конец
    // раздела» значит в конец списка.
    if (at < 0) {
      resources.add(resource);
    } else {
      resources.insert(at, resource);
    }
    _rebuildServices();
    notifyListeners();
    unawaited(_save());
  }

  /// Сохраняет ресурс: новый ([id] == null) или изменённый. [lines] — весь
  /// его список так, как он остался в поле ввода.
  void saveResource({
    String? id,
    required String name,
    required String section,
    required List<RouteLine> lines,
    bool enable = false,
  }) {
    final rid = id ?? _newId('custom');
    var domains = [
      for (final l in lines)
        if (l.kind == RouteLineKind.domain) l.value,
    ];
    var ips = [
      for (final l in lines)
        if (l.kind == RouteLineKind.network)
          l.value
        else if (l.kind == RouteLineKind.address)
          '${l.value}/32',
    ];
    var removed = const <String>[];
    // У ресурса из каталога запоминаем только отличия от каталога: тогда
    // обновление списков не затирает правки и не теряется само.
    final at = builtin.indexWhere((s) => s.id == rid);
    if (at >= 0) {
      final base = {...builtin[at].domains, ...builtin[at].ips};
      final kept = {...domains, ...ips};
      removed = [
        for (final v in base)
          if (!kept.contains(v)) v,
      ];
      domains = [
        for (final v in domains)
          if (!base.contains(v)) v,
      ];
      ips = [
        for (final v in ips)
          if (!base.contains(v)) v,
      ];
    }
    final resource = Resource(
      id: rid,
      name: name.trim(),
      section: section,
      domains: domains,
      ips: ips,
      removed: removed,
    );
    final index = resources.indexWhere((r) => r.id == rid);
    if (index < 0) {
      resources.add(resource);
      if (enable) enabled.add(rid);
    } else if (resources[index].section == section) {
      resources[index] = resource;
    } else {
      resources
        ..removeAt(index)
        ..add(resource);
    }
    _rebuildServices();
    _afterSelectionChange();
  }

  void deleteResource(String id) {
    for (final r in resources.where((r) => r.id == id).toList()) {
      _forget(r);
    }
    _rebuildServices();
    _afterSelectionChange();
  }

  void _forget(Resource r) {
    resources.remove(r);
    enabled.remove(r.id);
    if (builtin.any((s) => s.id == r.id)) deleted.add(r.id);
  }

  /// Возвращает удалённые разделы и ресурсы начального набора. То, что
  /// пользователь создал или изменил сам, остаётся как есть.
  void restoreDefaults() {
    deleted.clear();
    for (final g in serviceGroups) {
      if (sections.any((s) => s.id == g.id)) continue;
      sections.add(Section(id: g.id, name: g.label, icon: g.icon));
    }
    _addMissing();
    _rebuildServices();
    _afterSelectionChange();
  }

  void _afterSelectionChange() {
    notifyListeners();
    unawaited(_save());
    // Когда через VPN идёт весь трафик, переключатели сервисов на туннель
    // не влияют.
    if (status == VpnStatus.off || settings.fullTunnel || appMode) return;
    // Несколько переключений подряд применяются одним переподключением.
    _restartTimer?.cancel();
    _restartTimer = Timer(const Duration(milliseconds: 1200), () {
      if (enabled.isEmpty) {
        disconnect();
      } else {
        connect();
      }
    });
  }

  // ------------------------------------------------------------- настройки

  /// Меняет настройку и, если VPN включён, переподключается с новой.
  /// Меняет язык интерфейса: `ru` или `en`.
  void setLanguage(String code) {
    settings.language = code;
    appLang = code;
    notifyListeners();
    unawaited(_save());
  }

  void changeSettings(void Function(AppSettings s) change,
      {bool reconnect = true}) {
    change(settings);
    notifyListeners();
    unawaited(_save());
    if (reconnect && status != VpnStatus.off) {
      _restartTimer?.cancel();
      _restartTimer = Timer(const Duration(milliseconds: 1200), () {
        if (canConnect) {
          connect();
        } else {
          disconnect();
        }
      });
    }
  }

  static Future<bool> _autostartEnabled() async {
    try {
      final result =
          await Process.run('schtasks', ['/Query', '/TN', _autostartTask]);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  /// Создана ли задача автозапуска прежней сборкой (без ключа --hidden).
  static Future<bool> _autostartOutdated() async {
    try {
      final result = await Process.run(
        'schtasks',
        ['/Query', '/TN', _autostartTask, '/XML'],
      );
      if (result.exitCode != 0) return false;
      final task = '${result.stdout}'.toLowerCase();
      // Устарела и задача, которая запускает программу из другого места:
      // например, из папки сборки после установки приложения.
      return !task.contains('--hidden') ||
          !task.contains(Platform.resolvedExecutable.toLowerCase());
    } catch (_) {
      return false;
    }
  }

  /// Автозапуск через планировщик Windows: только так приложение может
  /// стартовать с правами администратора без запроса при каждом входе.
  Future<void> setAutostart(bool on) async {
    try {
      final result = on
          ? await Process.run('schtasks', [
              '/Create', '/TN', _autostartTask, '/TR', //
              // Ключ --hidden: при автозапуске окно не показывается, приложение
              // сразу уходит в трей.
              '"${Platform.resolvedExecutable}" --hidden',
              '/SC', 'ONLOGON', '/RL', 'HIGHEST', '/F',
            ])
          : await Process.run(
              'schtasks',
              ['/Delete', '/TN', _autostartTask, '/F'],
            );
      if (result.exitCode != 0) {
        addLog(tr('Не удалось изменить автозапуск: '
            '{0}', ['${result.stdout}${result.stderr}'.trim()]));
      } else if (on) {
        // По умолчанию планировщик не запускает задачу от батареи,
        // останавливает её при отключении от сети и через трое суток.
        // Для VPN на ноутбуке всё это нужно отключить.
        await Process.run('powershell', [
          '-NoProfile',
          '-Command',
          "Set-ScheduledTask -TaskName '$_autostartTask' -Settings "
              '(New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries '
              '-DontStopIfGoingOnBatteries '
              '-ExecutionTimeLimit ([TimeSpan]::Zero))',
        ]).timeout(const Duration(seconds: 30));
      }
    } catch (e) {
      addLog(tr('Не удалось изменить автозапуск: {0}', [e]));
    }
    autostart = await _autostartEnabled();
    notifyListeners();
  }

  /// Вызывается один раз после запуска приложения.
  void autoConnect() {
    if (status == VpnStatus.off &&
        settings.connectOnStart &&
        settings.wasOn &&
        server != null &&
        canConnect &&
        platformSupported &&
        elevated) {
      unawaited(connect());
    }
  }

  // ----------------------------------------------------------- подключение

  bool _validDns(String value) =>
      RegExp(r'^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$').hasMatch(value);

  Future<void> connect() async {
    final profile = server;
    if (profile == null) {
      _fail(tr('Сначала добавьте сервер на вкладке «Сервер».'));
      return;
    }
    final full = settings.fullTunnel;
    if (!canConnect) {
      _fail(appMode
          ? tr('Включите хотя бы одно приложение.')
          : tr('Включите хотя бы один сервис.'));
      return;
    }
    if (!platformSupported) {
      _fail(tr('Подключение на этой платформе пока не реализовано.'));
      return;
    }
    if (!elevated) {
      _fail(tr('Запустите приложение от имени администратора.'));
      return;
    }
    if (Platform.isAndroid) return _connectAndroid(profile);

    final run = ++_run;
    status = VpnStatus.connecting;
    error = null;
    if (browserOn) browserStatus = VpnStatus.connecting;
    notifyListeners();
    try {
      await _tunnel.ensureInstalled();
      if (run != _run) return;
      await _stopDomainRouting();

      final active = services.where((s) => enabled.contains(s.id)).toList();
      final matcher = settings.domainRouting && !full
          ? DomainMatcher(
              active.expand((s) => s.domains),
              active.expand((s) => s.keywords),
            )
          : DomainMatcher(const [], const []);
      final tunnelDns = _validDns(settings.dns) ? settings.dns : probeAddress;
      // Весь трафик: две половины адресного пространства вместо 0.0.0.0/0,
      // иначе клиент AmneziaWG включает блокировку всего, что идёт мимо
      // туннеля, и пропадает доступ к локальной сети.
      final ranges = full
          ? {'0.0.0.0/1', '128.0.0.0/1'}
          : collectCidrs(services, enabled);
      _staticRanges = CidrSet(ranges);
      // Адреса, найденные по доменам раньше, сразу возвращаем в туннель —
      // но только те, чьи сервисы сейчас включены.
      _routed
        ..clear()
        ..addAll(_learned.entries
            .where((e) => matcher.matches(e.value) && _routable(e.key, profile))
            .map((e) => e.key));
      _activeCidrs = {
        ...ranges,
        '$tunnelDns/32',
        for (final ip in _routed) '$ip/32',
      };

      // DNS-посредник поднимаем до туннеля: его адрес идёт в конфиг.
      // Когда в туннель идёт весь трафик, посредник не нужен: имена
      // спрашиваются прямо у DNS-сервера через туннель.
      String? dnsAddress = full ? tunnelDns : null;
      if (!matcher.isEmpty) {
        final proxy = DnsProxy(
          matcher: matcher,
          directUpstreams: await AwgManager.systemDnsServers(),
          tunnelUpstream: tunnelDns,
          onAddresses: (name, addresses) =>
              _routeByDomain(profile, name, addresses),
          log: addLog,
          ipv4Only: settings.ipv4Only,
        );
        try {
          await proxy.start();
          _dns = proxy;
          dnsAddress = DnsProxy.listenAddress;
          addLog(tr('Маршрутизация по доменам включена, обычный DNS: '
              '{0}.', [proxy.directUpstreams.join(', ')]));
        } catch (e) {
          addLog(tr('Маршрутизация по доменам недоступна (не удалось занять '
              '{0}:53): {1}. Работают только списки IP.', [DnsProxy.listenAddress, e]));
        }
      }
      if (run != _run) {
        // Отменили, пока поднимался посредник: он не должен остаться в фоне.
        if (status == VpnStatus.off) await _stopDomainRouting();
        return;
      }

      addLog(full
          ? tr('Поднимаю туннель AmneziaWG к {0}:{1} '
              '(весь трафик)…', [profile.host, profile.port])
          : tr('Поднимаю туннель AmneziaWG к {0}:{1} '
              '(диапазонов: {2}, адресов по доменам: '
              '{3})…', [profile.host, profile.port, ranges.length, _routed.length]));
      await _tunnel.start(
        buildClientConf(profile, _activeCidrs, dns: dnsAddress),
      );
      if (run != _run) {
        // Отменили во время запуска: туннель не должен остаться в фоне.
        if (status == VpnStatus.off) {
          await _stopDomainRouting();
          await _tunnel.stop();
        }
        return;
      }

      final shaken = await _tunnel.waitForHandshake(const Duration(seconds: 15));
      if (run != _run) return;
      if (!shaken) {
        _addBlock(tr('журнал клиента AmneziaWG'), await _tunnel.clientLog());
        await _stopDomainRouting();
        await _tunnel.stop();
        _fail(tr('Сервер не ответил на рукопожатие. Проверьте, что UDP-порт '
            '{0} открыт в файрволе хостинга. Подробности в журнале.', [profile.port]));
        return;
      }
      addLog(tr('Рукопожатие с сервером выполнено.'));
      if (full) await _tunnel.preferTunnelDns();
      final dnsProxy = _dns;
      if (dnsProxy != null) {
        await _tunnel.preferTunnelDns();
        // Ответы с адреса 127.66.77.1 Windows, судя по повторным запросам,
        // принимает не всегда. Поэтому посредник слушает ещё и на
        // собственном адресе компьютера в туннеле, и этот адрес ставится
        // первым; прежний остаётся запасным.
        if (await dnsProxy.listenAlso(profile.clientAddress)) {
          await _tunnel.setTunnelDns(
            [profile.clientAddress, DnsProxy.listenAddress],
          );
        } else {
          addLog(tr('DNS-посредник не смог занять {0}:53, '
              'остаётся прежний адрес.', [profile.clientAddress]));
        }
        if (run != _run) return;
        // Клиент AmneziaWG при смене сети заново выставляет маршруты только
        // из конфига, поэтому найденные по доменам периодически возвращаем.
        _routeKeeper = Timer.periodic(const Duration(seconds: 90), (_) {
          if (_routed.isEmpty) return;
          _enqueueRoutes(profile, _routed.toList());
        });
      }

      final address = await _probe();
      if (run != _run) return;
      status = VpnStatus.on;
      exitAddress = address;
      settings.wasOn = true;
      unawaited(_save());
      _startStats();
      if (browserOn) await _openBrowserPath(profile);
      if (address == null) {
        error = tr('Туннель поднят, но проверочный запрос через него не прошёл. '
            'Сайты могут не открываться — запустите диагностику в журнале.');
        addLog(error!);
      } else {
        addLog(tr('Подключено. Сайты видят вас под адресом {0}.', [address]));
      }
      notifyListeners();
    } catch (e) {
      if (run != _run) return;
      await _stopDomainRouting();
      await _tunnel.stop();
      _fail('$e');
    }
  }

  /// Подключение на Android. Маршруты задаются сразу при создании туннеля:
  /// либо диапазоны включённых сервисов, либо всё — для выбранных
  /// приложений или для всего телефона. Маршрутов по доменам здесь нет.
  Future<void> _connectAndroid(ServerProfile profile) async {
    final run = ++_run;
    status = VpnStatus.connecting;
    error = null;
    notifyListeners();
    try {
      final full = settings.fullTunnel;
      final byApps = !full && appMode;
      final tunnelDns = _validDns(settings.dns) ? settings.dns : probeAddress;
      final ranges = collectCidrs(services, enabled).map(alignCidr).toSet();
      _routed.clear();
      if (full || byApps) {
        // Один маршрут «всё»: тогда Android не выпускает трафик этих
        // приложений мимо VPN и по IPv6.
        _staticRanges = CidrSet(const ['0.0.0.0/0']);
        _activeCidrs = {'0.0.0.0/0'};
      } else {
        _staticRanges = CidrSet(ranges);
        _activeCidrs = {...ranges, '$tunnelDns/32'};
      }

      if (!await AndroidTunnel.prepare()) {
        if (run != _run) return;
        _fail(tr('Разрешите приложению создавать VPN-подключение и попробуйте '
            'снова.'));
        return;
      }
      if (run != _run) return;

      addLog(full
          ? tr('Поднимаю туннель AmneziaWG к {0}:{1} '
              '(весь трафик)…', [profile.host, profile.port])
          : byApps
              ? tr('Поднимаю туннель AmneziaWG к {0}:{1} '
                  '(приложений: {2})…', [profile.host, profile.port, enabledApps.length])
              : tr('Поднимаю туннель AmneziaWG к {0}:'
                  '{1} (диапазонов: {2})…', [profile.host, profile.port, ranges.length]));
      // Удалённое с телефона приложение Android в список не примет.
      if (byApps && apps.isEmpty) await loadApps();
      if (run != _run) return;
      final installed = {for (final a in apps) a.package};
      final included = [
        for (final p in enabledApps)
          if (installed.isEmpty || installed.contains(p)) p,
      ]..sort();
      if (byApps && included.isEmpty) {
        _fail(tr('Выбранные приложения не установлены на этом телефоне.'));
        return;
      }
      await AndroidTunnel.start(buildClientConf(
        profile,
        _activeCidrs,
        dns: tunnelDns,
        includedApps: byApps ? included : const [],
        androidOnly: true,
      ));
      if (run != _run) {
        // Отменили во время запуска: туннель не должен остаться в фоне.
        if (status == VpnStatus.off) await _tunnelStop();
        return;
      }

      var shaken = false;
      final deadline = DateTime.now().add(const Duration(seconds: 15));
      while (DateTime.now().isBefore(deadline)) {
        final current = await AndroidTunnel.stats();
        if (run != _run) return;
        if (current?.lastHandshake != null) {
          shaken = true;
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 700));
      }
      if (run != _run) return;
      if (!shaken) {
        await _tunnelStop();
        _fail(tr('Сервер не ответил на рукопожатие. Проверьте, что сервер '
            'включён и UDP-порт {0} открыт в файрволе хостинга.', [profile.port]));
        return;
      }
      addLog(tr('Рукопожатие с сервером выполнено.'));

      // В режиме «по приложениям» само ColdVPN идёт мимо туннеля, поэтому
      // проверочный запрос ничего бы не показал.
      final address = byApps ? null : await _probe();
      if (run != _run) return;
      status = VpnStatus.on;
      exitAddress = address;
      settings.wasOn = true;
      unawaited(_save());
      _startStats();
      if (byApps) {
        addLog(tr('Подключено. Через VPN идут выбранные приложения.'));
      } else if (address == null) {
        error = tr('Туннель поднят, но проверочный запрос через него не прошёл. '
            'Сайты могут не открываться — запустите диагностику в журнале.');
        addLog(error!);
      } else {
        addLog(tr('Подключено. Сайты видят вас под адресом {0}.', [address]));
      }
      notifyListeners();
    } on PlatformException catch (e) {
      if (run != _run) return;
      await _tunnelStop();
      _fail(tr('Не удалось поднять туннель: {0}', [trLoose(e.message ?? e.code)]));
    } catch (e) {
      if (run != _run) return;
      await _tunnelStop();
      _fail('$e');
    }
  }

  /// Годится ли адрес из ответа DNS для отправки в туннель. Локальные и
  /// служебные адреса (в том числе «заглушки» вроде 0.0.0.0 и 127.0.0.1)
  /// и адрес самого сервера туда попадать не должны.
  bool _routable(String ip, ServerProfile profile) {
    if (ip == profile.host) return false;
    final first = int.tryParse(ip.split('.').first) ?? 0;
    if (first == 0 || first == 10 || first == 127 || first >= 224) return false;
    return !(ip.startsWith('192.168.') ||
        ip.startsWith('169.254.') ||
        RegExp(r'^172\.(1[6-9]|2\d|3[01])\.').hasMatch(ip) ||
        RegExp(r'^100\.(6[4-9]|[7-9]\d|1[01]\d|12[0-7])\.').hasMatch(ip));
  }

  /// Вызывается DNS-посредником: программа спросила имя из списка, и вот
  /// его адреса. Новые адреса направляем в туннель и только потом
  /// возвращаем управление — к этому моменту маршрут уже должен работать.
  Future<void> _routeByDomain(
    ServerProfile profile,
    String name,
    List<String> addresses,
  ) async {
    final fresh = [
      for (final ip in addresses)
        if (!_routed.contains(ip) &&
            !_staticRanges.contains(ip) &&
            _routable(ip, profile))
          ip,
    ];
    if (fresh.isEmpty) return;
    for (final ip in fresh) {
      _routed.add(ip);
      _learned[ip] = name;
    }
    _activeCidrs.addAll(fresh.map((ip) => '$ip/32'));
    if (_learned.length > 4000) {
      // Самые старые записи вытесняются первыми.
      final extra = _learned.keys.take(_learned.length - 4000).toList();
      extra.forEach(_learned.remove);
    }
    if (++_routeLogCount <= 150) {
      addLog(tr('По домену {0} в туннель добавлено: {1}', [name, fresh.join(', ')]));
    } else if (_routeLogCount == 151) {
      addLog(tr('Дальше добавления по доменам в журнал не пишутся.'));
    }
    unawaited(_save());
    await _enqueueRoutes(profile, fresh);
    notifyListeners();
  }

  /// Команды изменения маршрутов выполняются строго по одной.
  Future<void> _enqueueRoutes(ServerProfile profile, List<String> addresses) {
    final conf = buildAllowedIpsUpdate(profile, _activeCidrs);
    return _routeQueue = _routeQueue.then((_) async {
      try {
        await _tunnel.routeAddresses(conf, addresses);
      } catch (e) {
        addLog(tr('Не удалось добавить маршруты: {0}', [e]));
      }
    });
  }

  Future<void> _stopDomainRouting() async {
    _routeKeeper?.cancel();
    _routeKeeper = null;
    final proxy = _dns;
    if (proxy == null) return;
    _dns = null;
    await proxy.stop();
    addLog(tr('DNS-посредник остановлен: запросов {0}, по спискам '
        'сервисов {1}, без ответа {2}, с '
        'опозданием через туннель {3}; адресов добавлено '
        'по доменам: {4}.', [proxy.total, proxy.matched, proxy.unanswered, proxy.tunnelLate, _routed.length]));
  }

  /// HTTP-клиент для проверок связи: проверочный запрос, доступность
  /// сервисов, замер скорости.
  ///
  /// Сертификаты здесь не проверяются. На части компьютеров в хранилище
  /// Windows нет нужных корневых сертификатов (система подгружает их по мере
  /// надобности, а Dart этого не умеет), и проверка связи падала с
  /// CERTIFICATE_VERIFY_FAILED при исправном туннеле. Через этот клиент не
  /// передаётся ничего секретного, а ответы нужны только чтобы понять,
  /// проходит ли трафик.
  static HttpClient _checkClient(Duration timeout) => HttpClient()
    ..connectionTimeout = timeout
    ..badCertificateCallback = (certificate, host, port) => true;

  /// Один запрос служебной страницы Cloudflare через туннель. Возвращает
  /// адрес, под которым она увидела запрос; при неудаче бросает исключение.
  Future<String> _probeOnce(HttpClient http) async {
    final request =
        await http.getUrl(Uri.parse('http://$probeAddress/cdn-cgi/trace'));
    final response = await request.close().timeout(const Duration(seconds: 8));
    final body = await response
        .transform(const Utf8Decoder(allowMalformed: true))
        .join()
        .timeout(const Duration(seconds: 8));
    final match = RegExp(r'^ip=(.+)$', multiLine: true).firstMatch(body);
    if (match == null) throw tr('неожиданный ответ {0}', [response.statusCode]);
    return match.group(1)!.trim();
  }

  /// Проверяет туннель после подключения. null — запрос не прошёл.
  Future<String?> _probe() async {
    final http = _checkClient(const Duration(seconds: 8));
    try {
      // Сразу после рукопожатия Windows ещё дописывает маршруты туннеля,
      // и первые запросы могут получить «сеть недоступна». Поэтому даём
      // системе до десяти секунд и сообщаем только об итоговой неудаче.
      const attempts = 7;
      Object? lastError;
      for (var attempt = 1; attempt <= attempts; attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 1500));
        try {
          return await _probeOnce(http);
        } catch (e) {
          lastError = e;
        }
      }
      addLog(tr('Проверка туннеля не прошла за {0} попыток: {1}', [attempts, lastError]));
      return null;
    } finally {
      http.close(force: true);
    }
  }

  void _startStats() {
    _statsTimer?.cancel();
    _lastSample = null;
    downRate = 0;
    upRate = 0;
    _statsTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      if (status != VpnStatus.on) return;
      final stats = await _tunnelStats();
      if (stats == null) {
        // На Android VPN может снять сама система: другой VPN или
        // выключатель в настройках телефона.
        if (Platform.isAndroid &&
            status == VpnStatus.on &&
            !await AndroidTunnel.isUp() &&
            status == VpnStatus.on) {
          settings.wasOn = false;
          unawaited(_save());
          _fail(tr('VPN отключён системой.'));
          notifyListeners();
        }
        return;
      }
      if (status != VpnStatus.on) return;
      final now = DateTime.now();
      final before = _lastSample;
      if (before != null) {
        final seconds = now.difference(before).inMilliseconds / 1000;
        if (seconds > 0) {
          downRate =
              ((stats.received - _lastRx) / seconds).clamp(0, 1e12).toDouble();
          upRate = ((stats.sent - _lastTx) / seconds).clamp(0, 1e12).toDouble();
        }
      }
      _lastSample = now;
      _lastRx = stats.received;
      _lastTx = stats.sent;
      received = stats.received;
      sent = stats.sent;
      lastHandshake = stats.lastHandshake;
      notifyListeners();
    });
  }

  void _stopStats() {
    _statsTimer?.cancel();
    _statsTimer = null;
    downRate = 0;
    upRate = 0;
    received = 0;
    sent = 0;
    lastHandshake = null;
  }

  /// Выключает VPN. [remember] = false — это временное отключение (смена
  /// сервера, закрытие приложения): при следующем запуске VPN включится сам.
  Future<void> disconnect({bool remember = true}) async {
    _restartTimer?.cancel();
    _run++;
    _stopStats();
    await _stopDomainRouting();
    await _tunnelStop();
    status = VpnStatus.off;
    exitAddress = null;
    if (remember) {
      settings.wasOn = false;
      unawaited(_save());
    }
    notifyListeners();
    // VPN в браузере живёт отдельно: туннель для него поднимается заново.
    if (browserOn) {
      browserStatus = VpnStatus.off;
      unawaited(_resumeBrowser());
    }
  }

  /// Полное выключение при выходе из приложения: и VPN, и VPN в браузере.
  Future<void> shutdown() async {
    browserOn = false;
    _browserClients.clear();
    await _closeBrowserPath();
    await disconnect(remember: false);
  }

  void _fail(String message) {
    _restartTimer?.cancel();
    _stopStats();
    status = VpnStatus.off;
    exitAddress = null;
    error = message;
    addLog(message);
    if (browserOn) unawaited(_resumeBrowser());
  }

  // ------------------------------------------------------ VPN в браузере

  /// Порт SOCKS5-прокси для браузера (только 127.0.0.1).
  static const browserProxyPort = 47320;

  /// Нужен ли VPN в браузере: его просит хотя бы одно расширение.
  bool browserOn = false;

  /// Состояние VPN в браузере: включается расширением, независимо от
  /// главной кнопки.
  VpnStatus browserStatus = VpnStatus.off;
  String? browserError;

  SocksProxy? _socks;
  Timer? _browserKeeper;
  int _browserRun = 0;

  /// Расширения, которые просят VPN: идентификатор → когда спрашивали.
  /// Каждое расширение напоминает о себе раз в полминуты; закрытый браузер
  /// перестаёт напоминать, и через пару минут VPN для него выключается.
  final Map<String, DateTime> _browserClients = {};

  /// Код для расширения; создаётся при первом обращении.
  String get browserKey {
    if (settings.browserKey.isEmpty) regenerateBrowserKey();
    return settings.browserKey;
  }

  void regenerateBrowserKey() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final random = Random.secure();
    settings.browserKey =
        List.generate(8, (_) => chars[random.nextInt(chars.length)]).join();
    unawaited(_save());
    notifyListeners();
  }

  /// Расширение [client] сообщает, нужен ли ему VPN.
  void browserRequest(String client, bool on) {
    final now = DateTime.now();
    if (on) {
      _browserClients[client] = now;
    } else {
      _browserClients.remove(client);
    }
    _browserClients.removeWhere(
      (_, seen) => now.difference(seen) > const Duration(seconds: 100),
    );
    unawaited(_setBrowser(_browserClients.isNotEmpty));
  }

  String get _tunnelDns =>
      _validDns(settings.dns) ? settings.dns : probeAddress;

  Future<void> _setBrowser(bool on) async {
    if (!Platform.isWindows) return;
    if (on == browserOn) {
      // Повторная просьба после сбоя — пробуем снова.
      if (on && browserStatus == VpnStatus.off) await _resumeBrowser();
      return;
    }
    browserOn = on;
    if (!on) {
      _browserRun++;
      await _closeBrowserPath();
      browserStatus = VpnStatus.off;
      browserError = null;
      addLog(tr('VPN в браузере выключен.'));
      // Туннель был нужен только браузеру — снимаем.
      if (status == VpnStatus.off) await _tunnel.stop();
      notifyListeners();
      return;
    }
    await _resumeBrowser();
  }

  /// Поднимает VPN в браузере в том состоянии, в каком сейчас приложение.
  Future<void> _resumeBrowser() async {
    if (!browserOn) return;
    final profile = server;
    if (status == VpnStatus.connecting) {
      // Путь откроет само подключение, когда закончит.
      browserStatus = VpnStatus.connecting;
      notifyListeners();
      return;
    }
    if (status == VpnStatus.on && profile != null) {
      await _openBrowserPath(profile);
      return;
    }
    // Туннель для браузера и так работает (например, не удалось включить
    // VPN для всей системы, а прежний туннель никто не трогал).
    if (browserStatus == VpnStatus.on) return;
    final run = ++_browserRun;
    browserError = null;
    if (profile == null) {
      browserStatus = VpnStatus.off;
      browserError = tr('Сначала добавьте сервер на вкладке «Сервер».');
      notifyListeners();
      return;
    }
    if (!elevated) {
      browserStatus = VpnStatus.off;
      browserError = tr('Запустите приложение от имени администратора.');
      notifyListeners();
      return;
    }
    browserStatus = VpnStatus.connecting;
    notifyListeners();
    try {
      await _tunnel.ensureInstalled();
      if (run != _browserRun || status != VpnStatus.off) return;
      addLog(tr('Поднимаю туннель AmneziaWG к {0}:{1} только для браузера…',
          [profile.host, profile.port]));
      // Системе — никаких маршрутов, кроме DNS-сервера для прокси.
      await _tunnel.start(buildClientConf(profile, {'$_tunnelDns/32'}));
      if (run != _browserRun || status != VpnStatus.off) return;
      if (!await _tunnel.waitForHandshake(const Duration(seconds: 15))) {
        if (run != _browserRun || status != VpnStatus.off) return;
        await _tunnel.stop();
        browserStatus = VpnStatus.off;
        browserError = tr('Сервер не ответил на рукопожатие. Проверьте, что '
            'сервер включён и UDP-порт {0} открыт в файрволе хостинга.',
            [profile.port]);
        addLog(browserError!);
        notifyListeners();
        return;
      }
      if (run != _browserRun || status != VpnStatus.off) return;
      await _openBrowserPath(profile);
    } catch (e) {
      if (run != _browserRun) return;
      browserStatus = VpnStatus.off;
      browserError = tr('Не удалось включить VPN в браузере: {0}', [e]);
      addLog(browserError!);
      notifyListeners();
    }
  }

  /// Туннель уже поднят: открываем в нём путь для браузера и прокси.
  Future<void> _openBrowserPath(ServerProfile profile) async {
    try {
      await _tunnel.openBrowserRoute(profile.serverPublicKey);
      final socks = _socks;
      if (socks == null) {
        _socks = await SocksProxy.start(
          port: browserProxyPort,
          resolver: TunnelResolver(
            source: profile.clientAddress,
            server: _tunnelDns,
          ),
          log: addLog,
        );
      } else {
        socks.resolver
          ..source = profile.clientAddress
          ..server = _tunnelDns;
      }
      // Клиент AmneziaWG при смене сети заново выставляет свои маршруты —
      // путь для браузера периодически возвращаем.
      _browserKeeper?.cancel();
      _browserKeeper = Timer.periodic(const Duration(seconds: 90), (_) {
        if (browserStatus == VpnStatus.on) {
          unawaited(_tunnel.openBrowserRoute(profile.serverPublicKey));
        }
      });
      final was = browserStatus;
      browserStatus = VpnStatus.on;
      browserError = null;
      if (was != VpnStatus.on) {
        addLog(tr('VPN в браузере включён: прокси 127.0.0.1:{0}.',
            [browserProxyPort]));
      }
    } catch (e) {
      browserStatus = VpnStatus.off;
      browserError = tr('Не удалось включить VPN в браузере: {0}', [e]);
      addLog(browserError!);
    }
    notifyListeners();
  }

  Future<void> _closeBrowserPath() async {
    _browserKeeper?.cancel();
    _browserKeeper = null;
    final socks = _socks;
    _socks = null;
    await socks?.stop();
    if (Platform.isWindows) await _tunnel.closeBrowserRoute();
  }

  /// Домены включённых ресурсов — то, что браузер отправляет через VPN.
  List<String> get browserDomains => {
        for (final s in services)
          if (enabled.contains(s.id)) ...s.domains,
      }.toList()
        ..sort();


  // -------------------------------------------------------------- маршруты

  /// Для вкладки «Маршруты»: сколько адресов найдено по доменам у сервиса.
  int learnedCountOf(ServiceEntry service) {
    if (_routed.isEmpty || service.domains.isEmpty) return 0;
    final matcher = DomainMatcher(service.domains, service.keywords);
    var count = 0;
    for (final ip in _routed) {
      final name = _learned[ip];
      if (name != null && matcher.matches(name)) count++;
    }
    return count;
  }

  /// Последние адреса, найденные по доменам: (имя, адрес), новые первыми.
  List<MapEntry<String, String>> recentLearned({int limit = 40}) {
    final result = <MapEntry<String, String>>[];
    final ips = _routed.toList();
    for (var i = ips.length - 1; i >= 0 && result.length < limit; i--) {
      result.add(MapEntry(_learned[ips[i]] ?? '', ips[i]));
    }
    return result;
  }

  int get learnedTotal => _learned.length;

  /// Забывает все адреса, найденные по доменам.
  Future<void> forgetLearned() async {
    _learned.clear();
    _routed.clear();
    await _save();
    addLog(tr('Найденные по доменам адреса забыты.'));
    if (status != VpnStatus.off) unawaited(connect());
  }

  // ----------------------------------------------------------- диагностика

  /// Дописывает в журнал состояние туннеля и журнал клиента AmneziaWG.
  Future<void> collectClientLog() async {
    if (Platform.isAndroid) {
      addLog(tr('На Android отдельного журнала туннеля нет.'));
      return;
    }
    final stats = await _tunnel.stats();
    if (stats == null) {
      addLog(tr('Туннель сейчас не поднят.'));
    } else {
      addLog(tr('Туннель: последнее рукопожатие '
          '{0}, получено {1} '
          'байт, отправлено {2} байт.', [stats.lastHandshake ?? tr('не было'), stats.received, stats.sent]));
    }
    _addBlock(tr('журнал клиента AmneziaWG'), await _tunnel.clientLog());
  }

  Future<bool> _reachable(String host) async {
    final http = _checkClient(const Duration(seconds: 5));
    try {
      final request = await http
          .headUrl(Uri.parse('https://$host/'))
          .timeout(const Duration(seconds: 6));
      request.followRedirects = false;
      final response = await request.close().timeout(const Duration(seconds: 6));
      try {
        await response.drain<void>().timeout(const Duration(seconds: 3));
      } catch (_) {}
      return true;
    } catch (_) {
      return false;
    } finally {
      http.close(force: true);
    }
  }

  static String _mbit(double bytesPerSecond) =>
      tr('{0} '
      'Мбит/с', [decimal(bytesPerSecond * 8 / 1e6)]);

  /// Замеряет скорость через туннель на узле измерения скорости Cloudflare:
  /// скачивает 8 МБ и отправляет 2 МБ.
  Future<({double down, double up, bool throughTunnel})> _speedTest() async {
    const host = 'speed.cloudflare.com';
    final profile = server;
    if (profile == null) throw tr('нет сервера');
    if (!settings.fullTunnel) {
      // Адреса узла измерения направляем в туннель, иначе замерится
      // скорость обычного подключения.
      final found = await InternetAddress.lookup(host)
          .timeout(const Duration(seconds: 8));
      final fresh = [
        for (final a in found)
          if (a.type == InternetAddressType.IPv4 &&
              !_routed.contains(a.address) &&
              !_staticRanges.contains(a.address))
            a.address,
      ];
      if (fresh.isNotEmpty) {
        _routed.addAll(fresh);
        _activeCidrs.addAll(fresh.map((ip) => '$ip/32'));
        await _enqueueRoutes(profile, fresh);
      }
    }

    final before = await _tunnelStats();
    final http = _checkClient(const Duration(seconds: 8));
    try {
      // Загрузка.
      final request = await http
          .getUrl(Uri.parse('https://$host/__down?bytes=8000000'))
          .timeout(const Duration(seconds: 10));
      final response =
          await request.close().timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) {
        throw tr('узел измерения ответил кодом {0}', [response.statusCode]);
      }
      final watch = Stopwatch()..start();
      var got = 0;
      try {
        await for (final chunk
            in response.timeout(const Duration(seconds: 6))) {
          got += chunk.length;
          // Медленное подключение не ждём до конца: хватит и части.
          if (watch.elapsedMilliseconds > 12000) break;
        }
      } on TimeoutException {
        // Поток замер — считаем по тому, что успело прийти.
      }
      final downSeconds = watch.elapsedMilliseconds / 1000;
      if (got < 100000 || downSeconds <= 0) throw tr('слишком мало данных');
      final down = got / downSeconds;

      // Отдача.
      const size = 2000000;
      final upload = await http
          .postUrl(Uri.parse('https://$host/__up'))
          .timeout(const Duration(seconds: 10));
      upload.headers.contentType = ContentType.binary;
      upload.contentLength = size;
      final block = List<int>.filled(50000, 0x55);
      final upWatch = Stopwatch()..start();
      for (var sent = 0; sent < size; sent += block.length) {
        upload.add(block);
        await upload.flush();
      }
      final uploaded = await upload.close().timeout(const Duration(seconds: 20));
      await uploaded.drain<void>().timeout(const Duration(seconds: 5));
      final upSeconds = upWatch.elapsedMilliseconds / 1000;
      final up = upSeconds <= 0 ? 0.0 : size / upSeconds;

      final after = await _tunnelStats();
      // Если счётчик туннеля вырос хотя бы на половину скачанного, замер шёл
      // через туннель.
      final through = before != null &&
          after != null &&
          after.received - before.received >= got ~/ 2;
      return (down: down, up: up, throughTunnel: through);
    } finally {
      http.close(force: true);
    }
  }

  /// Пошаговая проверка: клиент, связь, трафик, DNS, маршруты, сервисы,
  /// сервер. Результат — в [checks], [checkSummary] и [checkAdvice].
  Future<void> runChecks() async {
    if (checking) return;
    checking = true;
    checkSummary = '';
    checkAdvice = '';
    final client = CheckStep(tr('Клиент AmneziaWG'));
    final link = CheckStep(tr('Связь с сервером'));
    final traffic = CheckStep(tr('Трафик через туннель'));
    final dns = CheckStep('DNS');
    final routes = CheckStep(tr('Маршруты'));
    final sites = CheckStep(tr('Включённые сервисы'));
    final speed = CheckStep(tr('Скорость'));
    final remote = CheckStep(tr('Сервер изнутри'));
    checks = [client, link, traffic, dns, routes, sites, speed, remote];
    notifyListeners();

    void begin(CheckStep step) {
      step
        ..state = CheckState.run
        ..note = tr('проверяю…');
      notifyListeners();
    }

    void end(CheckStep step, CheckState state, String note) {
      step
        ..state = state
        ..note = note;
      notifyListeners();
    }

    final advice = <String>[];
    final on = status == VpnStatus.on;
    final offNote = tr('VPN выключен — включите его и повторите');

    try {
      // 1. Клиент.
      begin(client);
      if (Platform.isAndroid) {
        end(client, CheckState.ok, tr('встроен в приложение'));
      } else if (!_tunnel.isInstalled) {
        end(client, CheckState.warn,
            tr('ещё не установлен — поставится при первом включении VPN'));
      } else if (on && !await _tunnel.isRunning()) {
        end(client, CheckState.fail, tr('установлен, но служба туннеля не запущена'));
        advice.add(tr('Выключите и снова включите VPN.'));
      } else {
        end(client, CheckState.ok,
            on ? tr('установлен, служба туннеля запущена') : tr('установлен'));
      }

      // 2. Связь с сервером.
      begin(link);
      if (!on) {
        end(link, CheckState.skip, offNote);
      } else {
        final stats = await _tunnelStats();
        final last = stats?.lastHandshake;
        if (last == null) {
          end(link, CheckState.fail, tr('рукопожатия с сервером не было'));
          advice.add(tr('Проверьте, что сервер включён и его UDP-порт открыт '
              'в файрволе хостинга.'));
        } else {
          final age = DateTime.now().difference(last).inSeconds;
          if (age > 190) {
            end(link, CheckState.warn,
                tr('последнее рукопожатие {0} с назад — связь могла пропасть', [age]));
            advice.add(tr('Сервер давно не отвечал. Проверьте, что он работает.'));
          } else {
            end(link, CheckState.ok, tr('рукопожатие {0} с назад', [age]));
          }
        }
      }

      // 3. Трафик.
      begin(traffic);
      if (!on) {
        end(traffic, CheckState.skip, offNote);
      } else if (appMode && !settings.fullTunnel) {
        end(traffic, CheckState.skip,
            tr('в режиме «Приложения» само ColdVPN идёт мимо VPN'));
      } else {
        final http = _checkClient(const Duration(seconds: 8));
        try {
          final address = await _probeOnce(http);
          exitAddress = address;
          final expected = server?.host;
          if (expected != null && address != expected) {
            end(traffic, CheckState.ok,
                tr('сайты видят адрес {0} (у сервера другой исходящий адрес)', [address]));
          } else {
            end(traffic, CheckState.ok, tr('сайты видят адрес сервера {0}', [address]));
          }
        } catch (_) {
          end(traffic, CheckState.fail, tr('запрос через туннель не прошёл'));
          advice.add(tr('Туннель поднят, но трафик не проходит. Запустите '
              'проверку «Сервер изнутри» — для неё нужен пароль от сервера.'));
        } finally {
          http.close(force: true);
        }
      }

      // 4. DNS.
      begin(dns);
      final active = services.where((s) => enabled.contains(s.id)).toList();
      if (!on) {
        end(dns, CheckState.skip, offNote);
      } else if (_dns == null && !settings.fullTunnel) {
        end(dns, CheckState.skip,
            Platform.isAndroid
                ? tr('на Android маршрутов по доменам нет — работают списки IP')
                : tr('маршруты по доменам выключены — работают только списки IP'));
      } else {
        String sample = settings.fullTunnel ? 'www.cloudflare.com' : '';
        for (final s in sample.isEmpty ? active : const <ServiceEntry>[]) {
          final host = serviceProbeHosts[s.id] ??
              (s.domains.isEmpty ? '' : s.domains.first);
          if (host.isNotEmpty) {
            sample = host;
            break;
          }
        }
        if (sample.isEmpty) {
          end(dns, CheckState.skip, tr('у включённых сервисов нет доменов'));
        } else {
          final watch = Stopwatch()..start();
          try {
            await InternetAddress.lookup(sample)
                .timeout(const Duration(seconds: 8));
            final ms = watch.elapsedMilliseconds;
            end(dns, ms > 1500 ? CheckState.warn : CheckState.ok,
                tr('имя {0} найдено за {1} мс', [sample, ms]));
            if (ms > 1500) {
              advice.add(tr('DNS отвечает медленно — сайты могут открываться '
                  'с задержкой. Попробуйте другой DNS в настройках.'));
            }
          } catch (_) {
            end(dns, CheckState.fail, tr('имя {0} не найдено', [sample]));
            advice.add(tr('DNS не отвечает. Попробуйте другой DNS в настройках.'));
          }
        }
      }

      // 5. Маршруты.
      begin(routes);
      if (!on) {
        end(routes, CheckState.skip, offNote);
      } else {
        final expected = allowedIps(_activeCidrs).length;
        // На Android маршруты задаются при создании туннеля и не теряются.
        final actual = Platform.isAndroid
            ? expected
            : await _tunnel.allowedIpCount();
        if (actual == null) {
          end(routes, CheckState.fail, tr('не удалось прочитать маршруты туннеля'));
        } else if (actual < expected) {
          end(routes, CheckState.warn,
              tr('в туннеле {0} из {1} адресов и диапазонов', [actual, expected]));
          advice.add(tr('Часть маршрутов потерялась. Выключите и включите VPN.'));
        } else {
          end(
            routes,
            CheckState.ok,
            settings.fullTunnel
                ? tr('весь трафик направлен в туннель')
                : tr('{0} диапазонов и '
                    '{1} адресов по доменам — все на месте', [collectCidrs(services, enabled).length, _routed.length]),
          );
        }
      }

      // 6. Сервисы.
      begin(sites);
      if (!on) {
        end(sites, CheckState.skip, offNote);
      } else if (appMode && !settings.fullTunnel) {
        end(sites, CheckState.skip,
            tr('в режиме «Приложения» проверьте нужное приложение сами'));
      } else {
        final targets = <String, String>{};
        for (final s in active) {
          final host = serviceProbeHosts[s.id] ??
              (s.domains.isEmpty ? '' : s.domains.first);
          if (host.isNotEmpty) targets[s.name] = host;
        }
        if (targets.isEmpty) {
          end(sites, CheckState.skip, tr('нет сервисов с доменами для проверки'));
        } else {
          final names = targets.keys.toList();
          final results =
              await Future.wait([for (final n in names) _reachable(targets[n]!)]);
          final failed = [
            for (var i = 0; i < names.length; i++)
              if (!results[i]) names[i],
          ];
          if (failed.isEmpty) {
            end(sites, CheckState.ok, tr('отвечают все: {0}', [names.length]));
          } else {
            end(
              sites,
              failed.length == names.length ? CheckState.fail : CheckState.warn,
              tr('{0} из {1} отвечают · '
              'не ответили: {2}', [names.length - failed.length, names.length, failed.join(', ')]),
            );
            advice.add(tr('{0}: нет ответа через туннель. Чаще '
                'всего сервис блокирует адрес сервера — попробуйте другой '
                'сервер.', [failed.join(', ')]));
          }
        }
      }

      // 7. Скорость.
      begin(speed);
      if (!on) {
        end(speed, CheckState.skip, offNote);
      } else if (Platform.isAndroid && !settings.fullTunnel) {
        end(speed, CheckState.skip,
            tr('на Android замер работает только в режиме «Весь трафик»'));
      } else {
        try {
          final result = await _speedTest();
          if (result.throughTunnel) {
            end(speed, CheckState.ok,
                tr('↓ {0} · ↑ {1} через туннель', [_mbit(result.down), _mbit(result.up)]));
          } else {
            end(speed, CheckState.warn,
                tr('↓ {0} · ↑ {1}, но замер, '
                'похоже, прошёл мимо туннеля', [_mbit(result.down), _mbit(result.up)]));
          }
        } catch (e) {
          end(speed, CheckState.warn, tr('замерить не удалось: {0}', [e]));
        }
      }

      // 8. Сервер изнутри.
      begin(remote);
      final creds = credentials[server?.host];
      if (creds == null) {
        end(remote, CheckState.skip,
            tr('нужен пароль от сервера — введите его в «Поделиться» у этого '
            'сервера'));
      } else {
        try {
          final lines = await diagnoseServer(creds);
          _addBlock(tr('диагностика сервера'), lines);
          end(remote, CheckState.ok,
              tr('отчёт получен и записан во вкладку «Подробно»'));
        } catch (e) {
          end(remote, CheckState.fail, tr('не удалось подключиться: {0}', [e]));
        }
      }
    } catch (e) {
      addLog(tr('Диагностика прервалась: {0}', [e]));
    }

    int count(CheckState state) => checks.where((c) => c.state == state).length;
    final failed = count(CheckState.fail);
    final warned = count(CheckState.warn);
    if (!on) {
      checkSummary = tr('VPN выключен');
      checkAdvice = tr('Включите VPN на вкладке «Сервисы» и повторите проверку — '
          'тогда проверятся связь, DNS, маршруты и сервисы.');
    } else if (failed > 0) {
      checkSummary = tr('Есть проблемы: {0}', [failed]);
      checkAdvice = advice.join(' ');
    } else if (warned > 0) {
      checkSummary = tr('VPN работает, замечаний: {0}', [warned]);
      checkAdvice = advice.join(' ');
    } else {
      checkSummary = tr('Всё в порядке');
      checkAdvice = tr('VPN работает, включённые сервисы отвечают.');
    }
    addLog(tr('Диагностика завершена: в порядке {0}, '
        'замечаний {1}, ошибок {2}, пропущено '
        '{3}.', [count(CheckState.ok), warned, failed, count(CheckState.skip)]));
    checking = false;
    notifyListeners();
  }

  /// Текст отчёта диагностики для копирования.
  String get checkReport => [
        tr('Диагностика ColdVPN: {0}', [checkSummary]),
        for (final c in checks) '${_stateWord(c.state)} — ${c.title}: ${c.note}',
        if (checkAdvice.isNotEmpty) checkAdvice,
      ].join('\n');

  static String _stateWord(CheckState state) {
    switch (state) {
      case CheckState.ok:
        return tr('В порядке');
      case CheckState.warn:
        return tr('Замечание');
      case CheckState.fail:
        return tr('Ошибка');
      case CheckState.skip:
        return tr('Пропущено');
      case CheckState.run:
        return tr('Идёт');
      case CheckState.wait:
        return tr('В очереди');
    }
  }

  static String stateWord(CheckState state) => _stateWord(state);
}
