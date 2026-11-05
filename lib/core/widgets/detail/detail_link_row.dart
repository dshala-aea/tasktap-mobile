import 'package:flutter/material.dart';

import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';

/// Minimum touch target for a section row, matching `DetailSection`'s own 44px convention.
const double kDetailLinkRowMinHeight = 44;

/// One row of the prototype's section stack in `other-details.html`: a bold section name on the
/// left and a mono meta line on the right, separated from the next row by a hairline.
///
/// This is the generic piece the 10 master-data details would otherwise rebuild: a summary row
/// that opens a section (`Relazioni · 12 sedi · 4 contratti`), a date/scadenza fact, or a movement
/// line. Screens keep their own section content; this only draws the row.
///
/// ```dart
/// DetailLinkRow(
///   title: 'Relazioni',
///   meta: '12 sedi · 4 contratti · 3 referenti',
///   onTap: () => openRelazioni(),
/// )
/// ```
class DetailLinkRow extends StatelessWidget {
  const DetailLinkRow({
    super.key,
    required this.title,
    this.meta,
    this.onTap,
    this.showDivider = true,
    this.trailing,
    this.semanticsLabel,
  });

  final String title;

  /// Mono uppercase meta on the right. Null renders nothing.
  final String? meta;

  final VoidCallback? onTap;

  /// Pass `false` on the last row of a section.
  final bool showDivider;

  /// Replaces [meta] when a caller needs something other than text (a stamp, a link).
  final Widget? trailing;

  /// Explicit screen-reader label. Supply this when [trailing] carries meaning (a date, a stamp)
  /// that the default title/meta phrase would otherwise miss. When omitted and [trailing] is set,
  /// descendant semantics are kept so the trailing widget still announces itself.
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    final content = Container(
      constraints: const BoxConstraints(minHeight: kDetailLinkRowMinHeight),
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        border: showDivider
            ? Border(bottom: BorderSide(color: colors.borderLight))
            : null,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.bodySmall.copyWith(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                color: colors.ink,
              ),
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 8),
            trailing!,
          ] else if (meta != null) ...[
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                meta!.toUpperCase(),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: AppTextStyles.docCode.copyWith(
                  fontSize: 7.5,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.3,
                  color: colors.inkMuted,
                ),
              ),
            ),
          ],
        ],
      ),
    );

    if (onTap == null) {
      if (semanticsLabel == null) return content;
      return Semantics(
        label: semanticsLabel,
        excludeSemantics: true,
        child: content,
      );
    }

    // The label must describe what is actually on screen: when `trailing` replaces `meta`, the
    // hidden meta string must not be announced, and the trailing widget must keep its own
    // semantics unless the caller supplied a complete label.
    final resolvedLabel =
        semanticsLabel ??
        (trailing != null ? null : (meta == null ? title : '$title. $meta'));

    return Semantics(
      button: true,
      label: resolvedLabel,
      onTap: onTap,
      excludeSemantics: resolvedLabel != null,
      child: Material(
        color: Colors.transparent,
        child: InkWell(onTap: onTap, child: content),
      ),
    );
  }
}
