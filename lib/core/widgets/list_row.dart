import 'package:flutter/material.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import 'package:tasktap_mobile/core/theme/app_palette.dart';
import 'package:tasktap_mobile/core/theme/app_spacing.dart';
import 'package:tasktap_mobile/core/theme/app_vetro_palette.dart';

/// A row in a list — flat, hairline-separated, full-bleed.
///
/// Was a bordered "drawer front" cell (RackCell) on its own pitch of vertical gap between rows.
/// Replaced with the shape ticket_list_screen's `_TicketRow` and rapportini_list_screen's
/// `_RapportinoRow` already proved out for real content: no per-row card, border or radius — a
/// bottom hairline (`context.vetro.hairline`) between rows, same as Files, Settings, and every
/// other flat list these two screens were themselves modeled on. A per-row glass card
/// (`VetroGlass`'s own `BackdropFilter`) was considered and rejected for the same reason those two
/// screens rejected it: a list can run to dozens of rows, and a blur sigma per row is a real,
/// measured cost a flat row with one border paint is not.
///
/// [strapped]/[ledgeColor] keep their meaning — "this one needs you" / a state that is neither
/// ordinary nor live — but the mechanism moves from a recolored cell border to the same 3px
/// leading stripe `_TicketRow`'s priority marker and `_RapportinoRow`'s draft marker already use,
/// tinted with the Vetro gradient's own accent rather than invented separately for this widget.
///
/// [showDivider] used to be a no-op, kept only for call-site compatibility with the cell-gap
/// layout that made a divider redundant. It is live again now that a divider is genuinely what
/// separates one row from the next — callers already pass it correctly (typically `false` on a
/// list's last row), so this needed no call-site changes to take effect.
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

  /// Whether this row draws the hairline separating it from the next one — pass `false` on a
  /// list's last row.
  final bool showDivider;

  /// Selected, priority, or still-needs-finishing — turns the leading stripe the Vetro tint. Not
  /// for a live/running state: see `LiveDot`.
  final bool strapped;

  /// For a row whose state is neither ordinary nor live: overdue, rejected, queued.
  final Color? ledgeColor;

  @override
  Widget build(BuildContext context) {
    final v = context.vetro;
    final c = context.colors;
    final stripeColor = strapped ? v.tint : (ledgeColor ?? Colors.transparent);

    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.pagePadding, vertical: 11),
        decoration: BoxDecoration(
          border: showDivider ? Border(bottom: BorderSide(color: v.hairline)) : null,
        ),
        // IntrinsicHeight, not a bare `Row(crossAxisAlignment: stretch, ...)`: a caller may size
        // this row from a SliverChildBuilderDelegate item with no bounded height for `stretch` to
        // stretch the leading stripe into — same reasoning as `_TicketRow`'s own comment.
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: 3,
                margin: const EdgeInsets.only(right: 12),
                decoration: BoxDecoration(color: stripeColor, borderRadius: BorderRadius.circular(3)),
              ),
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
                      style: TextStyle(
                        fontFamily: 'Inter',
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
                        style: TextStyle(fontFamily: 'Inter', fontSize: 12, color: c.inkMuted),
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
      ),
    );
  }
}
