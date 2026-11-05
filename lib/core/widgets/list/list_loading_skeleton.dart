import 'package:flutter/material.dart';

import '../../theme/app_palette.dart';
import '../../theme/app_rack.dart';
import '../../theme/app_spacing.dart';

/// The list's loading state: group-header and row-shaped bars on the real spacing rhythm, so the
/// content does not jump when it arrives. Deliberately static — no pulse, so reduced-motion users
/// get the same thing everyone else does.
class ListLoadingSkeleton extends StatelessWidget {
  const ListLoadingSkeleton({
    super.key,
    this.groups = 2,
    this.rowsPerGroup = 3,
  });

  final int groups;
  final int rowsPerGroup;

  @override
  Widget build(BuildContext context) {
    final rule = context.colors.borderLight;

    return Padding(
      key: const Key('list-loading-skeleton'),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.pagePadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var g = 0; g < groups; g++) ...[
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 6),
              child: Row(
                children: [
                  _Bar(width: 128, height: 16, color: rule),
                  const Spacer(),
                  _Bar(width: 18, height: 8, color: rule),
                ],
              ),
            ),
            for (var r = 0; r < rowsPerGroup; r++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 9),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Bar(width: 200, height: 11, color: rule),
                    const SizedBox(height: 6),
                    _Bar(width: 150, height: 9, color: rule),
                    const SizedBox(height: 5),
                    _Bar(width: 110, height: 8, color: rule),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.width, required this.height, required this.color});

  final double width;
  final double height;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(color: color, borderRadius: AppRack.insetShape),
    );
  }
}
