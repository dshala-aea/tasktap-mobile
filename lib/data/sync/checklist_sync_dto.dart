// dart format width=100
// Dart DTOs for the checklist / strumenti members of GET /api/Sync/mobile (hand-off section 3).
//
// Every class publishes `wireKeys`: the exact keys its `fromJson` reads. The inbound contract test
// compares them with the OpenAPI snapshot in both directions, because nothing else on the phone
// notices a server-side rename of a field this code reads.
import '../../core/time/business_time.dart' show parseDateOnly;
import '../../domain/checklist/control_type.dart';

class SyncControlGroupDto {
  const SyncControlGroupDto({
    required this.id,
    this.parentGroupId,
    required this.maintenanceTemplateVersionId,
    required this.name,
    required this.sortOrder,
  });

  final String id;
  final String? parentGroupId;
  final String maintenanceTemplateVersionId;
  final String name;
  final int sortOrder;

  static const Set<String> wireKeys = {
    'id',
    'parentGroupId',
    'maintenanceTemplateVersionId',
    'name',
    'sortOrder',
  };

  factory SyncControlGroupDto.fromJson(Map<String, dynamic> j) => SyncControlGroupDto(
    id: j['id'] as String,
    parentGroupId: j['parentGroupId'] as String?,
    maintenanceTemplateVersionId: j['maintenanceTemplateVersionId'] as String,
    name: j['name'] as String? ?? '',
    sortOrder: _int(j['sortOrder']),
  );
}

/// One materialised checklist row. `prodottoAssistenzaId == null` means a ticket-level row.
class SyncTicketControlDto {
  const SyncTicketControlDto({
    required this.id,
    required this.ticketId,
    this.prodottoAssistenzaId,
    required this.templateControlId,
    required this.controlLineageId,
    required this.groupId,
    required this.label,
    this.description,
    required this.type,
    this.isRequired = false,
    this.options,
    this.sortOrder = 0,
    this.status = 'Pending',
    this.stringValue,
    this.boolValue,
    this.dateValue,
    this.numberValue,
    this.note,
  });

  final String id;
  final String ticketId;
  final String? prodottoAssistenzaId;
  final String templateControlId;

  /// Version-independent identity of the control: the key for bulk actions and for matching the
  /// same control across assets pinned to different template versions.
  final String controlLineageId;
  final String groupId;
  final String label;
  final String? description;
  final ControlType type;
  final bool isRequired;

  /// JSON array string of choices for [ControlType.options].
  final String? options;
  final int sortOrder;

  /// `Pending` | `Completed` | `NotApplicable`.
  final String status;
  final String? stringValue;
  final bool? boolValue;
  final DateTime? dateValue;
  final double? numberValue;
  final String? note;

  static const Set<String> wireKeys = {
    'id',
    'ticketId',
    'prodottoAssistenzaId',
    'templateControlId',
    'controlLineageId',
    'groupId',
    'label',
    'description',
    'type',
    'isRequired',
    'options',
    'sortOrder',
    'status',
    'stringValue',
    'boolValue',
    'dateValue',
    'numberValue',
    'note',
  };

  factory SyncTicketControlDto.fromJson(Map<String, dynamic> j) => SyncTicketControlDto(
    id: j['id'] as String,
    ticketId: j['ticketId'] as String,
    prodottoAssistenzaId: j['prodottoAssistenzaId'] as String?,
    templateControlId: j['templateControlId'] as String,
    controlLineageId: j['controlLineageId'] as String,
    groupId: j['groupId'] as String,
    label: j['label'] as String? ?? '',
    description: j['description'] as String?,
    type: controlTypeFromWire(j['type'] as String?),
    isRequired: j['isRequired'] as bool? ?? false,
    options: j['options'] as String?,
    sortOrder: _int(j['sortOrder']),
    status: j['status'] as String? ?? 'Pending',
    stringValue: j['stringValue'] as String?,
    boolValue: j['boolValue'] as bool?,
    dateValue: j['dateValue'] == null ? null : DateTime.parse(j['dateValue'] as String),
    numberValue: _dbl(j['numberValue']),
    note: j['note'] as String?,
  );
}

class SyncTicketAssetDto {
  const SyncTicketAssetDto({
    required this.ticketId,
    required this.prodottoAssistenzaId,
    this.controllato = false,
    this.note,
    this.maintenanceTemplateVersionId,
  });

  final String ticketId;
  final String prodottoAssistenzaId;

  /// Legacy per-asset flag; only meaningful when [maintenanceTemplateVersionId] is null.
  final bool controllato;
  final String? note;

  /// Non-null = the asset is templated and its answers live in `ticketControls`.
  final String? maintenanceTemplateVersionId;

  static const Set<String> wireKeys = {
    'ticketId',
    'prodottoAssistenzaId',
    'controllato',
    'note',
    'maintenanceTemplateVersionId',
  };

  factory SyncTicketAssetDto.fromJson(Map<String, dynamic> j) => SyncTicketAssetDto(
    ticketId: j['ticketId'] as String,
    prodottoAssistenzaId: j['prodottoAssistenzaId'] as String,
    controllato: j['controllato'] as bool? ?? false,
    note: j['note'] as String?,
    maintenanceTemplateVersionId: j['maintenanceTemplateVersionId'] as String?,
  );
}

class SyncAssetDto {
  const SyncAssetDto({
    required this.id,
    required this.name,
    this.serialNumber,
    this.matricola,
    this.librettoIds = const [],
  });

  final String id;
  final String name;
  final String? serialNumber;

  /// Active Matricola numbers joined with ", ", else the legacy serial (the report rule).
  final String? matricola;

  /// Memberships among ALL synced covered assets: intersect with a ticket's `ticketAssets`.
  final List<String> librettoIds;

  static const Set<String> wireKeys = {'id', 'name', 'serialNumber', 'matricola', 'librettoIds'};

  factory SyncAssetDto.fromJson(Map<String, dynamic> j) => SyncAssetDto(
    id: j['id'] as String,
    name: j['name'] as String? ?? '',
    serialNumber: j['serialNumber'] as String?,
    matricola: j['matricola'] as String?,
    librettoIds: ((j['librettoIds'] as List<dynamic>?) ?? const []).cast<String>(),
  );
}

class SyncStrumentoDto {
  const SyncStrumentoDto({
    required this.id,
    required this.name,
    required this.matricola,
    this.calibrationExpiry,
    this.certificateReference,
    this.isMine = false,
  });

  final String id;
  final String name;
  final String matricola;

  /// A civil date label (`DateTime.utc(y, m, d)`), never an instant.
  final DateTime? calibrationExpiry;
  final String? certificateReference;
  final bool isMine;

  static const Set<String> wireKeys = {
    'id',
    'name',
    'matricola',
    'calibrationExpiry',
    'certificateReference',
    'isMine',
  };

  factory SyncStrumentoDto.fromJson(Map<String, dynamic> j) => SyncStrumentoDto(
    id: j['id'] as String,
    name: j['name'] as String? ?? '',
    matricola: j['matricola'] as String? ?? '',
    calibrationExpiry: parseDateOnly(j['calibrationExpiry']),
    certificateReference: j['certificateReference'] as String?,
    isMine: j['isMine'] as bool? ?? false,
  );
}

class SyncReportStrumentoDto {
  const SyncReportStrumentoDto({
    required this.id,
    required this.reportId,
    this.strumentoId,
    required this.name,
    required this.matricola,
    this.calibrationExpiry,
    this.certificateReference,
    this.expiredAtUse = false,
    this.expiredAcknowledged = false,
  });

  final String id;
  final String reportId;
  final String? strumentoId;
  final String name;
  final String matricola;
  final DateTime? calibrationExpiry;
  final String? certificateReference;

  /// Server-computed; display only, NEVER sent back.
  final bool expiredAtUse;
  final bool expiredAcknowledged;

  static const Set<String> wireKeys = {
    'id',
    'reportId',
    'strumentoId',
    'name',
    'matricola',
    'calibrationExpiry',
    'certificateReference',
    'expiredAtUse',
    'expiredAcknowledged',
  };

  factory SyncReportStrumentoDto.fromJson(Map<String, dynamic> j) => SyncReportStrumentoDto(
    id: j['id'] as String,
    reportId: j['reportId'] as String,
    strumentoId: j['strumentoId'] as String?,
    name: j['name'] as String? ?? '',
    matricola: j['matricola'] as String? ?? '',
    calibrationExpiry: parseDateOnly(j['calibrationExpiry']),
    certificateReference: j['certificateReference'] as String?,
    expiredAtUse: j['expiredAtUse'] as bool? ?? false,
    expiredAcknowledged: j['expiredAcknowledged'] as bool? ?? false,
  );
}

// `int32` may arrive as a JSON number or a numeric string, `decimal` as a number or a string.
int _int(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;

double? _dbl(Object? v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  return double.tryParse('$v');
}
