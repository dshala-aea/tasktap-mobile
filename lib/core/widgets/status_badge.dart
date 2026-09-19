import 'package:flutter/material.dart';

import '../theme/status_colors.dart';
import 'status_stamp.dart';

/// Displays a [ReportStato] as Il Documento's stamp device — see [StatusStamp], which this now
/// renders through instead of a flat colored badge pill.
///
/// ```dart
/// StatusBadge(stato: ReportStato.inviato);
/// StatusBadge(stato: ReportStato.fatturato, size: StatusBadgeSize.large);
/// ```
enum StatusBadgeSize { small, medium, large }

class StatusBadge extends StatelessWidget {
  const StatusBadge({
    super.key,
    required this.stato,
    this.size = StatusBadgeSize.medium,
  });

  final ReportStato stato;
  final StatusBadgeSize size;

  @override
  Widget build(BuildContext context) {
    final label = statoLabel(stato);
    final stampSize = switch (size) {
      StatusBadgeSize.small => StampSize.small,
      StatusBadgeSize.medium => StampSize.medium,
      StatusBadgeSize.large => StampSize.large,
    };

    return StatusStamp(stato: label, size: stampSize);
  }
}
