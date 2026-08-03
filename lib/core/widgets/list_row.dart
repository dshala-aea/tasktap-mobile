import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../theme/app_colors.dart';

/// List row — 12/19 padding, gap 12, bottom 1 px BL divider; leading slot;
/// Manrope 600/14 title + Manrope 12 MUTED subtitle (both ellipsis); meta slot
/// (right); trailing chevron (16, DIS) when tappable.
///
/// ```dart
/// ListRow(
///   leading: AppAvatar(name: 'Mario Rossi'),
///   title: 'Sostituzione caldaia',
///   subtitle: 'Via Roma 12',
///   meta: StatusPill(stato: 'In corso'),
///   onTap: () {},
/// );
/// ```
class ListRow extends StatelessWidget {
  const ListRow({
    super.key,
    this.leading,
    required this.title,
    this.subtitle,
    this.meta,
    this.onTap,
    this.showDivider = true,
  });

  final Widget? leading;
  final String title;
  final String? subtitle;
  final Widget? meta;
  final VoidCallback? onTap;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final row = Container(
      constraints: const BoxConstraints(minHeight: 44),
      padding: const EdgeInsets.symmetric(horizontal: 19, vertical: 12),
      decoration: BoxDecoration(
        border: showDivider
            ? const Border(bottom: BorderSide(color: AppColors.BL))
            : null,
      ),
      child: Row(
        children: [
          if (leading != null) ...[
            leading!,
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.manrope(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.DARK,
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.manrope(
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                      color: AppColors.MUTED,
                    ),
                  ),
              ],
            ),
          ),
          if (meta != null) ...[
            const SizedBox(width: 12),
            meta!,
          ],
          if (onTap != null) ...[
            const SizedBox(width: 8),
            const Icon(
              LucideIcons.chevronRight,
              size: 16,
              color: AppColors.DIS,
            ),
          ],
        ],
      ),
    );

    if (onTap == null) return row;
    return Material(
      color: Colors.transparent,
      child: InkWell(onTap: onTap, child: row),
    );
  }
}
