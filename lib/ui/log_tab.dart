import 'dart:io' show Platform;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';
import '../route_input.dart';
import 'files.dart';
import 'shell.dart';
import 'theme.dart';
import '../l10n.dart';

enum _LogView { events, routes, raw }

/// Вкладка «Журнал»: события, маршруты, подробный журнал и диагностика.
class LogTab extends StatefulWidget {
  const LogTab({super.key, required this.state});

  final AppState state;

  @override
  State<LogTab> createState() => _LogTabState();
}

class _LogTabState extends State<LogTab> {
  _LogView _view = _LogView.events;

  AppState get state => widget.state;

  void _diagnose() {
    state.runChecks();
    showCvSheet<void>(context, builder: (_) => _CheckSheet(state: state));
  }

  Future<void> _saveLog() async {
    try {
      final note = savedNote(
        tr('Журнал сохранён'),
        await saveTextFile(
          name: 'coldvpn-log.txt',
          text: state.logText,
          type: XTypeGroup(label: tr('Текст'), extensions: ['txt']),
        ),
      );
      if (mounted && note != null) showNote(context, note);
    } catch (e) {
      if (mounted) showNote(context, tr('Не удалось сохранить журнал: {0}', [e]));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TabHeader(title: tr('Журнал')),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
          child: CvSegments<_LogView>(
            options: {
              _LogView.events: tr('События'),
              _LogView.routes: tr('Маршруты'),
              _LogView.raw: tr('Подробно'),
            },
            selected: _view,
            onChanged: (view) => setState(() => _view = view),
          ),
        ),
        Expanded(
          child: FadeSwap(
            expand: true,
            child: KeyedSubtree(key: ValueKey(_view), child: _body()),
          ),
        ),
      ],
    );
  }

  Widget _body() {
    switch (_view) {
      case _LogView.events:
        return _events();
      case _LogView.routes:
        return _routes();
      case _LogView.raw:
        return _raw();
    }
  }

  Widget _events() {
    final feed = state.feed;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: _eventList(feed)),
        // Кнопка закреплена внизу и не уезжает вместе со списком.
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CvButton(
                label: tr('Запустить диагностику'),
                kind: CvButtonKind.primary,
                onTap: _diagnose,
              ),
              const SizedBox(height: 6),
              Text(
                tr('Проверит клиент, связь, DNS, маршруты, сервисы и сервер.'),
                textAlign: TextAlign.center,
                style: tx(12, c: C.muted, h: 1.45),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _eventList(List<LogEvent> feed) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 4),
      children: [
        if (feed.isEmpty)
          CvCard(
            child: Text(
              tr('Событий пока нет. Они появятся, когда вы включите VPN.'),
              style: tx(13, c: C.muted, h: 1.45),
            ),
          ),
        for (var i = feed.length - 1; i >= 0 && i >= feed.length - 120; i--)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _EventRow(event: feed[i]),
          ),
      ],
    );
  }

  Widget _routes() {
    final full = state.settings.fullTunnel;
    final active = [
      for (final s in state.services)
        if (state.enabled.contains(s.id)) s,
    ];
    final learned = state.recentLearned();
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
      children: [
        if (full)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: CvCard(
              child: Text(
                tr('Включён режим «Весь трафик»: через VPN идёт всё, списки ниже '
                'сейчас не используются.'),
                style: tx(13, c: C.text, h: 1.45),
              ),
            ),
          ),
        CvCard(
          color: const Color.fromRGBO(42, 44, 132, 0.6),
          line: const Color.fromRGBO(110, 150, 255, 0.5),
          child: Row(
            children: [
              _Total(value: '${active.length}', label: tr('сервисов')),
              _Total(value: '${state.enabledRangeCount}', label: tr('диапазонов')),
              _Total(value: '${state.domainRouteCount}', label: tr('по доменам')),
            ],
          ),
        ),
        const SizedBox(height: 8),
        SectionTitle(tr('По сервисам')),
        const SizedBox(height: 8),
        if (active.isEmpty)
          CvCard(
            child: Text(
              tr('Ни один сервис не включён.'),
              style: tx(13, c: C.muted),
            ),
          )
        else
          CvCard(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
            child: Column(
              children: [
                for (var i = 0; i < active.length; i++)
                  Container(
                    constraints: const BoxConstraints(minHeight: 44),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: i == active.length - 1
                              ? const Color(0x00000000)
                              : C.rowLine,
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            active[i].name,
                            overflow: TextOverflow.ellipsis,
                            style: tx(14, w: w600, c: C.white),
                          ),
                        ),
                        Text(
                          '${active[i].ips.length}',
                          style: tx(12, c: C.soft, mono: true),
                        ),
                        SizedBox(
                          width: 44,
                          child: Text(
                            '+${state.learnedCountOf(active[i])}',
                            textAlign: TextAlign.right,
                            style: tx(12, c: C.routeText, mono: true),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        const SizedBox(height: 6),
        Text(
          tr('Первое число — диапазоны из списка, второе — адреса, найденные '
          'по доменам.'),
          style: tx(12, c: C.muted, h: 1.45),
        ),
        const SizedBox(height: 8),
        SectionTitle(tr('Найдено по доменам')),
        const SizedBox(height: 8),
        if (learned.isEmpty)
          CvCard(
            child: Text(
              tr('Пока ничего: адреса появляются, когда программы обращаются к '
              'сервисам при включённом VPN.'),
              style: tx(13, c: C.muted, h: 1.45),
            ),
          ),
        for (final e in learned)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: CvCard(
              radius: 14,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              line: const Color.fromRGBO(120, 140, 255, 0.18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    e.key.isEmpty ? '—' : e.key,
                    overflow: TextOverflow.ellipsis,
                    style: tx(13, c: C.white, mono: true),
                  ),
                  const SizedBox(height: 2),
                  Text(e.value, style: tx(12, c: C.muted, mono: true)),
                ],
              ),
            ),
          ),
        const SizedBox(height: 4),
        CvButton(
          label: tr('Забыть найденные адреса'),
          height: 48,
          onTap: state.learnedTotal == 0
              ? null
              : () {
                  state.forgetLearned();
                  showNote(context, tr('Найденные адреса забыты'));
                },
        ),
        const SizedBox(height: 6),
        Text(
          tr('Сохранено адресов: {0}. Приложение найдёт их '
          'заново, когда сервисы к ним обратятся.', [state.learnedTotal]),
          textAlign: TextAlign.center,
          style: tx(12, c: C.muted, h: 1.45),
        ),
      ],
    );
  }

  Widget _raw() {
    final lines = state.events;
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color.fromRGBO(4, 6, 20, 0.85),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: C.cardLine),
              ),
              child: lines.isEmpty
                  ? Text(tr('Журнал пуст.'), style: tx(12, c: C.muted, mono: true))
                  : SingleChildScrollView(
                      reverse: true,
                      child: SelectableText(
                        lines.join('\n'),
                        style: tx(
                          12,
                          c: const Color(0xFFD7DCF7),
                          mono: true,
                          h: 1.65,
                        ),
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              // Отдельный журнал туннеля есть только у клиента для Windows.
              if (!Platform.isAndroid) ...[
                Expanded(
                  child: CvButton(
                    label: tr('Журнал туннеля'),
                    height: 48,
                    onTap: state.collectClientLog,
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: CvButton(
                  label: Platform.isAndroid ? tr('Поделиться журналом') : tr('Сохранить в файл'),
                  height: 48,
                  onTap: _saveLog,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            tr('Пароли в журнал не попадают.'),
            textAlign: TextAlign.center,
            style: tx(12, c: C.muted),
          ),
        ],
      ),
    );
  }
}

class _Total extends StatelessWidget {
  const _Total({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(value, style: tx(20, w: w600, c: C.white, mono: true)),
          const SizedBox(height: 2),
          Text(label, style: tx(12, c: C.soft)),
        ],
      ),
    );
  }
}

class _EventRow extends StatelessWidget {
  const _EventRow({required this.event});

  final LogEvent event;

  @override
  Widget build(BuildContext context) {
    late final Color color;
    switch (event.kind) {
      case LogKind.ok:
        color = C.teal;
        break;
      case LogKind.route:
        color = const Color(0xFFA78BFA);
        break;
      case LogKind.warn:
        color = C.warn;
        break;
      case LogKind.info:
        color = const Color(0xFF60A5FA);
        break;
    }
    return CvCard(
      radius: 14,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      line: const Color.fromRGBO(120, 140, 255, 0.18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.only(top: 6),
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: color, blurRadius: 10)],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(event.text, style: tx(14, c: C.white, h: 1.4)),
          ),
          const SizedBox(width: 10),
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(event.time, style: tx(12, c: C.muted, mono: true)),
          ),
        ],
      ),
    );
  }
}

/// Панель диагностики: шаги по очереди и итог.
class _CheckSheet extends StatelessWidget {
  const _CheckSheet({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: state,
      builder: (context, _) {
        final steps = state.checks;
        final done = steps
            .where((s) => s.state != CheckState.wait && s.state != CheckState.run)
            .length;
        final finished = !state.checking && steps.isNotEmpty;
        final bad = steps.any((s) => s.state == CheckState.fail);
        final warned = steps.any((s) => s.state == CheckState.warn);
        final verdictColor = bad
            ? C.dangerLine
            : (warned || state.status != VpnStatus.on
                ? const Color.fromRGBO(251, 191, 36, 0.55)
                : const Color.fromRGBO(88, 224, 200, 0.55));
        final verdictBg = bad
            ? C.dangerBg
            : (warned || state.status != VpnStatus.on
                ? const Color.fromRGBO(251, 191, 36, 0.12)
                : const Color.fromRGBO(31, 159, 144, 0.16));
        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SheetHeader(
                title: tr('Диагностика'),
                subtitle: finished
                    ? tr('Готово: {0}', [plural(done, tr('шаг'), tr('шага'), tr('шагов'))])
                    : tr('Шаг {0}'
                        ' из {1}', [(done + 1).clamp(1, steps.isEmpty ? 1 : steps.length), steps.length]),
              ),
              const SizedBox(height: 10),
              Semantics(
                label: tr('Ход проверки'),
                value: tr('{0} из {1}', [done, steps.length]),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: steps.isEmpty ? 0 : done / steps.length,
                    minHeight: 6,
                    backgroundColor: const Color.fromRGBO(8, 11, 32, 0.8),
                    color: C.teal,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              for (final step in steps)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: _StepRow(step: step),
                ),
              Reveal(
                show: finished,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: verdictBg,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: verdictColor),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        state.checkSummary,
                        style: tx(16, w: w700, c: C.white),
                      ),
                      if (state.checkAdvice.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            state.checkAdvice,
                            style: tx(13, c: const Color(0xFFD7DCF7), h: 1.45),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: CvButton(
                        label: tr('Повторить'),
                        onTap: state.runChecks,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: CvButton(
                        label: tr('Скопировать отчёт'),
                        kind: CvButtonKind.primary,
                        onTap: () => copyText(
                          context,
                          state.checkReport,
                          tr('Отчёт скопирован'),
                        ),
                      ),
                    ),
                  ],
                ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({required this.step});

  final CheckStep step;

  @override
  Widget build(BuildContext context) {
    final s = step.state;
    late final Widget mark;
    switch (s) {
      case CheckState.run:
        mark = const SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 3, color: C.soft),
        );
        break;
      case CheckState.wait:
        mark = Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: const Color.fromRGBO(150, 160, 220, 0.5)),
          ),
        );
        break;
      case CheckState.ok:
        mark = const _Mark(Icons.check, C.teal, Color(0xFF0B2B27));
        break;
      case CheckState.warn:
        mark = const _Mark(Icons.priority_high, C.warn, Color(0xFF2B1D00));
        break;
      case CheckState.fail:
        mark = const _Mark(Icons.close, C.danger, C.white);
        break;
      case CheckState.skip:
        mark = const _Mark(Icons.remove, Color(0xFF3A416F), C.soft);
        break;
    }
    final finished = s != CheckState.wait && s != CheckState.run;
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 260),
      opacity: s == CheckState.wait ? 0.6 : 1,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 260),
        constraints: const BoxConstraints(minHeight: 56),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: C.rowOff,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: s == CheckState.run
                ? const Color.fromRGBO(150, 160, 255, 0.6)
                : (s == CheckState.warn
                    ? const Color.fromRGBO(251, 191, 36, 0.5)
                    : (s == CheckState.fail ? C.dangerLine : C.rowLine)),
          ),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 26,
              height: 26,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 260),
                switchInCurve: Curves.easeOutBack,
                transitionBuilder: (child, animation) => ScaleTransition(
                  scale: animation,
                  child: FadeTransition(opacity: animation, child: child),
                ),
                child: Center(key: ValueKey(s), child: mark),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(step.title, style: tx(14, w: w600, c: C.white)),
                  const SizedBox(height: 2),
                  Text(
                    step.note,
                    style: tx(
                      12,
                      c: s == CheckState.warn
                          ? C.warnText
                          : (s == CheckState.fail ? C.dangerText : C.muted),
                      h: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            if (finished) ...[
              const SizedBox(width: 8),
              Text(
                AppState.stateWord(s),
                style: tx(12, w: w600, c: C.soft),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Mark extends StatelessWidget {
  const _Mark(this.icon, this.bg, this.fg);

  final IconData icon;
  final Color bg;
  final Color fg;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
      child: Icon(icon, size: 15, color: fg),
    );
  }
}
