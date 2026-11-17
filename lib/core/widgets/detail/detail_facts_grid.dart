import 'package:flutter/material.dart';

import '../../theme/app_palette.dart';
import '../../theme/app_rack.dart';
import '../../theme/app_text_styles.dart';
import '../app_tappable.dart';
import 'detail_hero.dart' show DetailFact;

/// A two-column bordered grid of label/value facts — the mockup's `.facts`.
///
/// Sheet fill, 1px rules between cells, mono 8px uppercase labels, 11.5/500 single-line values that
/// ellipsize. A fact with an `onTap` becomes a tappable cell.
class DetailFactsGrid extends StatelessWidget {
  const DetailFactsGrid({super.key, required this.facts});

  final List<DetailFact> facts;

  @override
  Widget build(BuildContext context) {
    if (facts.isEmpty) return const SizedBox.shrink();
    final colors = context.colors;
    final rule = BorderSide(color: colors.borderLight);
    final rowCount = (facts.length + 1) ~/ 2;

    return Container(
      key: const Key('detail-facts-grid'),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border.fromBorderSide(rule),
        borderRadius: AppRack.freeShape,
      ),
      child: Column(
        children: [
          for (var r = 0; r < rowCount; r++)
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: _FactCell(
                      fact: facts[r * 2],
                      border: Border(
                        right: rule,
                        bottom: r < rowCount - 1 ? rule : BorderSide.none,
                      ),
                    ),
                  ),
                  Expanded(
                    child: r * 2 + 1 < facts.length
                        ? _FactCell(
                            fact: facts[r * 2 + 1],
                            border: Border(
                              bottom: r < rowCount - 1 ? rule : BorderSide.none,
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _FactCell extends StatelessWidget {
  const _FactCell({required this.fact, required this.border});

  final DetailFact fact;
  final Border border;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            fact.label.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.docCode.copyWith(
              fontSize: 8,
              letterSpacing: 0.64,
              color: colors.inkMuted,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            fact.value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.bodySmall.copyWith(
              fontSize: 11.5,
              height: 1.3,
              fontWeight: FontWeight.w500,
              color: colors.ink,
            ),
          ),
        ],
      ),
    );

    return DecoratedBox(
      decoration: BoxDecoration(border: border),
      child: fact.onTap == null
          ? content
          : AppTappable(onTap: fact.onTap, child: content),
    );
  }
}
