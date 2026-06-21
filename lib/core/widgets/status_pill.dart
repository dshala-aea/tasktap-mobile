import 'package:flutter/material.dart';

import '../theme/status_colors.dart';
import 'badge.dart';

/// Status pill badge — driven by the 13 Italian status strings.
///
/// Uses [statusColor] for background / foreground colours and wraps [AppBadge].
///
/// ```dart
/// StatusPill(stato: 'In corso');
/// StatusPill(stato: 'Completato', small: true);
/// ```
class StatusPill extends StatelessWidget {
  const StatusPill({
    super.key,
    required this.stato,
    this.small = false,
  });

  /// Italian status string — one of the 13 values in DESIGN-SPEC.md.
  final String stato;

  /// When true renders the smaller badge variant.
  final bool small;

  @override
  Widget build(BuildContext context) {
    final pair = statusColor(stato);

    return AppBadge(
      label: stato,
      small: small,
      bgColor: pair.background,
      fgColor: pair.foreground,
    );
  }
}
