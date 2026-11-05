import 'package:flutter/material.dart';

import '../../theme/app_palette.dart';
import '../../theme/app_rack.dart';
import '../../theme/app_text_styles.dart';
import 'list_models.dart';

/// The prototype's `.summary`: a flat two-part footer line under the last group
/// (`8 cantieri attivi | 2 oggi`), mono uppercase on a sheet.
class ListSummaryFooter extends StatelessWidget {
  const ListSummaryFooter({super.key, required this.data});

  final ListSummaryData data;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final style = AppTextStyles.docCode.copyWith(
      fontSize: 8,
      fontWeight: FontWeight.w500,
      letterSpacing: 0.32,
      color: colors.inkMuted,
    );

    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: AppRack.freeShape,
        border: Border.all(color: colors.borderLight),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              data.left.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            data.right.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style,
          ),
        ],
      ),
    );
  }
}
