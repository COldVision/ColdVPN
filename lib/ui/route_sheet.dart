import 'package:flutter/material.dart';

import '../app_state.dart';
import '../catalog.dart';
import '../models.dart';
import '../route_input.dart';
import 'section_sheets.dart';
import 'theme.dart';
import '../l10n.dart';

/// Панель ресурса: новый в разделе [section] или правка [service].
Future<void> showRouteSheet(
  BuildContext context,
  AppState state, {
  ServiceEntry? service,
  String? section,
}) {
  return showCvSheet<void>(
    context,
    builder: (context) =>
        _RouteSheet(state: state, service: service, section: section),
  );
}

class _RouteSheet extends StatefulWidget {
  const _RouteSheet({required this.state, this.service, this.section});

  final AppState state;
  final ServiceEntry? service;
  final String? section;

  @override
  State<_RouteSheet> createState() => _RouteSheetState();
}

/// Сколько строк проверки показывается за раз: у больших списков —
/// только ошибки и то, что найдено поиском.
const _shownLines = 30;

class _RouteSheetState extends State<_RouteSheet> {
  late final TextEditingController _name;
  late final TextEditingController _text;
  final _find = TextEditingController();
  List<RouteLine> _lines = const [];
  late String _section;
  bool _enable = true;

  bool get _edit => widget.service != null;

  @override
  void initState() {
    super.initState();
    final service = widget.service;
    _name = TextEditingController(text: service?.name ?? '');
    _text = TextEditingController(text: service?.text ?? '');
    _lines = parseRouteText(_text.text);
    _section = widget.section ??
        (service == null ? null : widget.state.sectionOf(service.id)?.id) ??
        '';
  }

  @override
  void dispose() {
    _name.dispose();
    _text.dispose();
    _find.dispose();
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

  Future<void> _pickSection() async {
    final picked = await pickSection(
      context,
      widget.state,
      title: tr('Раздел'),
      subtitle: _name.text.trim().isEmpty ? null : _name.text.trim(),
      current: _section,
    );
    if (picked != null && mounted) setState(() => _section = picked);
  }

  /// Убирает из поля ввода строку с этим доменом или адресом.
  void _removeLine(String value) {
    _text.text = _text.text
        .split('\n')
        .where((raw) => parseRouteLine(raw).value != value)
        .join('\n');
    _reparse();
  }

  void _submit() {
    widget.state.saveResource(
      id: widget.service?.id,
      name: _name.text,
      section: _section,
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

    final summary = [
      if (domains > 0) plural(domains, tr('домен'), tr('домена'), tr('доменов')),
      if (networks > 0) plural(networks, tr('диапазон'), tr('диапазона'), tr('диапазонов')),
      if (addresses > 0) plural(addresses, tr('адрес'), tr('адреса'), tr('адресов')),
      if (errors > 0) tr('ошибок: {0}', [errors]),
    ].join(' · ');

    Section? section;
    for (final s in widget.state.sections) {
      if (s.id == _section) section = s;
    }
    // У длинного списка строки показываются по поиску, иначе панель
    // превращается в простыню из сотен строк.
    final long = _lines.length > _shownLines;
    final query = _find.text.trim().toLowerCase();
    final shown = [
      for (final l in _lines)
        if (!long ||
            (query.isEmpty
                ? !l.accepted
                : l.value.toLowerCase().contains(query)))
          l,
    ];

    final canSubmit = nameOk && good > 0 && section != null;

    String? footNote;
    if (!nameOk) {
      footNote = tr('Укажите название ресурса');
    } else if (section == null) {
      footNote = tr('Выберите раздел');
    } else if (good == 0) {
      footNote = tr('Нужен хотя бы один правильный домен или адрес');
    } else if (errors > 0) {
      footNote = tr('Строки с ошибкой будут пропущены: {0}', [errors]);
    }

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SheetHeader(
            icon: sectionIcon(section?.icon ?? 'route'),
            title: _edit ? tr('Изменить ресурс') : tr('Новый ресурс'),
            subtitle: tr('Домены и адреса, которые пойдут через VPN'),
          ),
          const SizedBox(height: 14),
          CvField(
            controller: _name,
            label: tr('Название'),
            hint: tr('Например, Рабочий портал'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 14),
          Text(tr('Раздел'), style: tx(13, c: C.soft)),
          const SizedBox(height: 6),
          Semantics(
            button: true,
            child: InkWell(
              onTap: _pickSection,
              borderRadius: BorderRadius.circular(14),
              child: Container(
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: C.field,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: C.fieldLine),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        section?.title ?? tr('Выберите раздел'),
                        overflow: TextOverflow.ellipsis,
                        style: tx(15, c: C.white),
                      ),
                    ),
                    const Icon(Icons.expand_more, size: 20, color: C.soft),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          CvField(
            controller: _text,
            label: tr('Домены и IP-адреса, по одному в строке'),
            hint: 'example.com\n203.0.113.0/24',
            mono: true,
            minLines: 5,
            maxLines: 8,
            keyboardType: TextInputType.multiline,
            onChanged: (_) => _reparse(),
            trailing: CvLink(label: tr('Вставить'), onTap: _paste),
            helper: tr('Домен добавляется вместе с поддоменами. Можно '
                'вставить ссылку целиком — из неё возьмётся домен.'),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Text(tr('Проверка'), style: tx(13, c: C.soft)),
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
          if (long)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: CvField(
                controller: _find,
                label: tr('Найти в списке'),
                hint: tr('Часть домена или адреса'),
                mono: true,
                onChanged: (_) => setState(() {}),
                helper: query.isEmpty
                    ? tr('Список длинный: ниже показаны только строки с '
                        'ошибками. Найденную строку можно убрать крестиком.')
                    : shown.isEmpty
                        ? tr('Ничего не найдено')
                        : shown.length > _shownLines
                            ? tr('Найдено {0}, показаны первые '
                                '{1}', [shown.length, _shownLines])
                            : null,
              ),
            ),
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
                tr('Введите хотя бы один домен или адрес'),
                textAlign: TextAlign.center,
                style: tx(13, c: C.muted),
              ),
            )
          else
            for (final line in shown.take(_shownLines))
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: _LineRow(
                  line: line,
                  onRemove: long ? () => _removeLine(line.value) : null,
                ),
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
                        Text(tr('Включить сразу'), style: tx(14, w: w600, c: C.white)),
                        Text(
                          tr('Ресурс пойдёт через VPN после добавления'),
                          style: tx(12, c: C.muted),
                        ),
                      ],
                    ),
                  ),
                  CvSwitch(
                    value: _enable,
                    label: tr('Включить сразу'),
                    onChanged: (value) => setState(() => _enable = value),
                  ),
                ],
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
                  label: _edit ? tr('Сохранить') : tr('Добавить'),
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
  const _LineRow({required this.line, this.onRemove});

  final RouteLine line;

  /// Убрать строку из списка; null — кнопки нет.
  final VoidCallback? onRemove;

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
        badge = tr('Домен');
        fg = const Color(0xFFC9F7EE);
        bg = const Color.fromRGBO(31, 159, 144, 0.22);
        bd = const Color.fromRGBO(88, 224, 200, 0.55);
        break;
      case RouteLineKind.network:
      case RouteLineKind.address:
        badge = line.kind == RouteLineKind.network ? tr('Диапазон') : tr('Адрес');
        fg = const Color(0xFFDFE4FF);
        bg = const Color.fromRGBO(99, 102, 241, 0.25);
        bd = const Color.fromRGBO(150, 160, 255, 0.55);
        break;
      case RouteLineKind.duplicate:
        badge = tr('Повтор');
        fg = C.soft;
        bg = const Color.fromRGBO(90, 100, 160, 0.25);
        bd = const Color.fromRGBO(150, 160, 220, 0.4);
        break;
      case RouteLineKind.error:
        badge = tr('Ошибка');
        fg = const Color(0xFFFFD0D3);
        bg = const Color.fromRGBO(220, 50, 60, 0.3);
        bd = const Color.fromRGBO(255, 110, 120, 0.75);
        break;
    }
    return Opacity(
      opacity: dup ? 0.7 : 1,
      child: Container(
        constraints: const BoxConstraints(minHeight: 44),
        padding: EdgeInsets.fromLTRB(8, 6, onRemove == null ? 12 : 0, 6),
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
            if (onRemove != null)
              CvIconButton(
                icon: Icons.close,
                tooltip: tr('Убрать «{0}» из списка', [line.value]),
                framed: false,
                onTap: onRemove,
              ),
          ],
        ),
      ),
    );
  }
}
