// dart format width=100
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../providers/report_editor_providers.dart';

// ══════════════════════════════════════════════════════════════════════════════
// Step 4 — Controlli
//
// Free-form control values. Since the backend B13 control definitions are not
// yet synced, we show a simple "add control" UI that lets technicians enter
// any string/bool/date value keyed by control name.
// ══════════════════════════════════════════════════════════════════════════════

class StepControlli extends ConsumerWidget {
  const StepControlli({super.key, required this.reportId});

  final String reportId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(reportEditorProvider(reportId));
    final notifier = ref.read(reportEditorProvider(reportId).notifier);

    return Column(
      children: [
        Expanded(
          child: state.controlloRows.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Nessun controllo.\nPremi + per aggiungere un valore di controllo.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey, fontSize: 15),
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: state.controlloRows.length,
                  separatorBuilder: (_, __x) => const SizedBox(height: 8),
                  itemBuilder: (ctx, i) {
                    final c = state.controlloRows[i];
                    return ListTile(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                        side: BorderSide(color: Colors.grey[200]!),
                      ),
                      tileColor: Colors.white,
                      leading: const Icon(Icons.check_circle_outline),
                      title: Text(c.controlId),
                      subtitle: Text(
                        c.stringValue ??
                            (c.boolValue != null
                                ? (c.boolValue! ? 'Sì' : 'No')
                                : c.dateValue?.toIso8601String() ?? ''),
                      ),
                    );
                  },
                ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: OutlinedButton.icon(
              onPressed: () => _showAddControlloDialog(context, ref, notifier),
              icon: const Icon(Icons.add_task),
              label: const Text('Aggiungi controllo'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 52),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _showAddControlloDialog(
    BuildContext context,
    WidgetRef ref,
    ReportEditorNotifier notifier,
  ) {
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
}
