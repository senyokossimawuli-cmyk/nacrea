import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../theme/nacrea_theme.dart';

/// La caméra sert de scanner sur téléphone (Android, iPhone).
/// Sur PC, on utilise une douchette USB, qui tape le code comme un clavier.
bool get scanCameraDisponible => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

/// Ouvre la caméra et renvoie le code-barres lu (ou `null` si on annule).
Future<String?> scannerCodeBarres(BuildContext context) {
  return Navigator.of(context).push<String>(
    MaterialPageRoute(fullscreenDialog: true, builder: (_) => const _PageScanner()),
  );
}

class _PageScanner extends StatefulWidget {
  const _PageScanner();

  @override
  State<_PageScanner> createState() => _PageScannerState();
}

class _PageScannerState extends State<_PageScanner> {
  final _camera = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    formats: const [
      BarcodeFormat.ean13,
      BarcodeFormat.ean8,
      BarcodeFormat.upcA,
      BarcodeFormat.upcE,
      BarcodeFormat.code128,
      BarcodeFormat.code39,
      BarcodeFormat.itf14,
      BarcodeFormat.qrCode,
    ],
  );
  bool _fini = false;

  @override
  void dispose() {
    _camera.dispose();
    super.dispose();
  }

  void _lu(BarcodeCapture capture) {
    if (_fini) return;
    for (final b in capture.barcodes) {
      final code = b.rawValue?.trim();
      if (code != null && code.isNotEmpty) {
        _fini = true;
        Navigator.of(context).pop(code);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final largeur = MediaQuery.sizeOf(context).width * 0.8;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Scanner le code-barres'),
        actions: [
          IconButton(
            tooltip: 'Lampe',
            icon: const Icon(Icons.flashlight_on_outlined),
            onPressed: () => _camera.toggleTorch(),
          ),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: MobileScanner(controller: _camera, onDetect: _lu),
          ),
          Align(
            alignment: const Alignment(0, -0.2),
            child: IgnorePointer(
              child: Container(
                width: largeur,
                height: 170,
                decoration: BoxDecoration(
                  border: Border.all(color: NacreaColors.or, width: 3),
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),
          const Positioned(
            left: 24,
            right: 24,
            bottom: 48,
            child: Text(
              'Placez le code-barres dans le cadre doré.\nLa lecture est automatique.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white, fontSize: 16),
            ),
          ),
        ],
      ),
    );
  }
}
