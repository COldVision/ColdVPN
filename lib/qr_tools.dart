import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:zxing2/qrcode.dart';

/// Читает QR-код с картинки (PNG, JPEG и другие обычные форматы).
/// Возвращает текст кода или null, если код не найден.
///
/// Функция верхнего уровня: её можно выполнять в фоне через `compute`.
String? decodeQrImage(Uint8List bytes) {
  try {
    final image = img.decodeImage(bytes);
    if (image == null) return null;
    final longest = image.width > image.height ? image.width : image.height;
    final candidates = <img.Image>[
      image,
      // Очень крупные снимки распознаются хуже — пробуем уменьшенные копии.
      if (longest > 1600)
        img.copyResize(image, width: image.width * 1200 ~/ longest),
      if (longest > 900)
        img.copyResize(image, width: image.width * 700 ~/ longest),
    ];
    for (final candidate in candidates) {
      final text = _decode(candidate);
      if (text != null) return text;
    }
  } catch (_) {
    // Не картинка или повреждённый файл.
  }
  return null;
}

String? _decode(img.Image image) {
  try {
    final pixels = Uint8List.fromList(
      // Приводим к 8 битам на канал: у чёрно-белых PNG их бывает меньше.
      image
          .convert(format: img.Format.uint8, numChannels: 4)
          .getBytes(order: img.ChannelOrder.abgr),
    ).buffer.asInt32List();
    final LuminanceSource source =
        RGBLuminanceSource(image.width, image.height, pixels);
    final bitmap = BinaryBitmap(GlobalHistogramBinarizer(source));
    return QRCodeReader().decode(bitmap).text;
  } catch (_) {
    return null;
  }
}
