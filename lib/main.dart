import 'dart:io';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';

import 'app_state.dart';
import 'browser_api.dart';
import 'desktop.dart';
import 'ui/shell.dart';
import 'ui/theme.dart';
import 'l10n.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  final state = await AppState.load();

  // На Windows закрытием окна, треем и выходом управляет DesktopShell.
  var desktop = false;
  if (DesktopShell.supported) {
    try {
      // «Запускать в свёрнутом режиме»: и при автозапуске, и при обычном
      // запуске окно не показывается, приложение сразу в трее.
      await DesktopShell(state).init(startHidden: state.settings.startInTray);
      desktop = true;
    } catch (e) {
      state.addLog(tr('Не удалось настроить окно и трей: {0}', [e]));
    }
  }

  // На Android туннель живёт дольше окна, поэтому при закрытии окна его
  // снимать не нужно.
  runApp(ColdVpnApp(
    state: state,
    handleExit: !desktop && !state.isAndroid,
  ));
  // Расширение для браузера управляет приложением через 127.0.0.1.
  if (Platform.isWindows) await BrowserApi(state).start();
  state.autoConnect();
  state.autoUpdateLists();
}

class ColdVpnApp extends StatefulWidget {
  const ColdVpnApp({super.key, required this.state, required this.handleExit});

  final AppState state;

  /// Снимать туннель при закрытии окна самому приложению (там, где этим не
  /// занимается DesktopShell).
  final bool handleExit;

  @override
  State<ColdVpnApp> createState() => _ColdVpnAppState();
}

class _ColdVpnAppState extends State<ColdVpnApp> {
  AppLifecycleListener? _lifecycle;

  @override
  void initState() {
    super.initState();
    if (widget.handleExit) {
      // При закрытии окна снимаем туннель, чтобы он не остался в фоне. То,
      // что VPN был включён, запоминается: при следующем запуске он
      // включится сам.
      _lifecycle = AppLifecycleListener(
        onExitRequested: () async {
          await widget.state.shutdown();
          return AppExitResponse.exit;
        },
      );
    }
  }

  @override
  void dispose() {
    _lifecycle?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ColdVPN',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: Shell(state: widget.state),
    );
  }
}
