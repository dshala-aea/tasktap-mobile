import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

// ══════════════════════════════════════════════════════════════════════════════
// ContinuousScanView
//
// A QR camera view that STAYS OPEN: every detected code is reported through [onCode] and nothing
// is popped. Contrast with BarcodeScanSheet, which closes on the first detection. The camera
// stream fires onDetect many times a second while a code sits in frame, so de-duplication is the
// caller's job (see BadgeScanController). The raw value is handed over and never logged.
// ══════════════════════════════════════════════════════════════════════════════
class ContinuousScanView extends StatefulWidget {
  const ContinuousScanView({super.key, required this.onCode});

  final void Function(String code) onCode;

  @override
  State<ContinuousScanView> createState() => _ContinuousScanViewState();
}

class _ContinuousScanViewState extends State<ContinuousScanView> {
  late final MobileScannerController _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
  );

  void _onDetect(BarcodeCapture capture) {
    for (final b in capture.barcodes) {
      final v = b.rawValue;
      if (v != null && v.isNotEmpty) widget.onCode(v);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MobileScanner(
      controller: _controller,
      onDetect: _onDetect,
      errorBuilder: (context, error, child) => const ScanUnavailable(),
    );
  }
}

/// Shown instead of the preview when the camera cannot be used (permission denied, no camera).
class ScanUnavailable extends StatelessWidget {
  const ScanUnavailable({super.key});

  static const message = 'Impossibile usare la fotocamera — controlla i permessi dell\'app';

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(16),
      child: const Text(
        message,
        textAlign: TextAlign.center,
        style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
      ),
    );
  }
}
