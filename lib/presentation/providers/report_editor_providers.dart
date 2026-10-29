// dart format width=100
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/location/location_service.dart';
import '../../data/local/app_database.dart';
import '../../data/reports/draft_report_repository.dart';
import '../../data/sync/sync_service.dart';
import '../../domain/reports/customer_signature_absence_reason.dart';
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

/// One recorded work interval, as the device holds it.
///
/// [id] doubles as the wire `clientId`: it is the phone's own name for this tap, so a replayed
/// submit collapses server-side instead of counting the hours twice.
class StaffSegment {
  const StaffSegment({required this.id, required this.startUtc, required this.endUtc});

  final String id;
  final DateTime startUtc;
  final DateTime endUtc;

  Duration get duration => endUtc.difference(startUtc);
}

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
    this.segments = const [],
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

  /// The intervals this row's hours were measured from, in no particular order (the sum does not
  /// care). Empty for a row whose hours came from the office, a manual edit, or a client older
  /// than this table. Emptiness is meant to be the editor's only evidence that these hours were
  /// not measured here — where there is no interval there is nothing this device could have timed,
  /// so the hours are not its to re-derive.
  final List<StaffSegment> segments;

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
    List<StaffSegment>? segments,
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
      segments: segments ?? this.segments,
      timerRunning: timerRunning ?? this.timerRunning,
      timerStartedAt: clearTimer ? null : (timerStartedAt ?? this.timerStartedAt),
    );
  }

  /// Effective hours: the sum of the recorded intervals when there are any, else `hoursWorked`,
  /// else the timer's start→end span minus pauses.
  ///
  /// The intervals outrank `hoursWorked` because they are the evidence it is merely summarising:
  /// they are what the timer actually measured, so they exclude the idle gap between a stop and a
  /// later restart that the raw span would include (startTime is pinned to the very first start,
  /// and only [pauseMinutes] — never surfaced in the UI — could subtract it).
  ///
  /// `hoursWorked` still wins over the span whenever there are no intervals, and not just as a
  /// no-timer fallback: a manual "Ore" edit only ever touches `hoursWorked` (see step_ore.dart) —
  /// if the span won instead, that edit would render in the field but be silently ignored
  /// everywhere it's actually used (the total, the DB save, the submit payload).
  double get effectiveHours {
    if (segments.isNotEmpty) {
      // Summed in milliseconds and divided once: `inMinutes` truncates per interval, so k
      // sub-minute runs would otherwise contribute nothing at all — silently unpaid time.
      final millis = segments.fold<int>(0, (sum, s) => sum + s.duration.inMilliseconds);
      return millis / 3600000.0;
    }
    if (hoursWorked != null) return hoursWorked!;
    if (startTime != null && endTime != null) {
      final worked = endTime!.difference(startTime!).inMinutes - pauseMinutes;
      return worked / 60.0;
    }
    return 0.0;
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
    this.magazzinoId,
  });

  final String id;
  final String reportId;
  final String? materialeId;
  final String? freeTextName;
  final double quantity;
  final String? unitOfMeasure;
  final String? notes;

  /// Which warehouse this line was taken from — required for the server's
  /// `StockMovementService` to actually deplete stock on submit (it silently
  /// no-ops when this is null). Defaults to the technician's assigned
  /// furgone; see `_showAddMaterialeDialog` in step_materiali_fold.dart.
  final String? magazzinoId;

  String get displayName => freeTextName ?? materialeId ?? '';

  MaterialeRow copyWith({
    String? materialeId,
    String? freeTextName,
    double? quantity,
    String? unitOfMeasure,
    String? notes,
    String? magazzinoId,
  }) {
    return MaterialeRow(
      id: id,
      reportId: reportId,
      materialeId: materialeId ?? this.materialeId,
      freeTextName: freeTextName ?? this.freeTextName,
      quantity: quantity ?? this.quantity,
      unitOfMeasure: unitOfMeasure ?? this.unitOfMeasure,
      notes: notes ?? this.notes,
      magazzinoId: magazzinoId ?? this.magazzinoId,
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
    this.numberValue,
    this.note,
    this.controlLabel,
    this.assetId,
  });

  final String id;
  final String reportId;
  final String controlId;
  final String? stringValue;
  final bool? boolValue;
  final DateTime? dateValue;
  final double? numberValue;

  /// Per-answer remark (backend `ReportControlObservation.Note`, max 2000). A note is not itself an
  /// answer; a blank/omitted note never erases a stored one server-side.
  final String? note;

  /// The control's label and asset as the checklist showed them when this answer was typed.
  ///
  /// Persisted with the answer (see `ReportControlli.controlLabel`) because the server's copy of a
  /// report holds only the control id: without a snapshot, the sent report could only be read back
  /// on a device that still had the ticket's checklist, and printed GUIDs everywhere else.
  final String? controlLabel;
  final String? assetId;

  ControlloRow copyWith({
    String? stringValue,
    bool? boolValue,
    DateTime? dateValue,
    double? numberValue,
    String? note,
    bool clearNote = false,
    String? controlLabel,
    String? assetId,
  }) {
    return ControlloRow(
      id: id,
      reportId: reportId,
      controlId: controlId,
      stringValue: stringValue ?? this.stringValue,
      boolValue: boolValue ?? this.boolValue,
      dateValue: dateValue ?? this.dateValue,
      numberValue: numberValue ?? this.numberValue,
      note: clearNote ? null : (note ?? this.note),
      controlLabel: controlLabel ?? this.controlLabel,
      assetId: assetId ?? this.assetId,
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
    this.diagnosi,
    this.soluzione,
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
    this.richiedeSecondoIntervento = false,
    this.customerSignatureLocalPath,
    this.customerSignatureAllegatoId,
    this.customerSignatureAbsenceReason,
    this.customerSignatureAbsenceNote,
    this.technicianSignatureLocalPath,
    this.technicianSignatureAllegatoId,
    this.technicianSignaturePrefillSuppressed = false,
    this.customerSignoffText,
    this.allegatoRows = const [],
    this.isSaving = false,
    this.saveError,
    this.tenantId = '',
    this.insertedUserId = '',
    this.isLoading = false,
  });

  final String reportId;
  final RapportinoStep currentStep;

  // Step 1 — Dati
  final String title;
  final String details;

  /// Diagnosi / Soluzione. Tri-state like the Drift columns they mirror: null = never touched
  /// (submit omits it, the server keeps its value, e.g. text from an AI-confirmed report),
  /// '' = the technician cleared it, anything else replaces it.
  final String? diagnosi;
  final String? soluzione;
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

  /// "Da tornare" / "Serve un secondo intervento" — see `DraftReports
  /// .richiedeSecondoIntervento`'s own doc comment. Only meaningful when [ticketId] is set: a
  /// rapportino with no linked ticket has nothing for the backend to transition.
  final bool richiedeSecondoIntervento;

  // Step 5 — Firme
  final String? customerSignatureLocalPath;
  final String? customerSignatureAllegatoId;

  /// Why the customer did not sign ("Il cliente non può firmare"), or null when the customer
  /// signed or nothing was recorded. Mutually exclusive with [customerSignatureAllegatoId]; see
  /// `DraftReports.customerSignatureAbsenceReason`'s doc comment.
  final CustomerSignatureAbsenceReason? customerSignatureAbsenceReason;

  /// Free text explaining [customerSignatureAbsenceReason] — required when it is `altro`, optional
  /// otherwise. Null when there is nothing to say.
  final String? customerSignatureAbsenceNote;

  final String? technicianSignatureLocalPath;
  final String? technicianSignatureAllegatoId;

  /// See `DraftReports.technicianSignaturePrefillSuppressed`'s doc comment — persisted so it
  /// survives `StepRiepilogo`/this notifier being recreated on sheet close+reopen.
  final bool technicianSignaturePrefillSuppressed;

  /// What the customer is signing off on, captured on the same step as the signatures — the field
  /// the web calls "Dichiarazione cliente" and the office calls "Osservazioni cliente"
  /// (`Report.CustomerSignoffText`). Tri-state like [diagnosi]: null = never touched (a draft whose
  /// text came from an AI-confirmed report keeps it — the submit body omits null), '' = the
  /// technician cleared it.
  final String? customerSignoffText;

  // Step 6 — Allegati (photos)
  final List<AllegatoRow> allegatoRows;

  // Meta
  final bool isSaving;
  final String? saveError;
  final String tenantId;
  final String insertedUserId;

  /// True until the notifier has finished loading an existing draft's saved data from Drift.
  ///
  /// Defaults to `false` — a manually-constructed `ReportEditorState` (every widget test that
  /// overrides `reportEditorProvider` with hand-built data) is "already loaded" by definition.
  /// `ReportEditorNotifier`'s own constructor flips this to `true` for exactly as long as its
  /// real hydration read takes.
  final bool isLoading;

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
    diagnosi: diagnosi,
    soluzione: soluzione,
    metadataJson: null, // not consulted by validateDraft
    insertedUserId: insertedUserId,
    locationId: locationId ?? '',
    startedAt: null,
    endedAt: null,
    documentTemplateId: null,
    customerSignatureAllegatoId: customerSignatureAllegatoId,
    customerSignatureAbsenceReason: customerSignatureAbsenceReason?.wireValue,
    customerSignatureAbsenceNote: customerSignatureAbsenceNote,
    technicianSignatureAllegatoId: technicianSignatureAllegatoId,
    technicianSignaturePrefillSuppressed: technicianSignaturePrefillSuppressed,
    strumentiPrefilled: false,
    submissionProblemJson: null,
    technicianNotes: null,
    closedAt: null,
    stato: 'Bozza',
    inviatoAt: null,
    controllatoAt: null,
    controllatoDa: null,
    fatturatoAt: null,
    materialiNotRequired: materialiNotRequired,
    customerSignoffText: customerSignoffText,
    customerSignoffAt: null,
    richiedeSecondoIntervento: richiedeSecondoIntervento,
    isLocalOnly: true,
    submissionState: 'draft',
    idempotencyKey: null,
    submissionError: null,
    submissionAttempts: 0,
    submissionErrorTransient: false,
  );

  ReportEditorState copyWith({
    RapportinoStep? currentStep,
    String? title,
    String? details,
    String? diagnosi,
    String? soluzione,
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
    bool? richiedeSecondoIntervento,
    String? customerSignatureLocalPath,
    String? customerSignatureAllegatoId,
    CustomerSignatureAbsenceReason? customerSignatureAbsenceReason,
    String? customerSignatureAbsenceNote,
    String? technicianSignatureLocalPath,
    String? technicianSignatureAllegatoId,
    bool? technicianSignaturePrefillSuppressed,
    String? customerSignoffText,
    List<AllegatoRow>? allegatoRows,
    bool? isSaving,
    String? saveError,
    String? tenantId,
    String? insertedUserId,
    bool? isLoading,
    bool clearCustomerId = false,
    bool clearLocationId = false,
    bool clearTicketId = false,
    bool clearCantiereId = false,
    bool clearCustomerFreeText = false,
    bool clearLocationFreeText = false,
    bool clearTicketFreeText = false,
    bool clearCantiereFreeText = false,
    bool clearCustomerSignature = false,
    bool clearCustomerSignatureAbsence = false,
    bool clearCustomerSignatureAbsenceNote = false,
    bool clearTechnicianSignature = false,
    bool clearSaveError = false,
  }) {
    return ReportEditorState(
      reportId: reportId,
      currentStep: currentStep ?? this.currentStep,
      title: title ?? this.title,
      details: details ?? this.details,
      diagnosi: diagnosi ?? this.diagnosi,
      soluzione: soluzione ?? this.soluzione,
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
      richiedeSecondoIntervento: richiedeSecondoIntervento ?? this.richiedeSecondoIntervento,
      customerSignatureLocalPath: clearCustomerSignature
          ? null
          : (customerSignatureLocalPath ?? this.customerSignatureLocalPath),
      customerSignatureAllegatoId: clearCustomerSignature
          ? null
          : (customerSignatureAllegatoId ?? this.customerSignatureAllegatoId),
      customerSignatureAbsenceReason: clearCustomerSignatureAbsence
          ? null
          : (customerSignatureAbsenceReason ?? this.customerSignatureAbsenceReason),
      customerSignatureAbsenceNote:
          clearCustomerSignatureAbsence || clearCustomerSignatureAbsenceNote
              ? null
              : (customerSignatureAbsenceNote ?? this.customerSignatureAbsenceNote),
      technicianSignatureLocalPath: clearTechnicianSignature
          ? null
          : (technicianSignatureLocalPath ?? this.technicianSignatureLocalPath),
      technicianSignatureAllegatoId: clearTechnicianSignature
          ? null
          : (technicianSignatureAllegatoId ?? this.technicianSignatureAllegatoId),
      technicianSignaturePrefillSuppressed:
          technicianSignaturePrefillSuppressed ?? this.technicianSignaturePrefillSuppressed,
      customerSignoffText: customerSignoffText ?? this.customerSignoffText,
      allegatoRows: allegatoRows ?? this.allegatoRows,
      isSaving: isSaving ?? this.isSaving,
      saveError: clearSaveError ? null : (saveError ?? this.saveError),
      tenantId: tenantId ?? this.tenantId,
      insertedUserId: insertedUserId ?? this.insertedUserId,
      isLoading: isLoading ?? this.isLoading,
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
    ILocationService? locationService,
  }) : _repo = repo,
       _locationService = locationService ?? const DisabledLocationService(),
       super(initialState) {
    ready = _hydrate();
  }

  final DraftReportRepository _repo;
  final ILocationService _locationService;

  /// Resolves once hydration has either applied the draft's saved data or given up.
  ///
  /// Production code doesn't need this: `state.isLoading` drives the UI reactively (see
  /// RapportinoFormScreen's spinner). It exists for callers that need a stable starting state
  /// before doing anything else — every test in report_editor_providers_test.dart awaits this
  /// before calling setters, so a test's own state changes can't race hydration and get
  /// silently reverted by it.
  late final Future<void> ready;

  /// Set when this editor was opened on a report it must never write to: a SERVER-known row
  /// (`isLocalOnly == false`) that is no longer a Bozza. Every autosave becomes a no-op.
  ///
  /// This is the write-side half of owner decision D8 (offline slice O-3). The list routes
  /// Inviato/Respinto/Controllato/Fatturato to the read-only view, but the editor route is still
  /// reachable (a deep link, a stale navigation), and `_buildHeaderCompanion` hardcodes
  /// `stato:'Bozza'` + `isLocalOnly:true` — the exact pair that corrupts a synced report (audit
  /// F15): the device then shows a false Bozza, SyncService._upsertDraftReports skips the row
  /// forever (so Controllato/Fatturato never arrive again), and any submit is a permanent 400.
  /// Guarding the write here means that corruption cannot happen whatever opened the screen.
  bool _readOnly = false;

  // ── Hydration ─────────────────────────────────────────────────────────────
  //
  // `initialState` is a placeholder, not the draft's actual saved data — the family provider has
  // no way to read Drift synchronously at construction time. Without this, every reopened draft
  // (leave the screen and come back, or restart the app) started from a blank editor, and the
  // very next autosave — `_buildHeaderCompanion()` writes every column from `state` — overwrote
  // the real row's tenantId/ticketId/customerId/cantiereId/locationId/title back to blank. This
  // was silent: nothing crashed, nothing errored, a rapportino just quietly lost the ticket/
  // cantiere it was linked to and the customer it was for.
  //
  // `createLocalDraft` always inserts the row before navigating here, so a missing row (`draft ==
  // null`) only happens in tests that construct a `ReportEditorState` by hand with no matching
  // DB row — hydration is a no-op then, leaving that hand-built state exactly as given.
  //
  // Guarded by `mounted` throughout and never lets an exception escape: `.autoDispose` can tear
  // this notifier down mid-read (the screen closed before the load finished), and a database can
  // close mid-test — either would otherwise throw from a bare `state = ...` after disposal, or an
  // unhandled async error that fails a test that never even touches this notifier.
  Future<void> _hydrate() async {
    try {
      await _hydrateBody();
    } catch (_) {
      // Best-effort load. A failed hydration leaves `initialState` in place rather than crashing
      // the editor — the same "don't lose the session over a background read" reasoning as
      // `_autosaveHeader`'s own swallowed catch.
      if (mounted && state.isLoading) state = state.copyWith(isLoading: false);
    }
  }

  Future<void> _hydrateBody() async {
    final draft = await _repo.getDraft(state.reportId);
    if (!mounted) return;
    if (draft == null) {
      // No matching row: either a test-constructed state with nothing seeded (leave it exactly
      // as given), or — defensively — a reportId nothing ever created. Either way, stop spinning.
      if (state.isLoading) state = state.copyWith(isLoading: false);
      return;
    }

    // A server-known report past Bozza is read-only on mobile (owner decision D8): it is never
    // hydrated into an editable state and never written back. See [_readOnly]. Reached only if
    // something opened the editor route directly — the list sends these rows to the view.
    if (!draft.isLocalOnly && draft.stato != 'Bozza') {
      _readOnly = true;
      if (state.isLoading) state = state.copyWith(isLoading: false);
      return;
    }

    final staff = await _repo.getStaff(draft.id);
    final segments = await _repo.getSegments(draft.id);
    final materiali = await _repo.getMateriali(draft.id);
    final controlli = await _repo.getControlli(draft.id);
    final allegati = await _repo.getAllegati(draft.id);
    final signatureIds = {
      draft.customerSignatureAllegatoId,
      draft.technicianSignatureAllegatoId,
    }.whereType<String>().toSet();
    // The signature blob itself lives on disk, not in the draft row — only its allegatoId is
    // persisted there. Without re-deriving the local path from the matching allegato here, every
    // (re)open of this editor restores allegatoId but leaves localPath null, and
    // _SignatureBlock's `captured` check (localPath != null && allegatoId != null) reverts to
    // "not captured" even though the file and DB row both still exist.
    final customerSignatureRows = allegati
        .where((a) => a.id == draft.customerSignatureAllegatoId)
        .toList();
    final technicianSignatureRows = allegati
        .where((a) => a.id == draft.technicianSignatureAllegatoId)
        .toList();
    final customerSignatureLocalPath = customerSignatureRows.isNotEmpty
        ? customerSignatureRows.first.storagePath
        : null;
    final technicianSignatureLocalPath = technicianSignatureRows.isNotEmpty
        ? technicianSignatureRows.first.storagePath
        : null;
    final metadata = _parseMetadataJson(draft.metadataJson);
    // The intervals are one collection for the whole report, so they hang off `userId`, exactly
    // like the staff rows do. Grouping here (rather than a query per row) is what puts each
    // technician's own intervals beside their row, which is where both `effectiveHours` and
    // anything building a submit body will look for them.
    final segmentsByUser = <String, List<StaffSegment>>{};
    for (final g in segments) {
      (segmentsByUser[g.userId] ??= []).add(
        StaffSegment(id: g.id, startUtc: g.startUtc, endUtc: g.endUtc),
      );
    }
    if (!mounted) return;

    state = state.copyWith(
      title: draft.title,
      details: draft.details ?? '',
      diagnosi: draft.diagnosi,
      soluzione: draft.soluzione,
      customerId: draft.customerId,
      locationId: draft.locationId,
      ticketId: draft.ticketId,
      cantiereId: draft.cantiereId,
      scheduleId: draft.scheduleId,
      customerFreeText: metadata['customerFreeText'] as String?,
      locationFreeText: metadata['locationFreeText'] as String?,
      ticketFreeText: metadata['ticketFreeText'] as String?,
      cantiereFreeText: metadata['cantiereFreeText'] as String?,
      workAddress: metadata['workAddress'] as String?,
      gpsLatitude: (metadata['gpsLatitude'] as num?)?.toDouble(),
      gpsLongitude: (metadata['gpsLongitude'] as num?)?.toDouble(),
      createdAt: draft.createdAt,
      staffRows: [
        for (final s in staff)
          StaffRow(
            id: s.id,
            userId: s.userId,
            hoursWorked: s.hoursWorked,
            kmTraveled: s.kmTraveled,
            vehicle: s.vehicle,
            notes: s.notes,
            startTime: s.startTime,
            endTime: s.endTime,
            pauseMinutes: s.pauseMinutes,
            segments: segmentsByUser[s.userId] ?? const [],
          ),
      ],
      materialeRows: [
        for (final m in materiali)
          MaterialeRow(
            id: m.id,
            reportId: m.reportId,
            materialeId: m.materialeId,
            freeTextName: m.freeTextName,
            quantity: m.quantity,
            unitOfMeasure: m.unitOfMeasure,
            notes: m.notes,
            magazzinoId: m.magazzinoId,
          ),
      ],
      controlloRows: [
        for (final c in controlli)
          ControlloRow(
            id: c.id,
            reportId: c.reportId,
            controlId: c.controlId,
            stringValue: c.stringValue,
            boolValue: c.boolValue,
            dateValue: c.dateValue,
            numberValue: c.numberValue,
            note: c.note,
            // Carried through, not re-derived: editing an existing answer must not silently drop
            // the name the report was saved with.
            controlLabel: c.controlLabel,
            assetId: c.assetId,
          ),
      ],
      allegatoRows: [
        for (final a in allegati)
          AllegatoRow(
            id: a.id,
            localPath: a.storagePath,
            fileName: a.fileName,
            contentType: a.contentType,
            sizeBytes: a.sizeBytes,
            isSignature: signatureIds.contains(a.id),
          ),
      ],
      materialiNotRequired: draft.materialiNotRequired,
      isAiAssisted: draft.isAiAssisted,
      richiedeSecondoIntervento: draft.richiedeSecondoIntervento,
      customerSignatureAllegatoId: draft.customerSignatureAllegatoId,
      customerSignatureLocalPath: customerSignatureLocalPath,
      customerSignatureAbsenceReason: CustomerSignatureAbsenceReason.fromWire(
        draft.customerSignatureAbsenceReason,
      ),
      customerSignatureAbsenceNote: draft.customerSignatureAbsenceNote,
      technicianSignatureAllegatoId: draft.technicianSignatureAllegatoId,
      technicianSignatureLocalPath: technicianSignatureLocalPath,
      technicianSignaturePrefillSuppressed: draft.technicianSignaturePrefillSuppressed,
      // Hydrated like every other column, and for two reasons: the field must show the text a
      // reopened draft already holds (an AI-confirmed report's acceptance sentence included), and
      // the very next autosave — `_buildHeaderCompanion` writes every column from `state` — would
      // otherwise null the stored value out from under it.
      customerSignoffText: draft.customerSignoffText,
      tenantId: draft.tenantId,
      insertedUserId: draft.insertedUserId,
      isLoading: false,
    );
  }

  static Map<String, dynamic> _parseMetadataJson(String? json) {
    if (json == null || json.isEmpty) return const {};
    try {
      return jsonDecode(json) as Map<String, dynamic>;
    } catch (_) {
      // Malformed metadata is not worth losing the rest of the draft over.
      return const {};
    }
  }

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

  Future<void> setDiagnosi(String value) async {
    state = state.copyWith(diagnosi: value);
    await _autosave();
  }

  Future<void> setSoluzione(String value) async {
    state = state.copyWith(soluzione: value);
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
    // Read the userId before dropping the row: the intervals are keyed by
    // `(reportId, userId)`, not by the staff row's own id, so that is the only handle that can
    // still find them once the row is gone.
    final removed = state.staffRows.where((r) => r.id == staffId).toList();
    final updated = state.staffRows.where((r) => r.id != staffId).toList();
    state = state.copyWith(staffRows: updated);
    await _repo.deleteStaff(staffId);
    if (removed.isNotEmpty) {
      await _repo.deleteSegmentsForStaff(state.reportId, removed.first.userId);
    }
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

  /// Stop on-screen timer, record the interval, and recompute hoursWorked from the intervals.
  Future<void> stopTimer(String staffId) async {
    final row = state.staffRows.firstWhere((r) => r.id == staffId);
    final now = DateTime.now().toUtc();
    final startedAt = row.timerStartedAt;
    final added = startedAt == null
        ? const <StaffSegment>[]
        : [
            StaffSegment(
              // A UUID, not a readable `seg-<epoch>`: the server binds `Id` and `ClientId` as
              // `Guid`, so any other string fails to deserialize and the whole submit 400s. The
              // local id and the claimed `ClientId` are the same value, so a replayed tap
              // collapses onto the row it already wrote instead of recording the hours twice.
              id: const Uuid().v4(),
              startUtc: startedAt,
              endUtc: now,
            ),
          ];
    final newSegments = [...row.segments, ...added];
    final stopped = row.copyWith(
      timerRunning: false,
      endTime: now,
      segments: newSegments,
      clearTimer: true,
    );
    // Hours go on the row too, derived from the intervals: the office web and every older client
    // read `hoursWorked` and nothing else, so leaving it stale is what made the two disagree.
    await updateStaff(
      newSegments.isEmpty ? stopped : stopped.copyWith(hoursWorked: stopped.effectiveHours),
    );
    // Only the interval THIS stop measured, never the hydrated ones. Sync writes a server
    // interval's `clientId` from the payload — a different uuid from its `id`, and null for one
    // recorded by an older client. Re-upserting those rows would overwrite that claim with our own
    // id and reset `createdAt`, so the device would afterwards claim a client id it never sent and
    // the server's replay key would stop matching.
    await _repo.upsertSegments([
      for (final s in added)
        ReportStaffSegmentsCompanion.insert(
          id: s.id,
          tenantId: state.tenantId,
          createdAt: now,
          reportId: state.reportId,
          userId: row.userId,
          startUtc: s.startUtc,
          endUtc: s.endUtc,
          clientId: Value(s.id),
        ),
    ]);
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

  /// Toggles "Serve un secondo intervento" from the Riepilogo step. See
  /// `ReportEditorState.richiedeSecondoIntervento`'s own doc comment — only meaningful for a
  /// ticket-linked rapportino, but harmless (and simply ignored server-side) otherwise.
  Future<void> setRichiedeSecondoIntervento(bool value) async {
    state = state.copyWith(richiedeSecondoIntervento: value);
    await _autosave();
  }

  /// The customer's signoff text, typed on the same step as the signatures. See
  /// [ReportEditorState.customerSignoffText] for the null/''/text contract the submit body relies on.
  Future<void> setCustomerSignoffText(String value) async {
    state = state.copyWith(customerSignoffText: value);
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

  /// Drops a local answer (the technician cleared it): nothing is sent for that control, and a
  /// blank never wipes what the server already holds.
  Future<void> removeControllo(String rowId) async {
    state = state.copyWith(
      controlloRows: state.controlloRows.where((c) => c.id != rowId).toList(),
    );
    await _repo.deleteControllo(rowId);
  }

  /// Writes many answers with ONE state update and ONE Drift batch (a bulk action over 200 assets
  /// must not be 2000 notifications and 2000 awaited inserts).
  Future<void> applyControlloRows(List<ControlloRow> rows) async {
    if (rows.isEmpty) return;
    final byId = {for (final r in state.controlloRows) r.id: r};
    for (final r in rows) {
      byId[r.id] = r;
    }
    state = state.copyWith(controlloRows: byId.values.toList());
    await _repo.upsertControlli([for (final r in rows) _controlloToCompanion(r, state.tenantId)]);
  }

  Future<void> removeControlloRows(List<String> rowIds) async {
    if (rowIds.isEmpty) return;
    final drop = rowIds.toSet();
    state = state.copyWith(
      controlloRows: state.controlloRows.where((c) => !drop.contains(c.id)).toList(),
    );
    await _repo.deleteControlli(rowIds);
  }

  // ── Step 5: Firme ──────────────────────────────────────────────────────────

  /// Best-effort GPS capture for a signature. Mirrors `PunchNotifier._captureGpsSilently`:
  /// never prompts (a mid-signature system permission dialog with no explanation would be worse
  /// than no position) and never throws — a denied/unavailable position simply comes back null,
  /// and the signature is saved anyway. GPS must never block signature capture.
  Future<GpsCoords?> _captureGpsSilently() async {
    try {
      if (await _locationService.willPromptForPermission()) return null;
      return await _locationService.getCurrentPosition();
    } catch (_) {
      return null;
    }
  }

  /// Best-effort, no-prompt GPS capture for the report itself — same silent-only-if-already-decided
  /// contract as [_captureGpsSilently] (never surfaces the OS permission dialog, never throws), but
  /// also applies a successful fix to the draft via [setGps] so callers don't have to unpack coords
  /// themselves. Used for automatic acquisition on entering Dettagli — see `StepDettagli.initState`.
  Future<GpsCoords?> captureGpsSilently() async {
    final coords = await _captureGpsSilently();
    if (coords != null) setGps(coords.lat, coords.lng);
    return coords;
  }

  /// Saves a customer signature.
  ///
  /// [stampCapture] defaults to `true` — the real drawn/typed capture paths (see
  /// `_SignatureBlock._captureSig`) always want a live GPS position + timestamp, per
  /// [_captureGpsSilently]'s doc comment. There is currently no customer-side pre-fill (only the
  /// technician's own signature is reused across rapportini — see
  /// `StepRiepilogo._maybePrefillTechnicianSignature`), but the parameter exists here too so both
  /// signature roles share one honest contract if that ever changes.
  Future<void> saveCustomerSignature({
    required String allegatoId,
    required Uint8List bytes,
    required String localPath,
    bool stampCapture = true,
  }) async {
    GpsCoords? coords;
    DateTime? capturedAt;
    if (stampCapture) {
      coords = await _captureGpsSilently();
      capturedAt = DateTime.now().toUtc();
    }
    await _repo.saveSignature(
      reportId: state.reportId,
      allegatoId: allegatoId,
      tenantId: state.tenantId,
      uploadedByUserId: state.insertedUserId,
      bytes: bytes,
      localPath: localPath,
      isCustomer: true,
      capturedLatitude: coords?.lat,
      capturedLongitude: coords?.lng,
      capturedAt: capturedAt,
    );
    state = state.copyWith(
      customerSignatureLocalPath: localPath,
      customerSignatureAllegatoId: allegatoId,
      // A signed report cannot also say the customer could not sign. Capture is itself a
      // deliberate signing act, so any previously recorded reason no longer applies.
      clearCustomerSignatureAbsence: true,
    );
    await _autosave();
  }

  /// Records (or replaces) why the customer did not sign — "Il cliente non può firmare".
  ///
  /// [note] is trimmed and stored as null when blank. When [reason] is `altro` the UI requires a
  /// non-empty note before enabling Salva; this method trusts that and simply stores what it is
  /// given, because the same call also has to serve "Modifica motivo" for a reason that carries an
  /// optional note.
  ///
  /// Clearing the reason (passing null) is deliberately a separate method
  /// ([clearCustomerSignatureAbsence]) so an accidental null cannot silently erase a recorded
  /// reason.
  Future<void> setCustomerSignatureAbsence({
    required CustomerSignatureAbsenceReason reason,
    String? note,
  }) async {
    final trimmed = note?.trim();
    state = state.copyWith(
      customerSignatureAbsenceReason: reason,
      customerSignatureAbsenceNote: (trimmed?.isEmpty ?? true) ? null : trimmed,
      clearCustomerSignatureAbsenceNote: trimmed?.isEmpty ?? true,
    );
    await _autosave();
  }

  /// Removes the recorded absence reason and its note.
  Future<void> clearCustomerSignatureAbsence() async {
    state = state.copyWith(clearCustomerSignatureAbsence: true);
    await _autosave();
  }

  /// Saves a technician signature.
  ///
  /// [stampCapture] gates whether this save claims a live GPS position + capture timestamp, per
  /// [_captureGpsSilently]'s doc comment. The real drawn/typed capture path (`_captureSig`) always
  /// passes the default `true` — a technician standing in front of the customer actually just
  /// signed. `StepRiepilogo._maybePrefillTechnicianSignature` is the one caller that passes
  /// `false`: it silently reuses a *previously* saved signature to pre-fill a brand-new
  /// rapportino with no signing act at all, so stamping it with "here, right now" GPS + a fresh
  /// timestamp would misrepresent it as freshly captured. See that method's own doc comment.
  ///
  /// Also resets [ReportEditorState.technicianSignaturePrefillSuppressed] to `false` — a real
  /// signature (drawn or typed) is itself a fresh, deliberate signing act, so any earlier
  /// Cancella-driven suppression no longer applies to it. See
  /// `DraftReports.technicianSignaturePrefillSuppressed`'s own doc comment.
  Future<void> saveTechnicianSignature({
    required String allegatoId,
    required Uint8List bytes,
    required String localPath,
    bool stampCapture = true,
  }) async {
    GpsCoords? coords;
    DateTime? capturedAt;
    if (stampCapture) {
      coords = await _captureGpsSilently();
      capturedAt = DateTime.now().toUtc();
    }
    await _repo.saveSignature(
      reportId: state.reportId,
      allegatoId: allegatoId,
      tenantId: state.tenantId,
      uploadedByUserId: state.insertedUserId,
      bytes: bytes,
      localPath: localPath,
      isCustomer: false,
      capturedLatitude: coords?.lat,
      capturedLongitude: coords?.lng,
      capturedAt: capturedAt,
    );
    state = state.copyWith(
      technicianSignatureLocalPath: localPath,
      technicianSignatureAllegatoId: allegatoId,
      technicianSignaturePrefillSuppressed: false,
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

  /// Clears the technician signature, and — unlike the customer side — also marks the pre-fill
  /// suppressed on this draft.
  ///
  /// Without this, the field going back to `null` would be indistinguishable from a rapportino
  /// that never had a technician signature at all: `StepRiepilogo`'s pre-fill logic checks exactly
  /// that field, and `StepRiepilogo` itself is recreated (fresh `initState`) every time its
  /// containing bottom sheet is closed and reopened. Closing and reopening after a deliberate
  /// Cancella would otherwise silently re-fetch and reinstate the exact signature just removed —
  /// see `DraftReports.technicianSignaturePrefillSuppressed`'s own doc comment for why this needs
  /// to be a persisted column rather than in-memory state.
  Future<void> clearTechnicianSignature() async {
    if (state.technicianSignatureAllegatoId != null) {
      await _repo.deleteAllegato(state.technicianSignatureAllegatoId!);
    }
    state = state.copyWith(
      clearTechnicianSignature: true,
      technicianSignaturePrefillSuppressed: true,
    );
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
    // A read-only editor (see [_readOnly]) must never touch the row: the companion below writes
    // `stato:'Bozza'` + `isLocalOnly:true`, which is the F15 corruption.
    if (_readOnly) return;
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
    if (_readOnly) return;
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
      cantiereId: Value(state.cantiereId),
      customerId: Value(state.customerId),
      // The technician's actual typed description — NOT the GPS/free-text metadata blob. These
      // used to collide in this same column (see `metadataJson` doc comment on
      // DraftReports): every autosave overwrote whatever the technician had typed with a JSON
      // blob that never included it, and that blob is what reached the backend/customer PDF as
      // "Descrizione". `details` and `metadataJson` are independent columns now.
      details: Value(state.details.isEmpty ? null : state.details),
      // Written as-is: null (never touched) must stay null and '' (cleared) must stay '' — the
      // submit body turns them into "keep server value" vs "clear" respectively.
      diagnosi: Value(state.diagnosi),
      soluzione: Value(state.soluzione),
      metadataJson: Value(_buildMetadataJson()),
      insertedUserId: Value(state.insertedUserId),
      locationId: Value(state.locationId ?? ''),
      materialiNotRequired: Value(state.materialiNotRequired),
      isAiAssisted: Value(state.isAiAssisted),
      richiedeSecondoIntervento: Value(state.richiedeSecondoIntervento),
      customerSignatureAllegatoId: Value(state.customerSignatureAllegatoId),
      // The wire int, not the enum's ordinal — see
      // `DraftReports.customerSignatureAbsenceReason`'s doc comment.
      customerSignatureAbsenceReason: Value(state.customerSignatureAbsenceReason?.wireValue),
      customerSignatureAbsenceNote: Value(state.customerSignatureAbsenceNote),
      technicianSignatureAllegatoId: Value(state.technicianSignatureAllegatoId),
      technicianSignaturePrefillSuppressed: Value(state.technicianSignaturePrefillSuppressed),
      customerSignoffText: Value(state.customerSignoffText),
      stato: const Value('Bozza'),
      isLocalOnly: const Value(true),
    );
  }

  /// Pack free-text / GPS fields into the `metadataJson` column so they survive round-trips.
  ///
  /// Was packed into `details` — the same column the technician's typed description lives in
  /// (see `setDetails`) — which meant every autosave clobbered the typed text with this blob and
  /// the two never coexisted. `metadataJson` is its own column now (schema v14); this no longer
  /// touches `details` at all.
  String? _buildMetadataJson() {
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
      magazzinoId: Value(row.magazzinoId),
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
      numberValue: Value(row.numberValue),
      note: Value(row.note),
      // The row's own name and asset, captured while the checklist that names it is still in hand.
      // A sent report has to render itself later, and the server's copy carries only the control id.
      controlLabel: Value(row.controlLabel),
      assetId: Value(row.assetId),
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
        initialState: ReportEditorState(reportId: reportId, isLoading: true),
        repo: repo,
        locationService: ref.watch(locationServiceProvider),
      );
    });
