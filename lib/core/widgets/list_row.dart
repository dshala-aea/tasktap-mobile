import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import 'package:tasktap_mobile/core/theme/app_palette.dart';
import 'package:tasktap_mobile/core/theme/app_rack.dart';

import 'rack.dart';

/// A row in a list, now a drawer front rather than a divided line.
///
/// Twenty-eight call sites across twenty-one screens keep their exact API. What changed is what a
/// list *is*: rows were separated by a 1px hairline and shared one flat ground, so a list of eight
/// read as one undifferentiated slab. Cells are separate objects on a constant pitch
/// ([AppRack.cellGap]), which is how a rack reads and how a thumb finds the right one without
/// looking twice.
///
/// [showDivider] is retained for API compatibility and is now a no-op: the gap between cells is
/// the separation, and drawing a line as well would be saying it twice. It is not deprecated
/// because removing it would touch every call site to no visual effect.
class ListRow extends StatelessWidget {
  const ListRow({
    super.key,
    this.leading,
    required this.title,
    this.subtitle,
    this.meta,
    this.onTap,
    this.showDivider = true,
    this.strapped = false,
    this.ledgeColor,
  });

  final Widget? leading;
  final String title;
  final String? subtitle;
  final Widget? meta;
  final VoidCallback? onTap;

  /// Retained for compatibility. The pitch between cells is the separator now.
  final bool showDivider;

  /// Live, running, or selected — turns the ledge brand yellow.
  final bool strapped;

  /// For a row whose state is neither ordinary nor live: overdue, rejected, queued.
  final Color? ledgeColor;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppRack.cellGap),
      child: RackCell(
        onTap: onTap,
        strapped: strapped,
        ledgeColor: ledgeColor,
        padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
        child: Row(
          children: [
            if (leading != null) ...[leading!, const SizedBox(width: 12)],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    // Sora, not Manrope. The title is the label on the drawer front — the thing
                    // read at arm's length to decide whether this is the right cell — and the
                    // subtitle below it is what you read once you have decided. Two faces doing
                    // two jobs is the only reason this app carries two faces.
                    style: GoogleFonts.sora(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: c.ink,
                      letterSpacing: -0.1,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.manrope(
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                        color: c.inkMuted,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (meta != null) ...[const SizedBox(width: 12), meta!],
            if (onTap != null) ...[
              const SizedBox(width: 6),
              Icon(LucideIcons.chevronRight, size: 16, color: c.inkDisabled),
            ],
          ],
        ),
      ),
    );
  }
}
