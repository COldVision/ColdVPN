import 'dart:async';

import 'package:flutter/material.dart';

import '../android_tunnel.dart';
import '../app_state.dart';
import '../catalog.dart';
import '../models.dart';
import 'route_sheet.dart';
import 'section_sheets.dart';
import 'shell.dart';
import 'theme.dart';
import '../l10n.dart';

/// Вкладка «Сервисы»: кнопка включения, режим маршрутизации и группы.
class ServicesTab extends StatefulWidget {
  const ServicesTab({super.key, required this.state, required this.openServers});

  final AppState state;
  final VoidCallback openServers;

  @override
  State<ServicesTab> createState() => _ServicesTabState();
}

class _ServicesTabState extends State<ServicesTab> {
  /// Раскрыта может быть только одна группа.
  String? _open;

  AppState get state => widget.state;

  // Прокрутка списка, пока ресурс тащат у верхнего или нижнего края.
  final _scroll = ScrollController();
  final _listKey = GlobalKey();
  Timer? _autoScroll;
  double _scrollStep = 0;

  @override
  void dispose() {
    _autoScroll?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  /// [position] — где сейчас палец или курсор с ресурсом; null — отпустили.
  void _dragAt(Offset? position) {
    final box = _listKey.currentContext?.findRenderObject() as RenderBox?;
    if (position == null || box == null) {
      _autoScroll?.cancel();
      _autoScroll = null;
      return;
    }
    // Чем ближе к краю, тем быстрее: до 16 точек за кадр.
    const edge = 80.0;
    final y = box.globalToLocal(position).dy;
    final over = y < edge
        ? y - edge
        : y > box.size.height - edge
            ? y - (box.size.height - edge)
            : 0.0;
    _scrollStep = over.clamp(-edge, edge) / edge * 16;
    _autoScroll ??= Timer.periodic(const Duration(milliseconds: 16), (_) {
      if (_scrollStep == 0 || !_scroll.hasClients) return;
      final range = _scroll.position;
      _scroll.jumpTo((_scroll.offset + _scrollStep)
          .clamp(range.minScrollExtent, range.maxScrollExtent)
          .toDouble());
    });
  }

  void _togglePower() {
    if (state.status == VpnStatus.off) {
      state.connect();
    } else {
      state.disconnect();
    }
  }

  @override
  Widget build(BuildContext context) {
    final full = state.settings.fullTunnel;
    final order = state.sections;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TabHeader(
          title: 'ColdVPN',
          trailing: ServerPicker(state: state, onManage: widget.openServers),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
          child: _PowerButton(state: state, onTap: _togglePower),
        ),
        Reveal(
          show: !state.elevated,
          child: _Banner(
            text: tr('Приложение запущено без прав администратора — подключение '
                'не сработает. Закройте его и запустите от имени '
                'администратора.'),
          ),
        ),
        Reveal(
          show: state.error != null,
          child: _Banner(text: state.error ?? ''),
        ),
        Reveal(
          show: state.browserStatus != VpnStatus.off,
          child: _BrowserNote(state: state),
        ),
        if (state.isAndroid)
          // На Android три способа: сервисы по спискам адресов, выбранные
          // приложения целиком или весь трафик телефона.
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 0),
            child: CvSegments<int>(
              options: {0: tr('Сервисы'), 1: tr('Приложения'), 2: tr('Весь трафик')},
              selected: full ? 2 : (state.appMode ? 1 : 0),
              onChanged: (mode) => state.changeSettings((s) {
                s.fullTunnel = mode == 2;
                s.appMode = mode == 1;
              }),
            ),
          )
        else
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 0),
          child: CvCard(
            radius: 14,
            padding: const EdgeInsets.fromLTRB(14, 4, 2, 4),
            color: full ? C.rowOn : C.card,
            line: full ? const Color.fromRGBO(130, 150, 255, 0.55) : C.cardLine,
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        tr('Весь трафик через VPN'),
                        style: tx(14, w: w600, c: C.white),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        full
                            ? tr('Переключатели сервисов заблокированы')
                            : tr('Сейчас — только включённые сервисы'),
                        style: tx(12, c: C.muted),
                      ),
                    ],
                  ),
                ),
                CvSwitch(
                  value: full,
                  label: tr('Весь трафик через VPN'),
                  onChanged: (value) =>
                      state.changeSettings((s) => s.fullTunnel = value),
                ),
              ],
            ),
          ),
        ),
        if (state.appMode && !full)
          Expanded(child: _AppList(state: state))
        else
        Expanded(
          child: ReorderableListView.builder(
            key: _listKey,
            scrollController: _scroll,
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
            buildDefaultDragHandles: false,
            itemCount: order.length,
            onReorder: (from, to) {
              setState(() => _open = null);
              state.moveGroup(from, to);
            },
            proxyDecorator: (child, index, animation) => Material(
              type: MaterialType.transparency,
              child: Opacity(opacity: 0.9, child: child),
            ),
            footer: _AddButton(
              label: tr('Новый раздел'),
              center: true,
              onTap: () async {
                final id = await showSectionSheet(context, state);
                if (id != null && mounted) setState(() => _open = id);
              },
            ),
            itemBuilder: (context, index) {
              final group = order[index];
              return Padding(
                key: ValueKey(group.id),
                padding: const EdgeInsets.only(bottom: 10),
                child: _GroupCard(
                  state: state,
                  group: group,
                  index: index,
                  open: _open == group.id,
                  dimmed: full,
                  onDrag: _dragAt,
                  onToggle: () => setState(
                    () => _open = _open == group.id ? null : group.id,
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Список приложений телефона с переключателями (только Android).
class _AppList extends StatefulWidget {
  const _AppList({required this.state});

  final AppState state;

  @override
  State<_AppList> createState() => _AppListState();
}

class _AppListState extends State<_AppList> {
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.state.apps.isEmpty) widget.state.loadApps();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final query = _search.text.trim().toLowerCase();
    final shown = [
      for (final app in state.apps)
        if (query.isEmpty ||
            app.label.toLowerCase().contains(query) ||
            app.package.toLowerCase().contains(query))
          app,
    ];
    // Включённые — наверху, дальше по алфавиту.
    final picked = shown.where((a) => state.enabledApps.contains(a.package));
    final rest = shown.where((a) => !state.enabledApps.contains(a.package));
    final ordered = [...picked, ...rest];

    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
      children: [
        CvField(
          controller: _search,
          label: tr('Приложения, которые идут через VPN целиком'),
          hint: tr('Поиск по названию'),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 10),
        if (state.loadingApps && state.apps.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(
              child: CircularProgressIndicator(strokeWidth: 3, color: C.soft),
            ),
          )
        else if (ordered.isEmpty)
          CvCard(
            child: Text(
              state.apps.isEmpty
                  ? tr('Не удалось получить список приложений.')
                  : tr('Ничего не найдено.'),
              style: tx(13, c: C.muted),
            ),
          ),
        for (final app in ordered)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: _AppRow(state: state, app: app),
          ),
      ],
    );
  }
}

class _AppRow extends StatelessWidget {
  const _AppRow({required this.state, required this.app});

  final AppState state;
  final AndroidApp app;

  @override
  Widget build(BuildContext context) {
    final on = state.enabledApps.contains(app.package);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 260),
      constraints: const BoxConstraints(minHeight: 56),
      padding: const EdgeInsets.fromLTRB(14, 6, 2, 6),
      decoration: BoxDecoration(
        color: on ? C.rowOn : C.rowOff,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: on ? const Color.fromRGBO(130, 150, 255, 0.55) : C.rowLine,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  app.label,
                  overflow: TextOverflow.ellipsis,
                  style: tx(14, w: w600, c: C.white),
                ),
                const SizedBox(height: 2),
                Text(
                  app.package,
                  overflow: TextOverflow.ellipsis,
                  style: tx(12, c: C.muted, mono: true),
                ),
              ],
            ),
          ),
          CvSwitch(
            value: on,
            label: app.label,
            onChanged: (value) => state.toggleApp(app.package, value),
          ),
        ],
      ),
    );
  }
}

/// Подсказка, что VPN включён расширением только для браузера.
class _BrowserNote extends StatelessWidget {
  const _BrowserNote({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final on = state.browserStatus == VpnStatus.on;
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 0),
      child: CvCard(
        radius: 14,
        padding: const EdgeInsets.all(12),
        line: const Color.fromRGBO(88, 224, 200, 0.5),
        child: Row(
          children: [
            Icon(Icons.public, size: 18, color: on ? C.teal : C.soft),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                on
                    ? tr('VPN в браузере включён: сайты, выбранные в расширении '
                        'ColdVPN, идут через VPN только в браузере.')
                    : tr('Включаю VPN в браузере…'),
                style: tx(13, c: C.white, h: 1.4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 0),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: C.dangerBg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: C.dangerLine),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.error_outline, size: 18, color: C.dangerText),
            const SizedBox(width: 10),
            Expanded(
              child: Text(text, style: tx(13, c: C.white, h: 1.4)),
            ),
          ],
        ),
      ),
    );
  }
}

class _PowerButton extends StatelessWidget {
  const _PowerButton({required this.state, required this.onTap});

  final AppState state;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final on = state.status == VpnStatus.on;
    final busy = state.status == VpnStatus.connecting;
    final lit = on || busy;

    String title;
    String detail;
    if (busy) {
      title = tr('Подключаюсь…');
      detail = tr('Нажмите для отмены');
    } else if (on) {
      title = tr('VPN включён');
      detail = state.settings.fullTunnel
          ? tr('Весь трафик')
          : (state.appMode
              ? tr('Приложений: {0}', [state.enabledApps.length])
              : tr('В туннеле: {0}', [state.enabled.length]));
    } else {
      title = tr('VPN выключен');
      if (state.server == null) {
        detail = tr('Добавьте сервер');
      } else if (!state.canConnect) {
        detail = state.appMode
            ? tr('Включите приложения ниже')
            : tr('Включите сервисы ниже');
      } else {
        detail = tr('Нажмите для включения');
      }
    }

    return Semantics(
      button: true,
      toggled: on,
      label: '$title, $detail',
      excludeSemantics: true,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(24),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 420),
            constraints: const BoxConstraints(minHeight: 96),
            padding: const EdgeInsets.fromLTRB(16, 16, 18, 16),
            decoration: BoxDecoration(
              color: lit ? const Color.fromRGBO(42, 44, 132, 0.82) : C.card,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: lit
                    ? const Color.fromRGBO(110, 150, 255, 0.6)
                    : const Color.fromRGBO(120, 140, 255, 0.25),
              ),
              boxShadow: [
                BoxShadow(
                  color: lit
                      ? const Color.fromRGBO(70, 110, 255, 0.3)
                      : const Color(0x00466EFF),
                  blurRadius: 36,
                ),
              ],
            ),
            child: Row(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 420),
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: on
                        ? const Color(0xFF17506E)
                        : const Color.fromRGBO(40, 46, 90, 0.9),
                    shape: BoxShape.circle,
                    border: Border.all(
                      width: 2,
                      color: on
                          ? C.teal
                          : const Color.fromRGBO(150, 160, 220, 0.55),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: on
                            ? const Color.fromRGBO(88, 224, 200, 0.55)
                            : const Color(0x0058E0C8),
                        blurRadius: 22,
                      ),
                    ],
                  ),
                  child: FadeSwap(
                    alignment: Alignment.center,
                    child: busy
                        ? const Padding(
                            key: ValueKey('busy'),
                            padding: EdgeInsets.all(18),
                            child: CircularProgressIndicator(
                              strokeWidth: 3,
                              color: C.white,
                            ),
                          )
                        : const Icon(
                            Icons.power_settings_new,
                            key: ValueKey('power'),
                            size: 32,
                            color: C.white,
                          ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Текст не обрезается: если не помещается, слегка
                      // уменьшается целиком.
                      FadeSwap(
                        alignment: Alignment.centerLeft,
                        child: FittedBox(
                          key: ValueKey(title),
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            title,
                            maxLines: 1,
                            style: tx(18, w: w700, c: C.white),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      FadeSwap(
                        alignment: Alignment.centerLeft,
                        child: FittedBox(
                        key: ValueKey(detail),
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                        detail,
                        maxLines: 1,
                        style: tx(13, c: on ? C.tealText : C.muted),
                        ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // Ширина постоянная: иначе блок «плывёт», когда меняются цифры.
                SizedBox(
                  width: 104,
                  child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _Speed(
                      icon: Icons.arrow_downward,
                      color: C.teal,
                      text: on ? formatRate(state.downRate) : '—',
                      lit: on,
                    ),
                    const SizedBox(height: 8),
                    _Speed(
                      icon: Icons.arrow_upward,
                      color: const Color(0xFFA78BFA),
                      text: on ? formatRate(state.upRate) : '—',
                      lit: on,
                    ),
                  ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Speed extends StatelessWidget {
  const _Speed({
    required this.icon,
    required this.color,
    required this.text,
    required this.lit,
  });

  final IconData icon;
  final Color color;
  final String text;
  final bool lit;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 6),
        Text(
          text,
          maxLines: 1,
          style: tx(12, w: w600, c: lit ? C.white : C.muted, mono: true),
        ),
      ],
    );
  }
}

class _GroupCard extends StatelessWidget {
  const _GroupCard({
    required this.state,
    required this.group,
    required this.index,
    required this.open,
    required this.dimmed,
    required this.onToggle,
    required this.onDrag,
  });

  final AppState state;
  final Section group;
  final int index;
  final bool open;
  final bool dimmed;
  final VoidCallback onToggle;

  /// Сообщает, где сейчас тащат ресурс (null — отпустили).
  final ValueChanged<Offset?> onDrag;

  @override
  Widget build(BuildContext context) {
    final items = state.servicesOf(group.id);
    final onCount = items.where((s) => state.enabled.contains(s.id)).length;
    final lit = onCount > 0 && !dimmed;
    final allOn = items.isNotEmpty && onCount == items.length;
    final count = items.isEmpty
        ? tr('Пока пусто')
        : tr('Включено {0} из {1}', [onCount, items.length]);

    // Ресурс, брошенный на раздел (а не на строку в нём), встаёт в конец.
    return DragTarget<String>(
      onAcceptWithDetails: (drop) => state.placeResource(drop.data, group.id),
      builder: (context, incoming, _) => CvCard(
      padding: EdgeInsets.zero,
      color: open ? C.cardOpen : C.card,
      line: incoming.isNotEmpty
          ? C.teal
          : lit
              ? C.cardLineLit
              : const Color.fromRGBO(120, 140, 255, 0.2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // На сенсорном экране раздел берут долгим нажатием на шапку;
          // ручка слева работает и там, и с мышью.
          ReorderableDelayedDragStartListener(
            index: index,
            enabled: state.isAndroid,
            child: Row(
            children: [
              ReorderableDragStartListener(
                index: index,
                child: _Grip(
                  width: 36,
                  height: 60,
                  hint: tr('Перетащите, чтобы изменить порядок'),
                  label: tr('Переместить раздел «{0}»', [group.title]),
                ),
              ),
              Expanded(
                child: Semantics(
                  button: true,
                  expanded: open,
                  child: InkWell(
                    onTap: onToggle,
                    borderRadius: BorderRadius.circular(18),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(2, 8, 4, 8),
                      child: Row(
                        children: [
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: lit
                                  ? C.accent
                                  : const Color.fromRGBO(90, 100, 160, 0.35),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              sectionIcon(group.icon),
                              size: 22,
                              color: C.white,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  group.title,
                                  overflow: TextOverflow.ellipsis,
                                  style: tx(16, w: w600, c: C.white),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  count,
                                  style: tx(12, c: lit ? C.tealText : C.muted),
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
                tooltip: tr('Действия с разделом «{0}»', [group.title]),
                framed: false,
                onTap: () => showSectionMenu(context, state, group),
              ),
              InkWell(
                onTap: onToggle,
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 40,
                  height: 44,
                  child: AnimatedRotation(
                    turns: open ? 0.5 : 0,
                    duration: const Duration(milliseconds: 320),
                    curve: Curves.easeOutCubic,
                    child: const Icon(
                      Icons.expand_more,
                      size: 22,
                      color: C.soft,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
            ],
          ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: !open
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (items.isEmpty)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(4, 4, 4, 10),
                            child: Text(
                              tr('В разделе пока ничего нет.'),
                              style: tx(13, c: C.muted),
                            ),
                          ),
                        for (final s in items)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: _ServiceRow(
                              state: state,
                              service: s,
                              sectionId: group.id,
                              dimmed: dimmed,
                              onDrag: onDrag,
                            ),
                          ),
                        _AddButton(
                          label: tr('Добавить ресурс'),
                          onTap: () => showRouteSheet(
                            context,
                            state,
                            section: group.id,
                          ),
                        ),
                        if (items.length > 1 && !dimmed)
                          Align(
                            alignment: Alignment.centerRight,
                            child: InkWell(
                              onTap: () => state.setMany(
                                items.map((s) => s.id),
                                !allOn,
                              ),
                              borderRadius: BorderRadius.circular(10),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 9,
                                ),
                                child: Text(
                                  allOn ? tr('Выключить все') : tr('Включить все'),
                                  style: tx(13, c: C.link),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
      ),
    );
  }
}

/// Кнопка «добавить»: ресурс в раздел или новый раздел.
class _AddButton extends StatelessWidget {
  const _AddButton({
    required this.label,
    required this.onTap,
    this.center = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool center;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        constraints: const BoxConstraints(minHeight: 52),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: const Color.fromRGBO(40, 44, 120, 0.3),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color.fromRGBO(160, 150, 255, 0.6)),
        ),
        child: Row(
          mainAxisAlignment:
              center ? MainAxisAlignment.center : MainAxisAlignment.start,
          children: [
            const Icon(Icons.add, size: 18, color: Color(0xFFDFE4FF)),
            const SizedBox(width: 12),
            Text(label, style: tx(14, w: w600, c: const Color(0xFFDFE4FF))),
          ],
        ),
      ),
    );
  }
}

class _ServiceRow extends StatelessWidget {
  const _ServiceRow({
    required this.state,
    required this.service,
    required this.sectionId,
    required this.dimmed,
    required this.onDrag,
  });

  final AppState state;
  final ServiceEntry service;
  final String sectionId;
  final bool dimmed;
  final ValueChanged<Offset?> onDrag;

  @override
  Widget build(BuildContext context) {
    final on = state.enabled.contains(service.id);
    final lit = on && !dimmed;
    // Ресурс, брошенный на строку, встаёт перед ней.
    return DragTarget<String>(
      onAcceptWithDetails: (drop) =>
          state.placeResource(drop.data, sectionId, before: service.id),
      builder: (context, incoming, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            height: incoming.isNotEmpty && incoming.first != service.id ? 4 : 0,
            margin: const EdgeInsets.only(bottom: 2),
            decoration: BoxDecoration(
              color: C.teal,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          if (state.isAndroid)
            LongPressDraggable<String>(
              data: service.id,
              dragAnchorStrategy: pointerDragAnchorStrategy,
              onDragUpdate: (details) => onDrag(details.globalPosition),
              onDragEnd: (_) => onDrag(null),
              feedback: _feedback(),
              child: _row(context, on, lit),
            )
          else
            _row(context, on, lit),
        ],
      ),
    );
  }

  /// Плашка с названием, которая едет за пальцем или курсором.
  Widget _feedback() {
    return Material(
      type: MaterialType.transparency,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: C.menu,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: C.teal),
        ),
        child: Text(service.name, style: tx(14, w: w600, c: C.white)),
      ),
    );
  }

  Widget _row(BuildContext context, bool on, bool lit) {
    final grip = _Grip(
      width: 30,
      height: 44,
      hint: tr('Перетащите на нужное место или на другой раздел'),
      label: service.name,
    );
    return AnimatedContainer(
      duration: const Duration(milliseconds: 260),
      constraints: const BoxConstraints(minHeight: 56),
      padding: const EdgeInsets.fromLTRB(2, 6, 2, 6),
      decoration: BoxDecoration(
        color: lit ? C.rowOn : C.rowOff,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: lit ? const Color.fromRGBO(130, 150, 255, 0.55) : C.rowLine,
        ),
      ),
      child: Row(
        children: [
          // С мышью ресурс тянут за ручку; на сенсорном экране — долгим
          // нажатием на строку (см. build), ручка там только подсказка.
          if (state.isAndroid)
            grip
          else
            Draggable<String>(
              data: service.id,
              dragAnchorStrategy: pointerDragAnchorStrategy,
              onDragUpdate: (details) => onDrag(details.globalPosition),
              onDragEnd: (_) => onDrag(null),
              feedback: _feedback(),
              child: grip,
            ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  service.name,
                  overflow: TextOverflow.ellipsis,
                  style: tx(14, w: w600, c: C.white),
                ),
                const SizedBox(height: 2),
                Text(
                  tr('{0} IP · {1} доменов', [service.ips.length, service.domains.length]),
                  overflow: TextOverflow.ellipsis,
                  style: tx(12, c: C.muted, mono: true),
                ),
              ],
            ),
          ),
          CvIconButton(
            icon: Icons.more_vert,
            tooltip: tr('Действия с ресурсом «{0}»', [service.name]),
            framed: false,
            onTap: () => showResourceMenu(context, state, service),
          ),
          CvSwitch(
            value: on,
            label: service.name,
            locked: dimmed,
            onChanged: (value) => state.toggleService(service.id, value),
          ),
        ],
      ),
    );
  }
}

/// Ручка перетаскивания: шесть точек. Подсказка показывается только с
/// мышью — на сенсорном экране она перехватывала бы долгое нажатие.
class _Grip extends StatelessWidget {
  const _Grip({
    required this.width,
    required this.height,
    required this.hint,
    required this.label,
  });

  final double width;
  final double height;
  final String hint;
  final String label;

  @override
  Widget build(BuildContext context) {
    final grip = MouseRegion(
      cursor: SystemMouseCursors.grab,
      child: Semantics(
        label: label,
        child: SizedBox(
          width: width,
          height: height,
          child: const Icon(Icons.drag_indicator, size: 18, color: C.dim),
        ),
      ),
    );
    final touch = Theme.of(context).platform == TargetPlatform.android ||
        Theme.of(context).platform == TargetPlatform.iOS;
    return touch ? grip : Tooltip(message: hint, child: grip);
  }
}
