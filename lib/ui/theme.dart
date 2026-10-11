import 'dart:ui' show FontVariation;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../catalog.dart';
import '../models.dart';
import '../l10n.dart';

/// Цвета интерфейса.
class C {
  static const bg = Color(0xFF060817);
  static const sheet = Color(0xFF121740);
  static const menu = Color(0xFF141A48);
  static const card = Color.fromRGBO(18, 22, 52, 0.72);
  static const cardOpen = Color.fromRGBO(22, 27, 66, 0.85);
  static const cardLine = Color.fromRGBO(120, 140, 255, 0.22);
  static const cardLineLit = Color.fromRGBO(130, 150, 255, 0.5);
  static const rowOn = Color.fromRGBO(52, 60, 150, 0.55);
  static const rowOff = Color.fromRGBO(8, 11, 32, 0.6);
  static const rowLine = Color.fromRGBO(120, 140, 255, 0.14);
  static const field = Color.fromRGBO(8, 11, 32, 0.7);
  static const fieldLine = Color.fromRGBO(130, 150, 255, 0.5);
  static const pill = Color.fromRGBO(99, 102, 241, 0.5);
  static const pillLine = Color.fromRGBO(160, 150, 255, 0.5);
  static const accent = Color(0xFF6366F1);
  static const accentA = Color(0xFF5B5FF0);
  static const violet = Color(0xFF8B5CF6);
  static const teal = Color(0xFF58E0C8);
  static const tealDeep = Color(0xFF1F9F90);
  static const tealText = Color(0xFF9FF0E0);
  static const text = Color(0xFFE8ECFF);
  static const white = Color(0xFFFFFFFF);
  static const soft = Color(0xFFC5CDF5);
  static const muted = Color(0xFFAAB3E0);
  static const dim = Color(0xFF8C96C8);
  static const link = Color(0xFF9DB4FF);
  static const warn = Color(0xFFFBBF24);
  static const warnText = Color(0xFFFDE08A);
  static const danger = Color(0xFFC0303C);
  static const dangerLine = Color.fromRGBO(255, 110, 120, 0.65);
  static const dangerBg = Color.fromRGBO(220, 50, 60, 0.16);
  static const dangerText = Color(0xFFFFB3B8);
  static const routeText = Color(0xFFC4B5FD);
}

/// Стиль текста. Шрифты вариативные, поэтому насыщенность задаётся ещё и
/// осью `wght`.
TextStyle tx(
  double size, {
  FontWeight w = FontWeight.w400,
  Color c = C.text,
  bool mono = false,
  double? h,
}) {
  return TextStyle(
    fontFamily: mono ? 'JetBrainsMono' : 'Onest',
    fontSize: size,
    fontWeight: w,
    fontVariations: [FontVariation('wght', w.value.toDouble())],
    color: c,
    height: h,
    decoration: TextDecoration.none,
  );
}

const w600 = FontWeight.w600;
const w700 = FontWeight.w700;

ThemeData buildTheme() {
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    fontFamily: 'Onest',
    scaffoldBackgroundColor: C.bg,
    colorScheme: const ColorScheme.dark(
      primary: C.accent,
      secondary: C.teal,
      surface: C.sheet,
      error: C.danger,
    ),
    splashFactory: InkRipple.splashFactory,
  );
}

/// Фон экрана: тёмно-синий с двумя мягкими пятнами света.
class CvBackground extends StatelessWidget {
  const CvBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const Positioned.fill(child: ColoredBox(color: C.bg)),
        const Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(0.7, -1.1),
                radius: 0.9,
                colors: [Color(0xFF1E2470), Color(0x001E2470)],
              ),
            ),
          ),
        ),
        const Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(-1.0, 1.0),
                radius: 0.8,
                colors: [Color(0xFF2A1458), Color(0x002A1458)],
              ),
            ),
          ),
        ),
        Positioned.fill(child: child),
      ],
    );
  }
}

/// Карточка со скруглением и тонкой рамкой.
class CvCard extends StatelessWidget {
  const CvCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.color = C.card,
    this.line = C.cardLine,
    this.radius = 18,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color color;
  final Color line;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 280),
      padding: padding,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: line),
      ),
      child: child,
    );
  }
}

/// Плавная смена одного содержимого другим. У [child] должен быть ключ,
/// который меняется вместе с содержимым.
class FadeSwap extends StatelessWidget {
  const FadeSwap({
    super.key,
    required this.child,
    this.alignment = Alignment.topCenter,
    this.expand = false,
  });

  final Widget child;
  final AlignmentGeometry alignment;

  /// Растянуть содержимое на всё доступное место (для вкладок и списков).
  final bool expand;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 260),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      layoutBuilder: (current, previous) => Stack(
        alignment: alignment,
        fit: expand ? StackFit.expand : StackFit.loose,
        children: [...previous, if (current != null) current],
      ),
      child: child,
    );
  }
}

/// Блок, который плавно появляется и исчезает, раздвигая соседей.
class Reveal extends StatelessWidget {
  const Reveal({super.key, required this.show, required this.child});

  final bool show;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 260),
        opacity: show ? 1 : 0,
        child: show ? child : const SizedBox(width: double.infinity),
      ),
    );
  }
}

/// Заголовок раздела прописными буквами.
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 6, 2, 0),
      child: Text(
        text.toUpperCase(),
        style: tx(13, w: w600, c: C.muted).copyWith(letterSpacing: 1),
      ),
    );
  }
}

/// Переключатель с плавной анимацией.
class CvSwitch extends StatelessWidget {
  const CvSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    required this.label,
    this.locked = false,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final String label;

  /// Переключатель заблокирован: на нём замок, нажатия не действуют.
  final bool locked;

  @override
  Widget build(BuildContext context) {
    final handler = locked ? null : onChanged;
    return Semantics(
      label: locked ? tr('{0}, заблокировано', [label]) : label,
      toggled: value,
      button: true,
      enabled: handler != null,
      excludeSemantics: true,
      child: InkWell(
        onTap: handler == null ? null : () => handler(!value),
        borderRadius: BorderRadius.circular(22),
        child: SizedBox(
          width: 56,
          height: 44,
          child: FadeSwap(
            alignment: Alignment.center,
            child: locked
                // Заблокировано: вместо переключателя — замок.
                ? Container(
                    key: const ValueKey('locked'),
                    width: 44,
                    height: 32,
                    decoration: BoxDecoration(
                      color: const Color.fromRGBO(40, 46, 90, 0.9),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: const Color.fromRGBO(150, 160, 220, 0.55),
                      ),
                    ),
                    child: Icon(
                      Icons.lock,
                      size: 18,
                      color: value ? C.tealText : C.soft,
                    ),
                  )
                : AnimatedContainer(
              key: const ValueKey('switch'),
              duration: const Duration(milliseconds: 240),
              width: 44,
              height: 24,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: value ? C.tealDeep : const Color(0xFF282E5A),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: value
                      ? const Color(0xFF8FE9D8)
                      : const Color.fromRGBO(150, 160, 220, 0.55),
                ),
                boxShadow: [
                  BoxShadow(
                    color: value
                        ? const Color.fromRGBO(88, 224, 200, 0.45)
                        : const Color(0x0058E0C8),
                    blurRadius: 12,
                  ),
                ],
              ),
              child: AnimatedAlign(
                duration: const Duration(milliseconds: 240),
                curve: Curves.easeOutBack,
                alignment:
                    value ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  width: 16,
                  height: 16,
                  decoration: const BoxDecoration(
                    color: C.white,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

enum CvButtonKind { primary, secondary, danger, dangerSoft }

/// Кнопка высотой 50: основная (градиент), обычная или опасная.
class CvButton extends StatelessWidget {
  const CvButton({
    super.key,
    required this.label,
    required this.onTap,
    this.kind = CvButtonKind.secondary,
    this.icon,
    this.height = 50,
  });

  final String label;
  final VoidCallback? onTap;
  final CvButtonKind kind;
  final IconData? icon;
  final double height;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    late final BoxDecoration decoration;
    Color textColor = C.white;
    switch (kind) {
      case CvButtonKind.primary:
        decoration = enabled
            ? BoxDecoration(
                gradient: const LinearGradient(colors: [C.accentA, C.violet]),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: const Color.fromRGBO(170, 150, 255, 0.7),
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Color.fromRGBO(110, 110, 255, 0.35),
                    blurRadius: 22,
                  ),
                ],
              )
            : BoxDecoration(
                color: const Color.fromRGBO(40, 46, 90, 0.6),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: C.cardLine),
              );
        if (!enabled) textColor = C.dim;
        break;
      case CvButtonKind.secondary:
        decoration = BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color.fromRGBO(140, 150, 255, 0.4)),
        );
        textColor = enabled ? C.text : C.dim;
        break;
      case CvButtonKind.danger:
        decoration = BoxDecoration(
          color: C.danger,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFFF8A92)),
        );
        break;
      case CvButtonKind.dangerSoft:
        decoration = BoxDecoration(
          color: const Color.fromRGBO(220, 50, 60, 0.12),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color.fromRGBO(255, 110, 120, 0.5)),
        );
        textColor = C.dangerText;
        break;
    }
    return Material(
      type: MaterialType.transparency,
      child: Ink(
        decoration: decoration,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: height),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 18, color: textColor),
                    const SizedBox(width: 10),
                  ],
                  Flexible(
                    child: Text(
                      label,
                      textAlign: TextAlign.center,
                      style: tx(
                        15,
                        w: kind == CvButtonKind.secondary ? w600 : w700,
                        c: textColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Переключатель из нескольких вариантов в одной рамке.
class CvSegments<T> extends StatelessWidget {
  const CvSegments({
    super.key,
    required this.options,
    required this.selected,
    required this.onChanged,
    this.subtitles = const {},
  });

  final Map<T, String> options;
  final Map<T, String> subtitles;
  final T selected;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: C.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: C.cardLine),
      ),
      child: Row(
        children: [
          for (final entry in options.entries)
            Expanded(
              child: Semantics(
                button: true,
                selected: entry.key == selected,
                child: InkWell(
                  onTap: () => onChanged(entry.key),
                  borderRadius: BorderRadius.circular(11),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    constraints: const BoxConstraints(minHeight: 44),
                    alignment: Alignment.center,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                    decoration: BoxDecoration(
                      color: entry.key == selected
                          ? C.pill
                          : const Color(0x006366F1),
                      borderRadius: BorderRadius.circular(11),
                      border: Border.all(
                        color: entry.key == selected
                            ? C.pillLine
                            : const Color(0x00000000),
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          entry.value,
                          textAlign: TextAlign.center,
                          style: tx(
                            14,
                            w: entry.key == selected ? w600 : FontWeight.w400,
                            c: entry.key == selected ? C.white : C.soft,
                          ),
                        ),
                        if (subtitles[entry.key] != null)
                          Text(
                            subtitles[entry.key]!,
                            style: tx(12, c: C.soft, mono: true),
                          ),
                      ],
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

/// Поле ввода с подписью над ним.
class CvField extends StatelessWidget {
  const CvField({
    super.key,
    required this.controller,
    required this.label,
    this.hint,
    this.mono = false,
    this.minLines = 1,
    this.maxLines = 1,
    this.obscure = false,
    this.enabled = true,
    this.onChanged,
    this.keyboardType,
    this.helper,
    this.trailing,
  });

  /// Что показать справа от подписи, например ссылку «Вставить».
  final Widget? trailing;

  final TextEditingController controller;
  final String label;
  final String? hint;
  final String? helper;
  final bool mono;
  final int minLines;
  final int maxLines;
  final bool obscure;
  final bool enabled;
  final ValueChanged<String>? onChanged;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    OutlineInputBorder border(Color color, double width) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: color, width: width),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(child: Text(label, style: tx(13, c: C.soft))),
              if (trailing != null) trailing!,
            ],
          ),
        ),
        TextField(
          controller: controller,
          enabled: enabled,
          obscureText: obscure,
          minLines: obscure ? 1 : minLines,
          maxLines: obscure ? 1 : maxLines,
          onChanged: onChanged,
          keyboardType: keyboardType,
          autocorrect: false,
          enableSuggestions: false,
          style: tx(mono ? 13 : 15, c: C.white, mono: mono, h: mono ? 1.6 : null),
          cursorColor: C.teal,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: tx(mono ? 13 : 15, c: C.dim, mono: mono),
            helperText: helper,
            helperStyle: tx(12, c: C.muted),
            helperMaxLines: 3,
            filled: true,
            fillColor: C.field,
            isDense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            enabledBorder: border(C.fieldLine, 1),
            disabledBorder: border(C.rowLine, 1),
            focusedBorder: border(const Color(0xFFB9C2FF), 2),
          ),
        ),
      ],
    );
  }
}

/// Флаг страны сервера. Если страна неизвестна или флага нет в наборе,
/// показывается двухбуквенный код или глобус.
class CountryBadge extends StatelessWidget {
  const CountryBadge(this.server, {super.key});

  final SavedServer server;

  @override
  Widget build(BuildContext context) {
    final code = server.countryCode.toUpperCase();
    final fallback = Container(
      width: 30,
      height: 20,
      alignment: Alignment.center,
      color: const Color.fromRGBO(99, 102, 241, 0.35),
      child: code.isEmpty
          ? const Icon(Icons.public, size: 13, color: C.soft)
          : Text(code, style: tx(11, w: w700, c: C.white, mono: true)),
    );
    final index = flagIndex(code);
    return Semantics(
      label: server.country.isEmpty ? tr('Страна неизвестна') : server.country,
      excludeSemantics: true,
      child: Container(
        width: 30,
        height: 20,
        clipBehavior: Clip.antiAlias,
        foregroundDecoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: const Color.fromRGBO(255, 255, 255, 0.35)),
        ),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(4)),
        // Все флаги — одна картинка-сетка; показываем из неё нужную ячейку.
        child: index < 0
            ? fallback
            : OverflowBox(
                alignment: Alignment.topLeft,
                minWidth: 0,
                minHeight: 0,
                maxWidth: double.infinity,
                maxHeight: double.infinity,
                child: Transform.translate(
                  offset: Offset(
                    -30.0 * (index % flagColumns),
                    -20.0 * (index ~/ flagColumns),
                  ),
                  child: Image.asset(
                    'assets/flags.png',
                    width: 30.0 * flagColumns,
                    height: 20.0 * flagRows,
                    fit: BoxFit.fill,
                    filterQuality: FilterQuality.medium,
                    errorBuilder: (context, error, stack) => fallback,
                  ),
                ),
              ),
      ),
    );
  }
}

/// Небольшая текстовая ссылка-кнопка.
class CvLink extends StatelessWidget {
  const CvLink({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Text(label, style: tx(13, c: C.link)),
      ),
    );
  }
}

/// Квадратная кнопка-значок 44×44.
class CvIconButton extends StatelessWidget {
  const CvIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.framed = true,
    this.color = C.soft,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final bool framed;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        excludeSemantics: true,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: 44,
            height: 44,
            decoration: framed
                ? BoxDecoration(
                    color: C.card,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: const Color.fromRGBO(120, 140, 255, 0.28),
                    ),
                  )
                : null,
            child: Icon(icon, size: 18, color: color),
          ),
        ),
      ),
    );
  }
}

/// Логотип приложения — тот же рисунок, что и на значке.
class CvLogo extends StatelessWidget {
  const CvLogo({super.key, this.size = 44});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.23),
        boxShadow: const [
          BoxShadow(color: Color.fromRGBO(99, 102, 241, 0.5), blurRadius: 16),
        ],
      ),
      child: Image.asset(
        'assets/logo.png',
        width: size,
        height: size,
        filterQuality: FilterQuality.medium,
        excludeFromSemantics: true,
      ),
    );
  }
}

/// Панель, выезжающая снизу.
Future<T?> showCvSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0x00000000),
    barrierColor: const Color.fromRGBO(3, 4, 14, 0.66),
    builder: (context) {
      final media = MediaQuery.of(context);
      return Padding(
        padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 520,
              maxHeight: media.size.height * 0.94,
            ),
            child: Material(
              color: C.sheet,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
                side: BorderSide(color: Color.fromRGBO(140, 150, 255, 0.45)),
              ),
              clipBehavior: Clip.antiAlias,
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Container(
                          width: 44,
                          height: 4,
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: const Color.fromRGBO(170, 180, 240, 0.45),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      Flexible(child: builder(context)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

/// Заголовок панели: название, пояснение и кнопка закрытия.
class SheetHeader extends StatelessWidget {
  const SheetHeader({super.key, required this.title, this.subtitle, this.icon});

  final String title;
  final String? subtitle;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (icon != null) ...[
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: C.accent,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 22, color: C.white),
          ),
          const SizedBox(width: 12),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                child: Text(title, style: tx(20, w: w700, c: C.white)),
              ),
              if (subtitle != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(subtitle!, style: tx(13, c: C.muted)),
                ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        CvIconButton(
          icon: Icons.close,
          tooltip: tr('Закрыть'),
          framed: false,
          onTap: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}

/// Блок подтверждения опасного действия.
class DangerConfirm extends StatelessWidget {
  const DangerConfirm({
    super.key,
    required this.question,
    required this.note,
    required this.confirmLabel,
    required this.cancelLabel,
    required this.onConfirm,
    required this.onCancel,
  });

  final String question;
  final String note;
  final String confirmLabel;
  final String cancelLabel;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: C.dangerBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: C.dangerLine),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(question, style: tx(14, w: w600, c: C.white)),
          const SizedBox(height: 6),
          Text(note, style: tx(12, c: const Color(0xFFFFC4C8), h: 1.45)),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: CvButton(
                  label: cancelLabel,
                  onTap: onCancel,
                  height: 44,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: CvButton(
                  label: confirmLabel,
                  onTap: onConfirm,
                  kind: CvButtonKind.danger,
                  height: 44,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Строка-действие в списке: название, пояснение и стрелка.
class ActionLine extends StatelessWidget {
  const ActionLine({
    super.key,
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
                    if (note.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(note, style: tx(12, c: C.muted, h: 1.4)),
                    ],
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

/// Короткое сообщение внизу экрана.
void showNote(BuildContext context, String text) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(text, style: tx(14, c: C.white)),
        backgroundColor: C.menu,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
}

Future<void> copyText(BuildContext context, String text, String done) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (context.mounted) showNote(context, done);
}

/// Читает текст из буфера обмена; пустая строка, если там не текст.
Future<String> pasteText() async {
  final data = await Clipboard.getData(Clipboard.kTextPlain);
  return data?.text ?? '';
}
