import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../app_state.dart';
import '../awg_config.dart';
import '../models.dart';
import '../qr_tools.dart';
import '../server_installer.dart';
import 'files.dart';
import 'install_sheet.dart';
import 'qr_scan_page.dart';
import 'shell.dart';
import 'theme.dart';
import '../l10n.dart';

XTypeGroup get _confFiles => XTypeGroup(label: tr('Конфиг AmneziaWG'), extensions: ['conf']);
XTypeGroup get _imageFiles => XTypeGroup(
  label: tr('Картинка с QR-кодом'),
  extensions: ['png', 'jpg', 'jpeg', 'bmp', 'gif', 'webp'],
);
XTypeGroup get _pngFiles => XTypeGroup(label: tr('Картинка PNG'), extensions: ['png']);

String get _notConf => tr('Не похоже на конфиг AmneziaWG: нужны секции [Interface] '
    '(PrivateKey, Address) и [Peer] (PublicKey, Endpoint).');

/// Страница, где продаётся подписка на готовый сервер.
const subscriptionUrl = 'https://boosty.to/coldvisionx';

/// Вкладка «Сервер»: выбранный сервер, список серверов и добавление.
class ServerTab extends StatelessWidget {
  const ServerTab({super.key, required this.state});

  final AppState state;

  Future<void> _importFile(BuildContext context) async {
    try {
      final file = await pickFile(_confFiles);
      if (file == null) return;
      final profile = parseClientConf(await file.readAsString());
      if (!context.mounted) return;
      if (profile == null) {
        showNote(context, _notConf);
        return;
      }
      final entry = await state.addServer(profile);
      state.addLog(tr('Импортирован конфиг сервера {0}:'
          '{1} из файла.', [profile.host, profile.port]));
      if (context.mounted) showNote(context, tr('Сервер «{0}» добавлен', [entry.name]));
    } catch (e) {
      if (context.mounted) showNote(context, tr('Не удалось прочитать файл: {0}', [e]));
    }
  }

  /// На телефоне сначала спрашивает, откуда брать код: с камеры или с
  /// картинки. На компьютере — сразу картинка.
  Future<void> _importQr(BuildContext context) async {
    if (!Platform.isAndroid) return _importQrImage(context);
    final source = await showCvSheet<String>(
      context,
      builder: (sheet) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SheetHeader(icon: Icons.qr_code, title: tr('Импорт из QR-кода')),
          const SizedBox(height: 10),
          _ActionRow(
            icon: Icons.photo_camera_outlined,
            title: tr('Сканировать камерой'),
            note: tr('Наведите телефон на код'),
            onTap: () => Navigator.of(sheet).pop('camera'),
          ),
          _ActionRow(
            icon: Icons.image_outlined,
            title: tr('Выбрать картинку'),
            note: tr('Снимок экрана или фото с кодом'),
            onTap: () => Navigator.of(sheet).pop('image'),
          ),
        ],
      ),
    );
    if (!context.mounted || source == null) return;
    if (source == 'image') return _importQrImage(context);
    final text = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const QrScanPage()),
    );
    if (text == null || !context.mounted) return;
    await _addFromQr(context, text);
  }

  Future<void> _importQrImage(BuildContext context) async {
    try {
      final file = await pickFile(_imageFiles, mobileMime: 'image/*');
      if (file == null) return;
      final bytes = await file.readAsBytes();
      // Распознавание идёт в фоне, чтобы окно не замирало.
      final text = await compute(decodeQrImage, bytes);
      if (!context.mounted) return;
      if (text == null) {
        showNote(context, tr('На картинке не удалось найти QR-код.'));
        return;
      }
      await _addFromQr(context, text);
    } catch (e) {
      if (context.mounted) showNote(context, tr('Не удалось прочитать картинку: {0}', [e]));
    }
  }

  Future<void> _addFromQr(BuildContext context, String text) async {
    try {
      final profile = parseClientConf(text);
      if (profile == null) {
        showNote(context, tr('В QR-коде не конфиг AmneziaWG.'));
        return;
      }
      final entry = await state.addServer(profile);
      state.addLog(tr('Импортирован конфиг сервера {0}:'
          '{1} из QR-кода.', [profile.host, profile.port]));
      if (context.mounted) showNote(context, tr('Сервер «{0}» добавлен', [entry.name]));
    } catch (e) {
      if (context.mounted) showNote(context, tr('Не удалось добавить сервер: {0}', [e]));
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = state.current;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TabHeader(
          title: tr('Сервер'),
          trailing: ServerPicker(state: state),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
            children: [
              if (current == null)
                CvCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(tr('Сервера пока нет'), style: tx(16, w: w600, c: C.white)),
                      const SizedBox(height: 4),
                      Text(
                        tr('Арендуйте VPS и установите на него VPN прямо отсюда '
                        'или добавьте готовый конфиг AmneziaWG.'),
                        style: tx(13, c: C.muted, h: 1.45),
                      ),
                    ],
                  ),
                )
              else
                _CurrentCard(state: state, server: current),
              if (state.servers.isNotEmpty) ...[
                const SizedBox(height: 14),
                SectionTitle(tr('Мои серверы')),
                const SizedBox(height: 8),
                for (final s in state.servers)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _ServerRow(
                      state: state,
                      server: s,
                      selected: s.id == current?.id,
                    ),
                  ),
              ],
              const SizedBox(height: 6),
              SectionTitle(tr('Добавить сервер')),
              const SizedBox(height: 8),
              CvCard(
                padding: const EdgeInsets.all(6),
                child: Column(
                  children: [
                    _SubscribeButton(
                      onTap: () => openLink(context, subscriptionUrl),
                    ),
                    const SizedBox(height: 4),
                    _ActionRow(
                      icon: Icons.cloud_upload_outlined,
                      title: tr('Установить на свой VPS'),
                      note: tr('Нужны адрес сервера, логин и пароль'),
                      onTap: () => showInstallSheet(context, state),
                    ),
                    _ActionRow(
                      icon: Icons.content_paste,
                      title: tr('Вставить конфиг текстом'),
                      note: tr('Например, из сообщения'),
                      onTap: () => showCvSheet<void>(
                        context,
                        builder: (_) => _PasteSheet(state: state),
                      ),
                    ),
                    _ActionRow(
                      icon: Icons.qr_code,
                      title: tr('Импорт из QR-кода'),
                      note: Platform.isAndroid
                          ? tr('Камерой или с картинки')
                          : tr('Картинка или снимок экрана с кодом'),
                      onTap: () => _importQr(context),
                    ),
                    _ActionRow(
                      icon: Icons.insert_drive_file_outlined,
                      title: tr('Импорт из файла .conf'),
                      note: tr('Готовый конфиг AmneziaWG'),
                      onTap: () => _importFile(context),
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

class _CurrentCard extends StatelessWidget {
  const _CurrentCard({required this.state, required this.server});

  final AppState state;
  final SavedServer server;

  @override
  Widget build(BuildContext context) {
    final on = state.status == VpnStatus.on;
    final last = state.lastHandshake;
    final age = last == null ? null : DateTime.now().difference(last).inSeconds;
    return CvCard(
      color: const Color.fromRGBO(42, 44, 132, 0.6),
      line: const Color.fromRGBO(110, 150, 255, 0.5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  server.name,
                  overflow: TextOverflow.ellipsis,
                  style: tx(20, w: w700, c: C.white),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: on
                      ? const Color.fromRGBO(31, 159, 144, 0.22)
                      : const Color.fromRGBO(90, 100, 160, 0.25),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: on
                        ? const Color.fromRGBO(88, 224, 200, 0.55)
                        : const Color.fromRGBO(150, 160, 220, 0.4),
                  ),
                ),
                child: Text(
                  on ? tr('Подключён') : tr('Не подключён'),
                  style: tx(12, w: w600, c: on ? const Color(0xFFC9F7EE) : C.soft),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(server.profile.host, style: tx(13, c: C.soft, mono: true)),
          const SizedBox(height: 10),
          Row(
            children: [
              CountryBadge(server),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  server.place.isEmpty ? tr('Место не определено') : server.place,
                  overflow: TextOverflow.ellipsis,
                  style: tx(14, c: C.text),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _Stat(label: tr('Порт'), value: '${server.profile.port}'),
              _Stat(
                label: tr('Связь'),
                value: !on ? '—' : (age == null ? tr('нет') : tr('{0} с назад', [age])),
              ),
              _Stat(
                label: tr('Трафик'),
                value: on ? formatBytes(state.received + state.sent) : '—',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: tx(12, c: C.muted)),
          const SizedBox(height: 2),
          Text(
            value,
            overflow: TextOverflow.ellipsis,
            style: tx(14, w: w600, c: C.white, mono: true),
          ),
        ],
      ),
    );
  }
}

class _ServerRow extends StatelessWidget {
  const _ServerRow({
    required this.state,
    required this.server,
    required this.selected,
  });

  final AppState state;
  final SavedServer server;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return CvCard(
      radius: 14,
      padding: EdgeInsets.zero,
      color: selected ? C.rowOn : C.card,
      line: selected ? const Color.fromRGBO(130, 150, 255, 0.55) : C.cardLine,
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              button: true,
              selected: selected,
              child: InkWell(
                onTap: () => state.selectServer(server.id),
                borderRadius: BorderRadius.circular(14),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
                  child: Row(
                    children: [
                      Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            width: 2,
                            color: selected
                                ? C.teal
                                : const Color.fromRGBO(150, 160, 220, 0.6),
                          ),
                        ),
                        alignment: Alignment.center,
                        child: selected
                            ? Container(
                                width: 10,
                                height: 10,
                                decoration: const BoxDecoration(
                                  color: C.teal,
                                  shape: BoxShape.circle,
                                ),
                              )
                            : null,
                      ),
                      const SizedBox(width: 12),
                      CountryBadge(server),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              server.name,
                              overflow: TextOverflow.ellipsis,
                              style: tx(14, w: w600, c: C.white),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              server.place.isEmpty
                                  ? server.profile.host
                                  : '${server.place} · ${server.profile.host}',
                              overflow: TextOverflow.ellipsis,
                              style: tx(12, c: C.muted),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          CvIconButton(
            icon: Icons.more_vert,
            tooltip: tr('Действия с сервером «{0}»', [server.name]),
            framed: false,
            onTap: () => showCvSheet<void>(
              context,
              builder: (_) => _ServerSheet(state: state, serverId: server.id),
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }
}

/// Кнопка «Купить подписку»: залита цветом, чтобы выделяться среди
/// остальных способов добавить сервер.
class _SubscribeButton extends StatelessWidget {
  const _SubscribeButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      child: Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [C.accentA, C.violet]),
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: const Color.fromRGBO(190, 175, 255, 0.8)),
        ),
        // Свой слой Material: иначе отклик на нажатие рисуется под заливкой.
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(13),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 60),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.workspace_premium_outlined,
                      size: 22, color: C.white),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          tr('Купить подписку'),
                          style: tx(15, w: w700, c: C.white),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            tr('Страница оплаты откроется в браузере'),
                            style: tx(12, c: const Color(0xFFE6E2FF), h: 1.4),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.open_in_new, size: 18, color: C.white),
                ],
              ),
            ),
          ),
        ),
        ),
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.icon,
    required this.title,
    required this.note,
    required this.onTap,
    this.danger = false,
  });

  final IconData icon;
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
              Icon(icon, size: 20, color: danger ? C.dangerText : C.soft),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(title, style: tx(14, w: w600, c: color)),
                    if (note.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(note, style: tx(12, c: C.muted, h: 1.4)),
                      ),
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

/// Вставка конфига текстом.
class _PasteSheet extends StatefulWidget {
  const _PasteSheet({required this.state});

  final AppState state;

  @override
  State<_PasteSheet> createState() => _PasteSheetState();
}

class _PasteSheetState extends State<_PasteSheet> {
  final _text = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final clip = await pasteText();
    if (clip.trim().isEmpty) return;
    setState(() {
      _text.text = clip;
      _error = null;
    });
  }

  Future<void> _add() async {
    final profile = parseClientConf(_text.text);
    if (profile == null) {
      setState(() => _error = _notConf);
      return;
    }
    await widget.state.addServer(profile);
    widget.state.addLog(
      tr('Добавлен сервер {0}:{1} из вставленного текста.', [profile.host, profile.port]),
    );
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SheetHeader(
            icon: Icons.content_paste,
            title: tr('Вставить конфиг'),
            subtitle: tr('Текст конфига AmneziaWG'),
          ),
          const SizedBox(height: 14),
          CvField(
            controller: _text,
            label: tr('Текст конфига'),
            hint: '[Interface]\nPrivateKey = …\nAddress = …\n\n'
                '[Peer]\nPublicKey = …\nEndpoint = …',
            mono: true,
            minLines: 9,
            maxLines: 14,
            keyboardType: TextInputType.multiline,
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
            trailing: CvLink(label: tr('Вставить из буфера'), onTap: _paste),
            helper: tr('Маршруты из конфига не используются: через VPN пойдёт '
                'то, что выбрано на вкладке «Сервисы».'),
          ),
          Reveal(
            show: _error != null,
            child: Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(_error ?? '', style: tx(13, c: C.dangerText, h: 1.4)),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: CvButton(
                  label: tr('Отмена'),
                  onTap: () => Navigator.of(context).pop(),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: CvButton(
                  label: tr('Добавить'),
                  kind: CvButtonKind.primary,
                  onTap: _add,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

enum _SheetView { menu, edit, share, delete }

/// Действия с сервером: изменить, поделиться, удалить.
class _ServerSheet extends StatefulWidget {
  const _ServerSheet({required this.state, required this.serverId});

  final AppState state;
  final String serverId;

  @override
  State<_ServerSheet> createState() => _ServerSheetState();
}

class _ServerSheetState extends State<_ServerSheet> {
  _SheetView _view = _SheetView.menu;
  final _name = TextEditingController();
  final _country = TextEditingController();
  final _city = TextEditingController();

  // Данные для входа на сервер, если приложение их ещё не знает.
  final _login = TextEditingController(text: 'root');
  final _pass = TextEditingController();
  final _sshPort = TextEditingController(text: '22');
  bool _askCreds = false;

  // «Поделиться»: отдельный ключ, если его выпустили, и картинка QR-кода.
  GlobalKey _qrKey = GlobalKey();
  String? _issuedConf;
  bool _issuing = false;
  String? _issueError;

  SavedServer? get _server {
    for (final s in widget.state.servers) {
      if (s.id == widget.serverId) return s;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    final server = _server;
    if (server != null) {
      _name.text = server.name;
      _country.text = server.country;
      _city.text = server.city;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _country.dispose();
    _city.dispose();
    _login.dispose();
    _pass.dispose();
    _sshPort.dispose();
    super.dispose();
  }

  String _safeName(SavedServer server) {
    final safe = server.name.replaceAll(RegExp(r'[^\w\-а-яА-ЯёЁ]+'), '_');
    return safe.isEmpty ? 'server' : safe;
  }

  Future<void> _saveFile(SavedServer server, String conf) async {
    try {
      final note = savedNote(
        tr('Файл сохранён'),
        await saveTextFile(
          name: '${_safeName(server)}.conf',
          text: conf,
          type: _confFiles,
        ),
      );
      if (mounted && note != null) showNote(context, note);
    } catch (e) {
      if (mounted) showNote(context, tr('Не удалось сохранить файл: {0}', [e]));
    }
  }

  Future<void> _saveQr(SavedServer server) async {
    try {
      final boundary = _qrKey.currentContext?.findRenderObject();
      if (boundary is! RenderRepaintBoundary) return;
      // Втрое крупнее, чем на экране: так код уверенно читается камерой.
      final image = await boundary.toImage(pixelRatio: 3);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) throw tr('не удалось получить картинку');
      final note = savedNote(
        tr('QR-код сохранён'),
        await saveFile(
          name: '${_safeName(server)}.png',
          bytes: data.buffer.asUint8List(),
          type: _pngFiles,
          mimeType: 'image/png',
        ),
      );
      if (mounted && note != null) showNote(context, note);
    } catch (e) {
      if (mounted) showNote(context, tr('Не удалось сохранить QR-код: {0}', [e]));
    }
  }

  /// Кнопка «Выпустить отдельный ключ»: если пароль сервера неизвестен,
  /// сначала показывает поля для него, потом сохраняет и выпускает ключ.
  Future<void> _issuePressed(SavedServer server) async {
    final state = widget.state;
    if (state.canIssueKey(server)) {
      await _issueKey(server);
      return;
    }
    if (!_askCreds) {
      setState(() => _askCreds = true);
      return;
    }
    final port = int.tryParse(_sshPort.text.trim());
    if (_login.text.trim().isEmpty ||
        _pass.text.isEmpty ||
        port == null ||
        port < 1 ||
        port > 65535) {
      setState(() => _issueError = tr('Укажите логин, пароль и порт SSH.'));
      return;
    }
    await state.rememberCredentials(InstallRequest(
      host: server.profile.host,
      sshPort: port,
      username: _login.text.trim(),
      password: _pass.text,
    ));
    await _issueKey(server);
    if (!mounted) return;
    if (_issuedConf == null) {
      // Не вышло — скорее всего, пароль неверный: не оставляем его.
      await state.forgetCredentials(server.profile.host);
    } else {
      _pass.clear();
    }
  }

  Future<void> _issueKey(SavedServer server) async {
    setState(() {
      _issuing = true;
      _issueError = null;
    });
    try {
      final conf = await widget.state.issueDeviceConf(server);
      if (mounted) setState(() => _issuedConf = conf);
    } catch (e) {
      if (mounted) setState(() => _issueError = tr('Не удалось выпустить ключ: {0}', [e]));
    } finally {
      if (mounted) setState(() => _issuing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final server = _server;
    if (server == null) return const SizedBox(height: 20);

    Widget back() => CvButton(
          label: tr('Назад'),
          onTap: () => setState(() => _view = _SheetView.menu),
        );

    late final List<Widget> body;
    switch (_view) {
      case _SheetView.menu:
        body = [
          SheetHeader(
            title: server.name,
            subtitle: server.place.isEmpty
                ? server.profile.host
                : '${server.place} · ${server.profile.host}',
          ),
          const SizedBox(height: 10),
          _ActionRow(
            icon: Icons.edit_outlined,
            title: tr('Изменить название и место'),
            note: '',
            onTap: () => setState(() => _view = _SheetView.edit),
          ),
          _ActionRow(
            icon: Icons.ios_share,
            title: tr('Поделиться'),
            note: tr('QR-кодом, файлом .conf или текстом'),
            // Новый ключ на каждое открытие: при быстром «Назад» и снова
            // «Поделиться» старая и новая панели недолго живут вместе.
            onTap: () => setState(() {
              _qrKey = GlobalKey();
              _view = _SheetView.share;
            }),
          ),
          if (state.canIssueKey(server))
            _ActionRow(
              icon: Icons.key_off_outlined,
              title: tr('Забыть пароль сервера'),
              note: Platform.isWindows
                  ? tr('Сейчас он сохранён на этом компьютере')
                  : tr('Сейчас приложение его помнит'),
              onTap: () async {
                await state.forgetCredentials(server.profile.host);
                if (mounted) showNote(context, tr('Пароль сервера забыт'));
              },
            ),
          _ActionRow(
            icon: Icons.delete_outline,
            title: tr('Удалить сервер'),
            note: '',
            danger: true,
            onTap: () => setState(() => _view = _SheetView.delete),
          ),
        ];
        break;
      case _SheetView.edit:
        body = [
          SheetHeader(title: tr('Изменить сервер')),
          const SizedBox(height: 14),
          CvField(controller: _name, label: tr('Название')),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: CvField(controller: _country, label: tr('Страна'))),
              const SizedBox(width: 10),
              Expanded(child: CvField(controller: _city, label: tr('Город'))),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            tr('Место определяется по адресу сервера автоматически. Если оно '
            'определилось неверно, поправьте его здесь.'),
            style: tx(12, c: C.muted, h: 1.45),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: back()),
              const SizedBox(width: 10),
              Expanded(
                child: CvButton(
                  label: tr('Сохранить'),
                  kind: CvButtonKind.primary,
                  onTap: () async {
                    await state.updateServer(
                      server.id,
                      name: _name.text,
                      country: _country.text,
                      city: _city.text,
                    );
                    if (mounted) Navigator.of(context).pop();
                  },
                ),
              ),
            ],
          ),
        ];
        break;
      case _SheetView.share:
        final issued = _issuedConf;
        final conf = issued ?? state.exportConf(server);
        // В самый плотный QR-код помещается чуть меньше 3000 байт.
        final fitsQr = utf8.encode(conf).length <= 2900;
        body = [
          SheetHeader(title: tr('Поделиться'), subtitle: server.name),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: issued == null
                  ? const Color.fromRGBO(251, 191, 36, 0.12)
                  : const Color.fromRGBO(31, 159, 144, 0.16),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: issued == null
                    ? const Color.fromRGBO(251, 191, 36, 0.5)
                    : const Color.fromRGBO(88, 224, 200, 0.55),
              ),
            ),
            child: Text(
              issued == null
                  ? tr('Это конфиг вашего устройства. Два устройства не могут '
                      'пользоваться им одновременно: связь будет рваться у '
                      'обоих. В конфиге есть ключ доступа — передавайте его '
                      'только тем, кому доверяете.')
                  : tr('Это отдельный ключ: им можно пользоваться одновременно '
                      'с этим устройством. Передавайте его только тем, кому '
                      'доверяете.'),
              style: tx(
                13,
                c: issued == null ? C.warnText : const Color(0xFFC9F7EE),
                h: 1.45,
              ),
            ),
          ),
          if (issued == null && server.managed) ...[
            const SizedBox(height: 10),
            Reveal(
              show: _askCreds && !state.canIssueKey(server),
              child: Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 3,
                          child: CvField(
                            controller: _login,
                            label: tr('Логин'),
                            enabled: !_issuing,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 2,
                          child: CvField(
                            controller: _sshPort,
                            label: tr('Порт SSH'),
                            mono: true,
                            enabled: !_issuing,
                            keyboardType: TextInputType.number,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    CvField(
                      controller: _pass,
                      label: tr('Пароль от сервера {0}', [server.profile.host]),
                      obscure: true,
                      enabled: !_issuing,
                      helper: Platform.isWindows
                          ? tr('Приложение запомнит его и сохранит на этом '
                              'компьютере в зашифрованном виде')
                          : tr('Приложение запомнит его до закрытия'),
                    ),
                  ],
                ),
              ),
            ),
            CvButton(
              label: _issuing
                  ? tr('Выпускаю ключ…')
                  : (_askCreds && !state.canIssueKey(server)
                      ? tr('Сохранить и выпустить ключ')
                      : tr('Выпустить отдельный ключ')),
              icon: Icons.vpn_key_outlined,
              kind: CvButtonKind.primary,
              onTap: _issuing ? null : () => _issuePressed(server),
            ),
            const SizedBox(height: 6),
            Text(
              tr('Для другого устройства или друга. Связь с сервером прервётся '
              'на несколько секунд.'),
              textAlign: TextAlign.center,
              style: tx(12, c: C.muted, h: 1.45),
            ),
          ],
          if (_issueError != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_issueError!, style: tx(13, c: C.dangerText, h: 1.4)),
            ),
          const SizedBox(height: 12),
          if (fitsQr)
            Center(
              child: RepaintBoundary(
                key: _qrKey,
                child: Container(
                  color: Colors.white,
                  padding: const EdgeInsets.all(14),
                  child: QrImageView(
                    data: conf,
                    version: QrVersions.auto,
                    size: 260,
                    padding: EdgeInsets.zero,
                    backgroundColor: Colors.white,
                    semanticsLabel: tr('QR-код с конфигом сервера'),
                    errorStateBuilder: (context, error) => SizedBox(
                      width: 260,
                      height: 80,
                      child: Center(
                        child: Text(
                          tr('Не удалось построить QR-код'),
                          style: tx(13, c: const Color(0xFF101010)),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            )
          else
            Text(
              tr('Конфиг слишком длинный для QR-кода — передайте его файлом '
              'или текстом.'),
              textAlign: TextAlign.center,
              style: tx(13, c: C.muted, h: 1.45),
            ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: CvButton(
                  label: tr('Сохранить QR-код'),
                  onTap: fitsQr ? () => _saveQr(server) : null,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: CvButton(
                  label: tr('Сохранить .conf'),
                  onTap: () => _saveFile(server, conf),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          CvButton(
            label: tr('Скопировать текстом'),
            icon: Icons.copy,
            onTap: () => copyText(context, conf, tr('Конфиг скопирован')),
          ),
          const SizedBox(height: 10),
          back(),
        ];
        break;
      case _SheetView.delete:
        body = [
          SheetHeader(title: tr('Удалить сервер'), subtitle: server.name),
          const SizedBox(height: 12),
          DangerConfirm(
            question: tr('Удалить сервер «{0}» из приложения?', [server.name]),
            note: tr('Сам сервер останется настроенным. Чтобы вернуть его в '
                'приложение, понадобится конфиг или повторная установка.'),
            cancelLabel: tr('Не удалять'),
            confirmLabel: tr('Удалить'),
            onCancel: () => setState(() => _view = _SheetView.menu),
            onConfirm: () async {
              await state.deleteServer(server.id);
              if (mounted) Navigator.of(context).pop();
            },
          ),
        ];
        break;
    }

    return SingleChildScrollView(
      child: AnimatedSize(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
        alignment: Alignment.topCenter,
        child: FadeSwap(
          child: Column(
            key: ValueKey(_view),
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: body,
          ),
        ),
      ),
    );
  }
}
