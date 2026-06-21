// dart format width=100
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
// offline→online transition automatically attempts to flush the queue.
//
// Call [initSubmissionQueueWatcher] once from the root widget (after auth).
// ══════════════════════════════════════════════════════════════════════════════

/// Provides a [SubmissionQueue] backed by real Drift + Dio.
final realSubmissionQueueProvider = Provider<SubmissionQueue>((ref) {
  final repo = ref.watch(draftReportRepositoryProvider);
  final dio = ref.watch(dioProvider);
  final apiClient = ReportSubmitApiClient(dio);
  return SubmissionQueue(repo: repo, apiClient: apiClient);
});

/// Call once on app start (e.g. in main or the root widget).
/// Registers the reconnect → processAll hook.
void initSubmissionQueueWatcher(WidgetRef ref) {
  final connectivity = ref.read(connectivityProvider.notifier);
  connectivity.onReconnect(() {
    final queue = ref.read(realSubmissionQueueProvider);
    queue.processAll();
  });

  // Also attempt to flush on startup in case drafts are ready and we're online.
  void flush() {
    final queue = ref.read(realSubmissionQueueProvider);
    queue.processAll();
  }

  // Flush once after the first frame.
  Future.microtask(flush);
}
