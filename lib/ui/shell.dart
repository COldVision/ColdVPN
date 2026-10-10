import 'package:flutter/material.dart';

import '../app_state.dart';
import 'log_tab.dart';
import 'server_tab.dart';
import 'services_tab.dart';
import 'settings_tab.dart';
import 'theme.dart';

/// Каркас приложения: четыре вкладки и нижняя навигация.
class Shell extends StatefulWidget {
  const Shell({super.key, required this.state});

  final AppState state;

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _tab = 0;

  void _go(int tab) => setState(() => _tab = tab);

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    return Scaffold(
      backgroundColor: C.bg,
      body: CvBackground(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: AnimatedBuilder(
                animation: state,
                builder: (context, _) {
                  // Свой слой Material поверх фона: без него не видно
                  // отклика на нажатия и наведение.
                  return Material(
                    type: MaterialType.transparency,
                    child: Column(
                    children: [
                      Expanded(
                        child: _FadeTabs(
                          index: _tab,
                          children: [
                            ServicesTab(state: state, openServers: () => _go(1)),
                            ServerTab(state: state),
                            LogTab(state: state),
                            SettingsTab(state: state),
                          ],
                        ),
                      ),
                      _NavBar(current: _tab, onSelect: _go),
                    ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Вкладки, которые плавно сменяют друг друга. Все остаются в дереве,
/// поэтому помнят прокрутку и раскрытые группы.
class _FadeTabs extends StatelessWidget {
  const _FadeTabs({required this.index, required this.children});

  final int index;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        for (var i = 0; i < children.length; i++)
          IgnorePointer(
            ignoring: i != index,
            child: ExcludeFocus(
              excluding: i != index,
              child: ExcludeSemantics(
                excluding: i != index,
                child: AnimatedSlide(
                  duration: const Duration(milliseconds: 280),
                  curve: Curves.easeOutCubic,
                  offset: i == index ? Offset.zero : const Offset(0, 0.015),
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOut,
                    opacity: i == index ? 1 : 0,
                    child: children[i],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _NavBar extends StatelessWidget {
  const _NavBar({required this.current, required this.onSelect});

  final int current;
  final ValueChanged<int> onSelect;

  static const _items = [
    (Icons.tune, 'Сервисы'),
    (Icons.dns_outlined, 'Сервер'),
    (Icons.description_outlined, 'Журнал'),
    (Icons.settings_outlined, 'Настройки'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: const BoxDecoration(
        color: Color.fromRGBO(12, 15, 40, 0.92),
        border: Border(top: BorderSide(color: C.cardLine)),
      ),
      child: Row(
        children: [
          for (var i = 0; i < _items.length; i++)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Semantics(
                  button: true,
                  selected: i == current,
                  label: _items[i].$2,
                  excludeSemantics: true,
                  child: InkWell(
                    onTap: () => onSelect(i),
                    borderRadius: BorderRadius.circular(14),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      height: 52,
                      decoration: BoxDecoration(
                        gradient: i == current
                            ? const LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Color.fromRGBO(99, 102, 241, 0.5),
                                  Color.fromRGBO(139, 92, 246, 0.3),
                                ],
                              )
                            : null,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: i == current
                              ? const Color.fromRGBO(160, 150, 255, 0.45)
                              : const Color(0x00000000),
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _items[i].$1,
                            size: 18,
                            color: i == current
                                ? C.white
                                : const Color(0xFFB9C2EE),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _items[i].$2,
                            style: tx(
                              12,
                              w: i == current ? w600 : FontWeight.w400,
                              c: i == current
                                  ? C.white
                                  : const Color(0xFFB9C2EE),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Шапка вкладки: логотип, название и то, что справа.
class TabHeader extends StatelessWidget {
  const TabHeader({super.key, required this.title, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 0),
      child: SizedBox(
        height: 44,
        child: Row(
          children: [
            const CvLogo(),
            const SizedBox(width: 10),
            Expanded(
              child: Semantics(
                header: true,
                child: Text(
                  title,
                  overflow: TextOverflow.ellipsis,
                  style: tx(22, w: w700, c: C.white),
                ),
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
      ),
    );
  }
}

/// Кнопка выбора сервера с выпадающим списком.
class ServerPicker extends StatelessWidget {
  const ServerPicker({super.key, required this.state, this.onManage});

  final AppState state;

  /// Переход к управлению серверами (вкладка «Сервер»). null — пункт меню
  /// не показывается: мы уже на этой вкладке.
  final VoidCallback? onManage;

  static const _manage = '__manage__';

  @override
  Widget build(BuildContext context) {
    final current = state.current;
    final on = state.status == VpnStatus.on;
    return PopupMenuButton<String>(
      tooltip: 'Выбрать сервер',
      color: C.menu,
      offset: const Offset(0, 50),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: C.pillLine),
      ),
      constraints: const BoxConstraints(minWidth: 260, maxWidth: 300),
      onSelected: (value) {
        if (value == _manage) {
          onManage?.call();
        } else {
          state.selectServer(value);
        }
      },
      itemBuilder: (context) => [
        for (final s in state.servers)
          PopupMenuItem<String>(
            value: s.id,
            height: 52,
            child: Row(
              children: [
                CountryBadge(s),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        s.name,
                        overflow: TextOverflow.ellipsis,
                        style: tx(14, w: w600, c: C.white),
                      ),
                      Text(
                        s.place.isEmpty ? s.profile.host : s.place,
                        overflow: TextOverflow.ellipsis,
                        style: tx(12, c: C.muted),
                      ),
                    ],
                  ),
                ),
                if (s.id == current?.id)
                  const Icon(Icons.check, size: 18, color: C.tealText),
              ],
            ),
          ),
        if (onManage != null)
          PopupMenuItem<String>(
          value: _manage,
          height: 44,
          child: Row(
            children: [
              const Icon(Icons.add, size: 16, color: C.link),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  'Добавить или изменить серверы',
                  style: tx(14, c: C.link),
                ),
              ),
            ],
          ),
        ),
      ],
      child: Container(
        height: 44,
        constraints: const BoxConstraints(maxWidth: 190),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: const Color.fromRGBO(60, 64, 170, 0.45),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: C.pillLine),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: on ? C.teal : C.dim,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                current?.name ?? 'Нет сервера',
                overflow: TextOverflow.ellipsis,
                style: tx(14, w: w600, c: C.white),
              ),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.expand_more, size: 16, color: C.white),
          ],
        ),
      ),
    );
  }
}

/// Скорость в понятных единицах: «4,2 Мбит/с».
String formatRate(double bytesPerSecond) {
  final bits = bytesPerSecond * 8;
  if (bits >= 1e6) {
    return '${(bits / 1e6).toStringAsFixed(1).replaceAll('.', ',')} Мбит/с';
  }
  return '${(bits / 1e3).round()} Кбит/с';
}

/// Объём данных: «1,4 ГБ».
String formatBytes(int bytes) {
  String fixed(double v) => v.toStringAsFixed(1).replaceAll('.', ',');
  if (bytes >= 1 << 30) return '${fixed(bytes / (1 << 30))} ГБ';
  if (bytes >= 1 << 20) return '${fixed(bytes / (1 << 20))} МБ';
  return '${(bytes / 1024).round()} КБ';
}
