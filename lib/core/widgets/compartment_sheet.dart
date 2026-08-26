import 'package:flutter/material.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../theme/app_palette.dart';
import '../theme/app_spacing.dart';
import '../theme/app_vetro_palette.dart';
import 'screen_header.dart';

/// Opens a compartment's content as a bottom sheet over the current screen, rather than growing
/// the screen in place. First built for Ticket detail's compartment grid, reused by the Rapportino
/// wizard's own checklist grid — both replaced an in-place accordion/stepper with a fixed-shape
/// grid of tiles that each open a sheet, so the page itself never grows or shrinks around whatever
/// is open. Scrollable and height-capped: the content widgets this wraps were built to sit inside
/// an ambient scroll view, not to bound their own height, so this supplies both.
void openCompartmentSheet(BuildContext context, {required String label, required Widget content}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.92,
      expand: false,
      builder: (ctx, scrollController) => Column(
        children: [
          const Padding(padding: EdgeInsets.only(top: 10, bottom: 4), child: SheetHandle()),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.pagePadding,
              AppSpacing.sm,
              AppSpacing.pagePadding,
              AppSpacing.sm,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: ctx.colors.ink,
                    ),
                  ),
                ),
                HeaderIconBtn(
                  icon: LucideIcons.x,
                  label: 'Chiudi',
                  onTap: () => Navigator.of(ctx).pop(),
                ),
              ],
            ),
          ),
          Divider(height: 1, thickness: 1, color: ctx.vetro.hairline),
          Expanded(
            child: SingleChildScrollView(
              controller: scrollController,
              padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
              child: content,
            ),
          ),
        ],
      ),
    ),
  );
}

class SheetHandle extends StatelessWidget {
  const SheetHandle({super.key});

  @override
  Widget build(BuildContext context) {
    // A muted tint tone, not full-saturation accent — this is a drag affordance, not a call to
    // action, so it stays quiet while still carrying the one Vetro hue rather than plain grey.
    return Center(
      child: Container(
        width: 36,
        height: 4,
        decoration: BoxDecoration(
          color: context.vetro.tint.withAlpha(60),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}
