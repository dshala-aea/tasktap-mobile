import 'package:flutter/material.dart';

import 'status_stamp.dart';

/// Status pill — Il Documento's stamp device, driven by the ~15 Italian status strings this app
/// renders (see [statusFamilyOf] in `status_colors.dart`).
///
/// Was a flat colored [AppBadge] pill with an `outlined` flag every call site but two already set
/// true — a stepping-stone toward a stamped-placard look, per that flag's own retired doc comment.
/// Now renders a real [StatusStamp] unconditionally; the flag is gone rather than kept as a no-op,
/// since a stamp was never going to be a solid-filled pill either way.
///
/// ```dart
/// StatusPill(stato: 'In corso');
/// StatusPill(stato: 'Completato', small: true);
/// ```
class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.stato, this.small = false});

  /// Italian status string.
  final String stato;

  /// When true renders the smaller stamp size.
  final bool small;

  @override
  Widget build(BuildContext context) {
    return StatusStamp(
      stato: stato,
      size: small ? StampSize.small : StampSize.medium,
    );
  }
}
