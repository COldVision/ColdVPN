import 'package:flutter/material.dart';

import '../app_state.dart';
import '../server_installer.dart';
import 'theme.dart';

/// Панель «Установить на свой VPS».
Future<void> showInstallSheet(BuildContext context, AppState state) {
  return showCvSheet<void>(
    context,
    builder: (_) => _InstallSheet(state: state),
  );
}

class _InstallSheet extends StatefulWidget {
  const _InstallSheet({required this.state});

  final AppState state;

  @override
  State<_InstallSheet> createState() => _InstallSheetState();
}

class _InstallSheetState extends State<_InstallSheet> {
  final _host = TextEditingController();
  final _sshPort = TextEditingController(text: '22');
  final _user = TextEditingController(text: 'root');
  final _password = TextEditingController();
  final _key = TextEditingController();
  final _vpnPort = TextEditingController();

  final List<String> _log = [];
  bool _busy = false;
  bool _done = false;
  bool _advanced = false;
  bool _resetKeys = false;
  bool _remember = true;
  String? _error;

  @override
  void dispose() {
    for (final c in [_host, _sshPort, _user, _password, _key, _vpnPort]) {
      c.dispose();
    }
    super.dispose();
  }

  int? _port(String text) {
    final port = int.tryParse(text.trim());
    return (port == null || port < 1 || port > 65535) ? null : port;
  }

  String? _validate() {
    if (_host.text.trim().isEmpty) return 'Укажите адрес сервера.';
    if (_port(_sshPort.text) == null) return 'Порт SSH — число от 1 до 65535.';
    if (_user.text.trim().isEmpty) return 'Укажите логин.';
    if (_password.text.isEmpty && _key.text.trim().isEmpty) {
      return 'Укажите пароль или SSH-ключ.';
    }
    if (_vpnPort.text.trim().isNotEmpty && _port(_vpnPort.text) == null) {
      return 'UDP-порт VPN — число от 1 до 65535 или пусто.';
    }
    return null;
  }

  Future<void> _install() async {
    final problem = _validate();
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _log.clear();
    });
    final state = widget.state;
    var warnings = false;
    try {
      final request = InstallRequest(
        host: _host.text.trim(),
        sshPort: _port(_sshPort.text)!,
        username: _user.text.trim(),
        password: _password.text,
        privateKeyPem: _key.text,
        vpnPort: _port(_vpnPort.text) ?? 0,
        resetKeys: _resetKeys,
      );
      final profile = await installServer(
        request,
        (line) {
          if (mounted) setState(() => _log.add(line));
        },
        important: (line, {required bool problem}) {
          state.addLog(line);
          if (problem) warnings = true;
        },
      );
      await state.addOrReplaceServer(profile);
            await state.rememberCredentials(request, persist: _remember);
      state.addLog('Сервер ${profile.host} настроен, UDP-порт ${profile.port}.');
      _password.clear();
      _key.clear();
      if (!mounted) return;
      if (warnings) {
        // Оставляем панель открытой, чтобы предупреждения можно было прочитать.
        setState(() {
          _done = true;
          _error = 'Сервер сохранён, но при установке были предупреждения — '
              'они в журнале ниже.';
        });
      } else {
        showNote(context, 'Сервер настроен и добавлен');
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SheetHeader(
            icon: Icons.cloud_upload_outlined,
            title: 'Установка на VPS',
            subtitle: 'Приложение само поставит AmneziaWG',
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: CvField(
                  controller: _host,
                  label: 'IP-адрес сервера',
                  hint: '203.0.113.10',
                  mono: true,
                  enabled: !_busy,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: CvField(
                  controller: _sshPort,
                  label: 'Порт SSH',
                  mono: true,
                  enabled: !_busy,
                  keyboardType: TextInputType.number,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          CvField(controller: _user, label: 'Логин', enabled: !_busy),
          const SizedBox(height: 12),
          CvField(
            controller: _password,
            label: 'Пароль',
            obscure: true,
            enabled: !_busy,
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Запомнить пароль', style: tx(14, w: w600, c: C.white)),
                    Text(
                      'Чтобы потом выпускать ключи для других устройств. '
                      'Хранится на этом компьютере в зашифрованном виде',
                      style: tx(12, c: C.muted, h: 1.4),
                    ),
                  ],
                ),
              ),
              CvSwitch(
                value: _remember,
                label: 'Запомнить пароль',
                onChanged:
                    _busy ? null : (value) => setState(() => _remember = value),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: CvLink(
              label: _advanced ? 'Скрыть дополнительное' : 'Дополнительно',
              onTap: () => setState(() => _advanced = !_advanced),
            ),
          ),
          Reveal(
            show: _advanced,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
            const SizedBox(height: 6),
            CvField(
              controller: _key,
              label: 'Приватный SSH-ключ вместо пароля',
              hint: '-----BEGIN OPENSSH PRIVATE KEY-----',
              mono: true,
              minLines: 2,
              maxLines: 5,
              enabled: !_busy,
              keyboardType: TextInputType.multiline,
            ),
            const SizedBox(height: 12),
            CvField(
              controller: _vpnPort,
              label: 'UDP-порт VPN',
              mono: true,
              enabled: !_busy,
              keyboardType: TextInputType.number,
              helper: 'Пусто — сервер выберет случайный и запомнит',
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Выпустить новые ключи',
                        style: tx(14, w: w600, c: C.white),
                      ),
                      Text(
                        'Уже подключённые устройства перестанут работать',
                        style: tx(12, c: C.muted),
                      ),
                    ],
                  ),
                ),
                CvSwitch(
                  value: _resetKeys,
                  label: 'Выпустить новые ключи',
                  onChanged: _busy
                      ? null
                      : (value) => setState(() => _resetKeys = value),
                ),
              ],
            ),
              ],
            ),
          ),
          Reveal(
            show: _error != null,
            child: Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(_error ?? '', style: tx(13, c: C.dangerText, h: 1.4)),
            ),
          ),
          if (_log.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color.fromRGBO(4, 6, 20, 0.85),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: C.cardLine),
              ),
              child: SelectableText(
                _log.join('\n'),
                style: tx(12, c: const Color(0xFFD7DCF7), mono: true, h: 1.6),
              ),
            ),
          const SizedBox(height: 14),
          if (_done)
            CvButton(
              label: 'Готово',
              kind: CvButtonKind.primary,
              onTap: () => Navigator.of(context).pop(),
            )
          else
            CvButton(
              label: _busy ? 'Устанавливаю…' : 'Установить AmneziaWG',
              kind: CvButtonKind.primary,
              onTap: _busy ? null : _install,
            ),
        ],
      ),
    );
  }
}
