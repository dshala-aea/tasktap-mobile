// dart format width=100
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/error_message.dart' show isTransportOrServerFault;
import '../../data/local/app_database.dart';
import '../../data/reports/import_server_report.dart';
import '../../data/reports/server_report_api_client.dart';
import '../../data/reports/ticket_controls_cache_repository.dart';
import '../../data/sync/connectivity_provider.dart' show isOnlineProvider;
import '../../data/sync/sync_service.dart' show appDatabaseProvider, syncProvider;
import '../ticket/ticket_detail_api_client.dart';

/// [importServerReport] wired to the app's providers: fetch via the shared Dio client, warm the
/// ticket-checklist cache with the same online fetch the Controlli step uses, then start one sync so
/// the materials catalog and colleagues the imported rows point at are resolvable by name.
///
/// Throws if the report cannot be fetched/imported (callers must not open a blank editor then);
/// the cache warming steps never throw.
///
/// Its one remaining caller is the Rapportini list (`rapportini_list_screen.dart`), which opens a
/// server-side **Bozza** that arrived as a header-only sync row and needs the full children fetched
/// before the editor opens — otherwise the editor's submit would replace the server's data with an
/// empty set. The AI copilot used to call it too; since I2 (spec §5.5) the copilot applies the
/// confirm response to a local Drift draft instead, because Confirm no longer creates a server
/// object to fetch. Do not delete this function on the copilot's account: the list's call is a
/// different requirement with a different failure mode.
///
/// Offline (O-8a/O-8b) the report's whole aggregate is already mirrored in Drift, so the same
/// requirement is met without a request: [importServerReportFromMirror] promotes that row to a
/// working copy. The same fallback covers an online attempt that never got an answer or hit a
/// server fault — a connected-but-unreachable phone is the common case on site. It refuses when sync never delivered the children
/// ([ServerReportNotMirroredException]) — the one case where the editor must stay shut.
/// [overwriteLocal] has no offline meaning: there is no server copy to overwrite from, and the
/// local row is already the freshest thing the phone has.
Future<void> importServerReportForEditing(
  WidgetRef ref, {
  required String reportId,
  String? cantiereId,
  bool overwriteLocal = false,
}) async {
  final db = ref.read(appDatabaseProvider);
  if (!ref.read(isOnlineProvider)) {
    await importServerReportFromMirror(db: db, reportId: reportId);
    return;
  }
  try {
    await _importFromServer(
      ref,
      db: db,
      reportId: reportId,
      cantiereId: cantiereId,
      overwriteLocal: overwriteLocal,
    );
  } catch (e, st) {
    // The radio said online and the request never got an answer, or the server faulted: the report
    // may still be mirrored in full from the last sync, and opening it from there beats the "non
    // riesco ad aprire" toast a technician standing on site would otherwise see. A 4xx is an
    // answer (gone, forbidden) and still propagates.
    if (!isTransportOrServerFault(e)) rethrow;
    try {
      await importServerReportFromMirror(db: db, reportId: reportId);
    } on ServerReportNotMirroredException {
      // Nothing mirrored either: the original failure is the more accurate thing to report.
      Error.throwWithStackTrace(e, st);
    }
  }
}

Future<void> _importFromServer(
  WidgetRef ref, {
  required AppDatabase db,
  required String reportId,
  String? cantiereId,
  required bool overwriteLocal,
}) {
  return importServerReport(
    db: db,
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
