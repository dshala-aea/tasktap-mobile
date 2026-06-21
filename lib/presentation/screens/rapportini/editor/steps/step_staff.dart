// dart format width=100
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/theme/app_colors.dart';
import '../../../../providers/report_editor_providers.dart';

// ══════════════════════════════════════════════════════════════════════════════
// Step 2 — Staff / Ore
//
// Add per-technician rows: hours + km/travel, with optional start/stop timer.
// ══════════════════════════════════════════════════════════════════════════════

class StepStaff extends ConsumerWidget {
  const StepStaff({super.key, required this.reportId});

  final String reportId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(reportEditorProvider(reportId));
    final notifier = ref.read(reportEditorProvider(reportId).notifier);

    return Column(
      children: [
        Expanded(
          child: state.staffRows.isEmpty
              ? const Center(
                  child: Text(
                    'Nessun tecnico aggiunto.\nPremi + per aggiungere.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey, fontSize: 16),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: state.staffRows.length,
                  separatorBuilder: (_, i) => const SizedBox(height: 12),
                  itemBuilder: (context, i) {
                    return _StaffRowCard(
                      row: state.staffRows[i],
                      reportId: reportId,
                      onUpdate: (updated) => notifier.updateStaff(updated),
                      onRemove: () =>
                          notifier.removeStaff(state.staffRows[i].id),
                      onStartTimer: () =>
                          notifier.startTimer(state.staffRows[i].id),
                      onStopTimer: () =>
                          notifier.stopTimer(state.staffRows[i].id),
                    );
                  },
                ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: OutlinedButton.icon(
              onPressed: () => _showAddStaffDialog(context, ref),
              icon: const Icon(Icons.person_add_outlined),
              label: const Text('Aggiungi tecnico'),
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

  void _showAddStaffDialog(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(reportEditorProvider(reportId).notifier);
    final userIdCtrl = TextEditingController();
    final nameCtrl = TextEditingController();

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Aggiungi tecnico'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: 'Nome tecnico'),
            ),
            TextField(
              controller: userIdCtrl,
              decoration: const InputDecoration(labelText: 'ID utente'),
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
              final id = DateTime.now().millisecondsSinceEpoch.toString();
              notifier.addStaff(
                StaffRow(
                  id: 'staff-$id',
                  userId: userIdCtrl.text.trim().isEmpty
                      ? 'user-$id'
                      : userIdCtrl.text.trim(),
                  displayName: nameCtrl.text.trim(),
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

class _StaffRowCard extends StatefulWidget {
  const _StaffRowCard({
    required this.row,
    required this.reportId,
    required this.onUpdate,
    required this.onRemove,
    required this.onStartTimer,
    required this.onStopTimer,
  });

  final StaffRow row;
  final String reportId;
  final ValueChanged<StaffRow> onUpdate;
  final VoidCallback onRemove;
  final VoidCallback onStartTimer;
  final VoidCallback onStopTimer;

  @override
  State<_StaffRowCard> createState() => _StaffRowCardState();
}

class _StaffRowCardState extends State<_StaffRowCard> {
  late final TextEditingController _hoursCtrl;
  late final TextEditingController _kmCtrl;
  late final TextEditingController _vehicleCtrl;
  late final TextEditingController _notesCtrl;

  @override
  void initState() {
    super.initState();
    _hoursCtrl = TextEditingController(
      text: widget.row.hoursWorked?.toStringAsFixed(1) ?? '',
    );
    _kmCtrl = TextEditingController(
      text: widget.row.kmTraveled > 0
          ? widget.row.kmTraveled.toStringAsFixed(1)
          : '',
    );
    _vehicleCtrl = TextEditingController(text: widget.row.vehicle ?? '');
    _notesCtrl = TextEditingController(text: widget.row.notes ?? '');
  }

  @override
  void dispose() {
    _hoursCtrl.dispose();
    _kmCtrl.dispose();
    _vehicleCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final row = widget.row;

    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row
            Row(
              children: [
                const Icon(Icons.person_outline, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    row.displayName.isNotEmpty ? row.displayName : row.userId,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  onPressed: widget.onRemove,
                  tooltip: 'Rimuovi',
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Timer
            if (row.timerRunning)
              _TimerBadge(
                startedAt: row.timerStartedAt,
                onStop: widget.onStopTimer,
              )
            else
              OutlinedButton.icon(
                onPressed: widget.onStartTimer,
                icon: const Icon(Icons.timer_outlined, size: 18),
                label: Text(
                  row.startTime != null
                      ? 'Timer (già avviato)'
                      : 'Avvia timer lavoro',
                  style: const TextStyle(fontSize: 13),
                ),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 44),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),

            const SizedBox(height: 12),

            // Hours + KM row
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _hoursCtrl,
                    decoration: InputDecoration(
                      labelText: 'Ore lavorate',
                      suffixText: 'h',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                    ],
                    onChanged: (v) {
                      final h = double.tryParse(v);
                      widget.onUpdate(row.copyWith(hoursWorked: h));
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _kmCtrl,
                    decoration: InputDecoration(
                      labelText: 'Km percorsi',
                      suffixText: 'km',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                    ],
                    onChanged: (v) {
                      final km = double.tryParse(v) ?? 0.0;
                      widget.onUpdate(row.copyWith(kmTraveled: km));
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Vehicle
            TextFormField(
              controller: _vehicleCtrl,
              decoration: InputDecoration(
                labelText: 'Veicolo (opzionale)',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
              ),
              onChanged: (v) => widget.onUpdate(row.copyWith(vehicle: v)),
            ),

            // Time display if timer ran
            if (row.startTime != null) ...[
              const SizedBox(height: 8),
              Text(
                'Inizio: ${_fmt(row.startTime!)}'
                '${row.endTime != null ? ' → Fine: ${_fmt(row.endTime!)}' : ' (in corso)'}',
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
              Text(
                'Ore effettive: ${row.effectiveHours.toStringAsFixed(2)}h',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  color: Colors.black87,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _fmt(DateTime dt) =>
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
}

class _TimerBadge extends StatefulWidget {
  const _TimerBadge({this.startedAt, required this.onStop});

  final DateTime? startedAt;
  final VoidCallback onStop;

  @override
  State<_TimerBadge> createState() => _TimerBadgeState();
}

class _TimerBadgeState extends State<_TimerBadge>
    with SingleTickerProviderStateMixin {
  late final _ticker = createTicker((_) => setState(() {}));

  @override
  void initState() {
    super.initState();
    _ticker.start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final elapsed = widget.startedAt != null
        ? DateTime.now().toUtc().difference(widget.startedAt!)
        : Duration.zero;
    final hh = elapsed.inHours.toString().padLeft(2, '0');
    final mm = (elapsed.inMinutes % 60).toString().padLeft(2, '0');
    final ss = (elapsed.inSeconds % 60).toString().padLeft(2, '0');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.brand.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.brand),
      ),
      child: Row(
        children: [
          const Icon(Icons.timer, color: Colors.orange, size: 20),
          const SizedBox(width: 8),
          Text(
            '$hh:$mm:$ss',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 20,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          const Spacer(),
          ElevatedButton(
            onPressed: widget.onStop,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              minimumSize: const Size(80, 36),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text('Stop'),
          ),
        ],
      ),
    );
  }
}
