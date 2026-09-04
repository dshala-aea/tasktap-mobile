// dart format width=100
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../theme/app_colors.dart';

// ══════════════════════════════════════════════════════════════════════════════
// BarcodeScanSheet
//
// Full-screen camera capture for any barcode/QR lookup in the app — materiali is the first
// consumer, not the only intended one. Supports every symbology mobile_scanner's ML Kit backend
// recognizes (EAN-13, UPC, Code128, QR, ...) rather than pinning to one, since the backend's own
// MaterialeBarcode.BarcodeType is informational only and never gates a match.
//
// Returns the raw scanned string via Navigator.pop, or null if the technician backs out. Doesn't
// know what a barcode means — that's the caller's job (see materiale_barcode_lookup.dart for the
// materiali-specific resolution).
// ══════════════════════════════════════════════════════════════════════════════

Future<String?> openBarcodeScanSheet(BuildContext context, {String title = 'Scansiona'}) {
  return Navigator.of(context).push<String>(
    MaterialPageRoute(builder: (_) => BarcodeScanSheet(title: title), fullscreenDialog: true),
  );
}

class BarcodeScanSheet extends StatefulWidget {
  const BarcodeScanSheet({super.key, this.title = 'Scansiona'});

  final String title;

  @override
  State<BarcodeScanSheet> createState() => _BarcodeScanSheetState();
}

class _BarcodeScanSheetState extends State<BarcodeScanSheet> {
  late final MobileScannerController _controller = MobileScannerController(
    formats: BarcodeFormat.values,
  );

  // A camera stream fires onDetect many times a second while a code sits in frame — without this,
  // the same scan pops the route, then pops it again (or worse, pops whatever's now underneath)
  // on the next frame's detection before the route finishes closing.
  bool _handled = false;

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    if (capture.barcodes.isEmpty) return;
    final value = capture.barcodes.first.rawValue;
    if (value == null || value.isEmpty) return;
    _handled = true;
    Navigator.of(context).pop(value);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(controller: _controller, onDetect: _onDetect),
          _ScanOverlay(title: widget.title, onClose: () => Navigator.of(context).pop()),
        ],
      ),
    );
  }
}

class _ScanOverlay extends StatelessWidget {
  const _ScanOverlay({required this.title, required this.onClose});

  final String title;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(LucideIcons.x, color: Colors.white),
                  tooltip: 'Chiudi',
                  onPressed: onClose,
                ),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          // The frame is purely a visual guide — mobile_scanner reads the whole preview, not just
          // this rectangle. Narrowing detection to it would need cropRect math against the
          // preview's actual resolution for no real benefit here: a materiale's barcode is the
          // only thing likely to be in frame on a warehouse shelf or a rapportino photo.
          Container(
            width: 260,
            height: 180,
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.Y, width: 3),
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Inquadra il codice a barre o QR',
            style: TextStyle(fontFamily: 'Inter', color: Colors.white70, fontSize: 14),
          ),
          const Spacer(flex: 2),
        ],
      ),
    );
  }
}
