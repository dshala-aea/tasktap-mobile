// dart format width=100
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/reports/import_server_report.dart';
import '../../data/reports/server_report_api_client.dart';
import '../../data/reports/ticket_controls_cache_repository.dart';
import '../../data/sync/sync_service.dart' show appDatabaseProvider, syncProvider;
import '../ticket/ticket_detail_api_client.dart';

/// [importServerReport] wired to the app's providers: fetch via the shared Dio client, warm the
/// ticket-checklist cache with the same online fetch the Controlli step uses, then start one sync so
/// the materials catalog and colleagues the imported rows point at are resolvable by name.
///
/// Throws if the report cannot be fetched/imported (callers must not open a blank editor then);
/// the cache warming steps never throw.
Future<void> importServerReportForEditing(
  WidgetRef ref, {
  required String reportId,
  String? cantiereId,
  bool overwriteLocal = false,
}) {
  return importServerReport(
    db: ref.read(appDatabaseProvider),
    api: ref.read(serverReportApiClientProvider),
    reportId: reportId,
    cantiereId: cantiereId,
    overwriteLocal: overwriteLocal,
    prefetchControls: (ticketId) async {
      final groups = await ref.read(ticketDetailApiClientProvider).fetchControls(ticketId);
      await ref.read(ticketControlsCacheRepositoryProvider).cacheControls(ticketId, groups);
    },
    // Fire-and-forget: a sync can take long on a weak connection and must not delay (or fail)
    // opening a report whose data is already safely in Drift. Names fill in as the sync lands.
    refreshLookups: () async {
      unawaited(ref.read(syncProvider.notifier).performSync());
    },
  );
}
