// dart format width=100
import 'package:flutter/material.dart';

import 'package:tasktap_mobile/core/theme/app_palette.dart';
import 'package:tasktap_mobile/core/theme/app_spacing.dart';

/// The icon/titolo/motivo/senzaDiEsso block `askPermissionPurpose`'s sheet renders — extracted so
/// the onboarding flow can show the exact same explanation as a full page instead of a sheet,
/// without duplicating the copy layout. Carries no buttons and no sheet chrome (grab handle,
/// bottom-sheet padding): callers supply both, since a sheet and a full onboarding page want
/// different ones.
class PermissionPurposeCard extends StatelessWidget {
  const PermissionPurposeCard({
    super.key,
    required this.icon,
    required this.titolo,
    required this.motivo,
    required this.senzaDiEsso,
  });

  final IconData icon;
  final String titolo;
  final String motivo;
  final String senzaDiEsso;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: const BorderRadius.all(Radius.circular(2)),
        border: Border.all(color: c.borderLight),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.base,
          AppSpacing.lg,
          AppSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: c.ink),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    titolo,
                    style: TextStyle(
                      fontFamily: 'Archivo Narrow',
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
              style: TextStyle(fontFamily: 'Archivo', fontSize: 14, height: 1.45, color: c.ink),
            ),
            const SizedBox(height: 10),
            Text(
              senzaDiEsso,
              style: TextStyle(fontFamily: 'Archivo', fontSize: 13, height: 1.45, color: c.inkMuted),
            ),
          ],
        ),
      ),
    );
  }
}
