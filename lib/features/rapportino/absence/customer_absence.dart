// dart format width=100
import 'package:flutter/material.dart';

import '../../../core/icons/app_lucide_icons.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/widgets.dart';
import '../../../domain/reports/customer_signature_absence_reason.dart';

// ══════════════════════════════════════════════════════════════════════════════
// "Il cliente non può firmare" — the reason a rapportino carries no customer signature.
//
// Two screens ask this question: the editor's Riepilogo step, and the AI flow's Firma step. Both
// write the same two fields through `ReportEditorNotifier.setCustomerSignatureAbsence`, so both
// must ask it the same way — hence one dialog and one summary card here rather than a copy in each.
//
// The reason is what the office reads as "Senza firma cliente" in its control room: an unsigned
// report with no reason is indistinguishable from one the technician simply forgot to have signed,
// which is why the submit gate refuses it.
// ══════════════════════════════════════════════════════════════════════════════

/// What the absence dialog hands back: the chosen reason plus its (nullable) note.
class CustomerAbsenceChoice {
  const CustomerAbsenceChoice({required this.reason, this.note});

  final CustomerSignatureAbsenceReason reason;
  final String? note;
}

/// Stands in for the empty customer signature pad once a reason is recorded: what was chosen,
/// the note if any, and a way back into the dialog.
class CustomerAbsenceCard extends StatelessWidget {
  const CustomerAbsenceCard({
    super.key,
    required this.reason,
    required this.note,
    required this.onEdit,
  });

  final CustomerSignatureAbsenceReason reason;
  final String? note;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final hasNote = note?.isNotEmpty ?? false;
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.base),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(LucideIcons.fileX, color: context.colors.inkMuted, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Senza firma cliente — ${reason.summaryLabel}',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: context.colors.ink,
                  ),
                ),
              ),
            ],
          ),
          if (hasNote) ...[
            const SizedBox(height: 6),
            Text(
              note!,
              style: TextStyle(
                fontFamily: 'Archivo',
                fontSize: 13,
                color: context.colors.inkMuted,
                height: 1.4,
              ),
            ),
          ],
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: onEdit,
              style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
              child: Text(
                'Modifica motivo',
                style: TextStyle(color: context.colors.inkMuted, fontSize: 13),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Asks why the customer could not sign. The reason is required, the note is required only for
/// "Altro motivo" (and capped at 500 characters, with the field's own counter).
class CustomerAbsenceDialog extends StatefulWidget {
  const CustomerAbsenceDialog({super.key, this.initialReason, this.initialNote});

  final CustomerSignatureAbsenceReason? initialReason;
  final String? initialNote;

  @override
  State<CustomerAbsenceDialog> createState() => _CustomerAbsenceDialogState();
}

class _CustomerAbsenceDialogState extends State<CustomerAbsenceDialog> {
  static const _maxNoteLength = 500;

  late CustomerSignatureAbsenceReason? _reason = widget.initialReason;
  late final TextEditingController _noteCtrl = TextEditingController(
    text: widget.initialNote ?? '',
  );

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  bool get _canSave {
    if (_reason == null) return false;
    if (_reason == CustomerSignatureAbsenceReason.altro) {
      return _noteCtrl.text.trim().isNotEmpty;
    }
    return true;
  }

  void _save() {
    final trimmed = _noteCtrl.text.trim();
    Navigator.pop(
      context,
      CustomerAbsenceChoice(reason: _reason!, note: trimmed.isEmpty ? null : trimmed),
    );
  }

  @override
  Widget build(BuildContext context) {
    final reason = _reason;
    final noteRequired = reason == CustomerSignatureAbsenceReason.altro;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
      child: AppCard(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Il cliente non può firmare',
                style: TextStyle(
                  fontFamily: 'Archivo Narrow',
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: context.colors.ink,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Indica perché il rapporto di intervento non è firmato dal cliente.',
                style: TextStyle(
                  fontFamily: 'Archivo',
                  fontSize: 14,
                  color: context.colors.inkMuted,
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  for (final option in CustomerSignatureAbsenceReason.values)
                    ChoiceChip(
                      label: Text(option.chipLabel),
                      selected: reason == option,
                      onSelected: (_) => setState(() => _reason = option),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              AppTextField.multiline(
                label: noteRequired ? 'Motivo (obbligatorio)' : 'Nota (facoltativa)',
                controller: _noteCtrl,
                maxLines: 3,
                maxLength: _maxNoteLength,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: AppButton.ghost(
                      label: 'Annulla',
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: AppButton(label: 'Salva', onPressed: _canSave ? _save : null),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
