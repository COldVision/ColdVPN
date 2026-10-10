import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';

import 'awg_config.dart';
import 'awg_manager.dart';
import 'catalog.dart';
import 'dns_proxy.dart';
import 'list_updater.dart';
import 'models.dart';
import 'route_input.dart';
import 'secret_store.dart';
import 'server_installer.dart';

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
    _rebuildServices();
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

  /// Сервисы из встроенного списка.
  final List<ServiceEntry> builtin;

  /// Маршруты, добавленные пользователем.
  final List<CustomRoute> customRoutes = [];

  /// Встроенные сервисы и свои маршруты вместе.
  List<ServiceEntry> services = const [];

  final Set<String> enabled = {};

  /// Порядок групп на вкладке «Сервисы».
  List<String> groupOrder = [for (final g in serviceGroups) g.id];

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
      addLog('Не удалось сохранить пароль сервера: $e');
    }
  }

  // Диагностика.
  List<CheckStep> checks = [];
  bool checking = false;
  String checkSummary = '';
  String checkAdvice = '';

  /// Подключение пока реализовано только для Windows.
  bool get platformSupported => Platform.isWindows;

  SavedServer? get current {
    for (final s in servers) {
      if (s.id == selectedServerId) return s;
    }
    return servers.isEmpty ? null : servers.first;
  }

  ServerProfile? get server => current?.profile;

  /// Есть ли что направлять в туннель.
  bool get canConnect => settings.fullTunnel || enabled.isNotEmpty;

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
          services.addAll(byId.values);
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
    if (state.platformSupported && state.elevated) {
      await state._tunnel.removeLegacyTunnel();
      await state._tunnel.stop();
      // И правила DNS, которые создавала прежняя сборка: без работающего
      // приложения они оставляют имена сервисов без ответа.
      await AwgManager.clearDomainRules();
    }
    if (state.platformSupported) {
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
    services = [...builtin, for (final r in customRoutes) r.toService()];
  }

  Future<void> _read() async {
    if (!_stateFile.existsSync()) return;
    try {
      _apply(
        jsonDecode(await _stateFile.readAsString()) as Map<String, dynamic>,
      );
    } catch (e) {
      addLog('Не удалось прочитать сохранённые настройки: $e');
    }
  }

  /// Заменяет всё состояние приложения тем, что записано в [json].
  void _apply(Map<String, dynamic> json) {
    customRoutes.clear();
    enabled.clear();
    _learned.clear();
    servers.clear();

    for (final item in json['customRoutes'] as List? ?? const []) {
      customRoutes.add(CustomRoute.fromJson(item as Map<String, dynamic>));
    }
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
        name: 'Основной',
        profile: ServerProfile.fromJson(old),
      ));
    }
    selectedServerId = json['selectedServer'] as String?;

    final order = (json['groupOrder'] as List? ?? const []).cast<String>();
    final ids = [for (final g in serviceGroups) g.id];
    groupOrder = [
      ...order.where(ids.contains),
      ...ids.where((id) => !order.contains(id)),
    ];

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
      ..closeToTray = s.closeToTray
      ..autoUpdateLists = s.autoUpdateLists
      ..dns = s.dns;
  }

  Map<String, dynamic> _snapshot({bool withLearned = true}) => {
        'enabled': enabled.toList(),
        'servers': [for (final s in servers) s.toJson()],
        'selectedServer': selectedServerId,
        'customRoutes': [for (final r in customRoutes) r.toJson()],
        'groupOrder': groupOrder,
        'settings': settings.toJson(),
        if (withLearned) 'learned': _learned,
      };

  Future<void> _save() async {
    try {
      await _stateFile.parent.create(recursive: true);
      await _stateFile.writeAsString(jsonEncode(_snapshot()));
    } catch (e) {
      debugPrint('Не удалось сохранить настройки: $e');
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
      return 'Это не файл настроек ColdVPN.';
    }
    if (json is! Map<String, dynamic> ||
        json['app'] != 'ColdVPN' ||
        json['servers'] is! List) {
      return 'Это не файл настроек ColdVPN.';
    }
    if (status != VpnStatus.off) await disconnect();
    final backup = _snapshot();
    try {
      _apply(json);
    } catch (e) {
      // Файл оказался испорчен на середине — возвращаем то, что было.
      _apply(backup);
      notifyListeners();
      return 'Файл настроек повреждён: $e';
    }
    settings.wasOn = false;
    await _save();
    addLog('Настройки загружены из файла: серверов ${servers.length}, своих '
        'маршрутов ${customRoutes.length}.');
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
    addLog('Настройки сброшены.');
  }

  // ------------------------------------------------------ списки сервисов

  /// Обновляет списки сервисов из репозиториев. Сервис, для которого
  /// ничего не скачалось, остаётся с прежним списком.
  /// Возвращает короткий итог для показа пользователю.
  Future<String> updateLists() async {
    if (updatingLists) return 'Обновление уже идёт';
    updatingLists = true;
    notifyListeners();
    try {
      final selection = jsonDecode(
        await rootBundle.loadString('assets/selection.json'),
      ) as Map<String, dynamic>;
      final update = await downloadServices(selection);
      for (final problem in update.problems) {
        addLog('Списки: $problem');
      }
      if (update.services.isEmpty) {
        throw 'из репозиториев не удалось собрать ни одного сервиса';
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
      _rebuildServices();
      final summary = changed == 0
          ? 'Списки актуальны, изменений нет'
          : 'Списки обновлены, изменилось сервисов: $changed';
      addLog('$summary.');
      if (changed > 0 && status != VpnStatus.off && !settings.fullTunnel) {
        unawaited(connect());
      }
      return summary;
    } catch (e) {
      addLog('Не удалось обновить списки сервисов: $e');
      return 'Не удалось обновить списки. Подробности в журнале';
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
    if (line.startsWith('По домену')) return LogKind.route;
    const bad = [
      'не удалось', 'ошибка', 'внимание', 'не прошл', 'не ответил', //
      'недоступн', 'не пройдена', 'не разрешилось', 'прервалась',
    ];
    if (bad.any(low.contains)) return LogKind.warn;
    if (line.startsWith('Подключено') ||
        line.startsWith('Рукопожатие') ||
        low.contains('пройдена') ||
        low.contains('настроен')) {
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
    events.add('--- конец: $title ---');
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
          ? (servers.isEmpty ? 'Основной' : 'Сервер ${servers.length + 1}')
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
    if (wasOn) await disconnect(remember: false);
    selectedServerId = id;
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
    if (creds == null) throw 'Нет данных для входа на сервер.';
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
    addLog('На сервере ${entry.profile.host} выпущен отдельный ключ '
        '«$device» для другого устройства.');
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
        '&lang=ru',
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

  /// Сервисы группы в том порядке, в каком они показаны.
  List<ServiceEntry> servicesOf(String groupId) {
    if (groupId == customGroupId) {
      return [for (final r in customRoutes) r.toService()];
    }
    final grouped = {
      for (final g in serviceGroups)
        if (g.id != otherGroupId) ...g.serviceIds,
    };
    final group = serviceGroups.firstWhere((g) => g.id == groupId);
    return [
      for (final id in group.serviceIds)
        ...builtin.where((s) => s.id == id),
      if (groupId == otherGroupId)
        ...builtin.where(
          (s) => !grouped.contains(s.id) && !group.serviceIds.contains(s.id),
        ),
    ];
  }

  void moveGroup(int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex--;
    final id = groupOrder.removeAt(oldIndex);
    groupOrder.insert(newIndex.clamp(0, groupOrder.length).toInt(), id);
    notifyListeners();
    unawaited(_save());
  }

  /// Сохраняет свой маршрут: новый ([id] == null) или изменённый.
  void saveCustomRoute({
    String? id,
    required String name,
    required List<RouteLine> lines,
    bool enable = false,
  }) {
    final route = CustomRoute(
      id: id ?? _newId('custom'),
      name: name.trim(),
      domains: [
        for (final l in lines)
          if (l.kind == RouteLineKind.domain) l.value,
      ],
      ips: [
        for (final l in lines)
          if (l.kind == RouteLineKind.network)
            l.value
          else if (l.kind == RouteLineKind.address)
            '${l.value}/32',
      ],
    );
    final index = customRoutes.indexWhere((r) => r.id == route.id);
    if (index < 0) {
      customRoutes.add(route);
      if (enable) enabled.add(route.id);
    } else {
      customRoutes[index] = route;
    }
    _rebuildServices();
    _afterSelectionChange();
  }

  void deleteCustomRoute(String id) {
    customRoutes.removeWhere((r) => r.id == id);
    enabled.remove(id);
    _rebuildServices();
    _afterSelectionChange();
  }

  void _afterSelectionChange() {
    notifyListeners();
    unawaited(_save());
    // Когда через VPN идёт весь трафик, переключатели сервисов на туннель
    // не влияют.
    if (status == VpnStatus.off || settings.fullTunnel) return;
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
        addLog('Не удалось изменить автозапуск: '
            '${'${result.stdout}${result.stderr}'.trim()}');
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
      addLog('Не удалось изменить автозапуск: $e');
    }
    autostart = await _autostartEnabled();
    notifyListeners();
  }

  /// Вызывается один раз после запуска приложения.
  void autoConnect() {
    if (settings.connectOnStart &&
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
      _fail('Сначала добавьте сервер на вкладке «Сервер».');
      return;
    }
    final full = settings.fullTunnel;
    if (!full && enabled.isEmpty) {
      _fail('Включите хотя бы один сервис.');
      return;
    }
    if (!platformSupported) {
      _fail('Подключение на этой платформе пока не реализовано.');
      return;
    }
    if (!elevated) {
      _fail('Запустите приложение от имени администратора.');
      return;
    }

    final run = ++_run;
    status = VpnStatus.connecting;
    error = null;
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
          addLog('Маршрутизация по доменам включена, обычный DNS: '
              '${proxy.directUpstreams.join(', ')}.');
        } catch (e) {
          addLog('Маршрутизация по доменам недоступна (не удалось занять '
              '${DnsProxy.listenAddress}:53): $e. Работают только списки IP.');
        }
      }
      if (run != _run) {
        // Отменили, пока поднимался посредник: он не должен остаться в фоне.
        if (status == VpnStatus.off) await _stopDomainRouting();
        return;
      }

      addLog(full
          ? 'Поднимаю туннель AmneziaWG к ${profile.host}:${profile.port} '
              '(весь трафик)…'
          : 'Поднимаю туннель AmneziaWG к ${profile.host}:${profile.port} '
              '(диапазонов: ${ranges.length}, адресов по доменам: '
              '${_routed.length})…');
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
        _addBlock('журнал клиента AmneziaWG', await _tunnel.clientLog());
        await _stopDomainRouting();
        await _tunnel.stop();
        _fail('Сервер не ответил на рукопожатие. Проверьте, что UDP-порт '
            '${profile.port} открыт в файрволе хостинга. Подробности в журнале.');
        return;
      }
      addLog('Рукопожатие с сервером выполнено.');
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
          addLog('DNS-посредник не смог занять ${profile.clientAddress}:53, '
              'остаётся прежний адрес.');
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
      if (address == null) {
        error = 'Туннель поднят, но проверочный запрос через него не прошёл. '
            'Сайты могут не открываться — запустите диагностику в журнале.';
        addLog(error!);
      } else {
        addLog('Подключено. Сайты видят вас под адресом $address.');
      }
      notifyListeners();
    } catch (e) {
      if (run != _run) return;
      await _stopDomainRouting();
      await _tunnel.stop();
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
      addLog('По домену $name в туннель добавлено: ${fresh.join(', ')}');
    } else if (_routeLogCount == 151) {
      addLog('Дальше добавления по доменам в журнал не пишутся.');
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
        addLog('Не удалось добавить маршруты: $e');
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
    addLog('DNS-посредник остановлен: запросов ${proxy.total}, по спискам '
        'сервисов ${proxy.matched}, без ответа ${proxy.unanswered}, с '
        'опозданием через туннель ${proxy.tunnelLate}; адресов добавлено '
        'по доменам: ${_routed.length}.');
  }

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
    if (match == null) throw 'неожиданный ответ ${response.statusCode}';
    return match.group(1)!.trim();
  }

  /// Проверяет туннель после подключения. null — запрос не прошёл.
  Future<String?> _probe() async {
    final http = HttpClient()..connectionTimeout = const Duration(seconds: 8);
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
      addLog('Проверка туннеля не прошла за $attempts попыток: $lastError');
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
      final stats = await _tunnel.stats();
      if (stats == null || status != VpnStatus.on) return;
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
    await _tunnel.stop();
    status = VpnStatus.off;
    exitAddress = null;
    if (remember) {
      settings.wasOn = false;
      unawaited(_save());
    }
    notifyListeners();
  }

  void _fail(String message) {
    _restartTimer?.cancel();
    _stopStats();
    status = VpnStatus.off;
    exitAddress = null;
    error = message;
    addLog(message);
  }

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
    addLog('Найденные по доменам адреса забыты.');
    if (status != VpnStatus.off) unawaited(connect());
  }

  // ----------------------------------------------------------- диагностика

  /// Дописывает в журнал состояние туннеля и журнал клиента AmneziaWG.
  Future<void> collectClientLog() async {
    final stats = await _tunnel.stats();
    if (stats == null) {
      addLog('Туннель сейчас не поднят.');
    } else {
      addLog('Туннель: последнее рукопожатие '
          '${stats.lastHandshake ?? 'не было'}, получено ${stats.received} '
          'байт, отправлено ${stats.sent} байт.');
    }
    _addBlock('журнал клиента AmneziaWG', await _tunnel.clientLog());
  }

  Future<bool> _reachable(String host) async {
    final http = HttpClient()..connectionTimeout = const Duration(seconds: 5);
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
      '${(bytesPerSecond * 8 / 1e6).toStringAsFixed(1).replaceAll('.', ',')} '
      'Мбит/с';

  /// Замеряет скорость через туннель на узле измерения скорости Cloudflare:
  /// скачивает 8 МБ и отправляет 2 МБ.
  Future<({double down, double up, bool throughTunnel})> _speedTest() async {
    const host = 'speed.cloudflare.com';
    final profile = server;
    if (profile == null) throw 'нет сервера';
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

    final before = await _tunnel.stats();
    final http = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      // Загрузка.
      final request = await http
          .getUrl(Uri.parse('https://$host/__down?bytes=8000000'))
          .timeout(const Duration(seconds: 10));
      final response =
          await request.close().timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) {
        throw 'узел измерения ответил кодом ${response.statusCode}';
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
      if (got < 100000 || downSeconds <= 0) throw 'слишком мало данных';
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

      final after = await _tunnel.stats();
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
    final client = CheckStep('Клиент AmneziaWG');
    final link = CheckStep('Связь с сервером');
    final traffic = CheckStep('Трафик через туннель');
    final dns = CheckStep('DNS');
    final routes = CheckStep('Маршруты');
    final sites = CheckStep('Включённые сервисы');
    final speed = CheckStep('Скорость');
    final remote = CheckStep('Сервер изнутри');
    checks = [client, link, traffic, dns, routes, sites, speed, remote];
    notifyListeners();

    void begin(CheckStep step) {
      step
        ..state = CheckState.run
        ..note = 'проверяю…';
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
    const offNote = 'VPN выключен — включите его и повторите';

    try {
      // 1. Клиент.
      begin(client);
      if (!_tunnel.isInstalled) {
        end(client, CheckState.warn,
            'ещё не установлен — поставится при первом включении VPN');
      } else if (on && !await _tunnel.isRunning()) {
        end(client, CheckState.fail, 'установлен, но служба туннеля не запущена');
        advice.add('Выключите и снова включите VPN.');
      } else {
        end(client, CheckState.ok,
            on ? 'установлен, служба туннеля запущена' : 'установлен');
      }

      // 2. Связь с сервером.
      begin(link);
      if (!on) {
        end(link, CheckState.skip, offNote);
      } else {
        final stats = await _tunnel.stats();
        final last = stats?.lastHandshake;
        if (last == null) {
          end(link, CheckState.fail, 'рукопожатия с сервером не было');
          advice.add('Проверьте, что сервер включён и его UDP-порт открыт '
              'в файрволе хостинга.');
        } else {
          final age = DateTime.now().difference(last).inSeconds;
          if (age > 190) {
            end(link, CheckState.warn,
                'последнее рукопожатие $age с назад — связь могла пропасть');
            advice.add('Сервер давно не отвечал. Проверьте, что он работает.');
          } else {
            end(link, CheckState.ok, 'рукопожатие $age с назад');
          }
        }
      }

      // 3. Трафик.
      begin(traffic);
      if (!on) {
        end(traffic, CheckState.skip, offNote);
      } else {
        final http = HttpClient()
          ..connectionTimeout = const Duration(seconds: 8);
        try {
          final address = await _probeOnce(http);
          exitAddress = address;
          final expected = server?.host;
          if (expected != null && address != expected) {
            end(traffic, CheckState.ok,
                'сайты видят адрес $address (у сервера другой исходящий адрес)');
          } else {
            end(traffic, CheckState.ok, 'сайты видят адрес сервера $address');
          }
        } catch (_) {
          end(traffic, CheckState.fail, 'запрос через туннель не прошёл');
          advice.add('Туннель поднят, но трафик не проходит. Запустите '
              'проверку «Сервер изнутри» — для неё нужен пароль от сервера.');
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
            'маршруты по доменам выключены — работают только списки IP');
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
          end(dns, CheckState.skip, 'у включённых сервисов нет доменов');
        } else {
          final watch = Stopwatch()..start();
          try {
            await InternetAddress.lookup(sample)
                .timeout(const Duration(seconds: 8));
            final ms = watch.elapsedMilliseconds;
            end(dns, ms > 1500 ? CheckState.warn : CheckState.ok,
                'имя $sample найдено за $ms мс');
            if (ms > 1500) {
              advice.add('DNS отвечает медленно — сайты могут открываться '
                  'с задержкой. Попробуйте другой DNS в настройках.');
            }
          } catch (_) {
            end(dns, CheckState.fail, 'имя $sample не найдено');
            advice.add('DNS не отвечает. Попробуйте другой DNS в настройках.');
          }
        }
      }

      // 5. Маршруты.
      begin(routes);
      if (!on) {
        end(routes, CheckState.skip, offNote);
      } else {
        final expected = allowedIps(_activeCidrs).length;
        final actual = await _tunnel.allowedIpCount();
        if (actual == null) {
          end(routes, CheckState.fail, 'не удалось прочитать маршруты туннеля');
        } else if (actual < expected) {
          end(routes, CheckState.warn,
              'в туннеле $actual из $expected адресов и диапазонов');
          advice.add('Часть маршрутов потерялась. Выключите и включите VPN.');
        } else {
          end(
            routes,
            CheckState.ok,
            settings.fullTunnel
                ? 'весь трафик направлен в туннель'
                : '${collectCidrs(services, enabled).length} диапазонов и '
                    '${_routed.length} адресов по доменам — все на месте',
          );
        }
      }

      // 6. Сервисы.
      begin(sites);
      if (!on) {
        end(sites, CheckState.skip, offNote);
      } else {
        final targets = <String, String>{};
        for (final s in active) {
          final host = serviceProbeHosts[s.id] ??
              (s.domains.isEmpty ? '' : s.domains.first);
          if (host.isNotEmpty) targets[s.name] = host;
        }
        if (targets.isEmpty) {
          end(sites, CheckState.skip, 'нет сервисов с доменами для проверки');
        } else {
          final names = targets.keys.toList();
          final results =
              await Future.wait([for (final n in names) _reachable(targets[n]!)]);
          final failed = [
            for (var i = 0; i < names.length; i++)
              if (!results[i]) names[i],
          ];
          if (failed.isEmpty) {
            end(sites, CheckState.ok, 'отвечают все: ${names.length}');
          } else {
            end(
              sites,
              failed.length == names.length ? CheckState.fail : CheckState.warn,
              '${names.length - failed.length} из ${names.length} отвечают · '
              'не ответили: ${failed.join(', ')}',
            );
            advice.add('${failed.join(', ')}: нет ответа через туннель. Чаще '
                'всего сервис блокирует адрес сервера — попробуйте другой '
                'сервер.');
          }
        }
      }

      // 7. Скорость.
      begin(speed);
      if (!on) {
        end(speed, CheckState.skip, offNote);
      } else {
        try {
          final result = await _speedTest();
          if (result.throughTunnel) {
            end(speed, CheckState.ok,
                '↓ ${_mbit(result.down)} · ↑ ${_mbit(result.up)} через туннель');
          } else {
            end(speed, CheckState.warn,
                '↓ ${_mbit(result.down)} · ↑ ${_mbit(result.up)}, но замер, '
                'похоже, прошёл мимо туннеля');
          }
        } catch (e) {
          end(speed, CheckState.warn, 'замерить не удалось: $e');
        }
      }

      // 8. Сервер изнутри.
      begin(remote);
      final creds = credentials[server?.host];
      if (creds == null) {
        end(remote, CheckState.skip,
            'нужен пароль от сервера — введите его в «Поделиться» у этого '
            'сервера');
      } else {
        try {
          final lines = await diagnoseServer(creds);
          _addBlock('диагностика сервера', lines);
          end(remote, CheckState.ok,
              'отчёт получен и записан во вкладку «Подробно»');
        } catch (e) {
          end(remote, CheckState.fail, 'не удалось подключиться: $e');
        }
      }
    } catch (e) {
      addLog('Диагностика прервалась: $e');
    }

    int count(CheckState state) => checks.where((c) => c.state == state).length;
    final failed = count(CheckState.fail);
    final warned = count(CheckState.warn);
    if (!on) {
      checkSummary = 'VPN выключен';
      checkAdvice = 'Включите VPN на вкладке «Сервисы» и повторите проверку — '
          'тогда проверятся связь, DNS, маршруты и сервисы.';
    } else if (failed > 0) {
      checkSummary = 'Есть проблемы: $failed';
      checkAdvice = advice.join(' ');
    } else if (warned > 0) {
      checkSummary = 'VPN работает, замечаний: $warned';
      checkAdvice = advice.join(' ');
    } else {
      checkSummary = 'Всё в порядке';
      checkAdvice = 'VPN работает, включённые сервисы отвечают.';
    }
    addLog('Диагностика завершена: в порядке ${count(CheckState.ok)}, '
        'замечаний $warned, ошибок $failed, пропущено '
        '${count(CheckState.skip)}.');
    checking = false;
    notifyListeners();
  }

  /// Текст отчёта диагностики для копирования.
  String get checkReport => [
        'Диагностика ColdVPN: $checkSummary',
        for (final c in checks) '${_stateWord(c.state)} — ${c.title}: ${c.note}',
        if (checkAdvice.isNotEmpty) checkAdvice,
      ].join('\n');

  static String _stateWord(CheckState state) {
    switch (state) {
      case CheckState.ok:
        return 'В порядке';
      case CheckState.warn:
        return 'Замечание';
      case CheckState.fail:
        return 'Ошибка';
      case CheckState.skip:
        return 'Пропущено';
      case CheckState.run:
        return 'Идёт';
      case CheckState.wait:
        return 'В очереди';
    }
  }

  static String stateWord(CheckState state) => _stateWord(state);
}
