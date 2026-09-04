// dart format width=100
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/sync/connectivity_provider.dart';
import '../../data/sync/pending_sync_count_provider.dart';
import '../theme/app_palette.dart';

/// A slim, persistent top banner — offline, or N-pending/N-failed. Renders nothing when online
/// and fully synced, matching this app's existing "silence is correct" convention. Purely
/// additive: place via Stack over existing content, never restructure the content it sits above.
class OfflineSyncBanner extends ConsumerWidget {
  const OfflineSyncBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOnline = ref.watch(connectivityProvider).valueOrNull ?? true;
    final counts = ref.watch(pendingSyncCountProvider).valueOrNull ?? (pending: 0, failed: 0);

    final String? label;
    if (!isOnline) {
      label = 'Offline';
    } else if (counts.failed > 0) {
      label = '${counts.failed} da riprovare';
    } else if (counts.pending > 0) {
      label = '${counts.pending} in coda';
    } else {
      label = null;
    }

    if (label == null) return const SizedBox.shrink();

    return SafeArea(
      bottom: false,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 6),
        color: counts.failed > 0 ? context.colors.red : context.colors.inkMuted,
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}
