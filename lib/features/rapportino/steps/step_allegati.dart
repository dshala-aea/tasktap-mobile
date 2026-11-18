// dart format width=100
import 'dart:io';

import 'package:flutter/material.dart';
import '../../../core/widgets/widgets.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/catalog_constants.dart';
import '../../../core/utils/error_message.dart';
import '../../admin/admin_widgets.dart';
// Uses StepLabel — the padding-free sibling of SectionTitle, for headings inside a padded card.
import '../../../core/scanner/barcode_scan_sheet.dart';
import '../../../data/local/app_database.dart';
import '../../../data/magazzino/magazzino_api_client.dart';
import '../../../data/materiali/materiale_barcode_lookup.dart';
import '../../../data/reports/ticket_controls_cache_repository.dart';
import '../../../presentation/providers/auth_providers.dart';
import '../../../presentation/providers/report_editor_providers.dart';
import '../../../presentation/providers/schedule_providers.dart';
import '../../checklist/asset_checklist_entry_card.dart';
import '../../checklist/checklist_providers.dart';
import '../../magazzino/magazzino_providers.dart';
import '../../ticket/ticket_detail_api_client.dart';
import '../../ticket/ticket_providers.dart' show ticketMaterialiProvider;
import 'package:tasktap_mobile/core/theme/app_palette.dart';
import 'package:tasktap_mobile/core/theme/app_rack.dart';
import 'package:tasktap_mobile/core/theme/app_spacing.dart';

// ══════════════════════════════════════════════════════════════════════════════
// Step Allegati
//
// - Foto/allegati sub-section (addAllegato/removeAllegato)
//
// ══════════════════════════════════════════════════════════════════════════════

class StepAllegati extends ConsumerWidget {
  const StepAllegati({super.key, required this.reportId});

  final String reportId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(reportEditorProvider(reportId));
    final notifier = ref.read(reportEditorProvider(reportId).notifier);
    final photos = state.allegatoRows.where((a) => !a.isSignature).toList();

    // The technician's assigned van warehouse — watched here (not inside the dialog) so it is
    // fetched once per visit to this step and every "Aggiungi materiale" tap reuses it, rather
    // than re-fetching over the network on a dialog a technician can open a dozen times on one job.
    // The internal database Guid, not currentUserProvider.id (the Zitadel OIDC sub) — the
    // furgone-lookup endpoint is keyed by the internal Guid, so the sub never matched anyone.
    final internalUserId = ref.watch(internalUserIdProvider).valueOrNull;

    // A Column, not a ListView: this sits inside the compartment sheet's own ambient
    // SingleChildScrollView now, not a screen-height-bounded Expanded body — an inner scrollable
    // here would fight the outer one for an unbounded height and crash on layout.
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.pagePadding,
        AppSpacing.base,
        AppSpacing.pagePadding,
        AppSpacing.xl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Foto / Allegati sub-section ────────────────────────────────────
          StepLabel(title: 'Foto / Allegati (${photos.length})'),
          const SizedBox(height: 8),
          if (photos.isNotEmpty) ...[
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              itemCount: photos.length,
              itemBuilder: (ctx, i) => _PhotoThumb(
                row: photos[i],
                onRemove: () => notifier.removeAllegato(photos[i].id),
              ),
            ),
            const SizedBox(height: 12),
          ],
          Row(
            children: [
              Expanded(
                child: AppButton.secondary(
                  label: 'Galleria',
                  icon: const Icon(LucideIcons.image),
                  onPressed: () => _pickImage(context, ref, ImageSource.gallery),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: AppButton(
                  label: 'Fotocamera',
                  icon: const Icon(LucideIcons.camera),
                  onPressed: () => _pickImage(context, ref, ImageSource.camera),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Item 7: image_picker only ever offers camera/gallery, so a PDF (a datasheet, a signed
          // delivery note, a manufacturer certificate) could never be attached from here at all —
          // separate from any backend-side content-type restriction, which a backend agent is
          // relaxing concurrently. Goes through the same addAllegato path images already use.
          AppButton.secondary(
            label: 'Documento (PDF)',
            icon: const Icon(LucideIcons.fileText),
            onPressed: () => _pickDocument(context, ref),
          ),
        ],
      ),
    );
  }

  Future<void> _pickImage(BuildContext context, WidgetRef ref, ImageSource source) async {
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
      // Local capture and file write — never a server call, so there is no status to interpret and
      // one honest sentence covers every way it fails. It used to print the exception, which on a
      // full phone read as the app crashing rather than the storage being full.
      if (context.mounted) {
        showAppToast(
          context,
          message: 'Foto non salvata. Riprova, e controlla lo spazio libero sul telefono.',
          tone: ToastTone.error,
        );
      }
    }
  }

  /// Item 7: a document (PDF) alongside the camera/gallery photo pickers above. Goes through the
  /// same `addAllegato` path — same local row shape, same pending-upload flag, same eventual
  /// upload — images already use; only the source and the resulting `contentType` differ.
  Future<void> _pickDocument(BuildContext context, WidgetRef ref) async {
    final notifier = ref.read(reportEditorProvider(reportId).notifier);
    try {
      final result = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['pdf']);
      final files = result?.files ?? const <PlatformFile>[];
      if (files.isEmpty) return;
      final picked = files.first;
      // Path-based, like image_picker's XFile above — this app ships mobile-only (no web/
      // target), where FilePicker always returns a real file path.
      if (picked.path == null) return;
      final file = File(picked.path!);
      final bytes = await file.readAsBytes();
      final id = 'doc-${DateTime.now().millisecondsSinceEpoch}';
      await notifier.addAllegato(
        AllegatoRow(
          id: id,
          localPath: picked.path!,
          fileName: picked.name,
          contentType: 'application/pdf',
          sizeBytes: bytes.length,
        ),
      );
    } catch (e) {
      // Same reasoning as _pickImage's own catch above — local pick + file read, no server call.
      if (context.mounted) {
        showAppToast(
          context,
          message: 'Documento non salvato. Riprova, e controlla lo spazio libero sul telefono.',
          tone: ToastTone.error,
        );
      }
    }
  }
}


// ── Photo thumbnail ───────────────────────────────────────────────────────────

class _PhotoThumb extends StatelessWidget {
  const _PhotoThumb({required this.row, required this.onRemove});

  final AllegatoRow row;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    // The grid renders these three-up (see the `SliverGridDelegateWithFixedCrossAxisCount`
    // above) at a small square tile, but a camera photo decodes at full sensor resolution —
    // easily 3000+ px on a side. Without cacheWidth/cacheHeight, Flutter decodes and holds every
    // thumbnail at that full size, which is a lot of memory for a grid of tiles this small.
    final tileWidth = (MediaQuery.sizeOf(context).width - AppSpacing.pagePadding * 2 - 8 * 2) / 3;
    final cachePx = (tileWidth * MediaQuery.devicePixelRatioOf(context)).round();
    // Item 7: a PDF attachment lands in this same grid (addAllegato doesn't distinguish photos
    // from documents) but isn't decodable as an image — Image.file's errorBuilder would already
    // catch that, just as a generic "broken image" rather than naming what the tile actually is.
    final isImage = row.contentType.startsWith('image/');
    return Stack(
      fit: StackFit.expand,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: isImage
              ? Image.file(
                  File(row.localPath),
                  fit: BoxFit.cover,
                  cacheWidth: cachePx,
                  cacheHeight: cachePx,
                  errorBuilder: (ctx, e, _) => Container(
                    color: context.colors.bg3,
                    child: Icon(LucideIcons.imageOff, color: context.colors.inkMuted),
                  ),
                )
              : Container(
                  color: context.colors.bg3,
                  padding: const EdgeInsets.all(AppSpacing.xs),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(LucideIcons.fileText, color: context.colors.inkMuted),
                      const SizedBox(height: 2),
                      Text(
                        row.fileName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 9, color: context.colors.inkMuted),
                      ),
                    ],
                  ),
                ),
        ),
        Positioned(
          top: 4,
          right: 4,
          // Destructive, and it used to be a ~22dp circle sitting between other photo
          // thumbnails — the easiest mis-tap in the app, and the one that costs a photo the
          // technician cannot retake once they have left the site.
          child: Semantics(
            button: true,
            label: 'Rimuovi foto',
            child: AppTappable(
              onTap: onRemove,
              borderRadius: BorderRadius.circular(22),
              child: SizedBox(
                width: 44,
                height: 44,
                child: Center(
                  child: Container(
                    decoration: BoxDecoration(color: context.colors.red, shape: BoxShape.circle),
                    padding: const EdgeInsets.all(AppSpacing.xs),
                    child: const Icon(LucideIcons.x, color: Colors.white, size: 14),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

