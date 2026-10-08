// dart format width=100
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';
import 'package:tasktap_mobile/core/theme/app_palette.dart';
import 'package:tasktap_mobile/core/theme/app_spacing.dart';

import '../../core/widgets/widgets.dart';
import '../../data/reports/import_server_report.dart' show controlRowId;
import '../../domain/checklist/checklist_models.dart';
import '../../domain/checklist/control_type.dart';
import '../../presentation/providers/report_editor_providers.dart';
import '../admin/admin_widgets.dart';
import 'checklist_providers.dart';

/// The input for one checklist row, driven by its [ControlType], writing into the rapportino
/// editor under the TicketControl id (`ctrl-<report>-<control>`).
///
/// Rules it enforces (hand-off 2.2): only the column matching the type is ever written; a blank
/// answer removes the row instead of sending a blank (a blank never wipes server-side anyway); a
/// note never makes a row "answered"; a previous visit's answer is shown and pre-filled but creates
/// no row until the technician touches the field; touch targets are at least 48 dp (gloves).
class ControlAnswerField extends ConsumerStatefulWidget {
  const ControlAnswerField({super.key, required this.reportId, required this.control});

  final String reportId;
  final ChecklistControl control;

  @override
  ConsumerState<ControlAnswerField> createState() => _ControlAnswerFieldState();
}

class _ControlAnswerFieldState extends ConsumerState<ControlAnswerField> {
  late final TextEditingController _text;
  late final TextEditingController _number;
  late final TextEditingController _note;
  late bool _noteOpen;

  ChecklistControl get _c => widget.control;

  ChecklistAnswer get _base =>
      ref.read(controlAnswersProvider(widget.reportId))[_c.id] ?? _c.stored;

  @override
  void initState() {
    super.initState();
    final a = _base;
    _text = TextEditingController(text: a.stringValue ?? '');
    _number = TextEditingController(text: a.numberValue == null ? '' : _numText(a.numberValue!));
    _note = TextEditingController(text: a.note ?? '');
    _noteOpen = a.hasNote;
  }

  @override
  void dispose() {
    _text.dispose();
    _number.dispose();
    _note.dispose();
    super.dispose();
  }

  static String _numText(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : '$v';

  static bool _usesString(ControlType t) =>
      t == ControlType.text || t == ControlType.options || t == ControlType.unknown;

  /// Writes [next] (only the column matching the type) or removes the row when nothing is left.
  void _commit(ChecklistAnswer next) {
    final notifier = ref.read(reportEditorProvider(widget.reportId).notifier);
    final id = controlRowId(widget.reportId, _c.id);
    final note = next.hasNote ? next.note!.trim() : null;
    final string = _usesString(_c.type) && (next.stringValue ?? '').trim().isNotEmpty
        ? next.stringValue!.trim()
        : null;
    final flag = isBooleanControl(_c.type) ? next.boolValue : null;
    final date = _c.type == ControlType.dateTime ? next.dateValue : null;
    final number = _c.type == ControlType.number ? next.numberValue : null;
    if (string == null && flag == null && date == null && number == null && note == null) {
      notifier.removeControllo(id);
      return;
    }
    notifier.upsertControllo(
      ControlloRow(
        id: id,
        reportId: widget.reportId,
        controlId: _c.id,
        stringValue: string,
        boolValue: flag,
        dateValue: date,
        numberValue: number,
        note: note,
      ),
    );
  }

  ChecklistAnswer _answer({
    String? stringValue,
    bool? boolValue,
    DateTime? dateValue,
    double? numberValue,
  }) => ChecklistAnswer(
    stringValue: stringValue,
    boolValue: boolValue,
    dateValue: dateValue,
    numberValue: numberValue,
    note: _base.note,
  );

  void _setNote(String text) {
    final b = _base;
    _commit(
      ChecklistAnswer(
        stringValue: b.stringValue,
        boolValue: b.boolValue,
        dateValue: b.dateValue,
        numberValue: b.numberValue,
        note: text,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final existing = ref.watch(
      controlAnswersProvider(widget.reportId).select((m) => m[_c.id]),
    );
    final shown = existing ?? _c.stored;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _input(shown)),
            IconButton(
              tooltip: 'Nota',
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              icon: Icon(
                LucideIcons.pencil,
                size: 18,
                color: shown.hasNote ? context.colors.blue : context.colors.inkMuted,
              ),
              onPressed: () => setState(() => _noteOpen = !_noteOpen),
            ),
          ],
        ),
        if (_noteOpen)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: AppTextField.multiline(
              label: 'Nota',
              controller: _note,
              maxLines: 3,
              maxLength: 2000,
              onChanged: _setNote,
            ),
          ),
      ],
    );
  }

  Widget _input(ChecklistAnswer shown) {
    switch (_c.type) {
      case ControlType.checkbox:
      case ControlType.trueFalse:
        return Row(
          children: [
            Expanded(
              child: _ChoiceButton(
                label: 'Sì',
                selected: shown.boolValue == true,
                onTap: () => _commit(_answer(boolValue: shown.boolValue == true ? null : true)),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: _ChoiceButton(
                label: 'No',
                selected: shown.boolValue == false,
                onTap: () => _commit(_answer(boolValue: shown.boolValue == false ? null : false)),
              ),
            ),
          ],
        );
      case ControlType.number:
        return AppTextField(
          label: 'Valore',
          controller: _number,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (v) {
            final t = v.trim().replaceAll(',', '.');
            _commit(_answer(numberValue: t.isEmpty ? null : double.tryParse(t)));
          },
        );
      case ControlType.dateTime:
        final value = shown.dateValue;
        return AdminDateField(
          label: 'Valore',
          value: value != null ? DateFormat('dd/MM/yyyy').format(value.toLocal()) : 'Seleziona data',
          onTap: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: value ?? DateTime.now(),
              firstDate: DateTime.now().subtract(const Duration(days: 365 * 3)),
              lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
            );
            if (picked != null) _commit(_answer(dateValue: picked));
          },
        );
      case ControlType.options:
        final choices = _c.choices;
        if (choices.isEmpty) return _freeText();
        final current = shown.stringValue;
        return AppFieldShell(
          label: 'Valore',
          child: DropdownButtonFormField<String>(
            initialValue: choices.contains(current) ? current : null,
            isExpanded: true,
            items: [for (final o in choices) DropdownMenuItem(value: o, child: Text(o))],
            onChanged: (v) {
              if (v != null) _commit(_answer(stringValue: v));
            },
          ),
        );
      case ControlType.text:
      case ControlType.unknown:
        return _freeText();
    }
  }

  Widget _freeText() => AppTextField(
    label: 'Valore',
    controller: _text,
    onChanged: (v) => _commit(_answer(stringValue: v)),
  );
}

class _ChoiceButton extends StatelessWidget {
  const _ChoiceButton({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? c.blue.withAlpha(30) : Colors.transparent,
            border: Border.all(color: selected ? c.blue : c.borderMedium),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 15,
              color: selected ? c.blue : c.ink,
            ),
          ),
        ),
      ),
    );
  }
}
