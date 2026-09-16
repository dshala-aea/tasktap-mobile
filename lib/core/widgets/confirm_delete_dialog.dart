import 'package:flutter/material.dart';

import '../theme/app_palette.dart';
import '../theme/app_spacing.dart';
import 'app_button.dart';
import 'app_card.dart';

/// Shared confirm-then-delete dialog — this app's own Vetro `AppCard` + `AppButton` chrome via
/// `showDialog<bool>`, with the destructive action styled as `AppButton.danger`, so every
/// "Elimina"/"Rimuovi" confirmation in the app reads as destructive and as part of the app rather
/// than as a neutral, stock Material dialog. Same shape as the logout confirmation in
/// altro_hub_screen.dart.
///
/// Extracted out of the half-dozen hand-duplicated `showDialog<bool>` + `AlertDialog` blocks
/// across the admin cantiere/customer/contract detail screens (cantiere, contact, crew, customer,
/// location, contract) — each one built the same dialog by hand with no shared widget to reuse.
///
/// Returns `true` only when the user confirmed; `false` for cancel or a dismissed dialog (tap
/// outside, back button).
Future<bool> confirmDeleteDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Elimina',

  /// False for a confirm that reverses a prior destructive action (e.g. "Riattiva" undoing a
  /// deactivate) — same chrome, but the confirm button reads as a normal action, not a warning.
  bool danger = true,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
      child: AppCard(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                fontFamily: 'Archivo Narrow',
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: ctx.colors.ink,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: TextStyle(fontFamily: 'Archivo', fontSize: 14, color: ctx.colors.inkMuted),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: AppButton.ghost(
                    label: 'Annulla',
                    onPressed: () => Navigator.of(ctx).pop(false),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: danger
                      ? AppButton.danger(
                          label: confirmLabel,
                          onPressed: () => Navigator.of(ctx).pop(true),
                        )
                      : AppButton(
                          label: confirmLabel,
                          onPressed: () => Navigator.of(ctx).pop(true),
                        ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
  return confirmed ?? false;
}
