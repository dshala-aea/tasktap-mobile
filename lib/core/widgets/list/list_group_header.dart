import 'package:flutter/material.dart';

import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';

/// The prototype's `.group`: display title on the left, mono count on the right, one hairline
/// underneath. No card, no fill.
class ListGroupHeader extends StatelessWidget {
  const ListGroupHeader({super.key, required this.title, this.count});

  final String title;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Container(
      padding: const EdgeInsets.only(top: 12, bottom: 6),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.borderLight)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.titleLarge.copyWith(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: colors.ink,
              ),
            ),
          ),
          if (count != null) ...[
            const SizedBox(width: 8),
            Text(
              '$count',
              style: AppTextStyles.docCode.copyWith(
                fontSize: 8,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.32,
                color: colors.inkMuted,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
