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
// Why it exists: the editor hydrates only from Drift, and `POST /api/reports/submit` replaces the
// server's children with whatever the phone holds. Opening a report the phone does not fully hold
// either shows a blank editor or, worse, lets the technician submit a partial one that deletes the
// server's data. So the phone must hold the FULL report before the editor opens. Sync used to
// deliver report HEADERS only, which is why this fetch existed; O-8a now mirrors the whole
// aggregate for every in-scope report, so the offline case is served by
// [importServerReportFromMirror] below and the fetch is the online refresh.
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
  String toString() => 'Questo rapporto di intervento non è più modificabile.';
}

/// The full report is not on this device: sync never delivered its children (an older backend, or a
/// report outside the synced scope), so it cannot be opened here without a fetch.
class ServerReportNotMirroredException implements Exception {
  const ServerReportNotMirroredException();
  @override
  String toString() => 'I dati completi di questo rapporto di intervento non sono sul telefono.';
}

/// Row id the Controlli step uses for the answer to one checklist item
/// (step_materiali_fold.dart `_rowId`). Any other scheme makes the first edit insert a second
/// row for the same TicketControl.
String controlRowId(String reportId, String ticketControlId) =>
    'ctrl-$reportId-$ticketControlId';

/// Promote a server-authored Bozza that ALREADY arrived complete (O-8a: sync delivers every
/// in-scope report's staff, materiali, controlli and version) to a working copy, with no request.
///
/// [importServerReport] exists because a header-only row must not be opened: its submit would
/// replace the server's children with the phone's empty set. Now that the aggregate is mirrored,
/// the same report can be opened offline — the phone already holds those children.
///
/// Two preconditions, both refusals rather than best-effort:
///   * `expectedVersion` must be set. `SyncService._applyReportAggregate` writes it exactly for the
///     reports whose complete child set the payload carries, so it is this device's only evidence
///     that "no children here" means "no children on the server" and not "never delivered".
///   * the row must still be a Bozza: anything further along must not be resubmitted from a stale
///     copy, the same rule [importServerReport] applies to the server's answer.
///
/// Controlli rows are re-keyed to [controlRowId]: sync writes the server's row ids, and the editor
/// writes by its own convention, so leaving them would make the first edit insert a second answer
/// for the same checklist item. Staff and materiali keep their server ids — the editor keys those
/// by the row it was handed.
Future<void> importServerReportFromMirror({
  required AppDatabase db,
  required String reportId,
}) async {
  final local = await (db.select(db.draftReports)..where((r) => r.id.equals(reportId)))
      .getSingleOrNull();
  if (local == null) throw const ServerReportNotMirroredException();
  if (local.isLocalOnly) return;
  if (local.stato != 'Bozza') throw const ServerReportNotEditableException();
  if (local.expectedVersion == null) throw const ServerReportNotMirroredException();

  final now = DateTime.now().toUtc();
  await db.transaction(() async {
    final controlli =
        await (db.select(db.reportControlli)..where((c) => c.reportId.equals(reportId))).get();
    for (final c in controlli) {
      final keyed = controlRowId(reportId, c.controlId);
      if (c.id == keyed) continue;
      await (db.delete(db.reportControlli)..where((r) => r.id.equals(c.id))).go();
      await db
          .into(db.reportControlli)
          .insertOnConflictUpdate(
            ReportControlliCompanion.insert(
              id: keyed,
              tenantId: c.tenantId,
              createdAt: c.createdAt,
              updatedAt: Value(c.updatedAt),
              reportId: reportId,
              controlId: c.controlId,
              stringValue: Value(c.stringValue),
              boolValue: Value(c.boolValue),
              dateValue: Value(c.dateValue),
              numberValue: Value(c.numberValue),
              note: Value(c.note),
            ),
          );
    }

    await (db.update(db.draftReports)..where((r) => r.id.equals(reportId))).write(
      DraftReportsCompanion(
        updatedAt: Value(now),
        // Same meaning as the online import: the row is now this device's working copy, so the
        // sync tick neither overwrites it nor prunes its children. `expectedVersion` is left as the
        // sync wrote it — it is the version the phone last saw, and submit compares against it.
        isLocalOnly: const Value(true),
        submissionState: const Value('draft'),
        submissionError: const Value(null),
        submissionAttempts: const Value(0),
        submissionErrorTransient: const Value(false),
      ),
    );
  });
}

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
            // "Il cliente non può firmare": mirrored so a report opened from the server keeps the
            // reason instead of looking like an unsigned report with no explanation. The server
            // guarantees a report never carries both, but the signed signature wins here anyway —
            // the invariant the whole feature rests on is worth enforcing at the boundary.
            customerSignatureAbsenceReason: Value(
              report.customerSignatureAllegatoId == null
                  ? report.customerSignatureAbsenceReason?.wireValue
                  : null,
            ),
            customerSignatureAbsenceNote: Value(
              report.customerSignatureAllegatoId == null
                  ? report.customerSignatureAbsenceNote
                  : null,
            ),
            customerSignoffText: Value(report.customerSignoffText),
            materialiNotRequired: Value(report.materialiNotRequired),
            isAiAssisted: Value(report.isAiAssisted),
            // The stale-submit guard: the version of the server copy the phone is mirroring right
            // now. This is the one moment the phone *sees* the server's row, so it is the only
            // place this value may be captured — never fetched again at submit time, or the guard
            // would compare a version against itself and detect nothing. The editor's autosaves
            // never touch this column (their companion omits it), so it survives hours of offline
            // editing and goes out unchanged on submit.
            expectedVersion: Value(report.version),
            stato: const Value('Bozza'),
            isLocalOnly: const Value(true),
            submissionState: const Value('draft'),
            submissionError: const Value(null),
            submissionAttempts: const Value(0),
            submissionErrorTransient: const Value(false),
          ),
        );

    await (db.delete(db.reportStaffTable)..where((s) => s.reportId.equals(reportId))).go();
    // The staff rows are recreated below with new ids but the same user ids, so any interval that
    // survived would re-attach to a colleague whose hours now come from the server — and
    // `effectiveHours` prefers those intervals over the server's own number. Nothing imports
    // intervals here on purpose: this payload does not carry them.
    await (db.delete(db.reportStaffSegments)..where((g) => g.reportId.equals(reportId))).go();
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
