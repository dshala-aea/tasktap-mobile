// dart format width=100
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../../core/theme/app_palette.dart';
import '../../core/widgets/widgets.dart';

/// Opens the camera scan sheet and returns the raw scanned code, or null if the technician backed
/// out. Swappable in tests, where there is no camera.
typedef BarcodeScanner = Future<String?> Function(BuildContext context);

/// Parses a typed quantity, accepting `.` or `,`. Null when the text is not a positive number.
double? parseMaterialeQty(String text) {
  final normalized = text.trim().replaceAll(',', '.');
  if (normalized.isEmpty) return null;
  final q = double.tryParse(normalized);
  return q != null && q > 0 ? q : null;
}

String formatMaterialeQty(double q) =>
    q == q.truncateToDouble() ? q.toInt().toString() : q.toString();

/// One separator, at most two decimals. Rejects the edit rather than silently truncating.
class DecimalQtyInputFormatter extends TextInputFormatter {
  const DecimalQtyInputFormatter();

  static final _valid = RegExp(r'^\d*\.?\d{0,2}$');

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final normalized = newValue.text.replaceAll(',', '.');
    if (normalized.isEmpty) return newValue;
    return _valid.hasMatch(normalized) ? newValue : oldValue;
  }
}

/// The one quantity control: numeric keyboard + decimals between the −/+ buttons.
///
/// Used by the add-material picker and the stock-movement dialog so the parsing, formatting and
/// decimal limit cannot drift apart.
class MaterialeQtyField extends StatelessWidget {
  const MaterialeQtyField({
    super.key,
    required this.controller,
    required this.onChanged,
    this.onMinus,
    this.onPlus,
    this.fieldKey = const Key('materiale-qty-field'),
    this.errorText,
  });

  final TextEditingController controller;
  final VoidCallback onChanged;
  final VoidCallback? onMinus;
  final VoidCallback? onPlus;
  final Key fieldKey;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              'Qtà',
              style: TextStyle(
                fontFamily: 'Archivo',
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: context.colors.inkMuted,
              ),
            ),
            const Spacer(),
            QtyStepButton(
              icon: LucideIcons.minus,
              label: 'Diminuisci quantità',
              onTap: onMinus,
            ),
            const SizedBox(width: 6),
            SizedBox(
              width: 76,
              child: TextField(
                key: fieldKey,
                controller: controller,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: const [DecimalQtyInputFormatter()],
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: context.colors.ink,
                ),
                decoration: InputDecoration(
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onChanged: (_) => onChanged(),
              ),
            ),
            const SizedBox(width: 6),
            QtyStepButton(
              icon: LucideIcons.plus,
              label: 'Aumenta quantità',
              onTap: onPlus,
            ),
          ],
        ),
        if (errorText != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              errorText!,
              style: TextStyle(fontSize: 12, color: context.colors.red),
            ),
          ),
      ],
    );
  }
}

/// Circular −/+ target. Kept public so the report's saved-row stepper and both dialogs share it.
class QtyStepButton extends StatelessWidget {
  const QtyStepButton({super.key, required this.icon, required this.label, this.onTap});

  final IconData icon;

  /// Announced by TalkBack. The glyph carries no text, so without this the stepper was two
  /// unnamed buttons either side of a number.
  final String label;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: label,
      child: AppTappable(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: SizedBox(
          width: 48,
          height: 48,
          child: Center(
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: onTap != null ? context.colors.bg3 : context.colors.bg4,
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: 16,
                color: onTap != null ? context.colors.ink : context.colors.inkDisabled,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
