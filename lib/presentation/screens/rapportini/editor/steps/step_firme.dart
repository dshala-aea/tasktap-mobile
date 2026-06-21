// dart format width=100
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:signature/signature.dart';

import '../../../../../core/theme/app_colors.dart';
import '../../../../providers/report_editor_providers.dart';

// ══════════════════════════════════════════════════════════════════════════════
// Step 5 — Firme
//
// Customer + technician signature capture via the `signature` package.
// Signatures are stored as PNG bytes to a local file path, then the allegato id
// is written to the draft header.
// ══════════════════════════════════════════════════════════════════════════════

class StepFirme extends ConsumerWidget {
  const StepFirme({super.key, required this.reportId});

  final String reportId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(reportEditorProvider(reportId));

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SignatureSection(
            title: 'Firma Cliente *',
            allegatoId: state.customerSignatureAllegatoId,
            localPath: state.customerSignatureLocalPath,
            isCustomer: true,
            reportId: reportId,
          ),
          const SizedBox(height: 32),
          _SignatureSection(
            title: 'Firma Tecnico *',
            allegatoId: state.technicianSignatureAllegatoId,
            localPath: state.technicianSignatureLocalPath,
            isCustomer: false,
            reportId: reportId,
          ),
        ],
      ),
    );
  }
}

class _SignatureSection extends ConsumerWidget {
  const _SignatureSection({
    required this.title,
    required this.allegatoId,
    required this.localPath,
    required this.isCustomer,
    required this.reportId,
  });

  final String title;
  final String? allegatoId;
  final String? localPath;
  final bool isCustomer;
  final String reportId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        const SizedBox(height: 8),
        if (localPath != null && allegatoId != null) ...[
          // Show captured signature
          Container(
            height: 120,
            width: double.infinity,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey[300]!),
              borderRadius: BorderRadius.circular(12),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.file(
                File(localPath!),
                fit: BoxFit.contain,
                errorBuilder: (ctx, err, st) => const Icon(
                  Icons.broken_image_outlined,
                  color: Colors.grey,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.green, size: 16),
              const SizedBox(width: 4),
              const Text('Firma acquisita', style: TextStyle(color: Colors.green)),
              const Spacer(),
              TextButton(
                onPressed: () => _clearSignature(ref),
                child: const Text(
                  'Cancella',
                  style: TextStyle(color: Colors.red),
                ),
              ),
            ],
          ),
        ] else ...[
          Container(
            height: 120,
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.grey[50],
              border: Border.all(color: Colors.grey[300]!),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Center(
              child: Text(
                'Firma non acquisita',
                style: TextStyle(color: Colors.grey),
              ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _captureSignature(context, ref),
              icon: const Icon(Icons.edit_outlined),
              label: Text(
                isCustomer ? 'Acquisisci firma cliente' : 'Acquisisci firma tecnico',
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.brand,
                foregroundColor: AppColors.onBrand,
                minimumSize: const Size(double.infinity, 52),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _captureSignature(BuildContext context, WidgetRef ref) async {
    final bytes = await showDialog<Uint8List?>(
      context: context,
      builder: (_) => const _SignatureCaptureDialog(),
    );
    if (bytes == null || bytes.isEmpty) return;

    // Save to local file
    final dir = await getApplicationDocumentsDirectory();
    final allegatoId =
        '${isCustomer ? 'sig-cliente' : 'sig-tecnico'}-${DateTime.now().millisecondsSinceEpoch}';
    final file = File('${dir.path}/$allegatoId.png');
    await file.writeAsBytes(bytes);

    final notifier = ref.read(reportEditorProvider(reportId).notifier);
    if (isCustomer) {
      await notifier.saveCustomerSignature(
        allegatoId: allegatoId,
        bytes: bytes,
        localPath: file.path,
      );
    } else {
      await notifier.saveTechnicianSignature(
        allegatoId: allegatoId,
        bytes: bytes,
        localPath: file.path,
      );
    }
  }

  Future<void> _clearSignature(WidgetRef ref) async {
    final notifier = ref.read(reportEditorProvider(reportId).notifier);
    if (isCustomer) {
      await notifier.clearCustomerSignature();
    } else {
      await notifier.clearTechnicianSignature();
    }
  }
}

/// Full-screen dialog for capturing a signature.
class _SignatureCaptureDialog extends StatefulWidget {
  const _SignatureCaptureDialog();

  @override
  State<_SignatureCaptureDialog> createState() =>
      _SignatureCaptureDialogState();
}

class _SignatureCaptureDialogState extends State<_SignatureCaptureDialog> {
  late final SignatureController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = SignatureController(
      penStrokeWidth: 3,
      penColor: Colors.black,
      exportBackgroundColor: Colors.white,
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog.fullscreen(
      child: Column(
        children: [
          AppBar(
            title: const Text('Acquisisci firma'),
            backgroundColor: AppColors.brand,
            foregroundColor: AppColors.onBrand,
            leading: IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.pop(context),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  _ctrl.clear();
                },
                child: const Text(
                  'Cancella',
                  style: TextStyle(color: Colors.black54),
                ),
              ),
              TextButton(
                onPressed: () async {
                  if (_ctrl.isEmpty) {
                    Navigator.pop(context);
                    return;
                  }
                  final bytes = await _ctrl.toPngBytes();
                  if (context.mounted) {
                    Navigator.pop(context, bytes);
                  }
                },
                child: const Text(
                  'Conferma',
                  style: TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text(
              'Firma nell\'area sottostante',
              style: TextStyle(color: Colors.grey),
            ),
          ),
          Expanded(
            child: Signature(
              controller: _ctrl,
              backgroundColor: Colors.grey[100]!,
            ),
          ),
        ],
      ),
    );
  }
}
