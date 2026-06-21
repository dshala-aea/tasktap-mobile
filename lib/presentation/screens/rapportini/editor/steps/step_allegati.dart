// dart format width=100
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../../core/theme/app_colors.dart';
import '../../../../providers/report_editor_providers.dart';

// ══════════════════════════════════════════════════════════════════════════════
// Step 6 — Foto / Allegati
//
// Pick from gallery or camera via image_picker.
// Each file is stored locally (file path in report_allegati, isPendingUpload=true).
// ══════════════════════════════════════════════════════════════════════════════

class StepAllegati extends ConsumerWidget {
  const StepAllegati({super.key, required this.reportId});

  final String reportId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(reportEditorProvider(reportId));
    final notifier = ref.read(reportEditorProvider(reportId).notifier);

    final photos =
        state.allegatoRows.where((a) => !a.isSignature).toList();

    return Column(
      children: [
        if (photos.isEmpty)
          const Expanded(
            child: Center(
              child: Text(
                'Nessuna foto allegata.\nPremi il pulsante per aggiungere.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey, fontSize: 15),
              ),
            ),
          )
        else
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(16),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              itemCount: photos.length,
              itemBuilder: (ctx, i) => _PhotoTile(
                row: photos[i],
                onRemove: () => notifier.removeAllegato(photos[i].id),
              ),
            ),
          ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () =>
                        _pickImage(context, ref, ImageSource.gallery),
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text('Galleria'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 52),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () =>
                        _pickImage(context, ref, ImageSource.camera),
                    icon: const Icon(Icons.camera_alt_outlined),
                    label: const Text('Fotocamera'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.brand,
                      foregroundColor: AppColors.onBrand,
                      minimumSize: const Size(0, 52),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _pickImage(
    BuildContext context,
    WidgetRef ref,
    ImageSource source,
  ) async {
    final notifier = ref.read(reportEditorProvider(reportId).notifier);
    final picker = ImagePicker();

    try {
      final xfile = await picker.pickImage(source: source, imageQuality: 80);
      if (xfile == null) return;

      final file = File(xfile.path);
      final bytes = await file.readAsBytes();
      final id = 'photo-${DateTime.now().millisecondsSinceEpoch}';

      await notifier.addAllegato(
        AllegatoRow(
          id: id,
          localPath: xfile.path,
          fileName: xfile.name,
          contentType: 'image/jpeg',
          sizeBytes: bytes.length,
        ),
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Errore: ${e.toString()}')),
        );
      }
    }
  }
}

class _PhotoTile extends StatelessWidget {
  const _PhotoTile({required this.row, required this.onRemove});

  final AllegatoRow row;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.file(
            File(row.localPath),
            fit: BoxFit.cover,
            errorBuilder: (_, e, s) => Container(
              color: Colors.grey[200],
              child: const Icon(Icons.broken_image_outlined),
            ),
          ),
        ),
        Positioned(
          top: 4,
          right: 4,
          child: GestureDetector(
            onTap: onRemove,
            child: Container(
              decoration: const BoxDecoration(
                color: Colors.red,
                shape: BoxShape.circle,
              ),
              padding: const EdgeInsets.all(4),
              child: const Icon(
                Icons.close,
                color: Colors.white,
                size: 14,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
