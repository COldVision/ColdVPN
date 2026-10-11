import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'theme.dart';
import '../l10n.dart';

/// Сканирование QR-кода камерой телефона. Экран закрывается сам, как только
/// код прочитан, и возвращает его текст.
class QrScanPage extends StatefulWidget {
  const QrScanPage({super.key});

  @override
  State<QrScanPage> createState() => _QrScanPageState();
}

class _QrScanPageState extends State<QrScanPage> {
  bool _done = false;

  void _onDetect(BarcodeCapture capture) {
    if (_done) return;
    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue;
      if (value != null && value.isNotEmpty) {
        _done = true;
        Navigator.of(context).pop(value);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF000000),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(onDetect: _onDetect),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          tr('Наведите камеру на QR-код'),
                          style: tx(17, w: w700, c: C.white),
                        ),
                      ),
                      Material(
                        color: const Color.fromRGBO(0, 0, 0, 0.45),
                        shape: const CircleBorder(),
                        child: CvIconButton(
                          icon: Icons.close,
                          tooltip: tr('Закрыть'),
                          framed: false,
                          color: C.white,
                          onTap: () => Navigator.of(context).pop(),
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.all(18),
                  child: Text(
                    tr('Код можно показать на экране компьютера: «Сервер» → три '
                    'точки → «Поделиться».'),
                    textAlign: TextAlign.center,
                    style: tx(13, c: C.white, h: 1.45),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
