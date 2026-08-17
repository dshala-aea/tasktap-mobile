// dart format width=100
import 'package:drift/drift.dart';
import '../local/app_database.dart';
import '../sync/draft_submission_state.dart';

// ══════════════════════════════════════════════════════════════════════════════
// DraftReportRepository
//
// All CRUD for draft_reports + child tables (staff, materiali, controlli,
// allegati).  Everything runs against the local Drift DB — zero network.
// ══════════════════════════════════════════════════════════════════════════════

class DraftReportRepository {
  DraftReportRepository(this._db);

  final AppDatabase _db;

  // ── Draft header ───────────────────────────────────────────────────────────

  /// Create a new local-only draft, returning its id.
  Future<String> createDraft(DraftReportsCompanion companion) async {
    await _db.into(_db.draftReports).insert(companion);
    return companion.id.value;
  }

  /// Upsert the draft header (used for autosave on every field change).
  Future<void> saveDraft(DraftReportsCompanion companion) async {
    await _db.into(_db.draftReports).insertOnConflictUpdate(companion);
  }

  /// Load a single draft by id.
  Future<DraftReport?> getDraft(String id) async {
    return (_db.select(_db.draftReports)..where((r) => r.id.equals(id))).getSingleOrNull();
  }

  /// Stream a single draft (reactive — re-emits on every save).
  Stream<DraftReport?> watchDraft(String id) {
    return (_db.select(_db.draftReports)..where((r) => r.id.equals(id))).watchSingleOrNull();
  }

  /// Stream all local-only drafts, newest first.
  Stream<List<DraftReport>> watchLocalDrafts() {
    return (_db.select(_db.draftReports)
          ..where((r) => r.isLocalOnly.equals(true))
          ..orderBy([(r) => OrderingTerm.desc(r.updatedAt)]))
        .watch();
  }

  /// Delete a draft and all its children.
  Future<void> deleteDraft(String reportId) async {
    await _db.transaction(() async {
      await (_db.delete(_db.reportStaffTable)..where((s) => s.reportId.equals(reportId))).go();
      await (_db.delete(_db.reportMateriali)..where((m) => m.reportId.equals(reportId))).go();
      await (_db.delete(_db.reportControlli)..where((c) => c.reportId.equals(reportId))).go();
      await (_db.delete(_db.reportAllegati)..where((a) => a.entityId.equals(reportId))).go();
      await (_db.delete(_db.draftReports)..where((r) => r.id.equals(reportId))).go();
    });
  }

  // ── Staff ──────────────────────────────────────────────────────────────────

  Future<void> upsertStaff(ReportStaffTableCompanion companion) async {
    await _db.into(_db.reportStaffTable).insertOnConflictUpdate(companion);
  }

  Future<void> deleteStaff(String staffId) async {
    await (_db.delete(_db.reportStaffTable)..where((s) => s.id.equals(staffId))).go();
  }

  Future<List<ReportStaffTableData>> getStaff(String reportId) async {
    return (_db.select(_db.reportStaffTable)..where((s) => s.reportId.equals(reportId))).get();
  }

  Stream<List<ReportStaffTableData>> watchStaff(String reportId) {
    return (_db.select(_db.reportStaffTable)
          ..where((s) => s.reportId.equals(reportId))
          ..orderBy([(s) => OrderingTerm.asc(s.createdAt)]))
        .watch();
  }

  // ── Materiali ──────────────────────────────────────────────────────────────

  Future<void> upsertMateriale(ReportMaterialiCompanion companion) async {
    await _db.into(_db.reportMateriali).insertOnConflictUpdate(companion);
  }

  Future<void> deleteMateriale(String materialeId) async {
    await (_db.delete(_db.reportMateriali)..where((m) => m.id.equals(materialeId))).go();
  }

  Future<List<ReportMaterialiData>> getMateriali(String reportId) async {
    return (_db.select(_db.reportMateriali)..where((m) => m.reportId.equals(reportId))).get();
  }

  Stream<List<ReportMaterialiData>> watchMateriali(String reportId) {
    return (_db.select(_db.reportMateriali)
          ..where((m) => m.reportId.equals(reportId))
          ..orderBy([(m) => OrderingTerm.asc(m.createdAt)]))
        .watch();
  }

  // ── Controlli ──────────────────────────────────────────────────────────────

  Future<void> upsertControllo(ReportControlliCompanion companion) async {
    await _db.into(_db.reportControlli).insertOnConflictUpdate(companion);
  }

  Future<List<ReportControlliData>> getControlli(String reportId) async {
    return (_db.select(_db.reportControlli)..where((c) => c.reportId.equals(reportId))).get();
  }

  Stream<List<ReportControlliData>> watchControlli(String reportId) {
    return (_db.select(_db.reportControlli)..where((c) => c.reportId.equals(reportId))).watch();
  }

  // ── Allegati ───────────────────────────────────────────────────────────────

  Future<void> insertAllegato(ReportAllegatiCompanion companion) async {
    await _db.into(_db.reportAllegati).insert(companion);
  }

  Future<void> deleteAllegato(String allegatoId) async {
    await (_db.delete(_db.reportAllegati)..where((a) => a.id.equals(allegatoId))).go();
  }

  Future<List<ReportAllegatiData>> getAllegati(String reportId) async {
    return (_db.select(_db.reportAllegati)..where((a) => a.entityId.equals(reportId))).get();
  }

  Stream<List<ReportAllegatiData>> watchAllegati(String reportId) {
    return (_db.select(_db.reportAllegati)
          ..where((a) => a.entityId.equals(reportId))
          ..orderBy([(a) => OrderingTerm.asc(a.createdAt)]))
        .watch();
  }

  // ── Signature helpers ──────────────────────────────────────────────────────
  // Signatures are stored as allegati with special content types.
  // Returns the allegato id so the draft header can reference it.

  // ── Submission state ───────────────────────────────────────────────────────

  /// Update the submission state machine field on a draft.
  /// Only the provided fields are changed; others remain untouched.
  Future<void> updateSubmissionState({
    required String reportId,
    required DraftSubmissionState state,
    String? idempotencyKey,
    String? error,
    bool clearError = false,
  }) async {
    final companion = DraftReportsCompanion(
      id: Value(reportId),
      submissionState: Value(state.toPersistedString()),
      updatedAt: Value(DateTime.now().toUtc()),
      idempotencyKey: idempotencyKey != null ? Value(idempotencyKey) : const Value.absent(),
      submissionError: clearError || error == null ? const Value(null) : Value(error),
    );
    await (_db.update(_db.draftReports)..where((r) => r.id.equals(reportId))).write(companion);
  }

  /// Fetch all drafts currently in [readyToSubmit] state.
  Future<List<DraftReport>> getDraftsReadyToSubmit() async {
    return (_db.select(_db.draftReports)..where(
          (r) => r.submissionState.equals(DraftSubmissionState.readyToSubmit.toPersistedString()),
        ))
        .get();
  }

  /// Return all [ReportAllegatiData] for [reportId] that are still pending upload.
  Future<List<ReportAllegatiData>> getPendingAllegati(String reportId) async {
    return (_db.select(
      _db.reportAllegati,
    )..where((a) => a.entityId.equals(reportId) & a.isPendingUpload.equals(true))).get();
  }

  /// Mark an allegato as uploaded; replace its local id with the server id.
  Future<void> markAllegatoUploaded({
    required String localId,
    required String serverAllegatoId,
  }) async {
    // If the server echoed the same id, just clear the flag.
    if (localId == serverAllegatoId) {
      await (_db.update(_db.reportAllegati)..where((a) => a.id.equals(localId))).write(
        const ReportAllegatiCompanion(isPendingUpload: Value(false)),
      );
      return;
    }
    // Otherwise replace the row with a new id (server assigned a different UUID).
    final existing = await (_db.select(
      _db.reportAllegati,
    )..where((a) => a.id.equals(localId))).getSingleOrNull();
    if (existing == null) return;

    await _db.transaction(() async {
      await (_db.delete(_db.reportAllegati)..where((a) => a.id.equals(localId))).go();
      await _db
          .into(_db.reportAllegati)
          .insert(
            existing
                .toCompanion(true)
                .copyWith(id: Value(serverAllegatoId), isPendingUpload: const Value(false)),
          );
    });
  }

  /// Update the draft header's signature allegato id after a successful upload.
  Future<void> updateSignatureAllegatoId({
    required String reportId,
    required bool isCustomer,
    required String serverAllegatoId,
  }) async {
    final companion = isCustomer
        ? DraftReportsCompanion(
            customerSignatureAllegatoId: Value(serverAllegatoId),
            updatedAt: Value(DateTime.now().toUtc()),
          )
        : DraftReportsCompanion(
            technicianSignatureAllegatoId: Value(serverAllegatoId),
            updatedAt: Value(DateTime.now().toUtc()),
          );
    await (_db.update(_db.draftReports)..where((r) => r.id.equals(reportId))).write(companion);
  }

  /// Mark a draft as submitted (clear isLocalOnly flag).
  Future<void> markSubmitted(String reportId) async {
    await (_db.update(_db.draftReports)..where((r) => r.id.equals(reportId))).write(
      DraftReportsCompanion(
        isLocalOnly: const Value(false),
        stato: const Value('Inviato'),
        updatedAt: Value(DateTime.now().toUtc()),
      ),
    );
  }

  // ── Signature helpers ──────────────────────────────────────────────────────
  // Signatures are stored as allegati with special content types.
  // Returns the allegato id so the draft header can reference it.

  Future<String> saveSignature({
    required String reportId,
    required String allegatoId,
    required String tenantId,
    required String uploadedByUserId,
    required Uint8List bytes,
    required String localPath,
    required bool isCustomer,
  }) async {
    final companion = ReportAllegatiCompanion.insert(
      id: allegatoId,
      tenantId: tenantId,
      createdAt: DateTime.now().toUtc(),
      fileName: isCustomer ? 'firma_cliente.png' : 'firma_tecnico.png',
      contentType: 'image/png',
      sizeBytes: bytes.length,
      storagePath: localPath,
      url: localPath,
      entityType: 1, // Report
      entityId: reportId,
      uploadedByUserId: uploadedByUserId,
      isPendingUpload: const Value(true),
    );
    await _db.into(_db.reportAllegati).insertOnConflictUpdate(companion);
    return allegatoId;
  }
}
