import 'package:flutter/material.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../theme/app_colors.dart';
import '../theme/app_palette.dart';
import '../theme/app_spacing.dart';
import 'screen_header.dart';

/// Opens a compartment's content as a bottom sheet over the current screen, rather than growing
/// the screen in place. First built for Ticket detail's compartment grid, reused by the Rapportino
/// wizard's own checklist grid — both replaced an in-place accordion/stepper with a fixed-shape
/// grid of tiles that each open a sheet, so the page itself never grows or shrinks around whatever
/// is open. Scrollable and height-capped: the content widgets this wraps were built to sit inside
/// an ambient scroll view, not to bound their own height, so this supplies both.
///
/// [footer] pins a control below the scrollable content, outside it, so it stays put while the
/// form scrolls behind it — the place for a step's single action that must never scroll away.
/// Null by default, so every existing caller is unaffected.
void openCompartmentSheet(
  BuildContext context, {
  required String label,
  required Widget content,
  Widget? footer,
}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) {
      // Keyboard inset (viewInsets) plus the bottom safe-area/home-indicator inset (padding). The
      // scroll view otherwise sat flush against the home indicator on notched devices whenever the
      // keyboard was closed, since viewInsets.bottom is 0 in that state and carries none of the
      // safe-area reservation on its own. Applied once, below: when a footer owns the bottom edge it
      // takes the inset, and the scroll view keeps only a small gap.
      final bottomInset =
          MediaQuery.of(ctx).viewInsets.bottom +
          MediaQuery.of(ctx).padding.bottom;
      return DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.92,
        expand: false,
        builder: (ctx, scrollController) => Column(
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 10, bottom: AppSpacing.xs),
              child: SheetHandle(),
            ),
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
                        fontFamily: 'Archivo Narrow',
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
            Divider(height: 1, thickness: 1, color: ctx.colors.borderLight),
            Expanded(
              child: SingleChildScrollView(
                controller: scrollController,
                padding: EdgeInsets.only(
                  bottom: footer == null ? bottomInset : AppSpacing.sm,
                ),
                child: content,
              ),
            ),
            if (footer != null)
              DecoratedBox(
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(color: ctx.colors.borderLight, width: 1),
                  ),
                ),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    AppSpacing.pagePadding,
                    AppSpacing.sm,
                    AppSpacing.pagePadding,
                    bottomInset + AppSpacing.sm,
                  ),
                  child: footer,
                ),
              ),
          ],
        ),
      );
    },
  );
}

class SheetHandle extends StatelessWidget {
  const SheetHandle({super.key});

  @override
  Widget build(BuildContext context) {
    // A muted tone, not full-saturation accent — this is a drag affordance, not a call to
    // action, so it stays quiet while still carrying the one accent hue rather than plain grey.
    return Center(
      child: Container(
        width: 36,
        height: 4,
        decoration: BoxDecoration(
          color: AppColors.Y.withAlpha(60),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}
