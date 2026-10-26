// dart format width=100

// ══════════════════════════════════════════════════════════════════════════════
// SubmitReportRequest — mirrors SubmitReportRequest.cs exactly.
//
// Field names must match the backend's JSON serialization (camelCase from the
// C# PascalCase properties via the default System.Text.Json policy).
// ══════════════════════════════════════════════════════════════════════════════

import '../../domain/reports/customer_signature_absence_reason.dart';

/// Full rapportino payload sent to POST /api/reports/submit.
/// Mirror of backend SubmitReportRequest.cs — field names are identical.
class SubmitReportRequest {
  const SubmitReportRequest({
    required this.id,
    this.expectedVersion,
    this.scheduleId,
    this.ticketId,
    this.cantiereId,
    this.consumedCantiereWorkLogClientIds = const [],
    required this.locationId,
    required this.title,
    this.details,
    this.diagnosi,
    this.soluzione,
    this.technicianNotes,
    this.startedAt,
    this.endedAt,
    this.customerSignatureAllegatoId,
    this.customerSignatureAbsenceReason,
    this.customerSignatureAbsenceNote,
    this.technicianSignatureAllegatoId,
    this.customerSignoffText,
    this.materialiNotRequired = false,
    this.aiAssisted = false,
    this.richiedeSecondoIntervento = false,
    this.photoAllegatoIds = const [],
    this.staff = const [],
    this.materiali = const [],
    this.controlli = const [],
    this.strumenti = const [],
  });

  /// Client-generated report GUID. Enables idempotent re-submit.
  final String id;

  /// The report row's version (`xmin` as a decimal string) as this device last *saw* it — the
  /// `version` of `GET /api/reports/{id}`, persisted on the draft at import time
  /// (`DraftReports.expectedVersion`). Mirrors backend `SubmitReportRequest.ExpectedVersion`.
  ///
  /// The server compares it to the report's current version and rejects the submit with a 409
  /// `concurrency_conflict` when the office edited the report after this version was captured,
  /// instead of letting this submit silently overwrite that edit. Omitted from the JSON when null,
  /// which the server reads as "do not check" — the correct signal for a draft that has never been
  /// on the server (a brand-new offline rapportino), and the pre-guard behaviour for old builds.
  ///
  /// Never populate this from a fetch taken while building the request: a version read immediately
  /// before submitting always matches the row it is compared against, so the guard would be inert.
  final String? expectedVersion;

  /// Optional schedule the report belongs to.
  final String? scheduleId;

  /// Optional ticket the report belongs to.
  final String? ticketId;

  /// Optional cantiere (worksite) this rapportino belongs to — P2-6.
  ///
  /// The server has no other way to learn it on this path: `Report.CantiereId` used to be settable
  /// only by `POST /api/reports/from-cantiere-worklogs`, so a rapportino drafted from a cantiere
  /// while offline arrived with no cantiere at all. Omitted when null, which the server reads as
  /// "this client does not own the field" and leaves whatever it has in place (an older build
  /// submitting a server-created draft therefore cannot detach it).
  final String? cantiereId;

  /// The device's own cantiere punch ids (`CantiereWorkLog.ClientId` server-side) whose hours this
  /// rapportino already carries — P2-6.
  ///
  /// The server stamps exactly these rows as consumed (`CantiereWorkLog.ReportStaffId`) so a later
  /// cantiere-originated rapportino cannot count the same hours again. Ids the server cannot
  /// resolve yet (punch still queued) are ignored, never an error; always sent, empty included.
  final List<String> consumedCantiereWorkLogClientIds;

  /// Location of the intervention (required).
  final String locationId;

  /// Short title of the intervention.
  final String title;

  /// Full description / body.
  final String? details;

  /// What was found / what was done. Tri-state, matching the backend rule in
  /// `ReportSubmitService`: null = leave the server value alone (omitted from the JSON), ""
  /// = clear it, any other text = replace it.
  final String? diagnosi;
  final String? soluzione;

  /// Internal technician notes (not printed on customer PDF).
  final String? technicianNotes;

  /// When the work actually started (UTC ISO-8601).
  final DateTime? startedAt;

  /// When the work actually ended (UTC ISO-8601).
  final DateTime? endedAt;

  /// Allegato id of the customer's signature. Required only when no
  /// [customerSignatureAbsenceReason] is recorded: a report the customer could not sign states why
  /// instead.
  final String? customerSignatureAllegatoId;

  /// Why the customer did not sign ("Il cliente non può firmare"). Mirrors the backend
  /// `CustomerSignatureAbsenceReason`, serialized as an INTEGER (`Assente = 0`, `Rifiuta = 1`,
  /// `Altro = 2`). Never sent alongside [customerSignatureAllegatoId] — a report carries one or the
  /// other, never both.
  final CustomerSignatureAbsenceReason? customerSignatureAbsenceReason;

  /// Free text explaining [customerSignatureAbsenceReason]. Sent only when non-empty and only
  /// alongside a reason.
  final String? customerSignatureAbsenceNote;

  /// Allegato id of the technician's signature (required to submit).
  final String? technicianSignatureAllegatoId;

  /// Customer acceptance text captured at signing time.
  final String? customerSignoffText;

  /// When true, the operator confirmed no materials were used.
  final bool materialiNotRequired;

  /// Whether text produced by an AI draft is still in this rapportino.
  final bool aiAssisted;

  /// CSC requirement: the technician finished this visit but flags that a second one is needed
  /// ("Da tornare" / "Serve un secondo intervento"), set from the Riepilogo step alongside submit
  /// rather than through a separate status-change call. Applied atomically with the rest of this
  /// submit — see backend `ReportSubmitService.SubmitAsync`. No-op server-side when there is no
  /// linked ticket or the tenant has no status flagged `RequiresFollowUp`.
  final bool richiedeSecondoIntervento;

  /// Allegato ids of additional photos attached to the report.
  final List<String> photoAllegatoIds;

  /// Technicians who participated (≥1 required to submit).
  final List<SubmitReportStaffDto> staff;

  /// Materials consumed during the intervention.
  final List<SubmitReportMaterialeDto> materiali;

  /// Inspection control answers.
  final List<SubmitReportControlloDto> controlli;

  /// Instruments used. `expiredAtUse` is NEVER sent: the server recomputes it from the report's
  /// work date. An empty list keeps the server's rows (it cannot clear them).
  final List<SubmitReportStrumentoDto> strumenti;

  Map<String, dynamic> toJson() => {
    'id': id,
    // Emitted only when set: `null`/absent is the server's "do not check" path. `if (x != null)`
    // rather than always emitting means a never-on-the-server draft sends no `expectedVersion` at
    // all, exactly the pre-guard wire shape.
    if (expectedVersion != null) 'expectedVersion': expectedVersion,
    if (scheduleId != null) 'scheduleId': scheduleId,
    if (ticketId != null) 'ticketId': ticketId,
    if (cantiereId != null) 'cantiereId': cantiereId,
    'consumedCantiereWorkLogClientIds': consumedCantiereWorkLogClientIds,
    'locationId': locationId,
    'title': title,
    if (details != null) 'details': details,
    if (diagnosi != null) 'diagnosi': diagnosi,
    if (soluzione != null) 'soluzione': soluzione,
    if (technicianNotes != null) 'technicianNotes': technicianNotes,
    if (startedAt != null) 'startedAt': startedAt!.toUtc().toIso8601String(),
    if (endedAt != null) 'endedAt': endedAt!.toUtc().toIso8601String(),
    if (customerSignatureAllegatoId != null)
      'customerSignatureAllegatoId': customerSignatureAllegatoId,
    // Never both: a signed report emits no absence reason at all, even if the state somehow still
    // held one. The enum goes out as its wire int, never a string. The note rides along only with
    // a reason, and only when it has content — a blank note is not an answer.
    if (customerSignatureAllegatoId == null && customerSignatureAbsenceReason != null)
      'customerSignatureAbsenceReason': customerSignatureAbsenceReason!.wireValue,
    if (customerSignatureAllegatoId == null &&
        customerSignatureAbsenceReason != null &&
        (customerSignatureAbsenceNote?.trim().isNotEmpty ?? false))
      'customerSignatureAbsenceNote': customerSignatureAbsenceNote!.trim(),
    if (technicianSignatureAllegatoId != null)
      'technicianSignatureAllegatoId': technicianSignatureAllegatoId,
    if (customerSignoffText != null) 'customerSignoffText': customerSignoffText,
    'materialiNotRequired': materialiNotRequired,
    'aiAssisted': aiAssisted,
    'richiedeSecondoIntervento': richiedeSecondoIntervento,
    'photoAllegatoIds': photoAllegatoIds,
    'staff': staff.map((s) => s.toJson()).toList(),
    'materiali': materiali.map((m) => m.toJson()).toList(),
    'controlli': controlli.map((c) => c.toJson()).toList(),
    'strumenti': strumenti.map((s) => s.toJson()).toList(),
  };
}

/// One technician's time + travel contribution. Mirror of SubmitReportStaffDto.cs.
class SubmitReportStaffDto {
  const SubmitReportStaffDto({
    required this.userId,
    this.hoursWorked,
    this.kmTraveled = 0,
    this.vehicle,
    this.costPerKm,
    this.notes,
    this.startTime,
    this.endTime,
    this.pauseMinutes = 0,
  });

  final String userId;
  final double? hoursWorked;
  final double kmTraveled;
  final String? vehicle;
  final double? costPerKm;
  final String? notes;
  final DateTime? startTime;
  final DateTime? endTime;
  final int pauseMinutes;

  Map<String, dynamic> toJson() => {
    'userId': userId,
    if (hoursWorked != null) 'hoursWorked': hoursWorked,
    'kmTraveled': kmTraveled,
    if (vehicle != null) 'vehicle': vehicle,
    if (costPerKm != null) 'costPerKm': costPerKm,
    if (notes != null) 'notes': notes,
    if (startTime != null) 'startTime': startTime!.toUtc().toIso8601String(),
    if (endTime != null) 'endTime': endTime!.toUtc().toIso8601String(),
    'pauseMinutes': pauseMinutes,
  };
}

/// One material line. Mirror of SubmitReportMaterialeDto.cs.
class SubmitReportMaterialeDto {
  const SubmitReportMaterialeDto({
    this.materialeId,
    this.freeTextName,
    required this.quantity,
    this.unitOfMeasure,
    this.unitPrice,
    this.notes,
    this.magazzinoId,
  });

  final String? materialeId;
  final String? freeTextName;
  final double quantity;
  final String? unitOfMeasure;
  final double? unitPrice;
  final String? notes;
  final String? magazzinoId;

  Map<String, dynamic> toJson() => {
    if (materialeId != null) 'materialeId': materialeId,
    if (freeTextName != null) 'freeTextName': freeTextName,
    'quantity': quantity,
    if (unitOfMeasure != null) 'unitOfMeasure': unitOfMeasure,
    if (unitPrice != null) 'unitPrice': unitPrice,
    if (notes != null) 'notes': notes,
    if (magazzinoId != null) 'magazzinoId': magazzinoId,
  };
}

/// One inspection control answer. Mirror of SubmitReportControlloDto.cs.
///
/// The id is the **TicketControl** — this job's copy of a checklist item, resolved from the
/// published template version when the ticket was created (ADR-0012 §B.4) — not the template
/// control it came from. The server checks that every id belongs to this report's ticket, so a
/// mismatched name here does not fail quietly: it fails the whole submit.
class SubmitReportControlloDto {
  const SubmitReportControlloDto({
    required this.ticketControlId,
    this.stringValue,
    this.boolValue,
    this.dateValue,
    this.numberValue,
    this.note,
  });

  final String ticketControlId;
  final String? stringValue;
  final bool? boolValue;
  final DateTime? dateValue;
  final double? numberValue;
  final String? note;

  Map<String, dynamic> toJson() => {
    // 'ticketControlId', not 'controlId'. The server's field is a non-nullable Guid, so the
    // old name deserialized to Guid.Empty, which belongs to no ticket — and the ownership
    // guard rejected the entire submission. A technician who filled in the checklist could
    // not send their rapportino at all. Renamed by ADR-0012; mobile was never updated.
    'ticketControlId': ticketControlId,
    if (stringValue != null) 'stringValue': stringValue,
    if (boolValue != null) 'boolValue': boolValue,
    if (dateValue != null) 'dateValue': dateValue!.toUtc().toIso8601String(),
    if (numberValue != null) 'numberValue': numberValue,
    if (note != null && note!.trim().isNotEmpty) 'note': note!.trim(),
  };
}

/// One instrument used on the rapportino. Mirror of `SubmitReportStrumentoDto`: `strumentoId` +
/// `expiredAcknowledged` only. An expired instrument REQUIRES `expiredAcknowledged = true`; a valid
/// one forbids it (422 `strumenti_invalid` otherwise). Plus two optional free-text notes,
/// [usageDescription] (how it was used) and [outcome] (esito), each max 2000 chars server-side.
/// They are sent only when non-blank (the server trims and stores blank as null).
class SubmitReportStrumentoDto {
  const SubmitReportStrumentoDto({
    required this.strumentoId,
    this.expiredAcknowledged = false,
    this.usageDescription,
    this.outcome,
  });

  final String strumentoId;
  final bool expiredAcknowledged;
  final String? usageDescription;
  final String? outcome;

  Map<String, dynamic> toJson() => {
    'strumentoId': strumentoId,
    'expiredAcknowledged': expiredAcknowledged,
    if (usageDescription != null && usageDescription!.trim().isNotEmpty)
      'usageDescription': usageDescription!.trim(),
    if (outcome != null && outcome!.trim().isNotEmpty) 'outcome': outcome!.trim(),
  };
}

/// Response from POST /api/reports/submit.
class SubmitReportResponse {
  const SubmitReportResponse({
    required this.id,
    required this.title,
    required this.stato,
    required this.inviatoAt,
    this.replayed = false,
  });

  final String id;
  final String title;
  final String stato;
  final DateTime? inviatoAt;
  final bool replayed;

  factory SubmitReportResponse.fromJson(Map<String, dynamic> json) {
    return SubmitReportResponse(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      stato: json['stato']?.toString() ?? '',
      inviatoAt: json['inviatoAt'] != null ? DateTime.tryParse(json['inviatoAt'] as String) : null,
      replayed: json['replayed'] as bool? ?? false,
    );
  }
}

/// Response from POST /api/reports/{id}/attachments.
class ReportAttachmentUploadResponse {
  const ReportAttachmentUploadResponse({required this.allegatoId, this.url});

  final String allegatoId;
  final String? url;

  factory ReportAttachmentUploadResponse.fromJson(Map<String, dynamic> json) {
    return ReportAttachmentUploadResponse(
      allegatoId: json['allegatoId'] as String? ?? '',
      url: json['url'] as String?,
    );
  }
}
