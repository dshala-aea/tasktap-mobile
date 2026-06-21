// dart format width=100
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../providers/report_editor_providers.dart';
import '../../../../providers/schedule_providers.dart';

// ══════════════════════════════════════════════════════════════════════════════
// Step 3 — Materiali
//
// Add materials from cached picker OR free-text (B13 cache may be empty).
// "Nessun materiale utilizzato" toggle sets materialiNotRequired.
// ══════════════════════════════════════════════════════════════════════════════

class StepMateriali extends ConsumerWidget {
  const StepMateriali({super.key, required this.reportId});

  final String reportId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(reportEditorProvider(reportId));
    final notifier = ref.read(reportEditorProvider(reportId).notifier);

    return Column(
      children: [
        // "Nessun materiale" toggle
        SwitchListTile(
          title: const Text(
            'Nessun materiale utilizzato',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          subtitle: const Text(
            'Attiva se non sono stati usati materiali',
          ),
          value: state.materialiNotRequired,
          onChanged: (v) => notifier.setMaterialiNotRequired(v),
        ),

        if (!state.materialiNotRequired) ...[
          Expanded(
            child: state.materialeRows.isEmpty
                ? const Center(
                    child: Text(
                      'Nessun materiale aggiunto.\nPremi + per aggiungere.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey, fontSize: 16),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: state.materialeRows.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (ctx, i) => _MaterialeCard(
                      row: state.materialeRows[i],
                      onRemove: () =>
                          notifier.removeMateriale(state.materialeRows[i].id),
                      onUpdate: (updated) => notifier.updateMateriale(updated),
                    ),
                  ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: OutlinedButton.icon(
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
            ),
          ),
        ] else
          const Expanded(
            child: Center(
              child: Text(
                'Flag "nessun materiale" attivo.',
                style: TextStyle(color: Colors.grey),
              ),
            ),
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
                // Picker or free-text
                materialiAsync.when(
                  loading: () => const LinearProgressIndicator(),
                  error: (_, __) => TextField(
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
                        labelText: 'Materiale da catalogo',
                      ),
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
                          decimal: true,
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: uomCtrl,
                        decoration:
                            const InputDecoration(labelText: 'Unità (es. pz)'),
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
                    materialeId: selectedMaterialeId,
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
}

class _MaterialeCard extends StatelessWidget {
  const _MaterialeCard({
    required this.row,
    required this.onRemove,
    required this.onUpdate,
  });

  final MaterialeRow row;
  final VoidCallback onRemove;
  final ValueChanged<MaterialeRow> onUpdate;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: Colors.grey[200]!),
      ),
      tileColor: Colors.white,
      leading: const Icon(Icons.inventory_2_outlined),
      title: Text(row.displayName),
      subtitle: Text(
        'Qtà: ${row.quantity}${row.unitOfMeasure != null ? ' ${row.unitOfMeasure}' : ''}',
      ),
      trailing: IconButton(
        icon: const Icon(Icons.delete_outline, color: Colors.red),
        onPressed: onRemove,
      ),
    );
  }
}
