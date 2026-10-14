import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';
import 'files.dart';
import 'guide_page.dart';
import 'shell.dart';
import 'theme.dart';
import '../l10n.dart';

const repositoryUrl = 'https://github.com/ColdVision/ColdVPN';
const appVersion = '0.1.3';

XTypeGroup get _settingsFiles =>
    XTypeGroup(label: tr('Настройки ColdVPN'), extensions: ['json']);

/// Вкладка «Настройки».
class SettingsTab extends StatefulWidget {
  const SettingsTab({super.key, required this.state});

  final AppState state;

  @override
  State<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<SettingsTab> {
  late final TextEditingController _dns;
  bool _customDns = false;
  bool _confirmReset = false;

  AppState get state => widget.state;

  static const _cloudflare = '1.0.0.1';
  static const _google = '8.8.8.8';

  @override
  void initState() {
    super.initState();
    final dns = state.settings.dns;
    _customDns = dns != _cloudflare && dns != _google;
    _dns = TextEditingController(text: _customDns ? dns : '');
  }

  @override
  void dispose() {
    _dns.dispose();
    super.dispose();
  }

  bool _validIp(String value) {
    final parts = value.split('.');
    if (parts.length != 4) return false;
    return parts.every((p) {
      final n = int.tryParse(p);
      return n != null && n >= 0 && n <= 255 && p.length <= 3;
    });
  }

  void _pickDns(String choice) {
    if (choice == 'custom') {
      setState(() => _customDns = true);
      final value = _dns.text.trim();
      if (_validIp(value)) state.changeSettings((s) => s.dns = value);
    } else {
      setState(() => _customDns = false);
      state.changeSettings((s) => s.dns = choice);
    }
  }

  Future<void> _updateLists() async {
    final summary = await state.updateLists();
    if (mounted) showNote(context, summary);
  }

  Future<void> _export() async {
    try {
      final note = savedNote(
        tr('Настройки сохранены'),
        await saveTextFile(
          name: 'coldvpn-settings.json',
          text: state.exportSettings(),
          type: _settingsFiles,
          mimeType: 'application/json',
        ),
      );
      if (mounted && note != null) showNote(context, note);
    } catch (e) {
      if (mounted) showNote(context, tr('Не удалось сохранить настройки: {0}', [e]));
    }
  }

  Future<void> _import() async {
    try {
      final file = await pickFile(_settingsFiles);
      if (file == null) return;
      final problem = await state.importSettings(await file.readAsString());
      if (!mounted) return;
      _syncDnsField();
      showNote(context, problem ?? tr('Настройки загружены'));
    } catch (e) {
      if (mounted) showNote(context, tr('Не удалось прочитать файл: {0}', [e]));
    }
  }

  Future<void> _reset() async {
    await state.resetAll();
    if (!mounted) return;
    setState(() => _confirmReset = false);
    _syncDnsField();
    showNote(context, tr('Настройки сброшены'));
  }

  /// После загрузки или сброса настроек поле своего DNS должно показывать
  /// новое значение.
  void _syncDnsField() {
    final dns = state.settings.dns;
    setState(() {
      _customDns = dns != _cloudflare && dns != _google;
      _dns.text = _customDns ? dns : '';
    });
  }

  String _listsNote() {
    if (state.updatingLists) return tr('Загружаю списки с GitHub…');
    final at = state.listsUpdatedAt;
    if (at == null) return tr('Встроены в эту версию приложения');
    String two(int n) => n.toString().padLeft(2, '0');
    return tr('Обновлены {0}.{1}.{2} в '
        '{3}:{4}', [two(at.day), two(at.month), at.year, two(at.hour), two(at.minute)]);
  }

  Future<void> _openRepository() => openLink(context, repositoryUrl);

  @override
  Widget build(BuildContext context) {
    final settings = state.settings;
    final dnsChoice = _customDns
        ? 'custom'
        : (settings.dns == _google ? _google : _cloudflare);
    final customValue = _dns.text.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TabHeader(title: tr('Настройки')),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 18),
            children: [
              // Названия языков не переводятся: их должен узнать тот, кто
              // не читает на текущем языке.
              const SectionTitle('Язык · Language'),
              const SizedBox(height: 8),
              CvSegments<String>(
                options: const {'ru': 'Русский', 'en': 'English'},
                selected: appLang,
                onChanged: state.setLanguage,
              ),
              const SizedBox(height: 8),
              SectionTitle(tr('Запуск')),
              const SizedBox(height: 8),
              CvCard(
                padding: const EdgeInsets.fromLTRB(14, 4, 2, 4),
                child: Column(
                  children: [
                    if (Platform.isWindows)
                    _SwitchRow(
                      title: tr('Запускать вместе с системой'),
                      note: tr('При входе в Windows'),
                      value: state.autostart,
                      onChanged: state.platformSupported
                          ? (value) => state.setAutostart(value)
                          : null,
                    ),
                    if (Platform.isWindows)
                    _SwitchRow(
                      title: tr('Запускать в свёрнутом режиме'),
                      note: tr('Окно не открывается — приложение сразу уходит '
                          'в трей. Открыть — щелчком по значку'),
                      value: settings.startInTray,
                      onChanged: state.platformSupported
                          ? (value) => state.changeSettings(
                                (s) => s.startInTray = value,
                                reconnect: false,
                              )
                          : null,
                    ),
                    _SwitchRow(
                      title: tr('Подключаться при запуске'),
                      note: state.isAndroid
                          ? tr('При открытии приложения, если VPN был включён')
                          : tr('Если в прошлый раз VPN был включён'),
                      value: settings.connectOnStart,
                      last: !Platform.isWindows,
                      onChanged: (value) => state.changeSettings(
                        (s) => s.connectOnStart = value,
                        reconnect: false,
                      ),
                    ),
                    if (Platform.isWindows)
                    _SwitchRow(
                      title: tr('Сворачивать в трей при закрытии'),
                      note: tr('VPN продолжит работать в фоне. Выход — через '
                          'значок в трее'),
                      value: settings.closeToTray,
                      last: true,
                      onChanged: state.platformSupported
                          ? (value) => state.changeSettings(
                                (s) => s.closeToTray = value,
                                reconnect: false,
                              )
                          : null,
                    ),
                  ],
                ),
              ),
              // Маршруты по доменам есть только на Windows.
              if (!state.isAndroid) ...[
              const SizedBox(height: 8),
              SectionTitle(tr('Маршрутизация')),
              const SizedBox(height: 8),
              CvCard(
                padding: const EdgeInsets.fromLTRB(14, 4, 2, 4),
                child: Column(
                  children: [
                    _SwitchRow(
                      title: tr('Маршруты по доменам'),
                      note: tr('Добавлять адреса сервисов на лету через DNS'),
                      value: settings.domainRouting,
                      onChanged: (value) =>
                          state.changeSettings((s) => s.domainRouting = value),
                    ),
                    _SwitchRow(
                      title: tr('Только IPv4 для сервисов из списка'),
                      note: tr('Чтобы трафик не ушёл по IPv6 мимо VPN'),
                      value: settings.ipv4Only,
                      last: true,
                      onChanged: (value) =>
                          state.changeSettings((s) => s.ipv4Only = value),
                    ),
                  ],
                ),
              ),
              ],
              const SizedBox(height: 8),
              SectionTitle(tr('DNS для сервисов в туннеле')),
              const SizedBox(height: 8),
              CvSegments<String>(
                options: {
                  _cloudflare: 'Cloudflare',
                  _google: 'Google',
                  'custom': tr('Свой'),
                },
                subtitles: {
                  _cloudflare: _cloudflare,
                  _google: _google,
                  'custom': customValue.isEmpty ? '—' : customValue,
                },
                selected: dnsChoice,
                onChanged: _pickDns,
              ),
              Reveal(
                show: _customDns,
                child: Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: CvField(
                  controller: _dns,
                  label: tr('Адрес своего DNS-сервера'),
                  hint: '9.9.9.9',
                  mono: true,
                  keyboardType: TextInputType.number,
                  onChanged: (value) {
                    setState(() {});
                    final ip = value.trim();
                    if (_validIp(ip)) state.changeSettings((s) => s.dns = ip);
                  },
                  helper: customValue.isEmpty || _validIp(customValue)
                      ? null
                      : tr('Нужен адрес IPv4, например 9.9.9.9. Пока используется '
                          '{0}.', [settings.dns]),
                ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                tr('Через него узнаются адреса только включённых сервисов. '
                'Остальные сайты используют обычный DNS вашей сети.'),
                style: tx(12, c: C.muted, h: 1.45),
              ),
              const SizedBox(height: 8),
              SectionTitle(tr('Списки сервисов')),
              const SizedBox(height: 8),
              CvCard(
                padding: const EdgeInsets.fromLTRB(14, 4, 2, 4),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.fromLTRB(0, 10, 10, 10),
                      decoration: const BoxDecoration(
                        border: Border(bottom: BorderSide(color: C.rowLine)),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  tr('Сервисов: {0} · '
                                  'доменов: {1}', [state.builtin.length, state.builtinDomainCount]),
                                  style: tx(14, w: w600, c: C.white),
                                ),
                                const SizedBox(height: 2),
                                FadeSwap(
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    _listsNote(),
                                    key: ValueKey(_listsNote()),
                                    style: tx(12, c: C.muted),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          SizedBox(
                            width: 116,
                            child: CvButton(
                              label: state.updatingLists ? tr('Идёт…') : tr('Обновить'),
                              height: 44,
                              onTap: state.updatingLists ? null : _updateLists,
                            ),
                          ),
                        ],
                      ),
                    ),
                    _SwitchRow(
                      title: tr('Обновлять автоматически'),
                      note: tr('Раз в неделю, при запуске приложения'),
                      value: settings.autoUpdateLists,
                      last: true,
                      onChanged: (value) => state.changeSettings(
                        (s) => s.autoUpdateLists = value,
                        reconnect: false,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              SectionTitle(tr('Перенос и сброс')),
              const SizedBox(height: 8),
              CvCard(
                padding: const EdgeInsets.all(6),
                child: Column(
                  children: [
                    ActionLine(
                      title: tr('Сохранить настройки в файл'),
                      note: tr('Серверы, разделы и ресурсы со всеми правками. В '
                          'файле есть ключи серверов — храните его как пароль'),
                      onTap: _export,
                    ),
                    ActionLine(
                      title: tr('Загрузить настройки из файла'),
                      note: tr('Текущие настройки будут заменены'),
                      onTap: _import,
                    ),
                    ActionLine(
                      title: tr('Восстановить стандартные разделы'),
                      note: tr('Вернуть удалённые разделы и ресурсы. Ваши правки '
                          'и свои ресурсы останутся'),
                      onTap: () {
                        state.restoreDefaults();
                        showNote(context, tr('Стандартные разделы возвращены'));
                      },
                    ),
                    ActionLine(
                      title: tr('Сбросить все настройки'),
                      note: tr('Вернуть приложение к начальному состоянию'),
                      danger: true,
                      onTap: () => setState(() => _confirmReset = true),
                    ),
                  ],
                ),
              ),
              Reveal(
                show: _confirmReset,
                child: Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: DangerConfirm(
                    question: tr('Сбросить все настройки?'),
                    note: tr('Удалятся серверы, свои разделы и ресурсы, правки в '
                        'списках. Сами серверы останутся настроенными — их можно будет '
                        'добавить снова.'),
                    cancelLabel: tr('Не сбрасывать'),
                    confirmLabel: tr('Сбросить'),
                    onCancel: () => setState(() => _confirmReset = false),
                    onConfirm: _reset,
                  ),
                ),
              ),
              if (Platform.isWindows) ...[
                const SizedBox(height: 8),
                SectionTitle(tr('Расширение для браузера')),
                const SizedBox(height: 8),
                _BrowserCard(state: state),
              ],
              const SizedBox(height: 8),
              SectionTitle(tr('О программе')),
              const SizedBox(height: 8),
              CvCard(
                padding: const EdgeInsets.all(6),
                child: ActionLine(
                  title: tr('Инструкция'),
                  note: tr('Как работает приложение и как пользоваться всеми '
                      'его функциями'),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => const GuidePage()),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              CvCard(
                child: Column(
                  children: [
                    const _InfoRow(label: 'ColdVPN', value: appVersion),
                    const SizedBox(height: 6),
                    _InfoRow(label: tr('Клиент AmneziaWG'), value: '2.0.1'),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Text(tr('Исходный код'), style: tx(14, c: C.soft)),
                        const Spacer(),
                        CvLink(
                          label: 'github.com/ColdVision/ColdVPN',
                          onTap: _openRepository,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.title,
    required this.note,
    required this.value,
    required this.onChanged,
    this.last = false,
  });

  final String title;
  final String note;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: last ? const Color(0x00000000) : C.rowLine,
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: tx(14, w: w600, c: C.white)),
                  const SizedBox(height: 2),
                  Text(note, style: tx(12, c: C.muted, h: 1.4)),
                ],
              ),
            ),
          ),
          CvSwitch(value: value, label: title, onChanged: onChanged),
        ],
      ),
    );
  }
}

/// Код для расширения и папка, из которой его ставят в Chrome.
class _BrowserCard extends StatelessWidget {
  const _BrowserCard({required this.state});

  final AppState state;

  String get _folder =>
      '${File(Platform.resolvedExecutable).parent.path}\\chrome_extension';

  @override
  Widget build(BuildContext context) {
    final status = switch (state.browserStatus) {
      VpnStatus.on => tr('Сейчас VPN в браузере включён'),
      VpnStatus.connecting => tr('VPN в браузере включается…'),
      VpnStatus.off => state.browserError ?? tr('Сейчас VPN в браузере выключен'),
    };
    return CvCard(
      padding: const EdgeInsets.all(6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 4, 4),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(tr('Код для расширения'),
                          style: tx(14, w: w600, c: C.white)),
                      const SizedBox(height: 4),
                      SelectableText(
                        state.browserKey,
                        style: tx(20, w: w700, c: C.tealText, mono: true),
                      ),
                    ],
                  ),
                ),
                CvLink(
                  label: tr('Скопировать'),
                  onTap: () =>
                      copyText(context, state.browserKey, tr('Код скопирован')),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 6),
            child: Text(status, style: tx(12, c: C.muted, h: 1.4)),
          ),
          ActionLine(
            title: tr('Открыть папку расширения'),
            note: tr('В Chrome: «Расширения» → «Режим разработчика» → '
                '«Загрузить распакованное» и выберите эту папку'),
            onTap: () async {
              if (Directory(_folder).existsSync()) {
                await Process.run('explorer', [_folder]);
              } else if (context.mounted) {
                showNote(context, tr('Папка расширения не найдена: {0}', [_folder]));
              }
            },
          ),
          ActionLine(
            title: tr('Сменить код'),
            note: tr('Расширения со старым кодом перестанут управлять приложением'),
            onTap: state.regenerateBrowserKey,
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(label, style: tx(14, c: C.soft))),
        Text(value, style: tx(14, c: C.white, mono: true)),
      ],
    );
  }
}
