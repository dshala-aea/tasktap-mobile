import 'package:flutter/material.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../../theme/status_colors.dart';
import '../status_stamp.dart';
import 'list_models.dart';

/// One document row in the prototype's list: title / meta / secondary line / status stamp, a 1px
/// bottom rule and a chevron. No card chrome — the list is the sheet.
///
/// Real Italian strings are longer than the mockup's placeholders, so the title clamps to two
/// lines and the two muted lines to one, all with an ellipsis. The stamp always carries text
/// (and `StatusStamp` supplies its own semantic label).
class ListDocumentRow extends StatelessWidget {
  const ListDocumentRow({super.key, required this.data});

  final ListRowData data;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    final content = Container(
      constraints: const BoxConstraints(minHeight: 44),
      padding: const EdgeInsets.symmetric(vertical: 9),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.borderLight)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (data.leading != null) ...[
            data.leading!,
            const SizedBox(width: 9),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        data.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.bodySmall.copyWith(
                          fontSize: 11.5,
                          height: 1.25,
                          fontWeight: FontWeight.w600,
                          color: colors.ink,
                        ),
                      ),
                    ),
                    if (data.status != null) ...[
                      const SizedBox(width: 8),
                      StatusStamp(
                        stato: data.status!,
                        size: StampSize.small,
                        family: _familyFor(data.statusTone),
                      ),
                    ],
                  ],
                ),
                if (data.meta != null) ...[
                  const SizedBox(height: 1),
                  Text(
                    data.meta!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.bodySmall.copyWith(
                      fontSize: 10,
                      height: 1.4,
                      color: colors.inkMuted,
                    ),
                  ),
                ],
                if (data.secondary != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    data.secondary!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.bodySmall.copyWith(
                      fontSize: 9.5,
                      height: 1.35,
                      color: colors.inkMuted,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (data.onTap != null) ...[
            const SizedBox(width: 6),
            Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Icon(
                LucideIcons.chevronRight,
                size: 16,
                color: colors.inkMuted,
              ),
            ),
          ],
        ],
      ),
    );

    final labelled = Semantics(
      button: data.onTap != null,
      label: _semanticLabel(data),
      onTap: data.onTap,
      excludeSemantics: true,
      child: content,
    );

    if (data.onTap == null) return labelled;

    return Material(
      color: Colors.transparent,
      child: InkWell(onTap: data.onTap, child: labelled),
    );
  }

  static StatusFamily? _familyFor(ListStatusTone? tone) {
    return switch (tone) {
      null => null,
      ListStatusTone.neutral => StatusFamily.neutral,
      ListStatusTone.info => StatusFamily.info,
      ListStatusTone.good => StatusFamily.good,
      ListStatusTone.warn => StatusFamily.warn,
      ListStatusTone.bad => StatusFamily.bad,
    };
  }

  static String _semanticLabel(ListRowData data) {
    return [
      data.title,
      if (data.meta != null) data.meta!,
      if (data.secondary != null) data.secondary!,
      if (data.status != null) 'Stato: ${data.status}',
    ].join('. ');
  }
}
