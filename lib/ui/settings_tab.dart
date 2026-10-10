import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';
import 'shell.dart';
import 'theme.dart';

const repositoryUrl = 'https://github.com/ColdVision/ColdVPN';
const appVersion = '0.0.1';

const _settingsFiles =
    XTypeGroup(label: 'Настройки ColdVPN', extensions: ['json']);

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
      final location = await getSaveLocation(
        suggestedName: 'coldvpn-settings.json',
        acceptedTypeGroups: const [_settingsFiles],
      );
      if (location == null) return;
      var path = location.path;
      if (!path.toLowerCase().endsWith('.json')) path = '$path.json';
      await File(path).writeAsString(state.exportSettings());
      if (mounted) showNote(context, 'Настройки сохранены: $path');
    } catch (e) {
      if (mounted) showNote(context, 'Не удалось сохранить настройки: $e');
    }
  }

  Future<void> _import() async {
    try {
      final file = await openFile(acceptedTypeGroups: const [_settingsFiles]);
      if (file == null) return;
      final problem = await state.importSettings(await file.readAsString());
      if (!mounted) return;
      _syncDnsField();
      showNote(context, problem ?? 'Настройки загружены');
    } catch (e) {
      if (mounted) showNote(context, 'Не удалось прочитать файл: $e');
    }
  }

  Future<void> _reset() async {
    await state.resetAll();
    if (!mounted) return;
    setState(() => _confirmReset = false);
    _syncDnsField();
    showNote(context, 'Настройки сброшены');
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
    if (state.updatingLists) return 'Загружаю списки с GitHub…';
    final at = state.listsUpdatedAt;
    if (at == null) return 'Встроены в эту версию приложения';
    String two(int n) => n.toString().padLeft(2, '0');
    return 'Обновлены ${two(at.day)}.${two(at.month)}.${at.year} в '
        '${two(at.hour)}:${two(at.minute)}';
  }

  Future<void> _openRepository() async {
    try {
      if (Platform.isWindows) {
        await Process.run('explorer', [repositoryUrl]);
        return;
      }
    } catch (_) {}
    if (mounted) await copyText(context, repositoryUrl, 'Ссылка скопирована');
  }

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
        const TabHeader(title: 'Настройки'),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 18),
            children: [
              const SectionTitle('Запуск'),
              const SizedBox(height: 8),
              CvCard(
                padding: const EdgeInsets.fromLTRB(14, 4, 2, 4),
                child: Column(
                  children: [
                    _SwitchRow(
                      title: 'Запускать вместе с системой',
                      note: 'При входе в Windows, сразу в трей',
                      value: state.autostart,
                      onChanged: state.platformSupported
                          ? (value) => state.setAutostart(value)
                          : null,
                    ),
                    _SwitchRow(
                      title: 'Подключаться при запуске',
                      note: 'Если в прошлый раз VPN был включён',
                      value: settings.connectOnStart,
                      onChanged: (value) => state.changeSettings(
                        (s) => s.connectOnStart = value,
                        reconnect: false,
                      ),
                    ),
                    _SwitchRow(
                      title: 'Сворачивать в трей при закрытии',
                      note: 'VPN продолжит работать в фоне. Выход — через '
                          'значок в трее',
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
              const SizedBox(height: 8),
              const SectionTitle('Маршрутизация'),
              const SizedBox(height: 8),
              CvCard(
                padding: const EdgeInsets.fromLTRB(14, 4, 2, 4),
                child: Column(
                  children: [
                    _SwitchRow(
                      title: 'Маршруты по доменам',
                      note: 'Добавлять адреса сервисов на лету через DNS',
                      value: settings.domainRouting,
                      onChanged: (value) =>
                          state.changeSettings((s) => s.domainRouting = value),
                    ),
                    _SwitchRow(
                      title: 'Только IPv4 для сервисов из списка',
                      note: 'Чтобы трафик не ушёл по IPv6 мимо VPN',
                      value: settings.ipv4Only,
                      last: true,
                      onChanged: (value) =>
                          state.changeSettings((s) => s.ipv4Only = value),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              const SectionTitle('DNS для сервисов в туннеле'),
              const SizedBox(height: 8),
              CvSegments<String>(
                options: const {
                  _cloudflare: 'Cloudflare',
                  _google: 'Google',
                  'custom': 'Свой',
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
                  label: 'Адрес своего DNS-сервера',
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
                      : 'Нужен адрес IPv4, например 9.9.9.9. Пока используется '
                          '${settings.dns}.',
                ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Через него узнаются адреса только включённых сервисов. '
                'Остальные сайты используют обычный DNS вашей сети.',
                style: tx(12, c: C.muted, h: 1.45),
              ),
              const SizedBox(height: 8),
              const SectionTitle('Списки сервисов'),
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
                                  'Сервисов: ${state.builtin.length} · '
                                  'доменов: ${state.builtinDomainCount}',
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
                              label: state.updatingLists ? 'Идёт…' : 'Обновить',
                              height: 44,
                              onTap: state.updatingLists ? null : _updateLists,
                            ),
                          ),
                        ],
                      ),
                    ),
                    _SwitchRow(
                      title: 'Обновлять автоматически',
                      note: 'Раз в неделю, при запуске приложения',
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
              const SectionTitle('Перенос и сброс'),
              const SizedBox(height: 8),
              CvCard(
                padding: const EdgeInsets.all(6),
                child: Column(
                  children: [
                    _ActionLine(
                      title: 'Сохранить настройки в файл',
                      note: 'Серверы, свои маршруты и порядок групп. В файле '
                          'есть ключи серверов — храните его как пароль',
                      onTap: _export,
                    ),
                    _ActionLine(
                      title: 'Загрузить настройки из файла',
                      note: 'Текущие настройки будут заменены',
                      onTap: _import,
                    ),
                    _ActionLine(
                      title: 'Сбросить все настройки',
                      note: 'Вернуть приложение к начальному состоянию',
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
                    question: 'Сбросить все настройки?',
                    note: 'Удалятся серверы, свои маршруты и порядок групп. '
                        'Сами серверы останутся настроенными — их можно будет '
                        'добавить снова.',
                    cancelLabel: 'Не сбрасывать',
                    confirmLabel: 'Сбросить',
                    onCancel: () => setState(() => _confirmReset = false),
                    onConfirm: _reset,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              const SectionTitle('О программе'),
              const SizedBox(height: 8),
              CvCard(
                child: Column(
                  children: [
                    const _InfoRow(label: 'ColdVPN', value: appVersion),
                    const SizedBox(height: 6),
                    const _InfoRow(label: 'Клиент AmneziaWG', value: '2.0.1'),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Text('Исходный код', style: tx(14, c: C.soft)),
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

class _ActionLine extends StatelessWidget {
  const _ActionLine({
    required this.title,
    required this.note,
    required this.onTap,
    this.danger = false,
  });

  final String title;
  final String note;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = danger ? C.dangerText : C.white;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(13),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(title, style: tx(14, w: w600, c: color)),
                    const SizedBox(height: 2),
                    Text(note, style: tx(12, c: C.muted, h: 1.4)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, size: 18, color: color),
            ],
          ),
        ),
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
