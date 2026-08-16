// dart format width=100

// ══════════════════════════════════════════════════════════════════════════════
// SubmitReportRequest — mirrors SubmitReportRequest.cs exactly.
//
// Field names must match the backend's JSON serialization (camelCase from the
// C# PascalCase properties via the default System.Text.Json policy).
// ══════════════════════════════════════════════════════════════════════════════

/// Full rapportino payload sent to POST /api/reports/submit.
/// Mirror of backend SubmitReportRequest.cs — field names are identical.
class SubmitReportRequest {
  const SubmitReportRequest({
    required this.id,
    this.scheduleId,
    this.ticketId,
    required this.locationId,
    required this.title,
    this.details,
    this.technicianNotes,
    this.startedAt,
    this.endedAt,
    this.customerSignatureAllegatoId,
    this.technicianSignatureAllegatoId,
    this.customerSignoffText,
    this.materialiNotRequired = false,
    this.aiAssisted = false,
    this.photoAllegatoIds = const [],
    this.staff = const [],
    this.materiali = const [],
    this.controlli = const [],
  });

  /// Client-generated report GUID. Enables idempotent re-submit.
  final String id;

  /// Optional schedule the report belongs to.
  final String? scheduleId;

  /// Optional ticket the report belongs to.
  final String? ticketId;

  /// Location of the intervention (required).
  final String locationId;

  /// Short title of the intervention.
  final String title;

  /// Full description / body.
  final String? details;

  /// Internal technician notes (not printed on customer PDF).
  final String? technicianNotes;

  /// When the work actually started (UTC ISO-8601).
  final DateTime? startedAt;

  /// When the work actually ended (UTC ISO-8601).
  final DateTime? endedAt;

  /// Allegato id of the customer's signature (required to submit).
  final String? customerSignatureAllegatoId;

  /// Allegato id of the technician's signature (required to submit).
  final String? technicianSignatureAllegatoId;

  /// Customer acceptance text captured at signing time.
  final String? customerSignoffText;

  /// When true, the operator confirmed no materials were used.
  final bool materialiNotRequired;

  /// Whether text produced by an AI draft is still in this rapportino.
  final bool aiAssisted;

  /// Allegato ids of additional photos attached to the report.
  final List<String> photoAllegatoIds;

  /// Technicians who participated (≥1 required to submit).
  final List<SubmitReportStaffDto> staff;

  /// Materials consumed during the intervention.
  final List<SubmitReportMaterialeDto> materiali;

  /// Inspection control answers.
  final List<SubmitReportControlloDto> controlli;

  Map<String, dynamic> toJson() => {
    'id': id,
    if (scheduleId != null) 'scheduleId': scheduleId,
    if (ticketId != null) 'ticketId': ticketId,
    'locationId': locationId,
    'title': title,
    if (details != null) 'details': details,
    if (technicianNotes != null) 'technicianNotes': technicianNotes,
    if (startedAt != null) 'startedAt': startedAt!.toUtc().toIso8601String(),
    if (endedAt != null) 'endedAt': endedAt!.toUtc().toIso8601String(),
    if (customerSignatureAllegatoId != null)
      'customerSignatureAllegatoId': customerSignatureAllegatoId,
    if (technicianSignatureAllegatoId != null)
      'technicianSignatureAllegatoId': technicianSignatureAllegatoId,
    if (customerSignoffText != null) 'customerSignoffText': customerSignoffText,
    'materialiNotRequired': materialiNotRequired,
    'aiAssisted': aiAssisted,
    'photoAllegatoIds': photoAllegatoIds,
    'staff': staff.map((s) => s.toJson()).toList(),
    'materiali': materiali.map((m) => m.toJson()).toList(),
    'controlli': controlli.map((c) => c.toJson()).toList(),
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
  });

  final String ticketControlId;
  final String? stringValue;
  final bool? boolValue;
  final DateTime? dateValue;

  Map<String, dynamic> toJson() => {
    // 'ticketControlId', not 'controlId'. The server's field is a non-nullable Guid, so the
    // old name deserialized to Guid.Empty, which belongs to no ticket — and the ownership
    // guard rejected the entire submission. A technician who filled in the checklist could
    // not send their rapportino at all. Renamed by ADR-0012; mobile was never updated.
    'ticketControlId': ticketControlId,
    if (stringValue != null) 'stringValue': stringValue,
    if (boolValue != null) 'boolValue': boolValue,
    if (dateValue != null) 'dateValue': dateValue!.toUtc().toIso8601String(),
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
