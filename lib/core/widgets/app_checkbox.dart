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
    this.isRequired = false,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;

  /// The control's name, drawn to the RIGHT of the box, which is where a technician looks for it:
  /// the box alone sat above the sentence, so the row read as a stray rectangle and a caption
  /// under it rather than as one tickable line. Owners must therefore not print the label a second
  /// time for a checkbox row — this widget is the whole row.
  final String? label;

  /// Draws the required marker after the label. The marker is part of the row now that the label
  /// is, so the owner does not have to split the label out to keep it.
  final bool isRequired;

  static const double _box = 24;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final enabled = onChanged != null;

    return Semantics(
      checked: value,
      enabled: enabled,
      label: label == null ? null : (isRequired ? '$label (obbligatorio)' : label),
      // The tick is drawn, not text, so nothing below would contribute a name of its own; this
      // keeps the announced node to the one the caller names.
      excludeSemantics: true,
      child: InkWell(
        onTap: enabled ? () => onChanged!(!value) : null,
        borderRadius: BorderRadius.circular(8),
        child: ConstrainedBox(
          // The 48 dp target is padding around the square, never a height forced on it: a
          // `minHeight` here stretched a 24 dp box into a 24 x 48 sliver, so the tick read as a
          // squashed vertical rectangle instead of a checkbox.
          constraints: const BoxConstraints(minHeight: 48),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Container(
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
              ),
              if (label != null) ...[
                const SizedBox(width: 12),
                Flexible(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      label!,
                      style: TextStyle(fontSize: 14, height: 1.3, color: c.ink),
                    ),
                  ),
                ),
                if (isRequired)
                  Padding(
                    padding: const EdgeInsets.only(left: 4, top: 12),
                    child: Text(
                      '*',
                      style: TextStyle(color: c.red, fontWeight: FontWeight.bold),
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
