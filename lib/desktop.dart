import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import 'app_state.dart';

/// Окно и значок в области уведомлений Windows: сворачивание в трей при
/// закрытии, меню значка и корректный выход.
class DesktopShell with TrayListener, WindowListener {
  DesktopShell(this.state);

  final AppState state;
  bool _tray = false;
  bool _quitting = false;
  VpnStatus? _menuStatus;

  static bool get supported => Platform.isWindows;

  /// [startHidden] — приложение запущено автозапуском и должно остаться
  /// в трее, не показывая окно.
  Future<void> init({required bool startHidden}) async {
    await windowManager.ensureInitialized();
    // Закрытие окна перехватываем сами: либо прячем в трей, либо сначала
    // снимаем туннель и только потом выходим.
    windowManager.addListener(this);
    await windowManager.setPreventClose(true);
    await windowManager.setMinimumSize(const Size(380, 600));

    try {
      await trayManager.setIcon('assets/tray_icon.ico');
      await trayManager.setToolTip('ColdVPN');
      trayManager.addListener(this);
      await _updateMenu();
      state.addListener(_onStateChanged);
      _tray = true;
    } catch (e) {
      state.addLog('Значок в трее недоступен: $e');
    }

    if (startHidden && _tray && state.settings.closeToTray) {
      // Окно показывает сама оболочка Windows после первого кадра, поэтому
      // прячем его сразу следом.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Timer(const Duration(milliseconds: 400), () => windowManager.hide());
      });
    }
  }

  void _onStateChanged() {
    if (state.status != _menuStatus) unawaited(_updateMenu());
  }

  Future<void> _updateMenu() async {
    _menuStatus = state.status;
    try {
      await trayManager.setContextMenu(
        Menu(
          items: [
            MenuItem(key: 'show', label: 'Открыть ColdVPN'),
            MenuItem(
              key: 'toggle',
              label: state.status == VpnStatus.off
                  ? 'Включить VPN'
                  : 'Выключить VPN',
            ),
            MenuItem.separator(),
            MenuItem(key: 'quit', label: 'Выход'),
          ],
        ),
      );
      await trayManager.setToolTip(
        state.status == VpnStatus.on ? 'ColdVPN — включён' : 'ColdVPN',
      );
    } catch (_) {}
  }

  Future<void> _showWindow() async {
    await windowManager.show();
    await windowManager.focus();
  }

  /// Снимает туннель и закрывает приложение. То, что VPN был включён,
  /// запоминается: при следующем запуске он включится сам.
  Future<void> quit() async {
    if (_quitting) return;
    _quitting = true;
    try {
      await state.disconnect(remember: false);
    } catch (_) {}
    try {
      if (_tray) await trayManager.destroy();
    } catch (_) {}
    await windowManager.destroy();
  }

  @override
  void onWindowClose() {
    if (_quitting) return;
    if (_tray && state.settings.closeToTray) {
      unawaited(windowManager.hide());
    } else {
      unawaited(quit());
    }
  }

  @override
  void onTrayIconMouseDown() => unawaited(_showWindow());

  @override
  void onTrayIconRightMouseDown() => unawaited(
        // Без вывода приложения вперёд меню не закрывается по щелчку мимо.
        // ignore: deprecated_member_use
        trayManager.popUpContextMenu(bringAppToFront: true),
      );

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'show':
        unawaited(_showWindow());
        break;
      case 'toggle':
        if (state.status == VpnStatus.off) {
          unawaited(state.connect());
        } else {
          unawaited(state.disconnect());
        }
        break;
      case 'quit':
        unawaited(quit());
        break;
    }
  }
}
