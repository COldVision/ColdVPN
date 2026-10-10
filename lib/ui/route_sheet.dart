import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';
import '../route_input.dart';
import 'theme.dart';

/// Панель «Свой маршрут»: добавление ([route] == null) или правка.
Future<void> showRouteSheet(
  BuildContext context,
  AppState state, {
  CustomRoute? route,
}) {
  return showCvSheet<void>(
    context,
    builder: (context) => _RouteSheet(state: state, route: route),
  );
}

class _RouteSheet extends StatefulWidget {
  const _RouteSheet({required this.state, this.route});

  final AppState state;
  final CustomRoute? route;

  @override
  State<_RouteSheet> createState() => _RouteSheetState();
}

class _RouteSheetState extends State<_RouteSheet> {
  late final TextEditingController _name;
  late final TextEditingController _text;
  List<RouteLine> _lines = const [];
  bool _enable = true;
  bool _confirmDelete = false;

  bool get _edit => widget.route != null;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.route?.name ?? '');
    _text = TextEditingController(text: widget.route?.text ?? '');
    _lines = parseRouteText(_text.text);
  }

  @override
  void dispose() {
    _name.dispose();
    _text.dispose();
    super.dispose();
  }

  void _reparse() => setState(() => _lines = parseRouteText(_text.text));

  Future<void> _paste() async {
    final clip = (await pasteText()).trim();
    if (clip.isEmpty) return;
    final now = _text.text.trimRight();
    _text.text = now.isEmpty ? clip : '$now\n$clip';
    _reparse();
  }

  void _submit() {
    widget.state.saveCustomRoute(
      id: widget.route?.id,
      name: _name.text,
      lines: _lines,
      enable: _enable,
    );
    Navigator.of(context).pop();
  }

  int _count(RouteLineKind kind) => _lines.where((l) => l.kind == kind).length;

  @override
  Widget build(BuildContext context) {
    final domains = _count(RouteLineKind.domain);
    final networks = _count(RouteLineKind.network);
    final addresses = _count(RouteLineKind.address);
    final errors = _count(RouteLineKind.error);
    final good = domains + networks + addresses;
    final nameOk = _name.text.trim().isNotEmpty;
    final canSubmit = nameOk && good > 0;

    final summary = [
      if (domains > 0) plural(domains, 'домен', 'домена', 'доменов'),
      if (networks > 0) plural(networks, 'диапазон', 'диапазона', 'диапазонов'),
      if (addresses > 0) plural(addresses, 'адрес', 'адреса', 'адресов'),
      if (errors > 0) 'ошибок: $errors',
    ].join(' · ');

    String? footNote;
    if (!nameOk) {
      footNote = 'Укажите название маршрута';
    } else if (good == 0) {
      footNote = 'Нужен хотя бы один правильный домен или адрес';
    } else if (errors > 0) {
      footNote = 'Строки с ошибкой будут пропущены: $errors';
    }

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SheetHeader(
            icon: Icons.alt_route,
            title: _edit ? 'Изменить маршрут' : 'Свой маршрут',
            subtitle: _edit
                ? 'Группа «Мои маршруты»'
                : 'Появится в группе «Мои маршруты»',
          ),
          const SizedBox(height: 14),
          CvField(
            controller: _name,
            label: 'Название',
            hint: 'Например, Рабочий портал',
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 14),
          CvField(
            controller: _text,
            label: 'Домены и IP-адреса, по одному в строке',
            hint: 'example.com\n203.0.113.0/24',
            mono: true,
            minLines: 5,
            maxLines: 8,
            keyboardType: TextInputType.multiline,
            onChanged: (_) => _reparse(),
            trailing: CvLink(label: 'Вставить', onTap: _paste),
            helper: 'Домен добавляется вместе с поддоменами. Можно '
                'вставить ссылку целиком — из неё возьмётся домен.',
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Text('Проверка', style: tx(13, c: C.soft)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  summary,
                  textAlign: TextAlign.right,
                  style: tx(
                    12,
                    c: errors > 0 && good == 0 ? C.dangerText : C.tealText,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_lines.isEmpty)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: const Color.fromRGBO(120, 140, 255, 0.3),
                ),
              ),
              child: Text(
                'Введите хотя бы один домен или адрес',
                textAlign: TextAlign.center,
                style: tx(13, c: C.muted),
              ),
            )
          else
            for (final line in _lines)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: _LineRow(line: line),
              ),
          const SizedBox(height: 8),
          if (!_edit)
            CvCard(
              radius: 14,
              color: C.rowOff,
              line: const Color.fromRGBO(120, 140, 255, 0.2),
              padding: const EdgeInsets.fromLTRB(14, 4, 2, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Включить сразу', style: tx(14, w: w600, c: C.white)),
                        Text(
                          'Маршрут пойдёт через VPN после добавления',
                          style: tx(12, c: C.muted),
                        ),
                      ],
                    ),
                  ),
                  CvSwitch(
                    value: _enable,
                    label: 'Включить сразу',
                    onChanged: (value) => setState(() => _enable = value),
                  ),
                ],
              ),
            )
          else if (_confirmDelete)
            DangerConfirm(
              question: 'Удалить маршрут «${_name.text.trim()}»?',
              note: 'Его адреса перестанут идти через VPN.',
              cancelLabel: 'Не удалять',
              confirmLabel: 'Удалить',
              onCancel: () => setState(() => _confirmDelete = false),
              onConfirm: () {
                widget.state.deleteCustomRoute(widget.route!.id);
                Navigator.of(context).pop();
              },
            )
          else
            CvButton(
              label: 'Удалить маршрут',
              icon: Icons.delete_outline,
              kind: CvButtonKind.dangerSoft,
              height: 48,
              onTap: () => setState(() => _confirmDelete = true),
            ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: CvButton(
                  label: 'Отмена',
                  onTap: () => Navigator.of(context).pop(),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: CvButton(
                  label: _edit ? 'Сохранить' : 'Добавить',
                  kind: CvButtonKind.primary,
                  onTap: canSubmit ? _submit : null,
                ),
              ),
            ],
          ),
          if (footNote != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                footNote,
                textAlign: TextAlign.center,
                style: tx(12, c: C.dangerText),
              ),
            ),
        ],
      ),
    );
  }
}

class _LineRow extends StatelessWidget {
  const _LineRow({required this.line});

  final RouteLine line;

  @override
  Widget build(BuildContext context) {
    final bad = line.kind == RouteLineKind.error;
    final dup = line.kind == RouteLineKind.duplicate;
    late final String badge;
    late final Color fg;
    late final Color bg;
    late final Color bd;
    switch (line.kind) {
      case RouteLineKind.domain:
        badge = 'Домен';
        fg = const Color(0xFFC9F7EE);
        bg = const Color.fromRGBO(31, 159, 144, 0.22);
        bd = const Color.fromRGBO(88, 224, 200, 0.55);
        break;
      case RouteLineKind.network:
      case RouteLineKind.address:
        badge = line.kind == RouteLineKind.network ? 'Диапазон' : 'Адрес';
        fg = const Color(0xFFDFE4FF);
        bg = const Color.fromRGBO(99, 102, 241, 0.25);
        bd = const Color.fromRGBO(150, 160, 255, 0.55);
        break;
      case RouteLineKind.duplicate:
        badge = 'Повтор';
        fg = C.soft;
        bg = const Color.fromRGBO(90, 100, 160, 0.25);
        bd = const Color.fromRGBO(150, 160, 220, 0.4);
        break;
      case RouteLineKind.error:
        badge = 'Ошибка';
        fg = const Color(0xFFFFD0D3);
        bg = const Color.fromRGBO(220, 50, 60, 0.3);
        bd = const Color.fromRGBO(255, 110, 120, 0.75);
        break;
    }
    return Opacity(
      opacity: dup ? 0.7 : 1,
      child: Container(
        constraints: const BoxConstraints(minHeight: 44),
        padding: const EdgeInsets.fromLTRB(8, 6, 12, 6),
        decoration: BoxDecoration(
          color: bad ? const Color.fromRGBO(220, 50, 60, 0.14) : C.rowOff,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: bad ? C.dangerLine : C.rowLine),
        ),
        child: Row(
          children: [
            Container(
              width: 78,
              padding: const EdgeInsets.symmetric(vertical: 5),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: bd),
              ),
              child: Text(badge, style: tx(12, w: w600, c: fg)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    line.value,
                    overflow: TextOverflow.ellipsis,
                    style: tx(
                      13,
                      c: bad ? const Color(0xFFFF9EA5) : C.white,
                      mono: true,
                    ).copyWith(
                      decoration: bad
                          ? TextDecoration.lineThrough
                          : TextDecoration.none,
                    ),
                  ),
                  Text(
                    line.note,
                    style: tx(12, c: bad ? C.dangerText : C.muted),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
