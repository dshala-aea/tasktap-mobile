import 'package:flutter/material.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';
import 'package:tasktap_mobile/core/theme/app_palette.dart';

/// A checkbox: a square that is either ticked or not, with a 48 dp tap target around it.
///
/// Deliberately not [AppToggle] and not a Sì/No pair. The three answer different questions: a
/// checkbox asserts *this was done* (unticked is a real answer, an exception); a toggle is a
/// setting being on or off; Sì/No is a question with two valid answers. The web rapportino draws
/// the same line — a `checkbox` field is an `<input type="checkbox">`, a `trueFalse` field is a
/// Sì/No radio pair — and mobile used to collapse the two into Sì/No, which made a tick read as a
/// choice between two answers.
class AppCheckbox extends StatelessWidget {
  const AppCheckbox({
    super.key,
    required this.value,
    required this.onChanged,
    this.label,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;

  /// Accessible name and, when given, visible text beside the box. The checklist's own row already
  /// prints the control's label, so callers there pass it for semantics only.
  final String? label;

  static const double _box = 24;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final enabled = onChanged != null;

    return Semantics(
      checked: value,
      enabled: enabled,
      label: label,
      // The tick is drawn, not text, so nothing below would contribute a name of its own; without
      // this the row is announced twice (once here, once by the visible label).
      excludeSemantics: true,
      child: InkWell(
        onTap: enabled ? () => onChanged!(!value) : null,
        borderRadius: BorderRadius.circular(8),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: _box,
                height: _box,
                decoration: BoxDecoration(
                  color: value ? c.blue.withAlpha(30) : Colors.transparent,
                  border: Border.all(color: value ? c.blue : c.borderMedium, width: 1.5),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: value
                    ? Icon(LucideIcons.check, size: 16, color: c.blue)
                    : const SizedBox.shrink(),
              ),
              if (label != null) ...[
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    label!,
                    style: TextStyle(fontSize: 13, color: c.inkMuted),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
