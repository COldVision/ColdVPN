import 'package:flutter/material.dart';

import '../app_state.dart';
import '../catalog.dart';
import '../models.dart';
import '../route_input.dart';
import 'route_sheet.dart';
import 'theme.dart';
import '../l10n.dart';

/// Меню ресурса: изменить или удалить. Перемещают ресурс перетаскиванием.
Future<void> showResourceMenu(
  BuildContext context,
  AppState state,
  ServiceEntry service,
) async {
  final section = state.sectionOf(service.id);
  final action = await showCvSheet<String>(
    context,
    builder: (context) => _Menu(
      title: service.name,
      subtitle: tr('Раздел «{0}»', [section?.title ?? '']),
      actions: [
        _MenuAction('edit', tr('Изменить'), tr('Название, раздел, домены и адреса')),
      ],
      deleteLabel: tr('Удалить ресурс'),
      question: tr('Удалить ресурс «{0}»?', [service.name]),
      warning: tr('Его домены и адреса перестанут идти через VPN.'),
      onDelete: () => state.deleteResource(service.id),
    ),
  );
  if (!context.mounted) return;
  if (action == 'edit') {
    await showRouteSheet(context, state, service: service);
  }
}

/// Меню раздела: изменить название и значок, удалить.
Future<void> showSectionMenu(
  BuildContext context,
  AppState state,
  Section section,
) async {
  final count = state.servicesOf(section.id).length;
  final action = await showCvSheet<String>(
    context,
    builder: (context) => _Menu(
      title: section.title,
      subtitle: tr('Раздел · ресурсов: {0}', [count]),
      actions: [
        _MenuAction('edit', tr('Изменить название и значок'), ''),
        if (count > 0 && state.sections.length > 1)
          _MenuAction('move', tr('Удалить раздел, ресурсы перенести'),
              tr('Выберите, куда переедут ресурсы'),
              danger: true),
      ],
      deleteLabel:
          count > 0 ? tr('Удалить раздел вместе с ресурсами') : tr('Удалить раздел'),
      question: tr('Удалить раздел «{0}»?', [section.title]),
      warning: count > 0
          ? tr('Вместе с ним удалятся '
              '{0}. Вернуть '
              'начальный набор можно в настройках.', [plural(count, tr('ресурс'), tr('ресурса'), tr('ресурсов'))])
          : tr('Раздел пуст, больше ничего не удалится.'),
      onDelete: () => state.deleteSection(section.id),
    ),
  );
  if (!context.mounted) return;
  if (action == 'edit') {
    await showSectionSheet(context, state, section: section);
  } else if (action == 'move') {
    final to = await pickSection(
      context,
      state,
      title: tr('Куда перенести ресурсы?'),
      subtitle: tr('Раздел «{0}» будет удалён', [section.title]),
      exclude: section.id,
    );
    if (to != null) state.deleteSection(section.id, moveTo: to);
  }
}

const _newSection = '\u0000new';

/// Выбор раздела. Возвращает его идентификатор или null, если панель
/// закрыли. Пункт «Новый раздел» сразу создаёт раздел и возвращает его.
Future<String?> pickSection(
  BuildContext context,
  AppState state, {
  required String title,
  String? subtitle,
  String? current,
  String? exclude,
}) async {
  final picked = await showCvSheet<String>(
    context,
    builder: (context) => SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SheetHeader(title: title, subtitle: subtitle),
          const SizedBox(height: 12),
          for (final s in state.sections)
            if (s.id != exclude)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: _PickRow(
                  icon: sectionIcon(s.icon),
                  label: s.title,
                  selected: s.id == current,
                  onTap: () => Navigator.of(context).pop(s.id),
                ),
              ),
          _PickRow(
            icon: Icons.add,
            label: tr('Новый раздел…'),
            selected: false,
            onTap: () => Navigator.of(context).pop(_newSection),
          ),
        ],
      ),
    ),
  );
  if (picked != _newSection || !context.mounted) return picked;
  return showSectionSheet(context, state);
}

/// Панель раздела: новый ([section] == null) или правка названия и значка.
/// Возвращает идентификатор раздела или null, если панель закрыли.
Future<String?> showSectionSheet(
  BuildContext context,
  AppState state, {
  Section? section,
}) {
  return showCvSheet<String>(
    context,
    builder: (context) => _SectionSheet(state: state, section: section),
  );
}

class _MenuAction {
  const _MenuAction(this.id, this.title, this.note, {this.danger = false});

  final String id;
  final String title;
  final String note;
  final bool danger;
}

/// Список действий; удаление спрашивает подтверждение тут же.
class _Menu extends StatefulWidget {
  const _Menu({
    required this.title,
    required this.subtitle,
    required this.actions,
    required this.deleteLabel,
    required this.question,
    required this.warning,
    required this.onDelete,
  });

  final String title;
  final String subtitle;
  final List<_MenuAction> actions;
  final String deleteLabel;
  final String question;
  final String warning;
  final VoidCallback onDelete;

  @override
  State<_Menu> createState() => _MenuState();
}

class _MenuState extends State<_Menu> {
  bool _confirm = false;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SheetHeader(title: widget.title, subtitle: widget.subtitle),
          const SizedBox(height: 8),
          for (final a in widget.actions)
            ActionLine(
              title: a.title,
              note: a.note,
              danger: a.danger,
              onTap: () => Navigator.of(context).pop(a.id),
            ),
          if (_confirm)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: DangerConfirm(
                question: widget.question,
                note: widget.warning,
                cancelLabel: tr('Не удалять'),
                confirmLabel: tr('Удалить'),
                onCancel: () => setState(() => _confirm = false),
                onConfirm: () {
                  widget.onDelete();
                  Navigator.of(context).pop();
                },
              ),
            )
          else
            ActionLine(
              title: widget.deleteLabel,
              note: '',
              danger: true,
              onTap: () => setState(() => _confirm = true),
            ),
        ],
      ),
    );
  }
}

class _PickRow extends StatelessWidget {
  const _PickRow({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          constraints: const BoxConstraints(minHeight: 52),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: selected ? C.rowOn : C.rowOff,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected
                  ? const Color.fromRGBO(130, 150, 255, 0.55)
                  : C.rowLine,
            ),
          ),
          child: Row(
            children: [
              Icon(icon, size: 20, color: C.white),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: tx(14, w: w600, c: C.white),
                ),
              ),
              if (selected) const Icon(Icons.check, size: 18, color: C.teal),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionSheet extends StatefulWidget {
  const _SectionSheet({required this.state, this.section});

  final AppState state;
  final Section? section;

  @override
  State<_SectionSheet> createState() => _SectionSheetState();
}

class _SectionSheetState extends State<_SectionSheet> {
  late final TextEditingController _name;
  late String _icon;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.section?.title ?? '');
    _icon = widget.section?.icon ?? 'star';
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    final id = widget.state.saveSection(
      id: widget.section?.id,
      name: _name.text,
      icon: _icon,
    );
    Navigator.of(context).pop(id);
  }

  @override
  Widget build(BuildContext context) {
    final edit = widget.section != null;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SheetHeader(
            icon: sectionIcon(_icon),
            title: edit ? tr('Изменить раздел') : tr('Новый раздел'),
            subtitle: edit ? null : tr('Появится в конце списка, его можно перетащить'),
          ),
          const SizedBox(height: 14),
          CvField(
            controller: _name,
            label: tr('Название раздела'),
            hint: tr('Например, Игры'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 14),
          Text(tr('Значок'), style: tx(13, c: C.soft)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final entry in sectionIcons.entries)
                Semantics(
                  button: true,
                  selected: entry.key == _icon,
                  child: InkWell(
                    onTap: () => setState(() => _icon = entry.key),
                    borderRadius: BorderRadius.circular(12),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: entry.key == _icon
                            ? C.accent
                            : const Color.fromRGBO(90, 100, 160, 0.3),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          width: 2,
                          color: entry.key == _icon
                              ? C.white
                              : const Color(0x00000000),
                        ),
                      ),
                      child: Icon(entry.value, size: 22, color: C.white),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
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
                  label: edit ? tr('Сохранить') : tr('Создать'),
                  kind: CvButtonKind.primary,
                  onTap: _name.text.trim().isEmpty ? null : _submit,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
