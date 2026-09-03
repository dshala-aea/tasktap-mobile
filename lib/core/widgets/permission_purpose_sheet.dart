// dart format width=100
import 'package:flutter/material.dart';

import 'package:tasktap_mobile/core/theme/app_palette.dart';
import 'app_button.dart';

// ══════════════════════════════════════════════════════════════════════════════
// askPermissionPurpose
//
// The sentence that has to come before the OS dialog.
//
// This app took two permissions with no stated purpose: the notification
// prompt fired during app startup, before the technician had seen a single
// screen, and the location prompt fired inside a "Acquisisci" button with
// nothing saying what the coordinate would be used for or what would happen if
// they refused.
//
// Both are transparency failures, and both are also the most reliable way to
// lose the permission: an OS dialog with no context is the one people deny.
// The system dialog cannot be re-shown once refused on iOS, so the only chance
// to explain is before it.
//
// The rule this encodes: state the purpose, state what still works without it,
// and make refusing a first-class option rather than a greyed-out corner. The
// sheet returns false on dismiss, so a swipe-away is a refusal and nothing is
// requested.
// ══════════════════════════════════════════════════════════════════════════════

/// Asks for consent to ask. Returns true only on an explicit yes.
///
/// [motivo] says what the permission is for in the technician's own terms.
/// [senzaDiEsso] says what still works if they refuse — the part that makes
/// refusing safe to choose, and the part an OS dialog can never carry.
Future<bool> askPermissionPurpose(
  BuildContext context, {
  required IconData icon,
  required String titolo,
  required String motivo,
  required String senzaDiEsso,
  String cta = 'Continua',
}) async {
  final granted = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _PurposeSheet(
      icon: icon,
      titolo: titolo,
      motivo: motivo,
      senzaDiEsso: senzaDiEsso,
      cta: cta,
    ),
  );
  return granted ?? false;
}

class _PurposeSheet extends StatelessWidget {
  const _PurposeSheet({
    required this.icon,
    required this.titolo,
    required this.motivo,
    required this.senzaDiEsso,
    required this.cta,
  });

  final IconData icon;
  final String titolo;
  final String motivo;
  final String senzaDiEsso;
  final String cta;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: const BorderRadius.all(Radius.circular(20)),
            border: Border.all(color: c.borderLight),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Grab handle: this is a sheet, and a sheet that cannot be seen to be draggable
                // reads as a dialog with a missing dismiss.
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: c.borderMedium,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Row(
                  children: [
                    Icon(icon, size: 20, color: c.ink),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        titolo,
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: c.ink,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  motivo,
                  style: TextStyle(fontFamily: 'Inter', fontSize: 14, height: 1.45, color: c.ink),
                ),
                const SizedBox(height: 10),
                Text(
                  senzaDiEsso,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 13,
                    height: 1.45,
                    color: c.inkMuted,
                  ),
                ),
                const SizedBox(height: 20),
                AppButton(
                  label: cta,
                  onPressed: () => Navigator.of(context).pop(true),
                  size: AppButtonSize.lg,
                ),
                const SizedBox(height: 8),
                AppButton.secondary(
                  label: 'Non ora',
                  onPressed: () => Navigator.of(context).pop(false),
                  size: AppButtonSize.lg,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
