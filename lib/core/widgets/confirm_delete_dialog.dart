import 'package:flutter/material.dart';

import '../theme/app_palette.dart';

/// Shared confirm-then-delete dialog — a plain `AlertDialog` via `showDialog<bool>` with the
/// destructive action styled in `context.colors.red`, so every "Elimina"/"Rimuovi" confirmation
/// in the app reads as destructive rather than as a neutral action.
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
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annulla')),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: TextButton.styleFrom(foregroundColor: context.colors.red),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}
