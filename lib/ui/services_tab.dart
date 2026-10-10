import 'package:flutter/material.dart';

import '../app_state.dart';
import '../catalog.dart';
import '../models.dart';
import 'route_sheet.dart';
import 'shell.dart';
import 'theme.dart';

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
    final order = state.groupOrder;
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
          child: const _Banner(
            text: 'Приложение запущено без прав администратора — подключение '
                'не сработает. Закройте его и запустите от имени '
                'администратора.',
          ),
        ),
        Reveal(
          show: state.error != null,
          child: _Banner(text: state.error ?? ''),
        ),
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
                        'Весь трафик через VPN',
                        style: tx(14, w: w600, c: C.white),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        full
                            ? 'Переключатели сервисов заблокированы'
                            : 'Сейчас — только включённые сервисы',
                        style: tx(12, c: C.muted),
                      ),
                    ],
                  ),
                ),
                CvSwitch(
                  value: full,
                  label: 'Весь трафик через VPN',
                  onChanged: (value) =>
                      state.changeSettings((s) => s.fullTunnel = value),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: ReorderableListView.builder(
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
            itemBuilder: (context, index) {
              final group =
                  serviceGroups.firstWhere((g) => g.id == order[index]);
              return Padding(
                key: ValueKey(group.id),
                padding: const EdgeInsets.only(bottom: 10),
                child: _GroupCard(
                  state: state,
                  group: group,
                  index: index,
                  open: _open == group.id,
                  dimmed: full,
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
      title = 'Подключаюсь…';
      detail = 'Нажмите для отмены';
    } else if (on) {
      title = 'VPN включён';
      detail = state.settings.fullTunnel
          ? 'Весь трафик'
          : 'В туннеле: ${state.enabled.length}';
    } else {
      title = 'VPN выключен';
      if (state.server == null) {
        detail = 'Добавьте сервер';
      } else if (!state.canConnect) {
        detail = 'Включите сервисы ниже';
      } else {
        detail = 'Нажмите для включения';
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
  });

  final AppState state;
  final ServiceGroup group;
  final int index;
  final bool open;
  final bool dimmed;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final items = state.servicesOf(group.id);
    final onCount = items.where((s) => state.enabled.contains(s.id)).length;
    final lit = onCount > 0 && !dimmed;
    final allOn = items.isNotEmpty && onCount == items.length;
    final custom = group.id == customGroupId;
    final count = custom && items.isEmpty
        ? 'Пока пусто'
        : 'Включено $onCount из ${items.length}';

    return CvCard(
      padding: EdgeInsets.zero,
      color: open ? C.cardOpen : C.card,
      line: lit ? C.cardLineLit : const Color.fromRGBO(120, 140, 255, 0.2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              ReorderableDragStartListener(
                index: index,
                child: Tooltip(
                  message: 'Перетащите, чтобы изменить порядок',
                  child: MouseRegion(
                    cursor: SystemMouseCursors.grab,
                    child: Semantics(
                      label: 'Переместить группу «${group.label}»',
                      child: const SizedBox(
                        width: 36,
                        height: 60,
                        child: Icon(
                          Icons.drag_indicator,
                          size: 18,
                          color: C.dim,
                        ),
                      ),
                    ),
                  ),
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
                      padding: const EdgeInsets.fromLTRB(2, 8, 14, 8),
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
                            child: Icon(group.icon, size: 22, color: C.white),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  group.label,
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
                          AnimatedRotation(
                            turns: open ? 0.5 : 0,
                            duration: const Duration(milliseconds: 320),
                            curve: Curves.easeOutCubic,
                            child: const Icon(
                              Icons.expand_more,
                              size: 22,
                              color: C.soft,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
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
                        if (custom)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: _AddRouteButton(
                              onTap: () => showRouteSheet(context, state),
                            ),
                          ),
                        for (final s in items)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: _ServiceRow(
                              state: state,
                              service: s,
                              custom: custom,
                              dimmed: dimmed,
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
                                  allOn ? 'Выключить все' : 'Включить все',
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
    );
  }
}

class _AddRouteButton extends StatelessWidget {
  const _AddRouteButton({required this.onTap});

  final VoidCallback onTap;

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
          children: [
            const Icon(Icons.add, size: 18, color: Color(0xFFDFE4FF)),
            const SizedBox(width: 12),
            Text(
              'Добавить домен или IP',
              style: tx(14, w: w600, c: const Color(0xFFDFE4FF)),
            ),
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
    required this.custom,
    required this.dimmed,
  });

  final AppState state;
  final ServiceEntry service;
  final bool custom;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final on = state.enabled.contains(service.id);
    final lit = on && !dimmed;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 260),
      constraints: const BoxConstraints(minHeight: 56),
      padding: const EdgeInsets.fromLTRB(14, 6, 2, 6),
      decoration: BoxDecoration(
        color: lit ? C.rowOn : C.rowOff,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: lit ? const Color.fromRGBO(130, 150, 255, 0.55) : C.rowLine,
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
                  service.name,
                  overflow: TextOverflow.ellipsis,
                  style: tx(14, w: w600, c: C.white),
                ),
                const SizedBox(height: 2),
                Text(
                  '${service.ips.length} IP · ${service.domains.length} доменов',
                  style: tx(12, c: C.muted, mono: true),
                ),
              ],
            ),
          ),
          if (custom)
            CvIconButton(
              icon: Icons.edit_outlined,
              tooltip: 'Изменить маршрут «${service.name}»',
              framed: false,
              onTap: () {
                for (final r in state.customRoutes) {
                  if (r.id == service.id) {
                    showRouteSheet(context, state, route: r);
                    break;
                  }
                }
              },
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
