// dart format width=100
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_toggle.dart';
// section_title omitted — using inline _SL below
import '../../../presentation/providers/report_editor_providers.dart';
import '../../../presentation/providers/schedule_providers.dart';

// ══════════════════════════════════════════════════════════════════════════════
// Step 3 — Materiali  (folds Controlli + Foto/Allegati as sub-sections)
//
// - Qty steppers (− value +) per MaterialeRow
// - "Aggiungi materiale" opens picker dialog
// - "Nessun materiale" toggle (setMaterialiNotRequired)
// - Controlli sub-section (upsertControllo)
// - Foto/allegati sub-section (addAllegato/removeAllegato)
// ══════════════════════════════════════════════════════════════════════════════

class StepMaterialiFold extends ConsumerWidget {
  const StepMaterialiFold({super.key, required this.reportId});

  final String reportId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(reportEditorProvider(reportId));
    final notifier = ref.read(reportEditorProvider(reportId).notifier);
    final photos = state.allegatoRows.where((a) => !a.isSignature).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(19, 16, 19, 24),
      children: [
        // ── "Nessun materiale" toggle ──────────────────────────────────────
        AppCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            children: [
              Expanded(
                child: const Text(
                  'Nessun materiale utilizzato',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: AppColors.DARK,
                  ),
                ),
              ),
              AppToggle(
                value: state.materialiNotRequired,
                onChanged: (v) => notifier.setMaterialiNotRequired(v),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        if (!state.materialiNotRequired) ...[
          // ── Materiali list ──────────────────────────────────────────────
          _SL(title:'Materiali (${state.materialeRows.length})'),
          const SizedBox(height: 8),
          if (state.materialeRows.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'Nessun materiale aggiunto.',
                style: TextStyle(color: AppColors.MUTED),
              ),
            )
          else
            ...state.materialeRows.map(
              (row) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _MaterialeQtyStepper(
                  row: row,
                  onQtyChanged: (qty) =>
                      notifier.updateMateriale(row.copyWith(quantity: qty)),
                  onRemove: () => notifier.removeMateriale(row.id),
                ),
              ),
            ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => _showAddMaterialeDialog(context, ref),
            icon: const Icon(Icons.add_box_outlined),
            label: const Text('Aggiungi materiale'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, 52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],

        // ── Controlli sub-section ──────────────────────────────────────────
        _SL(title:'Controlli (${state.controlloRows.length})'),
        const SizedBox(height: 8),
        if (state.controlloRows.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'Nessun controllo aggiunto.',
              style: TextStyle(color: AppColors.MUTED, fontSize: 13),
            ),
          )
        else
          ...state.controlloRows.map(
            (c) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: AppCard(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle_outline,
                        size: 18, color: AppColors.GREEN),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            c.controlId,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                          if (c.stringValue != null)
                            Text(
                              c.stringValue!,
                              style: const TextStyle(
                                  color: AppColors.MUTED, fontSize: 12),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => _showAddControlloDialog(context, ref),
          icon: const Icon(Icons.add_task),
          label: const Text('Aggiungi controllo'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(double.infinity, 52),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        const SizedBox(height: 24),

        // ── Foto / Allegati sub-section ────────────────────────────────────
        _SL(title:'Foto / Allegati (${photos.length})'),
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
      ],
    );
  }

  void _showAddMaterialeDialog(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(reportEditorProvider(reportId).notifier);
    final materialiAsync = ref.read(allMaterialiProvider);

    final nameCtrl = TextEditingController();
    final qtyCtrl = TextEditingController(text: '1');
    final uomCtrl = TextEditingController();
    String? selectedMaterialeId;
    bool freeTextMode = true;

    materialiAsync.whenData((list) {
      if (list.isNotEmpty) freeTextMode = false;
    });

    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Aggiungi materiale'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                materialiAsync.when(
                  loading: () => const LinearProgressIndicator(),
                  error: (e, _) => TextField(
                    controller: nameCtrl,
                    decoration:
                        const InputDecoration(labelText: 'Nome materiale'),
                  ),
                  data: (list) {
                    if (list.isEmpty || freeTextMode) {
                      return Column(
                        children: [
                          TextField(
                            controller: nameCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Nome materiale (testo libero)',
                            ),
                          ),
                          if (list.isNotEmpty)
                            TextButton(
                              onPressed: () =>
                                  setDialogState(() => freeTextMode = false),
                              child: const Text('Seleziona da catalogo'),
                            ),
                        ],
                      );
                    }
                    return DropdownButtonFormField<String>(
                      initialValue: selectedMaterialeId,
                      decoration: const InputDecoration(
                          labelText: 'Materiale da catalogo'),
                      isExpanded: true,
                      items: list
                          .map(
                            (m) => DropdownMenuItem(
                              value: m.id,
                              child: Text(m.name),
                            ),
                          )
                          .toList(),
                      onChanged: (v) =>
                          setDialogState(() => selectedMaterialeId = v),
                    );
                  },
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: qtyCtrl,
                        decoration: const InputDecoration(labelText: 'Qtà'),
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                              RegExp(r'[0-9.]')),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: uomCtrl,
                        decoration: const InputDecoration(
                            labelText: 'Unità (es. pz)'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Annulla'),
            ),
            ElevatedButton(
              onPressed: () {
                final qty = double.tryParse(qtyCtrl.text) ?? 1.0;
                final id = 'mat-${DateTime.now().millisecondsSinceEpoch}';
                notifier.addMateriale(
                  MaterialeRow(
                    id: id,
                    reportId: reportId,
                    materialeId: freeTextMode ? null : selectedMaterialeId,
                    freeTextName: freeTextMode ? nameCtrl.text.trim() : null,
                    quantity: qty,
                    unitOfMeasure:
                        uomCtrl.text.trim().isEmpty ? null : uomCtrl.text.trim(),
                  ),
                );
                Navigator.pop(ctx);
              },
              child: const Text('Aggiungi'),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddControlloDialog(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(reportEditorProvider(reportId).notifier);
    final controlIdCtrl = TextEditingController();
    final valueCtrl = TextEditingController();

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Aggiungi controllo'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controlIdCtrl,
              decoration:
                  const InputDecoration(labelText: 'Nome controllo / ID'),
            ),
            TextField(
              controller: valueCtrl,
              decoration: const InputDecoration(labelText: 'Valore'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annulla'),
          ),
          ElevatedButton(
            onPressed: () {
              final id = 'ctrl-${DateTime.now().millisecondsSinceEpoch}';
              notifier.upsertControllo(
                ControlloRow(
                  id: id,
                  reportId: reportId,
                  controlId: controlIdCtrl.text.trim(),
                  stringValue: valueCtrl.text.trim().isEmpty
                      ? null
                      : valueCtrl.text.trim(),
                ),
              );
              Navigator.pop(ctx);
            },
            child: const Text('Aggiungi'),
          ),
        ],
      ),
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

// ── Qty stepper card ──────────────────────────────────────────────────────────

class _MaterialeQtyStepper extends StatelessWidget {
  const _MaterialeQtyStepper({
    required this.row,
    required this.onQtyChanged,
    required this.onRemove,
  });

  final MaterialeRow row;
  final ValueChanged<double> onQtyChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          const Icon(Icons.inventory_2_outlined,
              size: 18, color: AppColors.MUTED),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row.displayName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: AppColors.DARK,
                  ),
                ),
                if (row.unitOfMeasure != null)
                  Text(
                    row.unitOfMeasure!,
                    style: const TextStyle(
                        color: AppColors.MUTED, fontSize: 11),
                  ),
              ],
            ),
          ),
          // − qty + stepper
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _QtyBtn(
                icon: Icons.remove,
                onTap: row.quantity > 1
                    ? () => onQtyChanged(row.quantity - 1)
                    : null,
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  row.quantity.toStringAsFixed(
                      row.quantity == row.quantity.truncateToDouble() ? 0 : 1),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: AppColors.DARK,
                  ),
                ),
              ),
              _QtyBtn(
                icon: Icons.add,
                onTap: () => onQtyChanged(row.quantity + 1),
              ),
            ],
          ),
          const SizedBox(width: 4),
          IconButton(
            icon: const Icon(Icons.delete_outline,
                color: AppColors.RED, size: 18),
            constraints:
                const BoxConstraints(minWidth: 44, minHeight: 44),
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}

class _QtyBtn extends StatelessWidget {
  const _QtyBtn({required this.icon, this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: onTap != null ? AppColors.BG3 : AppColors.BG4,
          shape: BoxShape.circle,
        ),
        child: Icon(
          icon,
          size: 16,
          color: onTap != null ? AppColors.DARK : AppColors.DIS,
        ),
      ),
    );
  }
}

// ── Photo thumbnail ───────────────────────────────────────────────────────────

class _PhotoThumb extends StatelessWidget {
  const _PhotoThumb({required this.row, required this.onRemove});

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
            errorBuilder: (ctx, e, _) => Container(
              color: AppColors.BG3,
              child: const Icon(Icons.broken_image_outlined,
                  color: AppColors.MUTED),
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
                color: AppColors.RED,
                shape: BoxShape.circle,
              ),
              padding: const EdgeInsets.all(4),
              child: const Icon(Icons.close, color: Colors.white, size: 14),
            ),
          ),
        ),
      ],
    );
  }
}

class _SL extends StatelessWidget {
  const _SL({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(
        fontFamily: 'Sora',
        fontSize: 15,
        fontWeight: FontWeight.w700,
        color: Color(0xFF363636),
      ),
    );
  }
}
