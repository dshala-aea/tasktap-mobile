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

    // Same failed-wins-over-pending precedence either way — offline just also surfaces whichever
    // count applies, instead of hiding it: offline is exactly the state where the queue grows.
    final String? label;
    if (!isOnline) {
      if (counts.failed > 0) {
        label = 'Offline · ${counts.failed} da riprovare';
      } else if (counts.pending > 0) {
        label = 'Offline · ${counts.pending} in coda';
      } else {
        label = 'Offline';
      }
    } else if (counts.failed > 0) {
      label = '${counts.failed} da riprovare';
    } else if (counts.pending > 0) {
      label = '${counts.pending} in coda';
    } else {
      label = null;
    }

    if (label == null) return const SizedBox.shrink();

    final isFailed = counts.failed > 0;

    // Colour pairing verified to clear WCAG AA (4.5:1) for 12px/w600 text in BOTH themes — see
    // test/core/theme/app_palette_contrast_test.dart's method, applied to these two pairs:
    //   - failed:  context.colors.red (bg) / context.colors.inkInverse (fg) — inkInverse is this
    //     palette's documented "text on top of ... the brand colour" token; light 4.73:1,
    //     dark 5.78:1. (`Colors.white` on `context.colors.red` was the original, wrong, guess:
    //     white-on-red only clears ~2.84:1 in dark mode.)
    //   - pending/offline: context.colors.bg3 (bg) / context.colors.inkMuted (fg) — the same
    //     neutral "no state that needs colour" pairing `statusColor()` uses
    //     (lib/core/theme/status_colors.dart); light 4.69:1, dark 4.87:1.
    final Color bg = isFailed ? context.colors.red : context.colors.bg3;
    final Color fg = isFailed ? context.colors.inkInverse : context.colors.inkMuted;

    // Non-interactive: this banner has no tap targets of its own, but it sits in a Stack directly
    // above ScreenHeader's back/action buttons (home_shell.dart), and a hit-test-opaque Container
    // at that same top edge would otherwise silently swallow taps meant for those buttons.
    return IgnorePointer(
      child: SafeArea(
        bottom: false,
        child: Container(
          key: const Key('offlineSyncBannerContainer'),
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 6),
          color: bg,
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }
}
