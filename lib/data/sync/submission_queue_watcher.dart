// dart format width=100
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/dio_client.dart';
import '../reports/report_submit_api_client.dart';
import 'connectivity_provider.dart';
import 'submission_queue.dart';
import '../../presentation/providers/report_editor_providers.dart'
    show draftReportRepositoryProvider;

// ══════════════════════════════════════════════════════════════════════════════
// SubmissionQueueWatcher
//
// Wires ConnectivityNotifier → SubmissionQueue.processAll() so that every
// offline→online transition automatically attempts to flush the queue. The same flush
// (which also re-sends transiently-failed rows, up to the queue's retry cap) runs on
// startup and app resume — see [flushSubmissionQueue].
//
// Call [initSubmissionQueueWatcher] once from the root widget (after auth).
// ══════════════════════════════════════════════════════════════════════════════

/// Provides a [SubmissionQueue] backed by real Drift + Dio.
final realSubmissionQueueProvider = Provider<SubmissionQueue>((ref) {
  final repo = ref.watch(draftReportRepositoryProvider);
  final dio = ref.watch(dioProvider);
  final apiClient = ReportSubmitApiClient(dio);
  // Offline gating lives in the queue itself so every trigger (Riepilogo "Invia", reconnect,
  // resume, startup) shares it: offline, a row simply stays readyToSubmit.
  return SubmissionQueue(
    repo: repo,
    apiClient: apiClient,
    isOnline: () => ref.read(isOnlineProvider),
    recheckOnline: () async {
      final r = await Connectivity().checkConnectivity();
      return r.any((c) => c != ConnectivityResult.none);
    },
  );
});

/// Call once on app start (e.g. in HomeShell.initState via addPostFrameCallback).
///
/// Returns the cancel function `onReconnect` hands back — the caller (HomeShell) must invoke it
/// from `dispose()`, matching every sibling watcher (see e.g. `initTimbraSyncWatcher`'s own doc
/// comment for why: without it, a widget remount leaves the old closure's `ref` in the listener
/// list forever).
VoidCallback initSubmissionQueueWatcher(WidgetRef ref) {
  final connectivity = ref.read(connectivityProvider.notifier);
  final cancel = connectivity.onReconnect(() {
    final queue = ref.read(realSubmissionQueueProvider);
    queue.processAll();
  });

  // Startup: first reset rows an app kill left mid-send, then flush once connectivity is known
  // (the queue refuses to send while the provider still reads "offline", which is its value
  // until the first connectivity check resolves).
  Future.microtask(() async {
    try {
      await ref.read(realSubmissionQueueProvider).recoverInterrupted();
      await ref.read(connectivityProvider.future);
    } catch (_) {
      // Connectivity check failed: fall through, the queue's own gate decides.
    }
    await flushSubmissionQueue(ref);
  });

  return cancel;
}

/// Sends every ready row plus transiently-failed rows with retry budget left. Safe to call from
/// any trigger (resume, reconnect, startup); a no-op while offline or already running.
Future<void> flushSubmissionQueue(WidgetRef ref) async {
  try {
    await ref.read(realSubmissionQueueProvider).processAll();
  } catch (_) {
    // processAll records per-draft failures itself; nothing here should crash a lifecycle hook.
  }
}
