// Dart DTOs for the MobileUserSyncResult payload.
// These mirror the C# entities serialised as JSON from GET /api/sync/mobile.

class SyncResultDto {
  final DateTime syncedAt;
  final DateTime? since;
  final List<ScheduleDto> schedules;
  final List<ReportDto> draftReports;
  final List<CustomerDto> customers;
  final List<LocationDto> locations;
  final List<TicketDto> tickets;
  final List<MaterialeDto> materiali;
  final List<CantiereDto> cantieri;
  final List<TicketStatusDto> ticketStatuses;
  final List<TicketTypeDto> ticketTypes;
  final List<ColleagueDto> colleagues;

  const SyncResultDto({
    required this.syncedAt,
    required this.since,
    required this.schedules,
    required this.draftReports,
    required this.customers,
    required this.locations,
    required this.tickets,
    required this.materiali,
    required this.cantieri,
    required this.ticketStatuses,
    required this.ticketTypes,
    required this.colleagues,
  });

  factory SyncResultDto.fromJson(Map<String, dynamic> j) {
    return SyncResultDto(
      syncedAt: DateTime.parse(j['syncedAt'] as String),
      since: j['since'] == null ? null : DateTime.parse(j['since'] as String),
      schedules: _list(j['schedules'], ScheduleDto.fromJson),
      draftReports: _list(j['draftReports'], ReportDto.fromJson),
      customers: _list(j['customers'], CustomerDto.fromJson),
      locations: _list(j['locations'], LocationDto.fromJson),
      tickets: _list(j['tickets'], TicketDto.fromJson),
      materiali: _list(j['materiali'], MaterialeDto.fromJson),
      cantieri: _list(j['cantieri'], CantiereDto.fromJson),
      ticketStatuses: _list(j['ticketStatuses'], TicketStatusDto.fromJson),
      ticketTypes: _list(j['ticketTypes'], TicketTypeDto.fromJson),
      colleagues: _list(j['colleagues'], ColleagueDto.fromJson),
    );
  }
}

// ── Colleague ──────────────────────────────────────────────────────────────────

/// A colleague the technician can name on a rapportino. Id and display name only — see the
/// server's SyncColleagueDto for why the rest of the user row does not travel to a phone.
class ColleagueDto {
  final String id;
  final String displayName;

  const ColleagueDto({required this.id, required this.displayName});

  factory ColleagueDto.fromJson(Map<String, dynamic> j) =>
      ColleagueDto(id: j['id'] as String, displayName: j['displayName'] as String? ?? '');
}

// ── Customer ───────────────────────────────────────────────────────────────────

class CustomerDto {
  final String id;
  final String tenantId;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final String companyName;
  final String? taxId;
  final String? address;
  final String? city;
  final String? postalCode;
  final String? country;
  final String? phone;
  final String? email;
  final String? contactPerson;
  final String? notes;
  final bool isActive;

  const CustomerDto({
    required this.id,
    required this.tenantId,
    required this.createdAt,
    this.updatedAt,
    required this.companyName,
    this.taxId,
    this.address,
    this.city,
    this.postalCode,
    this.country,
    this.phone,
    this.email,
    this.contactPerson,
    this.notes,
    this.isActive = true,
  });

  factory CustomerDto.fromJson(Map<String, dynamic> j) => CustomerDto(
    id: j['id'] as String,
    tenantId: j['tenantId'] as String,
    createdAt: DateTime.parse(j['createdAt'] as String),
    updatedAt: _dt(j['updatedAt']),
    companyName: j['companyName'] as String,
    taxId: j['taxId'] as String?,
    address: j['address'] as String?,
    city: j['city'] as String?,
    postalCode: j['postalCode'] as String?,
    country: j['country'] as String?,
    phone: j['phone'] as String?,
    email: j['email'] as String?,
    contactPerson: j['contactPerson'] as String?,
    notes: j['notes'] as String?,
    isActive: j['isActive'] as bool? ?? true,
  );
}

// ── Location ───────────────────────────────────────────────────────────────────

class LocationDto {
  final String id;
  final String tenantId;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final String customerId;
  final String name;
  final String? address;
  final String? city;
  final String? postalCode;
  final String? country;
  final double? latitude;
  final double? longitude;
  final String? phone;
  final String? notes;
  final bool isActive;

  const LocationDto({
    required this.id,
    required this.tenantId,
    required this.createdAt,
    this.updatedAt,
    required this.customerId,
    required this.name,
    this.address,
    this.city,
    this.postalCode,
    this.country,
    this.latitude,
    this.longitude,
    this.phone,
    this.notes,
    this.isActive = true,
  });

  factory LocationDto.fromJson(Map<String, dynamic> j) => LocationDto(
    id: j['id'] as String,
    tenantId: j['tenantId'] as String,
    createdAt: DateTime.parse(j['createdAt'] as String),
    updatedAt: _dt(j['updatedAt']),
    customerId: j['customerId'] as String,
    name: j['name'] as String,
    address: j['address'] as String?,
    city: j['city'] as String?,
    postalCode: j['postalCode'] as String?,
    country: j['country'] as String?,
    latitude: _dbl(j['latitude']),
    longitude: _dbl(j['longitude']),
    phone: j['phone'] as String?,
    notes: j['notes'] as String?,
    isActive: j['isActive'] as bool? ?? true,
  );
}

// ── Ticket ─────────────────────────────────────────────────────────────────────

class TicketDto {
  final String id;
  final String tenantId;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final String title;

  /// The per-tenant display number — what a technician and the customer both call this job.
  ///
  /// It has been on the wire the whole time: mobile sync returns the `Ticket` entity itself and
  /// the entity carries `Numero`. This client simply never read it, so every ticket surface fell
  /// back to `id.substring(0, 8)` and titled the screen with eight hex characters of a GUID.
  ///
  /// Null for tickets created before numbering existed. Null means *no number*, and the UI shows
  /// nothing rather than reaching for the id again.
  final String? numero;

  final String? description;
  final String customerId;
  final String locationId;
  final String? assignedUserId;
  final int statusId;
  final int typeId;
  final String? agentId;
  final DateTime? closedAt;
  final String? technicianNotes;
  final String? internalNotes;
  final String? contractId;
  final String? prodottoAssistenzaId;
  final String? commessaId;

  const TicketDto({
    required this.id,
    required this.tenantId,
    required this.createdAt,
    this.updatedAt,
    required this.title,
    this.numero,
    this.description,
    required this.customerId,
    required this.locationId,
    this.assignedUserId,
    required this.statusId,
    required this.typeId,
    this.agentId,
    this.closedAt,
    this.technicianNotes,
    this.internalNotes,
    this.contractId,
    this.prodottoAssistenzaId,
    this.commessaId,
  });

  factory TicketDto.fromJson(Map<String, dynamic> j) => TicketDto(
    id: j['id'] as String,
    tenantId: j['tenantId'] as String,
    createdAt: DateTime.parse(j['createdAt'] as String),
    updatedAt: _dt(j['updatedAt']),
    title: j['title'] as String,
    numero: j['numero'] as String?,
    description: j['description'] as String?,
    customerId: j['customerId'] as String,
    locationId: j['locationId'] as String,
    assignedUserId: j['assignedUserId'] as String?,
    statusId: (j['statusId'] as num).toInt(),
    typeId: (j['typeId'] as num).toInt(),
    agentId: j['agentId'] as String?,
    closedAt: _dt(j['closedAt']),
    technicianNotes: j['technicianNotes'] as String?,
    internalNotes: j['internalNotes'] as String?,
    contractId: j['contractId'] as String?,
    prodottoAssistenzaId: j['prodottoAssistenzaId'] as String?,
    commessaId: j['commessaId'] as String?,
  );
}

// ── Materiale ──────────────────────────────────────────────────────────────────

class MaterialeDto {
  final String id;
  final String tenantId;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final String code;
  final String name;
  final String? description;
  final String? unitOfMeasure;
  final String? category;
  final String? marca;
  final double? purchasePrice;
  final double? salePrice;
  final bool isActive;

  const MaterialeDto({
    required this.id,
    required this.tenantId,
    required this.createdAt,
    this.updatedAt,
    required this.code,
    required this.name,
    this.description,
    this.unitOfMeasure,
    this.category,
    this.marca,
    this.purchasePrice,
    this.salePrice,
    this.isActive = true,
  });

  factory MaterialeDto.fromJson(Map<String, dynamic> j) => MaterialeDto(
    id: j['id'] as String,
    tenantId: j['tenantId'] as String,
    createdAt: DateTime.parse(j['createdAt'] as String),
    updatedAt: _dt(j['updatedAt']),
    code: j['code'] as String,
    name: j['name'] as String,
    description: j['description'] as String?,
    unitOfMeasure: j['unitOfMeasure'] as String?,
    category: j['category'] as String?,
    marca: j['marca'] as String?,
    // decimal? fields serialise as either a JSON number or a string
    // (pattern-validated), same idiom as ReportMateriale.UnitPrice — see
    // Materiale.AliquotaIVA's XML doc for why.
    purchasePrice: _dbl(j['purchasePrice']),
    salePrice: _dbl(j['salePrice']),
    isActive: j['isActive'] as bool? ?? true,
  );
}

// ── Cantiere ───────────────────────────────────────────────────────────────────

/// CantiereStatusEnum values, in the same order as the backend enum
/// (`[JsonConverter(typeof(JsonStringEnumConverter))] enum CantiereStatusEnum`)
/// and as the `Cantieri.status` Drift column (Active=0, Completed=1, Cancelled=2).
const _cantiereStatusValues = <String, int>{'Active': 0, 'Completed': 1, 'Cancelled': 2};

/// Parses the wire enum string to the int the Drift column stores.
/// Unknown/missing values default to Active — the safest fallback for a
/// picker that filters on "active" cantieri (see [CantieriProvider] usage).
int parseCantiereStatus(dynamic v) => _cantiereStatusValues[v as String?] ?? 0;

class CantiereDto {
  final String id;
  final String tenantId;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final String name;
  final String? address;
  final String? city;
  final String? postalCode;
  final String? notes;
  final DateTime? startDate;
  final DateTime? endDate;
  final int status;
  final String? customerId;
  final String? commessaId;

  const CantiereDto({
    required this.id,
    required this.tenantId,
    required this.createdAt,
    this.updatedAt,
    required this.name,
    this.address,
    this.city,
    this.postalCode,
    this.notes,
    this.startDate,
    this.endDate,
    this.status = 0,
    this.customerId,
    this.commessaId,
  });

  factory CantiereDto.fromJson(Map<String, dynamic> j) => CantiereDto(
    id: j['id'] as String,
    tenantId: j['tenantId'] as String,
    createdAt: DateTime.parse(j['createdAt'] as String),
    updatedAt: _dt(j['updatedAt']),
    name: j['name'] as String,
    address: j['address'] as String?,
    city: j['city'] as String?,
    postalCode: j['postalCode'] as String?,
    notes: j['notes'] as String?,
    startDate: _dt(j['startDate']),
    endDate: _dt(j['endDate']),
    status: parseCantiereStatus(j['status']),
    customerId: j['customerId'] as String?,
    commessaId: j['commessaId'] as String?,
  );
}

// ── TicketStatus ───────────────────────────────────────────────────────────────

class TicketStatusDto {
  final int id;
  final String tenantId;
  final String name;
  final bool isDefault;
  final bool isClosed;

  const TicketStatusDto({
    required this.id,
    required this.tenantId,
    required this.name,
    required this.isDefault,
    required this.isClosed,
  });

  factory TicketStatusDto.fromJson(Map<String, dynamic> j) => TicketStatusDto(
    id: (j['id'] as num).toInt(),
    tenantId: j['tenantId'] as String,
    name: j['name'] as String,
    isDefault: j['isDefault'] as bool? ?? false,
    isClosed: j['isClosed'] as bool? ?? false,
  );
}

// ── TicketType ─────────────────────────────────────────────────────────────────

class TicketTypeDto {
  final int id;
  final String tenantId;
  final String name;
  final String? description;

  const TicketTypeDto({
    required this.id,
    required this.tenantId,
    required this.name,
    this.description,
  });

  factory TicketTypeDto.fromJson(Map<String, dynamic> j) => TicketTypeDto(
    id: (j['id'] as num).toInt(),
    tenantId: j['tenantId'] as String,
    name: j['name'] as String,
    description: j['description'] as String?,
  );
}

// ── Schedule ───────────────────────────────────────────────────────────────────

class ScheduleDto {
  final String id;
  final String tenantId;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final String? ticketId;
  final DateTime activityDate;

  /// TimeStart serialised as "hh:mm:ss" string (C# TimeSpan JSON default)
  final String timeStart;

  /// TimeEnd serialised as "hh:mm:ss" string
  final String timeEnd;
  final String userId;
  final int statusId;
  final String locationId;
  final bool allDay;
  final String title;
  final String description;

  /// Everyone on this schedule, with every reason they are on it.
  ///
  /// Replaces teamLeadId / staffIds / squadraId, which the server dropped (backend ADR-0009).
  /// Those three expressed three overlapping halves of one answer and could not express the
  /// fourth at all: a job assigned to a squadra named nobody the device could see.
  final List<ScheduleAssigneeDto> assignees;

  const ScheduleDto({
    required this.id,
    required this.tenantId,
    required this.createdAt,
    this.updatedAt,
    this.ticketId,
    required this.activityDate,
    required this.timeStart,
    required this.timeEnd,
    required this.userId,
    required this.statusId,
    required this.locationId,
    required this.allDay,
    required this.title,
    required this.description,
    this.assignees = const [],
  });

  factory ScheduleDto.fromJson(Map<String, dynamic> j) {
    // TimeSpan comes as "HH:MM:SS" from System.Text.Json default serialization
    final tsRaw = j['timeStart'] as String? ?? '00:00:00';
    final teRaw = j['timeEnd'] as String? ?? '00:00:00';

    return ScheduleDto(
      id: j['id'] as String,
      tenantId: j['tenantId'] as String,
      createdAt: DateTime.parse(j['createdAt'] as String),
      updatedAt: _dt(j['updatedAt']),
      ticketId: j['ticketId'] as String?,
      activityDate: DateTime.parse(j['activityDate'] as String),
      timeStart: tsRaw,
      timeEnd: teRaw,
      userId: j['userId'] as String,
      statusId: (j['statusId'] as num).toInt(),
      locationId: j['locationId'] as String,
      allDay: j['allDay'] as bool? ?? false,
      title: j['title'] as String? ?? '',
      description: j['description'] as String? ?? '',
      assignees: (j['assignees'] as List<dynamic>? ?? const [])
          .map((e) => ScheduleAssigneeDto.fromJson(e as Map<String, dynamic>))
          .toList(growable: false),
    );
  }

  /// The directly assigned technician, or null when the job is only assigned to a squadra.
  ///
  /// [userId] still carries the same value the server sends, and the server still sends the
  /// all-zeros guid when there is nobody — this is the honest reading of it.
  String? get directAssigneeId {
    for (final a in assignees) {
      if (a.isDirect) return a.userId;
    }
    return null;
  }

  /// Parse "HH:MM:SS" → total minutes since midnight.
  static int parseTimeToMinutes(String hhmm) {
    final parts = hhmm.split(':');
    if (parts.length < 2) return 0;
    final h = int.tryParse(parts[0]) ?? 0;
    final m = int.tryParse(parts[1]) ?? 0;
    return h * 60 + m;
  }
}

// ── ScheduleAssignee ───────────────────────────────────────────────────────────

/// One person on a schedule, carrying every reason they are on it rather than only the
/// strongest.
///
/// The flags are deliberately not collapsed into a single "role". A screen asking "may this
/// person write the rapportino" reads [isLead]; one asking "who is on the squadra" reads
/// [isTeam]. A single winner would make the second question unanswerable without another call —
/// which is how the server-side model went wrong in the first place.
class ScheduleAssigneeDto {
  final String userId;
  final bool isUserActive;
  final bool isDirect;
  final bool isLead;
  final bool isTeam;
  final bool isLegacyStaff;

  const ScheduleAssigneeDto({
    required this.userId,
    this.isUserActive = true,
    this.isDirect = false,
    this.isLead = false,
    this.isTeam = false,
    this.isLegacyStaff = false,
  });

  factory ScheduleAssigneeDto.fromJson(Map<String, dynamic> j) => ScheduleAssigneeDto(
    userId: j['userId'] as String,
    isUserActive: j['isUserActive'] as bool? ?? true,
    isDirect: j['isDirect'] as bool? ?? false,
    isLead: j['isLead'] as bool? ?? false,
    isTeam: j['isTeam'] as bool? ?? false,
    isLegacyStaff: j['isLegacyStaff'] as bool? ?? false,
  );
}

// ── Report (draft) ─────────────────────────────────────────────────────────────

class ReportDto {
  final String id;
  final String tenantId;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final String title;
  final String? scheduleId;
  final String? ticketId;
  final String? customerId;
  final String? details;
  final String insertedUserId;
  final String locationId;
  final DateTime? startedAt;
  final DateTime? endedAt;
  final String? documentTemplateId;
  final String? customerSignatureAllegatoId;
  final String? technicianSignatureAllegatoId;
  final String? technicianNotes;
  final DateTime? closedAt;
  final String stato;
  final DateTime? inviatoAt;
  final DateTime? controllatoAt;
  final String? controllatoDa;
  final DateTime? fatturatoAt;
  final bool materialiNotRequired;
  final String? customerSignoffText;
  final DateTime? customerSignoffAt;

  const ReportDto({
    required this.id,
    required this.tenantId,
    required this.createdAt,
    this.updatedAt,
    required this.title,
    this.scheduleId,
    this.ticketId,
    this.customerId,
    this.details,
    required this.insertedUserId,
    required this.locationId,
    this.startedAt,
    this.endedAt,
    this.documentTemplateId,
    this.customerSignatureAllegatoId,
    this.technicianSignatureAllegatoId,
    this.technicianNotes,
    this.closedAt,
    this.stato = 'Bozza',
    this.inviatoAt,
    this.controllatoAt,
    this.controllatoDa,
    this.fatturatoAt,
    this.materialiNotRequired = false,
    this.customerSignoffText,
    this.customerSignoffAt,
  });

  factory ReportDto.fromJson(Map<String, dynamic> j) => ReportDto(
    id: j['id'] as String,
    tenantId: j['tenantId'] as String,
    createdAt: DateTime.parse(j['createdAt'] as String),
    updatedAt: _dt(j['updatedAt']),
    title: j['title'] as String,
    scheduleId: j['scheduleId'] as String?,
    ticketId: j['ticketId'] as String?,
    customerId: j['customerId'] as String?,
    details: j['details'] as String?,
    insertedUserId: j['insertedUserId'] as String,
    locationId: j['locationId'] as String,
    startedAt: _dt(j['startedAt']),
    endedAt: _dt(j['endedAt']),
    documentTemplateId: j['documentTemplateId'] as String?,
    customerSignatureAllegatoId: j['customerSignatureAllegatoId'] as String?,
    technicianSignatureAllegatoId: j['technicianSignatureAllegatoId'] as String?,
    technicianNotes: j['technicianNotes'] as String?,
    closedAt: _dt(j['closedAt']),
    stato: j['stato'] as String? ?? 'Bozza',
    inviatoAt: _dt(j['inviatoAt']),
    controllatoAt: _dt(j['controllatoAt']),
    controllatoDa: j['controllatoDa'] as String?,
    fatturatoAt: _dt(j['fatturatoAt']),
    materialiNotRequired: j['materialiNotRequired'] as bool? ?? false,
    customerSignoffText: j['customerSignoffText'] as String?,
    customerSignoffAt: _dt(j['customerSignoffAt']),
  );
}

// ── Helpers ────────────────────────────────────────────────────────────────────

DateTime? _dt(dynamic v) => v == null ? null : DateTime.parse(v as String);

double? _dbl(dynamic v) {
  if (v == null) return null;
  if (v is double) return v;
  if (v is int) return v.toDouble();
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v);
  return null;
}

List<T> _list<T>(dynamic v, T Function(Map<String, dynamic>) fromJson) {
  if (v == null) return [];
  return (v as List).map((e) => fromJson(e as Map<String, dynamic>)).toList();
}
