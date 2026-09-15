// dart format width=100
// ══════════════════════════════════════════════════════════════════════════════
// GpsStatusIndicator
//
// A small, passive "did we get a position" row for the cantiere timbratura flow. GPS capture on
// this flow has always been fully automatic — see cantiere_timbra_screen.dart's own header
// comment and `_confirmGpsPurpose()` — there is no button here and this widget adds none; it only
// tells the technician a position was (or wasn't) picked up, near the arrival/departure action.
//
// [ILocationService] exposes no observable "do we currently have a fix" state (see
// location_service.dart) — only a one-shot `getCurrentPosition()` and `willPromptForPermission()`.
// This widget deliberately does NOT call `getCurrentPosition()` when permission hasn't been
// decided yet (`willPromptForPermission()` true): doing so would silently trigger the OS
// permission dialog the moment this indicator mounts, with no purpose explanation shown first —
// exactly what `_confirmGpsPurpose()` exists to prevent for the real start/end actions. Once
// permission is already decided one way or another (granted, permanently denied, or the app
// setting is off), `getCurrentPosition()` cannot show any OS UI on its own, so it's safe to call
// here purely to report the outcome.
// ══════════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../../core/location/location_service.dart';
import '../../core/theme/app_palette.dart';

enum GpsIndicatorStatus {
  /// Permission hasn't been asked yet — calling `getCurrentPosition()` here would prompt.
  pending,

  /// A position was obtained.
  acquired,

  /// Permission denied (incl. permanently), GPS off, the app setting disabled it, or the device
  /// simply could not get a fix in time.
  unavailable,
}

/// Read-only, display-only peek at GPS availability — never the same call site the real
/// start/end actions use to actually capture a position (see this file's own header comment).
final gpsIndicatorStatusProvider = FutureProvider.autoDispose<GpsIndicatorStatus>((ref) async {
  final service = ref.watch(locationServiceProvider);
  if (await service.willPromptForPermission()) return GpsIndicatorStatus.pending;
  final position = await service.getCurrentPosition();
  return position != null ? GpsIndicatorStatus.acquired : GpsIndicatorStatus.unavailable;
});

/// A dot + one line of status text. No tap target — see this file's header comment.
class GpsStatusIndicator extends ConsumerWidget {
  const GpsStatusIndicator({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statusAsync = ref.watch(gpsIndicatorStatusProvider);

    final (Color dotColor, String label) = switch (statusAsync) {
      AsyncData(value: GpsIndicatorStatus.acquired) => (
        context.colors.green,
        'Posizione rilevata automaticamente',
      ),
      AsyncData(value: GpsIndicatorStatus.pending) => (
        context.colors.amber,
        'Posizione richiesta al primo utilizzo',
      ),
      AsyncData(value: GpsIndicatorStatus.unavailable) => (
        context.colors.inkMuted,
        'Posizione non disponibile',
      ),
      AsyncError() => (context.colors.inkMuted, 'Posizione non disponibile'),
      _ => (context.colors.inkMuted, 'Verifica della posizione…'),
    };

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(LucideIcons.mapPin, size: 13, color: dotColor),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            label,
            // Follows the same state colour as the icon/dot above — the label used to stay a
            // fixed inkMuted regardless of state, so the two elements visually disagreed (a red
            // dot next to muted-grey text reads as "nothing wrong").
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: dotColor,
            ),
          ),
        ),
      ],
    );
  }
}
