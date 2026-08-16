// dart format width=100
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/local/app_database.dart';
import '../../data/reports/draft_report_repository.dart';
import '../../data/sync/sync_service.dart';
import '../../domain/reports/draft_validation.dart';

// ══════════════════════════════════════════════════════════════════════════════
// ReportEditorState
//
// Holds the in-progress rapportino being edited.  The editor autosaves to Drift
// on every significant change so the user can leave and resume without losing
// work.
// ══════════════════════════════════════════════════════════════════════════════

/// Which step is currently shown in the multi-step editor.
enum RapportinoStep { dati, staff, materiali, controlli, firme, allegati, review }

/// Represents one staff/technician row being edited.
class StaffRow {
  const StaffRow({
    required this.id,
    required this.userId,
    this.displayName = '',
    this.hoursWorked,
    this.kmTraveled = 0.0,
    this.vehicle,
    this.notes,
    this.startTime,
    this.endTime,
    this.pauseMinutes = 0,
    // Timer state (not persisted; recalculated on resume)
    this.timerRunning = false,
    this.timerStartedAt,
  });

  final String id;
  final String userId;
  final String displayName;
  final double? hoursWorked;
  final double kmTraveled;
  final String? vehicle;
  final String? notes;
  final DateTime? startTime;
  final DateTime? endTime;
  final int pauseMinutes;

  // Live timer fields (transient — not in Drift)
  final bool timerRunning;
  final DateTime? timerStartedAt;

  StaffRow copyWith({
    String? userId,
    String? displayName,
    double? hoursWorked,
    double? kmTraveled,
    String? vehicle,
    String? notes,
    DateTime? startTime,
    DateTime? endTime,
    int? pauseMinutes,
    bool? timerRunning,
    DateTime? timerStartedAt,
    bool clearTimer = false,
  }) {
    return StaffRow(
      id: id,
      userId: userId ?? this.userId,
      displayName: displayName ?? this.displayName,
      hoursWorked: hoursWorked ?? this.hoursWorked,
      kmTraveled: kmTraveled ?? this.kmTraveled,
      vehicle: vehicle ?? this.vehicle,
      notes: notes ?? this.notes,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      pauseMinutes: pauseMinutes ?? this.pauseMinutes,
      timerRunning: timerRunning ?? this.timerRunning,
      timerStartedAt: clearTimer ? null : (timerStartedAt ?? this.timerStartedAt),
    );
  }

  /// Effective hours from timer (start→end minus pauses), or hoursWorked.
  double get effectiveHours {
    if (startTime != null && endTime != null) {
      final worked = endTime!.difference(startTime!).inMinutes - pauseMinutes;
      return worked / 60.0;
    }
    return hoursWorked ?? 0.0;
  }
}

/// One materiale row in the editor.
class MaterialeRow {
  const MaterialeRow({
    required this.id,
    required this.reportId,
    this.materialeId, // null → free-text
    this.freeTextName,
    required this.quantity,
    this.unitOfMeasure,
    this.notes,
  });

  final String id;
  final String reportId;
  final String? materialeId;
  final String? freeTextName;
  final double quantity;
  final String? unitOfMeasure;
  final String? notes;

  String get displayName => freeTextName ?? materialeId ?? '';

  MaterialeRow copyWith({
    String? materialeId,
    String? freeTextName,
    double? quantity,
    String? unitOfMeasure,
    String? notes,
  }) {
    return MaterialeRow(
      id: id,
      reportId: reportId,
      materialeId: materialeId ?? this.materialeId,
      freeTextName: freeTextName ?? this.freeTextName,
      quantity: quantity ?? this.quantity,
      unitOfMeasure: unitOfMeasure ?? this.unitOfMeasure,
      notes: notes ?? this.notes,
    );
  }
}

/// One controllo row.
class ControlloRow {
  const ControlloRow({
    required this.id,
    required this.reportId,
    required this.controlId,
    this.stringValue,
    this.boolValue,
    this.dateValue,
  });

  final String id;
  final String reportId;
  final String controlId;
  final String? stringValue;
  final bool? boolValue;
  final DateTime? dateValue;

  ControlloRow copyWith({String? stringValue, bool? boolValue, DateTime? dateValue}) {
    return ControlloRow(
      id: id,
      reportId: reportId,
      controlId: controlId,
      stringValue: stringValue ?? this.stringValue,
      boolValue: boolValue ?? this.boolValue,
      dateValue: dateValue ?? this.dateValue,
    );
  }
}

/// One attachment/photo row.
class AllegatoRow {
  const AllegatoRow({
    required this.id,
    required this.localPath,
    required this.fileName,
    required this.contentType,
    required this.sizeBytes,
    this.isSignature = false,
  });

  final String id;
  final String localPath;
  final String fileName;
  final String contentType;
  final int sizeBytes;
  final bool isSignature;
}

/// Full editor state for one rapportino.
class ReportEditorState {
  const ReportEditorState({
    required this.reportId,
    this.currentStep = RapportinoStep.dati,
    this.title = '',
    this.details = '',
    this.customerId,
    this.customerFreeText,
    this.workAddress,
    this.locationId,
    this.locationFreeText,
    this.ticketId,
    this.ticketFreeText,
    this.cantiereId,
    this.cantiereFreeText,
    this.scheduleId,
    this.gpsLatitude,
    this.gpsLongitude,
    this.createdAt,
    this.staffRows = const [],
    this.materialeRows = const [],
    this.controlloRows = const [],
    this.materialiNotRequired = false,
    this.isAiAssisted = false,
    this.customerSignatureLocalPath,
    this.customerSignatureAllegatoId,
    this.technicianSignatureLocalPath,
    this.technicianSignatureAllegatoId,
    this.allegatoRows = const [],
    this.isSaving = false,
    this.saveError,
    this.tenantId = '',
    this.insertedUserId = '',
  });

  final String reportId;
  final RapportinoStep currentStep;

  // Step 1 — Dati
  final String title;
  final String details;
  final String? customerId;
  final String? customerFreeText;
  final String? workAddress;
  final String? locationId;
  final String? locationFreeText;
  final String? ticketId;
  final String? ticketFreeText;
  final String? cantiereId;
  final String? cantiereFreeText;
  final String? scheduleId;
  final double? gpsLatitude;
  final double? gpsLongitude;
  final DateTime? createdAt;

  // Step 2 — Staff
  final List<StaffRow> staffRows;

  // Step 3 — Materiali
  final List<MaterialeRow> materialeRows;
  final List<ControlloRow> controlloRows;
  final bool materialiNotRequired;

  /// Whether text produced by the AI draft is still in this rapportino.
  ///
  /// One-way: set when a draft is applied, and never cleared. Clearing it when the technician
  /// edits the text afterwards would be wrong — editing a generated paragraph is still working
  /// from a generated paragraph, and it would make the marker trivially removable by typing a
  /// character. The honest claim is "a model was involved in producing this", not "this is
  /// verbatim model output".
  final bool isAiAssisted;


  // Step 5 — Firme
  final String? customerSignatureLocalPath;
  final String? customerSignatureAllegatoId;
  final String? technicianSignatureLocalPath;
  final String? technicianSignatureAllegatoId;

  // Step 6 — Allegati (photos)
  final List<AllegatoRow> allegatoRows;

  // Meta
  final bool isSaving;
  final String? saveError;
  final String tenantId;
  final String insertedUserId;

  // ── Validation ────────────────────────────────────────────────────────────

  DraftValidationResult get validation => validateDraft(
    draft: _syntheticDraft,
    staffCount: staffRows.length,
    materialiCount: materialeRows.length,
    customerFreeText: customerFreeText,
  );

  bool get isReadyToSubmit => validation.isValid;

  /// Build a synthetic DraftReport for validation without hitting Drift.
  DraftReport get _syntheticDraft => DraftReport(
    id: reportId,
    tenantId: tenantId,
    createdAt: createdAt ?? DateTime.now().toUtc(),
    updatedAt: null,
    isAiAssisted: isAiAssisted,
    title: title,
    scheduleId: scheduleId,
    ticketId: ticketId,
    customerId: customerId,
    details: details.isEmpty ? null : details,
    insertedUserId: insertedUserId,
    locationId: locationId ?? '',
    startedAt: null,
    endedAt: null,
    documentTemplateId: null,
    customerSignatureAllegatoId: customerSignatureAllegatoId,
    technicianSignatureAllegatoId: technicianSignatureAllegatoId,
    technicianNotes: null,
    closedAt: null,
    stato: 'Bozza',
    inviatoAt: null,
    controllatoAt: null,
    controllatoDa: null,
    fatturatoAt: null,
    materialiNotRequired: materialiNotRequired,
    customerSignoffText: null,
    customerSignoffAt: null,
    isLocalOnly: true,
    submissionState: 'draft',
    idempotencyKey: null,
    submissionError: null,
  );

  ReportEditorState copyWith({
    RapportinoStep? currentStep,
    String? title,
    String? details,
    String? customerId,
    String? customerFreeText,
    String? workAddress,
    String? locationId,
    String? locationFreeText,
    String? ticketId,
    String? ticketFreeText,
    String? cantiereId,
    String? cantiereFreeText,
    String? scheduleId,
    double? gpsLatitude,
    double? gpsLongitude,
    DateTime? createdAt,
    List<StaffRow>? staffRows,
    List<MaterialeRow>? materialeRows,
    List<ControlloRow>? controlloRows,
    bool? materialiNotRequired,
    bool? isAiAssisted,
    String? customerSignatureLocalPath,
    String? customerSignatureAllegatoId,
    String? technicianSignatureLocalPath,
    String? technicianSignatureAllegatoId,
    List<AllegatoRow>? allegatoRows,
    bool? isSaving,
    String? saveError,
    String? tenantId,
    String? insertedUserId,
    bool clearCustomerId = false,
    bool clearLocationId = false,
    bool clearTicketId = false,
    bool clearCantiereId = false,
    bool clearCustomerFreeText = false,
    bool clearLocationFreeText = false,
    bool clearTicketFreeText = false,
    bool clearCantiereFreeText = false,
    bool clearCustomerSignature = false,
    bool clearTechnicianSignature = false,
    bool clearSaveError = false,
  }) {
    return ReportEditorState(
      reportId: reportId,
      currentStep: currentStep ?? this.currentStep,
      title: title ?? this.title,
      details: details ?? this.details,
      customerId: clearCustomerId ? null : (customerId ?? this.customerId),
      customerFreeText: clearCustomerFreeText ? null : (customerFreeText ?? this.customerFreeText),
      workAddress: workAddress ?? this.workAddress,
      locationId: clearLocationId ? null : (locationId ?? this.locationId),
      locationFreeText: clearLocationFreeText ? null : (locationFreeText ?? this.locationFreeText),
      ticketId: clearTicketId ? null : (ticketId ?? this.ticketId),
      ticketFreeText: clearTicketFreeText ? null : (ticketFreeText ?? this.ticketFreeText),
      cantiereId: clearCantiereId ? null : (cantiereId ?? this.cantiereId),
      cantiereFreeText: clearCantiereFreeText ? null : (cantiereFreeText ?? this.cantiereFreeText),
      scheduleId: scheduleId ?? this.scheduleId,
      gpsLatitude: gpsLatitude ?? this.gpsLatitude,
      gpsLongitude: gpsLongitude ?? this.gpsLongitude,
      createdAt: createdAt ?? this.createdAt,
      staffRows: staffRows ?? this.staffRows,
      materialeRows: materialeRows ?? this.materialeRows,
      controlloRows: controlloRows ?? this.controlloRows,
      materialiNotRequired: materialiNotRequired ?? this.materialiNotRequired,
      isAiAssisted: isAiAssisted ?? this.isAiAssisted,
      customerSignatureLocalPath: clearCustomerSignature
          ? null
          : (customerSignatureLocalPath ?? this.customerSignatureLocalPath),
      customerSignatureAllegatoId: clearCustomerSignature
          ? null
          : (customerSignatureAllegatoId ?? this.customerSignatureAllegatoId),
      technicianSignatureLocalPath: clearTechnicianSignature
          ? null
          : (technicianSignatureLocalPath ?? this.technicianSignatureLocalPath),
      technicianSignatureAllegatoId: clearTechnicianSignature
          ? null
          : (technicianSignatureAllegatoId ?? this.technicianSignatureAllegatoId),
      allegatoRows: allegatoRows ?? this.allegatoRows,
      isSaving: isSaving ?? this.isSaving,
      saveError: clearSaveError ? null : (saveError ?? this.saveError),
      tenantId: tenantId ?? this.tenantId,
      insertedUserId: insertedUserId ?? this.insertedUserId,
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// ReportEditorNotifier
// ══════════════════════════════════════════════════════════════════════════════

class ReportEditorNotifier extends StateNotifier<ReportEditorState> {
  ReportEditorNotifier({
    required ReportEditorState initialState,
    required DraftReportRepository repo,
  }) : _repo = repo,
       super(initialState);

  final DraftReportRepository _repo;

  // ── Step navigation ────────────────────────────────────────────────────────

  Future<void> goToStep(RapportinoStep step) async {
    state = state.copyWith(currentStep: step);
    await _autosave();
  }

  Future<void> nextStep() async {
    final steps = RapportinoStep.values;
    final idx = steps.indexOf(state.currentStep);
    if (idx < steps.length - 1) {
      await goToStep(steps[idx + 1]);
    }
  }

  Future<void> prevStep() async {
    final steps = RapportinoStep.values;
    final idx = steps.indexOf(state.currentStep);
    if (idx > 0) {
      await goToStep(steps[idx - 1]);
    }
  }

  // ── Step 1: Dati ───────────────────────────────────────────────────────────

  Future<void> setTitle(String value) async {
    state = state.copyWith(title: value);
    await _autosave();
  }

  Future<void> setDetails(String value) async {
    state = state.copyWith(details: value);
    await _autosave();
  }

  Future<void> setCustomerFromCache(String customerId) async {
    state = state.copyWith(customerId: customerId, clearCustomerFreeText: true);
    await _autosave();
  }

  Future<void> setCustomerFreeText(String name) async {
    state = state.copyWith(customerFreeText: name, clearCustomerId: true);
    await _autosave();
  }

  Future<void> setWorkAddress(String address) async {
    state = state.copyWith(workAddress: address);
    await _autosave();
  }

  Future<void> setLocationFromCache(String locationId) async {
    state = state.copyWith(locationId: locationId, clearLocationFreeText: true);
    await _autosave();
  }

  Future<void> setLocationFreeText(String name) async {
    state = state.copyWith(locationFreeText: name, clearLocationId: true);
    await _autosave();
  }

  Future<void> setTicketFromCache(String ticketId) async {
    state = state.copyWith(
      ticketId: ticketId,
      clearTicketFreeText: true,
      clearCantiereId: true,
      clearCantiereFreeText: true,
    );
    await _autosave();
  }

  Future<void> setTicketFreeText(String ref) async {
    state = state.copyWith(
      ticketFreeText: ref,
      clearTicketId: true,
      clearCantiereId: true,
      clearCantiereFreeText: true,
    );
    await _autosave();
  }

  Future<void> setCantiereFromCache(String cantiereId) async {
    state = state.copyWith(
      cantiereId: cantiereId,
      clearCantiereFreeText: true,
      clearTicketId: true,
      clearTicketFreeText: true,
    );
    await _autosave();
  }

  Future<void> setCantiereFreeText(String name) async {
    state = state.copyWith(
      cantiereFreeText: name,
      clearCantiereId: true,
      clearTicketId: true,
      clearTicketFreeText: true,
    );
    await _autosave();
  }

  void setGps(double lat, double lng) {
    state = state.copyWith(gpsLatitude: lat, gpsLongitude: lng);
    // Fire-and-forget autosave for GPS (don't await in the callback)
    _autosave();
  }

  // ── Step 2: Staff ──────────────────────────────────────────────────────────

  Future<void> addStaff(StaffRow row) async {
    final updated = [...state.staffRows, row];
    state = state.copyWith(staffRows: updated);
    await _repo.upsertStaff(_staffToCompanion(row, state.reportId, state.tenantId));
    await _autosaveHeader();
  }

  Future<void> updateStaff(StaffRow row) async {
    final updated = [for (final r in state.staffRows) r.id == row.id ? row : r];
    state = state.copyWith(staffRows: updated);
    await _repo.upsertStaff(_staffToCompanion(row, state.reportId, state.tenantId));
  }

  Future<void> removeStaff(String staffId) async {
    final updated = state.staffRows.where((r) => r.id != staffId).toList();
    state = state.copyWith(staffRows: updated);
    await _repo.deleteStaff(staffId);
    await _autosaveHeader();
  }

  /// Start on-screen travel/work timer for a staff row.
  Future<void> startTimer(String staffId) async {
    final row = state.staffRows.firstWhere((r) => r.id == staffId);
    final started = row.copyWith(
      timerRunning: true,
      timerStartedAt: DateTime.now().toUtc(),
      startTime: row.startTime ?? DateTime.now().toUtc(),
    );
    await updateStaff(started);
  }

  /// Stop on-screen timer and compute hoursWorked.
  Future<void> stopTimer(String staffId) async {
    final row = state.staffRows.firstWhere((r) => r.id == staffId);
    final now = DateTime.now().toUtc();
    final stopped = row.copyWith(
      timerRunning: false,
      endTime: now,
      hoursWorked:
          row.effectiveHours +
          (row.timerStartedAt != null ? now.difference(row.timerStartedAt!).inMinutes / 60.0 : 0.0),
      clearTimer: true,
    );
    await updateStaff(stopped);
  }

  // ── Step 3: Materiali ──────────────────────────────────────────────────────

  Future<void> addMateriale(MaterialeRow row) async {
    final updated = [...state.materialeRows, row];
    state = state.copyWith(materialeRows: updated);
    await _repo.upsertMateriale(_materialeToCompanion(row, state.tenantId));
    await _autosaveHeader();
  }

  Future<void> updateMateriale(MaterialeRow row) async {
    final updated = [for (final r in state.materialeRows) r.id == row.id ? row : r];
    state = state.copyWith(materialeRows: updated);
    await _repo.upsertMateriale(_materialeToCompanion(row, state.tenantId));
  }

  Future<void> removeMateriale(String materialeId) async {
    final updated = state.materialeRows.where((r) => r.id != materialeId).toList();
    state = state.copyWith(materialeRows: updated);
    await _repo.deleteMateriale(materialeId);
    await _autosaveHeader();
  }

  Future<void> setMaterialiNotRequired(bool value) async {
    state = state.copyWith(materialiNotRequired: value);
    await _autosave();
  }

  /// Records that an AI draft was applied to this rapportino.
  ///
  /// No matching "unset": provenance is not a preference. See [ReportEditorState.isAiAssisted].
  Future<void> markAiAssisted() async {
    if (state.isAiAssisted) return;
    state = state.copyWith(isAiAssisted: true);
    await _autosave();
  }

  // ── Step 4: Controlli ──────────────────────────────────────────────────────

  Future<void> upsertControllo(ControlloRow row) async {
    final existing = state.controlloRows.indexWhere((c) => c.id == row.id);
    List<ControlloRow> updated;
    if (existing >= 0) {
      updated = List<ControlloRow>.from(state.controlloRows);
      updated[existing] = row;
    } else {
      updated = [...state.controlloRows, row];
    }
    state = state.copyWith(controlloRows: updated);
    await _repo.upsertControllo(_controlloToCompanion(row, state.tenantId));
  }

  // ── Step 5: Firme ──────────────────────────────────────────────────────────

  Future<void> saveCustomerSignature({
    required String allegatoId,
    required Uint8List bytes,
    required String localPath,
  }) async {
    await _repo.saveSignature(
      reportId: state.reportId,
      allegatoId: allegatoId,
      tenantId: state.tenantId,
      uploadedByUserId: state.insertedUserId,
      bytes: bytes,
      localPath: localPath,
      isCustomer: true,
    );
    state = state.copyWith(
      customerSignatureLocalPath: localPath,
      customerSignatureAllegatoId: allegatoId,
    );
    await _autosave();
  }

  Future<void> saveTechnicianSignature({
    required String allegatoId,
    required Uint8List bytes,
    required String localPath,
  }) async {
    await _repo.saveSignature(
      reportId: state.reportId,
      allegatoId: allegatoId,
      tenantId: state.tenantId,
      uploadedByUserId: state.insertedUserId,
      bytes: bytes,
      localPath: localPath,
      isCustomer: false,
    );
    state = state.copyWith(
      technicianSignatureLocalPath: localPath,
      technicianSignatureAllegatoId: allegatoId,
    );
    await _autosave();
  }

  Future<void> clearCustomerSignature() async {
    if (state.customerSignatureAllegatoId != null) {
      await _repo.deleteAllegato(state.customerSignatureAllegatoId!);
    }
    state = state.copyWith(clearCustomerSignature: true);
    await _autosave();
  }

  Future<void> clearTechnicianSignature() async {
    if (state.technicianSignatureAllegatoId != null) {
      await _repo.deleteAllegato(state.technicianSignatureAllegatoId!);
    }
    state = state.copyWith(clearTechnicianSignature: true);
    await _autosave();
  }

  // ── Step 6: Allegati (photos) ──────────────────────────────────────────────

  Future<void> addAllegato(AllegatoRow row) async {
    await _repo.insertAllegato(
      ReportAllegatiCompanion.insert(
        id: row.id,
        tenantId: state.tenantId,
        createdAt: DateTime.now().toUtc(),
        fileName: row.fileName,
        contentType: row.contentType,
        sizeBytes: row.sizeBytes,
        storagePath: row.localPath,
        url: row.localPath,
        entityType: 1, // Report
        entityId: state.reportId,
        uploadedByUserId: state.insertedUserId,
        isPendingUpload: const Value(true),
      ),
    );
    state = state.copyWith(allegatoRows: [...state.allegatoRows, row]);
  }

  Future<void> removeAllegato(String allegatoId) async {
    await _repo.deleteAllegato(allegatoId);
    state = state.copyWith(
      allegatoRows: state.allegatoRows.where((a) => a.id != allegatoId).toList(),
    );
  }

  // ── Autosave ───────────────────────────────────────────────────────────────

  /// Persist the full draft header to Drift.  Child rows are saved
  /// individually in their respective methods.
  Future<void> _autosave() async {
    state = state.copyWith(isSaving: true, clearSaveError: true);
    try {
      await _repo.saveDraft(_buildHeaderCompanion());
      state = state.copyWith(isSaving: false);
    } catch (e) {
      state = state.copyWith(isSaving: false, saveError: e.toString());
    }
  }

  /// Autosave header only (not full state rebuild — used after child mutations).
  Future<void> _autosaveHeader() async {
    try {
      await _repo.saveDraft(_buildHeaderCompanion());
    } catch (_) {
      // Swallow — the child row is already saved.
    }
  }

  DraftReportsCompanion _buildHeaderCompanion() {
    return DraftReportsCompanion(
      id: Value(state.reportId),
      tenantId: Value(state.tenantId),
      createdAt: Value(state.createdAt ?? DateTime.now().toUtc()),
      updatedAt: Value(DateTime.now().toUtc()),
      title: Value(state.title),
      scheduleId: Value(state.scheduleId),
      ticketId: Value(state.ticketId),
      customerId: Value(state.customerId),
      details: Value(_buildDetailsJson()),
      insertedUserId: Value(state.insertedUserId),
      locationId: Value(state.locationId ?? ''),
      materialiNotRequired: Value(state.materialiNotRequired),
      isAiAssisted: Value(state.isAiAssisted),
      customerSignatureAllegatoId: Value(state.customerSignatureAllegatoId),
      technicianSignatureAllegatoId: Value(state.technicianSignatureAllegatoId),
      stato: const Value('Bozza'),
      isLocalOnly: const Value(true),
    );
  }

  /// Pack free-text / GPS fields into the `details` JSON column so they survive
  /// round-trips without requiring extra schema columns.
  String? _buildDetailsJson() {
    final parts = <String>[];
    if (state.customerFreeText?.isNotEmpty ?? false) {
      parts.add('"customerFreeText":"${state.customerFreeText}"');
    }
    if (state.locationFreeText?.isNotEmpty ?? false) {
      parts.add('"locationFreeText":"${state.locationFreeText}"');
    }
    if (state.ticketFreeText?.isNotEmpty ?? false) {
      parts.add('"ticketFreeText":"${state.ticketFreeText}"');
    }
    if (state.cantiereFreeText?.isNotEmpty ?? false) {
      parts.add('"cantiereFreeText":"${state.cantiereFreeText}"');
    }
    if (state.workAddress?.isNotEmpty ?? false) {
      parts.add('"workAddress":"${state.workAddress}"');
    }
    if (state.gpsLatitude != null) {
      parts.add('"gpsLatitude":${state.gpsLatitude}');
    }
    if (state.gpsLongitude != null) {
      parts.add('"gpsLongitude":${state.gpsLongitude}');
    }
    if (parts.isEmpty) return null;
    return '{${parts.join(',')}}';
  }

  // ── Static companion builders ──────────────────────────────────────────────

  static ReportStaffTableCompanion _staffToCompanion(
    StaffRow row,
    String reportId,
    String tenantId,
  ) {
    return ReportStaffTableCompanion(
      id: Value(row.id),
      tenantId: Value(tenantId),
      createdAt: Value(DateTime.now().toUtc()),
      updatedAt: Value(DateTime.now().toUtc()),
      reportId: Value(reportId),
      userId: Value(row.userId),
      hoursWorked: Value(row.effectiveHours > 0 ? row.effectiveHours : row.hoursWorked),
      kmTraveled: Value(row.kmTraveled),
      vehicle: Value(row.vehicle),
      notes: Value(row.notes),
      startTime: Value(row.startTime),
      endTime: Value(row.endTime),
      pauseMinutes: Value(row.pauseMinutes),
    );
  }

  static ReportMaterialiCompanion _materialeToCompanion(MaterialeRow row, String tenantId) {
    return ReportMaterialiCompanion(
      id: Value(row.id),
      tenantId: Value(tenantId),
      createdAt: Value(DateTime.now().toUtc()),
      updatedAt: Value(DateTime.now().toUtc()),
      reportId: Value(row.reportId),
      materialeId: Value(row.materialeId),
      freeTextName: Value(row.freeTextName),
      quantity: Value(row.quantity),
      unitOfMeasure: Value(row.unitOfMeasure),
      notes: Value(row.notes),
    );
  }

  static ReportControlliCompanion _controlloToCompanion(ControlloRow row, String tenantId) {
    return ReportControlliCompanion(
      id: Value(row.id),
      tenantId: Value(tenantId),
      createdAt: Value(DateTime.now().toUtc()),
      updatedAt: Value(DateTime.now().toUtc()),
      reportId: Value(row.reportId),
      controlId: Value(row.controlId),
      stringValue: Value(row.stringValue),
      boolValue: Value(row.boolValue),
      dateValue: Value(row.dateValue),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Providers
// ══════════════════════════════════════════════════════════════════════════════

/// Provides the DraftReportRepository.
final draftReportRepositoryProvider = Provider<DraftReportRepository>((ref) {
  return DraftReportRepository(ref.watch(appDatabaseProvider));
});

/// Family provider: opens an editor for a given report id.
/// Pass [ReportEditorArgs] to distinguish "new" from "resume".
class ReportEditorArgs {
  const ReportEditorArgs({
    required this.reportId,
    required this.tenantId,
    required this.userId,
    this.prefillFromScheduleId,
  });

  final String reportId;
  final String tenantId;
  final String userId;
  final String? prefillFromScheduleId;
}

/// StateNotifierProvider.family keyed by report id string.
final reportEditorProvider = StateNotifierProvider.autoDispose
    .family<ReportEditorNotifier, ReportEditorState, String>((ref, reportId) {
      final repo = ref.watch(draftReportRepositoryProvider);
      return ReportEditorNotifier(
        initialState: ReportEditorState(reportId: reportId),
        repo: repo,
      );
    });
