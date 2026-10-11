import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/widgets.dart';
import 'package:share_plus/share_plus.dart';

import '../android_tunnel.dart';
import '../l10n.dart';
import 'theme.dart';

/// Открывает ссылку в браузере. Если открыть не удалось, копирует её в
/// буфер обмена и сообщает об этом.
Future<void> openLink(BuildContext context, String url) async {
  var opened = false;
  try {
    if (Platform.isWindows) {
      await Process.run('explorer', [url]);
      opened = true;
    } else if (Platform.isAndroid) {
      opened = await AndroidTunnel.openUrl(url);
    }
  } catch (_) {}
  if (!opened && context.mounted) {
    await copyText(context, url, tr('Ссылка скопирована'));
  }
}

/// Сохраняет файл так, как принято на платформе.
///
/// На компьютере открывает окно «Сохранить как» и возвращает путь к файлу
/// (null — пользователь отменил). На телефоне открывает системное окно
/// «Поделиться», откуда файл можно сохранить или отправить, и возвращает
/// пустую строку.
Future<String?> saveFile({
  required String name,
  required List<int> bytes,
  required XTypeGroup type,
  String? mimeType,
}) async {
  if (Platform.isAndroid || Platform.isIOS) {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$name');
    await file.writeAsBytes(bytes, flush: true);
    await Share.shareXFiles([XFile(file.path, mimeType: mimeType)]);
    return '';
  }
  final location = await getSaveLocation(
    suggestedName: name,
    acceptedTypeGroups: [type],
  );
  if (location == null) return null;
  var path = location.path;
  final dot = name.lastIndexOf('.');
  final extension = dot < 0 ? '' : name.substring(dot);
  if (!path.toLowerCase().endsWith(extension.toLowerCase())) path += extension;
  await File(path).writeAsBytes(bytes, flush: true);
  return path;
}

Future<String?> saveTextFile({
  required String name,
  required String text,
  required XTypeGroup type,
  String mimeType = 'text/plain',
}) =>
    saveFile(
      name: name,
      bytes: utf8.encode(text),
      type: type,
      mimeType: mimeType,
    );

/// Открывает окно выбора файла. На телефоне расширения вроде `.conf`
/// системе неизвестны, поэтому там выбор не ограничивается (или
/// ограничивается типом [mobileMime], например `image/*`).
Future<XFile?> pickFile(XTypeGroup type, {String? mobileMime}) {
  if (Platform.isAndroid || Platform.isIOS) {
    return openFile(
      acceptedTypeGroups: mobileMime == null
          ? const []
          : [
              XTypeGroup(mimeTypes: [mobileMime]),
            ],
    );
  }
  return openFile(acceptedTypeGroups: [type]);
}

/// Сообщение об итоге сохранения для показа пользователю; null — нечего
/// показывать (пользователь отменил или открылось окно «Поделиться»).
String? savedNote(String what, String? path) =>
    (path == null || path.isEmpty) ? null : '$what: $path';
