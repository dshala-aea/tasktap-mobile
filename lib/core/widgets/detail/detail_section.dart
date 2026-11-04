import 'package:flutter/material.dart';

import '../../theme/app_palette.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';

class DetailSectionData {
  const DetailSectionData({
    required this.title,
    required this.child,
    this.trailing,
    this.isEmpty = false,
  });

  final String title;
  final Widget child;
  final Widget? trailing;
  final bool isEmpty;
}

class DetailSection extends StatelessWidget {
  const DetailSection({super.key, required this.data});

  final DetailSectionData data;

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) return const SizedBox.shrink();

    final colors = context.colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                data.title,
                style: AppTextStyles.headlineMedium.copyWith(
                  fontWeight: FontWeight.w700,
                  color: colors.ink,
                ),
              ),
            ),
            if (data.trailing != null) ...[
              const SizedBox(width: AppSpacing.sm),
              DefaultTextStyle.merge(
                style: AppTextStyles.docCode.copyWith(
                  fontSize: 11,
                  color: colors.inkMuted,
                ),
                child: data.trailing!,
              ),
            ],
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        data.child,
      ],
    );
  }
}
