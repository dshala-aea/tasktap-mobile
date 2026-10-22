// dart format width=100
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/sync/sync_service.dart' show SyncStatus, syncProvider;
import 'app_toast.dart';

/// Pull-to-refresh that says when it failed.
///
/// `SyncNotifier.performSync()` never throws — it catches internally and parks the outcome in
/// `SyncState.status`/`errorMessage` (see `sync_service.dart`). So a bare
/// `onRefresh: () => ref.read(syncProvider.notifier).performSync()` stops the spinner and tells the
/// technician nothing, whether it pulled the latest data or never reached the server at all. That is
/// the one thing a refresh must not do: leave stale data looking fresh.
///
/// The dashboard grew this check first and inline; the other pull-to-refresh sites did not, so the
/// same failure was visible on one screen and silent on the rest. One helper, used by all of them,
/// is what keeps them from drifting apart again.
Future<void> refreshWithFeedback(BuildContext context, WidgetRef ref) async {
  await ref.read(syncProvider.notifier).performSync();
  if (!context.mounted) return;
  if (ref.read(syncProvider).status == SyncStatus.error) {
    showAppToast(
      context,
      message: 'Aggiornamento non riuscito. Riprova.',
      tone: ToastTone.error,
    );
  }
}
