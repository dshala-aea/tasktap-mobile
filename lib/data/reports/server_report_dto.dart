// dart format width=100
// ══════════════════════════════════════════════════════════════════════════════
// ServerReportDto — typed mirror of `GET /api/Reports/{id}`.
//
// The OpenAPI snapshot describes this response as "Report details." with NO schema, so nothing
// but this file and test/data/reports/server_report_dto_test.dart (which parses a fixture
// copied from the backend projection) pins its shape. A hand-written DTO rename is invisible to
// the compiler and to the contract gate; that test is the only guard.
//
// Source of truth (property names, casing, and which fields exist):
//   backend: src/TaskTapAPI.Api/Controllers/ReportsController.cs  `GetById`
//     - the header is a hand-rolled ANONYMOUS projection. It carries NO `cantiereId`, so the
//       cantiere link cannot be read back here and is supplied by the caller.
//     - `stato` is NOT passed through the entity's JsonStringEnumConverter (anonymous types do
//       not inherit property attributes), so it arrives as the raw int of ReportStatoEnum
//       (0 = Bozza). A string is accepted too in case the server ever stringifies it.
//     - `materiali` / `staff` / `observations` are the EF entities passed through whole
//       (ReportMateriale / ReportStaff / ReportControlObservation, TaskTapAPI.Core/Entities),
//       serialised camelCase by System.Text.Json; only the fields the editor holds are read.
//       decimals arrive as JSON numbers.
// ══════════════════════════════════════════════════════════════════════════════

/// `ReportStatoEnum.Bozza` on the wire.
const int kReportStatoBozzaWire = 0;

class ServerReportStaffDto {
  const ServerReportStaffDto({
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

  factory ServerReportStaffDto.fromJson(Map<String, dynamic> j) => ServerReportStaffDto(
    userId: j['userId'] as String,
    hoursWorked: _num(j['hoursWorked']),
    kmTraveled: _num(j['kmTraveled']) ?? 0,
    vehicle: j['vehicle'] as String?,
    costPerKm: _num(j['costPerKm']),
    notes: j['notes'] as String?,
    startTime: _dt(j['startTime']),
    endTime: _dt(j['endTime']),
    pauseMinutes: (j['pauseMinutes'] as num?)?.toInt() ?? 0,
  );
}

class ServerReportMaterialeDto {
  const ServerReportMaterialeDto({
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

  factory ServerReportMaterialeDto.fromJson(Map<String, dynamic> j) => ServerReportMaterialeDto(
    materialeId: j['materialeId'] as String?,
    freeTextName: j['freeTextName'] as String?,
    quantity: _num(j['quantity']) ?? 0,
    unitOfMeasure: j['unitOfMeasure'] as String?,
    unitPrice: _num(j['unitPrice']),
    notes: j['notes'] as String?,
    magazzinoId: j['magazzinoId'] as String?,
  );
}

/// One checklist answer (`ReportControlObservation`), keyed by the TicketControl it answers.
class ServerReportObservationDto {
  const ServerReportObservationDto({
    required this.ticketControlId,
    this.stringValue,
    this.boolValue,
    this.dateValue,
    this.numberValue,
  });

  final String ticketControlId;
  final String? stringValue;
  final bool? boolValue;
  final DateTime? dateValue;
  final double? numberValue;

  factory ServerReportObservationDto.fromJson(Map<String, dynamic> j) =>
      ServerReportObservationDto(
        ticketControlId: j['ticketControlId'] as String,
        stringValue: j['stringValue'] as String?,
        boolValue: j['boolValue'] as bool?,
        dateValue: _dt(j['dateValue']),
        numberValue: _num(j['numberValue']),
      );
}

class ServerReportDto {
  const ServerReportDto({
    required this.id,
    required this.tenantId,
    required this.title,
    this.scheduleId,
    this.ticketId,
    this.customerId,
    this.details,
    required this.insertedUserId,
    required this.locationId,
    this.startedAt,
    this.endedAt,
    this.customerSignatureAllegatoId,
    this.technicianSignatureAllegatoId,
    this.technicianNotes,
    required this.stato,
    this.diagnosi,
    this.soluzione,
    this.materialiNotRequired = false,
    this.customerSignoffText,
    this.isAiAssisted = false,
    this.createdAt,
    this.staff = const [],
    this.materiali = const [],
    this.observations = const [],
  });

  final String id;
  final String tenantId;
  final String title;
  final String? scheduleId;
  final String? ticketId;
  final String? customerId;
  final String? details;
  final String insertedUserId;
  final String locationId;
  final DateTime? startedAt;
  final DateTime? endedAt;
  final String? customerSignatureAllegatoId;
  final String? technicianSignatureAllegatoId;
  final String? technicianNotes;

  /// Raw wire value: int (ReportStatoEnum) or its name. Use [isBozza].
  final Object? stato;
  final String? diagnosi;
  final String? soluzione;
  final bool materialiNotRequired;
  final String? customerSignoffText;
  final bool isAiAssisted;
  final DateTime? createdAt;
  final List<ServerReportStaffDto> staff;
  final List<ServerReportMaterialeDto> materiali;
  final List<ServerReportObservationDto> observations;

  bool get isBozza => stato == kReportStatoBozzaWire || stato == 'Bozza';

  factory ServerReportDto.fromJson(Map<String, dynamic> j) => ServerReportDto(
    id: j['id'] as String,
    tenantId: j['tenantId'] as String,
    title: j['title'] as String? ?? '',
    scheduleId: j['scheduleId'] as String?,
    ticketId: j['ticketId'] as String?,
    customerId: j['customerId'] as String?,
    details: j['details'] as String?,
    insertedUserId: j['insertedUserId'] as String,
    locationId: j['locationId'] as String,
    startedAt: _dt(j['startedAt']),
    endedAt: _dt(j['endedAt']),
    customerSignatureAllegatoId: j['customerSignatureAllegatoId'] as String?,
    technicianSignatureAllegatoId: j['technicianSignatureAllegatoId'] as String?,
    technicianNotes: j['technicianNotes'] as String?,
    stato: j['stato'],
    diagnosi: j['diagnosi'] as String?,
    soluzione: j['soluzione'] as String?,
    materialiNotRequired: j['materialiNotRequired'] as bool? ?? false,
    customerSignoffText: j['customerSignoffText'] as String?,
    isAiAssisted: j['isAiAssisted'] as bool? ?? false,
    createdAt: _dt(j['createdAt']),
    staff: _list(j['staff'], ServerReportStaffDto.fromJson),
    materiali: _list(j['materiali'], ServerReportMaterialeDto.fromJson),
    observations: _list(j['observations'], ServerReportObservationDto.fromJson),
  );
}

List<T> _list<T>(Object? raw, T Function(Map<String, dynamic>) f) =>
    (raw as List<dynamic>? ?? const []).cast<Map<String, dynamic>>().map(f).toList();

double? _num(Object? v) => (v as num?)?.toDouble();

DateTime? _dt(Object? v) => v == null ? null : DateTime.parse(v as String);
