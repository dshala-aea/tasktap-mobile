// dart format width=100
import 'package:flutter/material.dart';

import '../../core/theme/app_palette.dart';
import '../../core/widgets/widgets.dart';

/// The visible "this document was drafted by AI, then reviewed" marker, matching the web badge.
///
/// The report view already carries a "Redazione: AI, poi rivista" fact, but a fact in a grid is not
/// a badge: it is invisible in the list and easy to miss on the hero. This is the one marker the
/// list and the hero share.
class AiAssistedBadge extends StatelessWidget {
  const AiAssistedBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Assistito da AI',
      excludeSemantics: true,
      child: AppBadge(
        label: 'AI',
        small: true,
        outlined: true,
        fgColor: context.colors.accentInk,
      ),
    );
  }
}
