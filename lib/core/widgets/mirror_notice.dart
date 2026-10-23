import 'package:flutter/material.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../theme/app_palette.dart';

/// The line a list says when its rows came from the device's synced mirror rather than from the
/// server: *these are the records this device has, and that may not be all of them*.
///
/// A mirrored list is not a wrong list, but it is a **partial** one — the sync payload is scoped,
/// so a tenant with more records than this account's scope never sees the rest, and an office edit
/// made after the last sync is not here yet. Presenting that as the complete list is the one thing
/// this widget exists to prevent: the technician reads "12 totali" and believes it.
///
/// [what] names the records in the technician's own words ("interventi", "contratti"), so the
/// sentence reads as a statement about *these rows*, not about the app being offline.
///
/// ```dart
/// if (rows.fromMirror) const MirrorNotice(what: 'contratti'),
/// ```
class MirrorNotice extends StatelessWidget {
  const MirrorNotice({super.key, required this.what});

  /// The plural noun naming the rows below, lowercase and already inflected: "contratti".
  final String what;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(LucideIcons.wifiOff, size: 14, color: c.inkMuted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Dati salvati sul dispositivo: potrebbero mancare $what non ancora scaricati.',
              style: TextStyle(
                fontFamily: 'Archivo',
                fontSize: 12,
                fontWeight: FontWeight.w400,
                color: c.inkMuted,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
