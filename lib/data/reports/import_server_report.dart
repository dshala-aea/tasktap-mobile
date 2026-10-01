// dart format width=100
import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:uuid/uuid.dart';

import '../local/app_database.dart';
import 'server_report_api_client.dart';

// ══════════════════════════════════════════════════════════════════════════════
// importServerReport — make a report that was created SERVER-side (the AI copilot's Confirm, or a
// Bozza authored on another device) editable on this phone.
//
// Why it exists: the editor hydrates only from Drift, sync delivers only report HEADERS (no
// staff / materiali / controlli), and `POST /api/reports/submit` replaces the server's children
// with whatever the phone holds. Opening such a report without importing it either shows a blank
// editor or, worse, lets the technician submit a partial one that deletes the server's data. So
// the phone must hold the FULL report before the editor opens.
//
// isLocalOnly = true, deliberately:
//   * SyncService._upsertDraftReports skips rows with isLocalOnly, so a later 60 s sync tick can
//     neither overwrite what the technician edits nor reset the header to the server's copy while
//     the children stay local.
//   * The editor's autosave writes isLocalOnly=true on its very first save anyway; importing with
//     the same value keeps the row's meaning stable instead of flipping it on first keystroke.
//   * Rapportini list "local drafts" and the submission queue treat the row like any other draft;
//     `markSubmitted` clears the flag after a successful submit, after which sync owns it again.
// ══════════════════════════════════════════════════════════════════════════════

const _uuid = Uuid();

/// The server copy is not a Bozza (already submitted/checked/...): it must not be opened as an
/// editable draft, and importing it would let a stale phone copy be resubmitted.
class ServerReportNotEditableException implements Exception {
  const ServerReportNotEditableException();
  @override
  String toString() => 'Questo rapportino non è più modificabile.';
}

/// Row id the Controlli step uses for the answer to one checklist item
/// (step_materiali_fold.dart `_rowId`). Any other scheme makes the first edit insert a second
/// row for the same TicketControl.
String controlRowId(String reportId, String ticketControlId) =>
    'ctrl-$reportId-$ticketControlId';

/// Fetch report [reportId] and mirror it into Drift in ONE transaction (header with the server id
/// + children replaced). Throws on fetch failure, or [ServerReportNotEditableException]; in both
/// cases nothing is written.
///
/// A local row with isLocalOnly=true is already this device's working copy (an earlier import, or
/// the technician's edits): it is left untouched and no request is made, unless [overwriteLocal].
///
/// [cantiereId] is supplied by the caller because GET /api/Reports/{id} does not return it.
/// [prefetchControls] / [refreshLookups] are best-effort and never fail the import: they warm the
/// caches (ticket checklist, materials catalog, colleagues) the editor resolves names against.
Future<void> importServerReport({
  required AppDatabase db,
  required ServerReportApiClient api,
  required String reportId,
  String? cantiereId,
  bool overwriteLocal = false,
  Future<void> Function(String ticketId)? prefetchControls,
  Future<void> Function()? refreshLookups,
}) async {
  if (!overwriteLocal) {
    final local = await (db.select(db.draftReports)..where((r) => r.id.equals(reportId)))
        .getSingleOrNull();
    if (local != null && local.isLocalOnly) return;
  }

  final report = await api.fetchReport(reportId);
  if (!report.isBozza) throw const ServerReportNotEditableException();

  final now = DateTime.now().toUtc();
  await db.transaction(() async {
    await db
        .into(db.draftReports)
        .insertOnConflictUpdate(
          DraftReportsCompanion(
            id: Value(report.id),
            tenantId: Value(report.tenantId),
            createdAt: Value(report.createdAt ?? now),
            updatedAt: Value(now),
            title: Value(report.title),
            scheduleId: Value(report.scheduleId),
            ticketId: Value(report.ticketId),
            customerId: Value(report.customerId),
            // Only overwrite the link when the caller knows it: the GET omits it, and a null
            // here would erase a cantiereId a header sync already delivered.
            cantiereId: cantiereId == null ? const Value.absent() : Value(cantiereId),
            details: Value(report.details),
            diagnosi: Value(report.diagnosi),
            soluzione: Value(report.soluzione),
            insertedUserId: Value(report.insertedUserId),
            locationId: Value(report.locationId),
            startedAt: Value(report.startedAt),
            endedAt: Value(report.endedAt),
            technicianNotes: Value(report.technicianNotes),
            customerSignoffText: Value(report.customerSignoffText),
            materialiNotRequired: Value(report.materialiNotRequired),
            isAiAssisted: Value(report.isAiAssisted),
            stato: const Value('Bozza'),
            isLocalOnly: const Value(true),
            submissionState: const Value('draft'),
            submissionError: const Value(null),
            submissionAttempts: const Value(0),
            submissionErrorTransient: const Value(false),
          ),
        );

    await (db.delete(db.reportStaffTable)..where((s) => s.reportId.equals(reportId))).go();
    await (db.delete(db.reportMateriali)..where((m) => m.reportId.equals(reportId))).go();
    await (db.delete(db.reportControlli)..where((c) => c.reportId.equals(reportId))).go();

    for (final s in report.staff) {
      await db
          .into(db.reportStaffTable)
          .insert(
            ReportStaffTableCompanion.insert(
              id: _uuid.v4(),
              tenantId: report.tenantId,
              createdAt: now,
              reportId: reportId,
              userId: s.userId,
              hoursWorked: Value(s.hoursWorked),
              kmTraveled: Value(s.kmTraveled),
              vehicle: Value(s.vehicle),
              costPerKm: Value(s.costPerKm),
              notes: Value(s.notes),
              startTime: Value(s.startTime),
              endTime: Value(s.endTime),
              pauseMinutes: Value(s.pauseMinutes),
            ),
          );
    }
    for (final m in report.materiali) {
      await db
          .into(db.reportMateriali)
          .insert(
            ReportMaterialiCompanion.insert(
              id: _uuid.v4(),
              tenantId: report.tenantId,
              createdAt: now,
              reportId: reportId,
              materialeId: Value(m.materialeId),
              freeTextName: Value(m.freeTextName),
              quantity: m.quantity,
              unitOfMeasure: Value(m.unitOfMeasure),
              unitPrice: Value(m.unitPrice),
              notes: Value(m.notes),
              magazzinoId: Value(m.magazzinoId),
            ),
          );
    }
    for (final o in report.observations) {
      await db
          .into(db.reportControlli)
          .insertOnConflictUpdate(
            ReportControlliCompanion.insert(
              id: controlRowId(reportId, o.ticketControlId),
              tenantId: report.tenantId,
              createdAt: now,
              reportId: reportId,
              controlId: o.ticketControlId,
              stringValue: Value(o.stringValue),
              boolValue: Value(o.boolValue),
              dateValue: Value(o.dateValue),
              numberValue: Value(o.numberValue),
            ),
          );
    }
  });

  // Best-effort cache warming, after the data is safely committed.
  final ticketId = report.ticketId;
  if (prefetchControls != null && ticketId != null) {
    try {
      await prefetchControls(ticketId);
    } catch (e) {
      debugPrint('importServerReport: checklist prefetch failed ($e); editor falls back to cache');
    }
  }
  if (refreshLookups != null) {
    try {
      await refreshLookups();
    } catch (e) {
      debugPrint('importServerReport: lookup refresh failed ($e)');
    }
  }
}
