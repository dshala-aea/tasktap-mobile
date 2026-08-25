import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api/dio_client.dart';
import '../../data/api/json_parse.dart';

// ══════════════════════════════════════════════════════════════════════════════
// AdminApiClient
//
// Shared Dio wrapper for admin CRUD operations across all entities.
// All methods POST/PUT/DELETE to the backend; reads still come from the
// local Drift cache for offline-first behavior.
// ══════════════════════════════════════════════════════════════════════════════

/// Squadra member role — mirrors backend `SquadraRuoloEnum` (`WorkEnums.cs`), which has no
/// `[JsonStringEnumConverter]` and no `TeamLead` value. It deserializes as a bare integer, so
/// sending `ruolo` as a JSON string (e.g. `"TeamLead"`) fails backend deserialization for the
/// whole add-member/change-role call.
class SquadraRuolo {
  static const int membro = 0;
  static const int capo = 1;

  /// Display label for a `ruolo` value read back from the backend. Defaults to "Membro" for
  /// anything other than [capo] (including missing/null), matching the backend enum's own
  /// `Membro = 0` default.
  static String label(Object? ruolo) => ruolo == capo ? 'Capo' : 'Membro';
}

/// One existing schedule that overlaps a proposed one, from
/// `POST /api/schedules/check-conflicts` (`ScheduleConflictDto` in `SchedulesController.cs`).
class ScheduleConflict {
  const ScheduleConflict({
    required this.id,
    required this.activityDate,
    required this.timeStart,
    required this.timeEnd,
    this.userId,
    this.squadraId,
    required this.title,
    required this.conflictOnUser,
    required this.conflictOnSquadra,
  });

  final String id;
  final DateTime activityDate;

  /// "HH:MM:SS", as the backend's `TimeSpan` serialises.
  final String timeStart;
  final String timeEnd;

  final String? userId;
  final String? squadraId;
  final String title;

  /// Whether the checked technician is the one directly assigned on this conflicting schedule.
  final bool conflictOnUser;

  /// Whether the checked squadra is the one assigned on this conflicting schedule.
  final bool conflictOnSquadra;

  factory ScheduleConflict.fromJson(Map<String, dynamic> j) => ScheduleConflict(
    id: j['id'] as String,
    activityDate: DateTime.parse(j['activityDate'] as String),
    timeStart: j['timeStart'] as String? ?? '00:00:00',
    timeEnd: j['timeEnd'] as String? ?? '00:00:00',
    userId: j['userId'] as String?,
    squadraId: j['squadraId'] as String?,
    title: j['title'] as String? ?? '',
    conflictOnUser: j['conflictOnUser'] as bool? ?? false,
    conflictOnSquadra: j['conflictOnSquadra'] as bool? ?? false,
  );
}

class AdminApiClient {
  AdminApiClient(this._dio);
  final Dio _dio;

  // ── Customers ────────────────────────────────────────────────────────────

  Future<String> createCustomer({
    required String companyName,
    String? taxId,
    String? address,
    String? city,
    String? postalCode,
    String? country,
    String? phone,
    String? email,
    String? contactPerson,
    String? notes,
  }) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/api/customers',
      data: {
        'companyName': companyName,
        if (taxId != null && taxId.isNotEmpty) 'taxId': taxId,
        if (address != null && address.isNotEmpty) 'address': address,
        if (city != null && city.isNotEmpty) 'city': city,
        if (postalCode != null && postalCode.isNotEmpty)
          'postalCode': postalCode,
        if (country != null && country.isNotEmpty) 'country': country,
        if (phone != null && phone.isNotEmpty) 'phone': phone,
        if (email != null && email.isNotEmpty) 'email': email,
        if (contactPerson != null && contactPerson.isNotEmpty)
          'contactPerson': contactPerson,
        if (notes != null && notes.isNotEmpty) 'notes': notes,
      },
    );
    return res.data!['id'] as String;
  }

  Future<void> updateCustomer(
    String id, {
    String? companyName,
    String? taxId,
    String? address,
    String? city,
    String? postalCode,
    String? country,
    String? phone,
    String? email,
    String? contactPerson,
    String? notes,
    bool? isActive,
  }) async {
    await _dio.put(
      '/api/customers/$id',
      data: {
        'companyName': ?companyName,
        'taxId': ?taxId,
        'address': ?address,
        'city': ?city,
        'postalCode': ?postalCode,
        'country': ?country,
        'phone': ?phone,
        'email': ?email,
        'contactPerson': ?contactPerson,
        'notes': ?notes,
        'isActive': ?isActive,
      },
    );
  }

  /// Soft-deletes a customer. Mirrors `DELETE /api/customers/{id}` (CustomersController.Delete).
  Future<void> deleteCustomer(String id) async {
    await _dio.delete('/api/customers/$id');
  }

  // ── Locations ────────────────────────────────────────────────────────────

  Future<String> createLocation({
    required String customerId,
    required String name,
    String? address,
    String? city,
    String? postalCode,
    String? country,
    double? latitude,
    double? longitude,
    String? phone,
    String? notes,
  }) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/api/locations',
      data: {
        'customerId': customerId,
        'name': name,
        if (address != null && address.isNotEmpty) 'address': address,
        if (city != null && city.isNotEmpty) 'city': city,
        if (postalCode != null && postalCode.isNotEmpty)
          'postalCode': postalCode,
        if (country != null && country.isNotEmpty) 'country': country,
        'latitude': ?latitude,
        'longitude': ?longitude,
        if (phone != null && phone.isNotEmpty) 'phone': phone,
        if (notes != null && notes.isNotEmpty) 'notes': notes,
      },
    );
    return res.data!['id'] as String;
  }

  Future<void> updateLocation(
    String id, {
    String? customerId,
    String? name,
    String? address,
    String? city,
    String? postalCode,
    String? country,
    double? latitude,
    double? longitude,
    String? phone,
    String? notes,
    bool? isActive,
  }) async {
    await _dio.put(
      '/api/locations/$id',
      data: {
        'customerId': ?customerId,
        'name': ?name,
        'address': ?address,
        'city': ?city,
        'postalCode': ?postalCode,
        'country': ?country,
        'latitude': ?latitude,
        'longitude': ?longitude,
        'phone': ?phone,
        'notes': ?notes,
        'isActive': ?isActive,
      },
    );
  }

  /// Mirrors `DELETE /api/locations/{id}` (`LocationsController.Delete`). Gap 3 of the feature
  /// audit — the create/edit half of Sedi CRUD existed, delete did not, on the customer detail
  /// screen or anywhere else in the app.
  Future<void> deleteLocation(String id) async {
    await _dio.delete('/api/locations/$id');
  }

  // ── Cantieri ─────────────────────────────────────────────────────────────

  Future<String> createCantiere({
    required String name,
    String? address,
    String? city,
    String? postalCode,
    String? notes,
    DateTime? startDate,
    DateTime? endDate,
    int status = 0,
    String? customerId,
    // CreateCantiereRequest.CommessaId (CantieriController.cs) — landed backend-side in af9039c;
    // before that this field didn't exist on the request DTO at all, so sending it would have
    // silently no-opped (see Gap 5 of the feature audit).
    String? commessaId,
  }) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/api/cantieri',
      data: {
        'name': name,
        if (address != null && address.isNotEmpty) 'address': address,
        if (city != null && city.isNotEmpty) 'city': city,
        if (postalCode != null && postalCode.isNotEmpty)
          'postalCode': postalCode,
        if (notes != null && notes.isNotEmpty) 'notes': notes,
        if (startDate != null) 'startDate': startDate.toIso8601String(),
        if (endDate != null) 'endDate': endDate.toIso8601String(),
        'status': status,
        'customerId': ?customerId,
        'commessaId': ?commessaId,
      },
    );
    return res.data!['id'] as String;
  }

  Future<void> updateCantiere(
    String id, {
    required String name,
    String? address,
    String? city,
    String? postalCode,
    String? notes,
    DateTime? startDate,
    DateTime? endDate,
    int status = 0,
    String? customerId,
    /// See [createCantiere]'s own doc comment on this field.
    String? commessaId,
  }) async {
    await _dio.put(
      '/api/cantieri/$id',
      data: {
        'name': name,
        'address': ?address,
        'city': ?city,
        'postalCode': ?postalCode,
        'notes': ?notes,
        if (startDate != null) 'startDate': startDate.toIso8601String(),
        if (endDate != null) 'endDate': endDate.toIso8601String(),
        'status': status,
        'customerId': ?customerId,
        'commessaId': ?commessaId,
      },
    );
  }

  /// Hard-deletes a cantiere. Mirrors `DELETE /api/cantieri/{id}` (CantieriController.Delete).
  Future<void> deleteCantiere(String id) async {
    await _dio.delete('/api/cantieri/$id');
  }

  /// Live cantiere detail — `GET /api/cantieri/{id}` (`CantieriController.GetById`), returning
  /// `CantiereDetailResponse` (`{cantiere, contacts, assignments}`). Unlike the Drift mirror
  /// (`Cantieri` table, base fields only), this is the only source for a cantiere's contacts and
  /// crew assignments — neither sub-resource is synced to the device.
  Future<Map<String, dynamic>?> fetchCantiereDetail(String id) async {
    final res = await _dio.get<Map<String, dynamic>>('/api/cantieri/$id');
    return res.data;
  }

  // ── Cantiere contacts ────────────────────────────────────────────────────
  //
  // Mirrors UpsertCantiereContactRequest (CantieriController.cs:386-393) — the same shape for
  // both add and update, name required, everything else optional.

  Future<String> addCantiereContact(
    String cantiereId, {
    required String name,
    String? role,
    String? phone,
    String? email,
    String? notes,
  }) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/api/cantieri/$cantiereId/contacts',
      data: {'name': name, 'role': ?role, 'phone': ?phone, 'email': ?email, 'notes': ?notes},
    );
    return res.data!['id'] as String;
  }

  Future<void> updateCantiereContact(
    String cantiereId,
    String contactId, {
    required String name,
    String? role,
    String? phone,
    String? email,
    String? notes,
  }) async {
    await _dio.put(
      '/api/cantieri/$cantiereId/contacts/$contactId',
      data: {'name': name, 'role': ?role, 'phone': ?phone, 'email': ?email, 'notes': ?notes},
    );
  }

  /// Mirrors `DELETE /api/cantieri/{id}/contacts/{contactId}` (`CantieriController.DeleteContact`).
  Future<void> deleteCantiereContact(String cantiereId, String contactId) async {
    await _dio.delete('/api/cantieri/$cantiereId/contacts/$contactId');
  }

  // ── Cantiere crew assignments ───────────────────────────────────────────
  //
  // Individual technician only — `CantiereAssignment` has no `SquadraId` (unlike
  // `ScheduleAssignment`), so there is no squadra-level assignment to offer here.

  Future<String> addCantiereAssignment(
    String cantiereId, {
    required String userId,
    String? role,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/api/cantieri/$cantiereId/assignments',
      data: {
        'userId': userId,
        'role': ?role,
        if (startDate != null) 'startDate': startDate.toIso8601String(),
        if (endDate != null) 'endDate': endDate.toIso8601String(),
      },
    );
    return res.data!['id'] as String;
  }

  /// Mirrors `DELETE /api/cantieri/{id}/assignments/{assignmentId}`
  /// (`CantieriController.RemoveAssignment`).
  Future<void> removeCantiereAssignment(String cantiereId, String assignmentId) async {
    await _dio.delete('/api/cantieri/$cantiereId/assignments/$assignmentId');
  }

  // ── Cantiere linked records (read-only) ─────────────────────────────────
  //
  // None of these are synced to Drift — the cantiere detail screen's Ore/Interventi/Rapportini
  // sections fetch them live, mirroring web's OreSection/InterventiSection/RapportiniSection
  // (frontend/src/features/cantieri/CantiereSections.tsx).

  /// Interventi (tickets) raised on this cantiere — `GET /api/tickets?cantiereId=`.
  Future<List<Map<String, dynamic>>> fetchCantiereTickets(String cantiereId) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/api/tickets',
      queryParameters: {'cantiereId': cantiereId, 'pageSize': 50, 'sort': '-createdAt'},
    );
    return pagedItems(res.data);
  }

  /// Hours logged on this cantiere — `GET /api/cantiereworklog?cantiereId=`.
  Future<List<Map<String, dynamic>>> fetchCantiereWorkLogs(String cantiereId) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/api/cantiereworklog',
      queryParameters: {'cantiereId': cantiereId, 'pageSize': 50, 'sort': '-workDate'},
    );
    return pagedItems(res.data);
  }

  // ── Commesse ─────────────────────────────────────────────────────────────
  //
  // No local Drift mirror — like Squadre/ProdottoAssistenza, fetched live wherever a picker needs
  // the list (here: the cantiere form's Commessa field, Gap 5 of the feature audit).

  Future<List<Map<String, dynamic>>> fetchCommesse() async {
    final res = await _dio.get<Map<String, dynamic>>('/api/commesse');
    return pagedItems(res.data);
  }

  // ── Schedules ────────────────────────────────────────────────────────────

  Future<String> createSchedule({
    required DateTime activityDate,
    required int timeStartMinutes,
    required int timeEndMinutes,
    // Optional, matching backend `CreateScheduleRequest.UserId` (ADR-0009): a schedule can be
    // assigned to a squadra and to no individual, and requiring this here made a team-only
    // schedule impossible to create from mobile.
    String? userId,
    required int statusId,
    required String locationId,
    String? ticketId,
    bool allDay = false,
    String? title,
    String? description,
    String? teamLeadId,
    String? staffIds,
    String? squadraId,

    /// Sent as `?force=true` when the caller already showed the admin a conflict list (from
    /// [checkScheduleConflicts]) and they chose to save anyway. Mirrors
    /// `SchedulesController.Create`'s `force` query param, which otherwise answers 409 with the
    /// conflicts.
    bool force = false,
  }) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/api/schedules',
      queryParameters: force ? {'force': true} : null,
      data: {
        'activityDate': activityDate.toIso8601String(),
        'timeStart':
            '${(timeStartMinutes ~/ 60).toString().padLeft(2, '0')}:${(timeStartMinutes % 60).toString().padLeft(2, '0')}:00',
        'timeEnd':
            '${(timeEndMinutes ~/ 60).toString().padLeft(2, '0')}:${(timeEndMinutes % 60).toString().padLeft(2, '0')}:00',
        'userId': ?userId,
        'statusId': statusId,
        'locationId': locationId,
        'ticketId': ?ticketId,
        'allDay': allDay,
        if (title != null && title.isNotEmpty) 'title': title,
        if (description != null && description.isNotEmpty)
          'description': description,
        'teamLeadId': ?teamLeadId,
        'staffIds': ?staffIds,
        'squadraId': ?squadraId,
      },
    );
    return res.data!['id'] as String;
  }

  /// Updates a schedule, including its assignment (`teamLeadId`/`staffIds`/`squadraId`) — this used
  /// to only cover the five scalar fields, which meant an admin could never re-assign an existing
  /// schedule from mobile even though `UpdateScheduleRequest` (`SchedulesController.cs`) has always
  /// accepted these.
  ///
  /// To actually *change* which assignment kind a schedule has (e.g. individual → squadra), the
  /// caller must explicitly clear the sources being replaced by passing the all-zeros GUID
  /// (`00000000-0000-0000-0000-000000000000`) for `userId`/`teamLeadId`/`squadraId`, or `"[]"` for
  /// `staffIds` — omitting a field here means "untouched" server-side
  /// (`ScheduleAssignmentWriter.ApplyAsync`: "only sources the input speaks about are reconciled"),
  /// and a JSON `null` binds identically to an absent key, so there is no other way to say "no
  /// longer this". `AdminScheduleFormScreen._save` does this when switching assignment type.
  Future<void> updateSchedule(
    String id, {
    DateTime? activityDate,
    int? timeStartMinutes,
    int? timeEndMinutes,
    String? userId,
    int? statusId,
    String? locationId,
    String? ticketId,
    bool? allDay,
    String? title,
    String? description,
    String? teamLeadId,
    String? staffIds,
    String? squadraId,

    /// See [createSchedule]'s `force`.
    bool force = false,
  }) async {
    await _dio.put(
      '/api/schedules/$id',
      queryParameters: force ? {'force': true} : null,
      data: {
        if (activityDate != null)
          'activityDate': activityDate.toIso8601String(),
        if (timeStartMinutes != null)
          'timeStart':
              '${(timeStartMinutes ~/ 60).toString().padLeft(2, '0')}:${(timeStartMinutes % 60).toString().padLeft(2, '0')}:00',
        if (timeEndMinutes != null)
          'timeEnd':
              '${(timeEndMinutes ~/ 60).toString().padLeft(2, '0')}:${(timeEndMinutes % 60).toString().padLeft(2, '0')}:00',
        'userId': ?userId,
        'statusId': ?statusId,
        'locationId': ?locationId,
        'ticketId': ?ticketId,
        'allDay': ?allDay,
        'title': ?title,
        'description': ?description,
        'teamLeadId': ?teamLeadId,
        'staffIds': ?staffIds,
        'squadraId': ?squadraId,
      },
    );
  }

  /// Live schedule detail — `GET /api/schedules/{id}` (`SchedulesController.GetById`). Unlike the
  /// Drift mirror (`Schedule` row + `ScheduleAssignees`, synced from the sparser sync payload),
  /// this resolves `teamLeadId`/`squadraId`/`squadraNome`, which nothing on-device carries. Used to
  /// prefill the assignment picker when opening the edit form — offline, the form falls back to
  /// what the mirror knows (direct/team, no squadra id) rather than blocking entirely.
  Future<Map<String, dynamic>?> fetchScheduleDetail(String id) async {
    final res = await _dio.get<Map<String, dynamic>>('/api/schedules/$id');
    return res.data;
  }

  /// The all-zeros GUID `updateSchedule` needs to *explicitly* clear an assignment field — see
  /// that method's doc comment for why an omitted/null field cannot do this.
  static const String emptyAssignmentId =
      '00000000-0000-0000-0000-000000000000';

  /// Pre-flight conflict check, mirroring `POST /api/schedules/check-conflicts`
  /// (`SchedulesController.CheckConflicts`). Returns every schedule the given user/squadra is
  /// already explicitly booked on for the same day with an overlapping time (or either is
  /// `allDay`). An empty list means it is safe to save without `force`.
  Future<List<ScheduleConflict>> checkScheduleConflicts({
    required DateTime activityDate,
    required int timeStartMinutes,
    required int timeEndMinutes,
    bool allDay = false,
    String? userId,
    String? squadraId,
    String? excludeScheduleId,
  }) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/api/schedules/check-conflicts',
      data: {
        'activityDate': activityDate.toIso8601String(),
        'timeStart':
            '${(timeStartMinutes ~/ 60).toString().padLeft(2, '0')}:${(timeStartMinutes % 60).toString().padLeft(2, '0')}:00',
        'timeEnd':
            '${(timeEndMinutes ~/ 60).toString().padLeft(2, '0')}:${(timeEndMinutes % 60).toString().padLeft(2, '0')}:00',
        'allDay': allDay,
        'userId': ?userId,
        'squadraId': ?squadraId,
        'excludeScheduleId': ?excludeScheduleId,
      },
    );
    final conflicts = res.data?['conflicts'] as List<dynamic>? ?? const [];
    return conflicts
        .map((e) => ScheduleConflict.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
  }

  // ── Tickets ─────────────────────────────────────────────────────────────

  Future<void> assignTicket(String ticketId, String? userId) async {
    await _dio.put('/api/tickets/$ticketId', data: {'assignedUserId': ?userId});
  }

  /// General field edit from ticket detail (`EditTicketScreen`) — distinct from [assignTicket],
  /// which narrowly sends `assignedUserId` for the "Assegna" action.
  ///
  /// Matches `UpdateTicketRequest` (`TicketsController.cs`): every field is optional there too,
  /// but this only ever sends the five the edit screen actually exposes — title, description,
  /// customer, location, type. `statusId` has no PUT field at all (status changes go through
  /// `PUT /api/Tickets/{id}/status` — see `TicketWorkflowApiClient.updateStatus`) and priority is
  /// deliberately left alone (see `StepDettagliTicket.showPriority`'s doc comment for why).
  Future<void> updateTicket(
    String id, {
    String? title,
    String? description,
    String? customerId,
    String? locationId,
    int? typeId,
  }) async {
    await _dio.put(
      '/api/tickets/$id',
      data: {
        'title': ?title,
        'description': ?description,
        'customerId': ?customerId,
        'locationId': ?locationId,
        'typeId': ?typeId,
      },
    );
  }

  Future<List<Map<String, dynamic>>> fetchTechnicians() async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/api/users',
      queryParameters: {
        'role': 'Technician',
        'isActive': 'true',
        'pageSize': 200,
      },
    );
    return pagedItems(res.data);
  }

  // ── Materiali ────────────────────────────────────────────────────────────

  Future<String> createMateriale({
    required String code,
    required String name,
    String? description,
    String? unitOfMeasure,
    String? category,
    String? marca,
    double? purchasePrice,
    double? salePrice,
    double? aliquotaIva,
  }) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/api/materiali',
      data: {
        'code': code,
        'name': name,
        if (description != null && description.isNotEmpty)
          'description': description,
        if (unitOfMeasure != null && unitOfMeasure.isNotEmpty)
          'unitOfMeasure': unitOfMeasure,
        if (category != null && category.isNotEmpty) 'category': category,
        if (marca != null && marca.isNotEmpty) 'marca': marca,
        'purchasePrice': ?purchasePrice,
        'salePrice': ?salePrice,
        'aliquotaIVA': ?aliquotaIva,
      },
    );
    return res.data!['id'] as String;
  }

  Future<void> updateMateriale(
    String id, {
    String? code,
    String? name,
    String? description,
    String? unitOfMeasure,
    String? category,
    String? marca,
    double? purchasePrice,
    double? salePrice,
    double? aliquotaIva,
    bool? isActive,
  }) async {
    await _dio.put(
      '/api/materiali/$id',
      data: {
        'code': ?code,
        'name': ?name,
        'description': ?description,
        'unitOfMeasure': ?unitOfMeasure,
        'category': ?category,
        'marca': ?marca,
        'purchasePrice': ?purchasePrice,
        'salePrice': ?salePrice,
        'aliquotaIVA': ?aliquotaIva,
        'isActive': ?isActive,
      },
    );
  }

  /// Soft-deletes a materiale — mirrors `DELETE /api/materiali/{id}` (`MaterialiController.Delete`),
  /// which sets `IsActive = false` server-side rather than removing the row. Reactivating is a
  /// plain [updateMateriale] call with `isActive: true` — there is no separate "undelete" route.
  Future<void> deleteMateriale(String id) async {
    await _dio.delete('/api/materiali/$id');
  }

  // ── Materiale barcodes ───────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> fetchMaterialeBarcodes(
    String materialeId,
  ) async {
    final res = await _dio.get<List<dynamic>>(
      '/api/materiali/$materialeId/barcodes',
    );
    return (res.data ?? const []).cast<Map<String, dynamic>>();
  }

  Future<void> addMaterialeBarcode(
    String materialeId, {
    required String barcode,
    String? barcodeType,
    bool isPrimary = false,
  }) async {
    await _dio.post(
      '/api/materiali/$materialeId/barcodes',
      data: {
        'barcode': barcode,
        'barcodeType': ?barcodeType,
        'isPrimary': isPrimary,
      },
    );
  }

  Future<void> updateMaterialeBarcode(
    String materialeId,
    String barcodeId, {
    String? barcode,
    String? barcodeType,
    bool? isPrimary,
  }) async {
    await _dio.put(
      '/api/materiali/$materialeId/barcodes/$barcodeId',
      data: {
        'barcode': ?barcode,
        'barcodeType': ?barcodeType,
        'isPrimary': ?isPrimary,
      },
    );
  }

  Future<void> deleteMaterialeBarcode(
    String materialeId,
    String barcodeId,
  ) async {
    await _dio.delete('/api/materiali/$materialeId/barcodes/$barcodeId');
  }

  Future<void> setPrimaryMaterialeBarcode(
    String materialeId,
    String barcodeId,
  ) async {
    await _dio.put('/api/materiali/$materialeId/barcodes/$barcodeId/primary');
  }

  // ── Materiale image ──────────────────────────────────────────────────────

  /// Uploads (replacing any previous) image for a materiale — multipart, field name `file` to
  /// match `MaterialiController.UploadImage(Guid id, IFormFile file, ...)`. Returns the content
  /// URL to serve it back (`MaterialeImageResponse.ContentUrl`), never a storage key.
  Future<String> uploadMaterialeImage(
    String materialeId, {
    required List<int> bytes,
    required String fileName,
    String? contentType,
  }) async {
    final formData = FormData.fromMap({
      'file': MultipartFile.fromBytes(
        bytes,
        filename: fileName,
        contentType: contentType == null
            ? null
            : DioMediaType.parse(contentType),
      ),
    });
    final res = await _dio.post<Map<String, dynamic>>(
      '/api/materiali/$materialeId/image',
      data: formData,
      options: Options(headers: {'Content-Type': 'multipart/form-data'}),
    );
    return res.data!['contentUrl'] as String;
  }

  Future<void> deleteMaterialeImage(String materialeId) async {
    await _dio.delete('/api/materiali/$materialeId/image');
  }

  /// Live materiale detail — `GET /api/materiali/{id}` (`MaterialiController.GetById`), the full
  /// `MaterialeWithBarcodesDto`. Used to prefill fields the local Drift mirror does not carry
  /// (`AliquotaIVA`, barcodes) when opening the edit form — best-effort, offline just leaves that
  /// management unavailable this session rather than blocking the base-field prefill, which
  /// already comes from Drift and works offline.
  Future<Map<String, dynamic>?> fetchMaterialeDetail(String id) async {
    final res = await _dio.get<Map<String, dynamic>>('/api/materiali/$id');
    return res.data;
  }

  // ── ProdottoAssistenza ──────────────────────────────────────────────────

  /// [customerId], when given, filters server-side via `ProdottoAssistenzaController.GetAll`'s
  /// own `customerId` query param (Gap 8 of the feature audit — a customer's Prodotti section
  /// needs this scoped, not a client-side filter over an unpaginated fetch that could miss rows
  /// past the default 20-item page).
  Future<List<Map<String, dynamic>>> fetchProdottiAssistenza({String? customerId}) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/api/prodottoassistenza',
      queryParameters: {'customerId': ?customerId, 'pageSize': 100},
    );
    return pagedItems(res.data);
  }

  /// [code]/[category]/[unitOfMeasure]/[purchasePrice]/[salePrice] are the commercial fields
  /// (W6b Task 6 migration `AddProdottoAssistenzaCommercialFields`, Gap 1 of the feature audit);
  /// [marca]/[modello]/[tipo]/[dataInstallazione]/[ultimaManutenzione]/[prossimaManutenzione]/
  /// [contrattoId] are the lifecycle fields (W6b Task 6, Gap 2); [externalId] is the legacy
  /// gestionale id (W6b Task 8, Gap 7). Dart param names follow this file's existing English
  /// convention (matching [createMateriale]'s `code`/`category`/`unitOfMeasure`/`purchasePrice`/
  /// `salePrice`), but the wire names are Italian per `ProdottoAssistenza.cs`'s
  /// `[JsonPropertyName]` overrides — most notably [marca] → `"marchio"` on the wire, NOT
  /// `"marca"` (that's Materiale's brand field name, a different entity with a different wire
  /// name for the same concept).
  Future<String> createProdottoAssistenza({
    required String name,
    required String customerId,
    required String locationId,
    String? description,
    String? serialNumber,
    DateTime? warrantyExpiryDate,
    String? notes,
    String? code,
    String? category,
    String? unitOfMeasure,
    double? purchasePrice,
    double? salePrice,
    String? marca,
    String? modello,
    String? tipo,
    DateTime? dataInstallazione,
    DateTime? ultimaManutenzione,
    DateTime? prossimaManutenzione,
    String? contrattoId,
    String? externalId,
  }) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/api/prodottoassistenza',
      data: {
        'name': name,
        'customerId': customerId,
        'locationId': locationId,
        if (description != null && description.isNotEmpty)
          'description': description,
        if (serialNumber != null && serialNumber.isNotEmpty)
          'serialNumber': serialNumber,
        if (warrantyExpiryDate != null)
          'warrantyExpiryDate': warrantyExpiryDate.toIso8601String(),
        if (notes != null && notes.isNotEmpty) 'notes': notes,
        if (code != null && code.isNotEmpty) 'codice': code,
        if (category != null && category.isNotEmpty) 'categoria': category,
        if (unitOfMeasure != null && unitOfMeasure.isNotEmpty) 'um': unitOfMeasure,
        'prezzoAcquisto': ?purchasePrice,
        'prezzoVendita': ?salePrice,
        if (marca != null && marca.isNotEmpty) 'marchio': marca,
        if (modello != null && modello.isNotEmpty) 'modello': modello,
        if (tipo != null && tipo.isNotEmpty) 'tipo': tipo,
        if (dataInstallazione != null)
          'dataInstallazione': dataInstallazione.toIso8601String(),
        if (ultimaManutenzione != null)
          'ultimaManutenzione': ultimaManutenzione.toIso8601String(),
        if (prossimaManutenzione != null)
          'prossimaManutenzione': prossimaManutenzione.toIso8601String(),
        'contrattoId': ?contrattoId,
        if (externalId != null && externalId.isNotEmpty) 'externalId': externalId,
      },
    );
    return res.data!['id'] as String;
  }

  /// See [createProdottoAssistenza]'s doc comment for the field-name mapping. Following this
  /// file's established update convention, every optional field here uses the null-aware `?`
  /// map-entry spread — omitted (untouched server-side) only when null, sent (including empty
  /// string, to clear) otherwise. The one exception is the four `DateTime?` fields, which the
  /// backend's `UpdateProdottoAssistenzaRequest` can only ever *set* (each guarded by
  /// `.HasValue` server-side, matching `warrantyExpiryDate`'s pre-existing behavior here) — there
  /// is no way to clear a date once set via this endpoint.
  Future<void> updateProdottoAssistenza(
    String id, {
    String? name,
    String? customerId,
    String? locationId,
    String? description,
    String? serialNumber,
    DateTime? warrantyExpiryDate,
    String? notes,
    bool? isActive,
    String? code,
    String? category,
    String? unitOfMeasure,
    double? purchasePrice,
    double? salePrice,
    String? marca,
    String? modello,
    String? tipo,
    DateTime? dataInstallazione,
    DateTime? ultimaManutenzione,
    DateTime? prossimaManutenzione,
    String? contrattoId,
    String? externalId,
  }) async {
    await _dio.put(
      '/api/prodottoassistenza/$id',
      data: {
        'name': ?name,
        'customerId': ?customerId,
        'locationId': ?locationId,
        'description': ?description,
        'serialNumber': ?serialNumber,
        if (warrantyExpiryDate != null)
          'warrantyExpiryDate': warrantyExpiryDate.toIso8601String(),
        'notes': ?notes,
        'isActive': ?isActive,
        'codice': ?code,
        'categoria': ?category,
        'um': ?unitOfMeasure,
        'prezzoAcquisto': ?purchasePrice,
        'prezzoVendita': ?salePrice,
        'marchio': ?marca,
        'modello': ?modello,
        'tipo': ?tipo,
        if (dataInstallazione != null)
          'dataInstallazione': dataInstallazione.toIso8601String(),
        if (ultimaManutenzione != null)
          'ultimaManutenzione': ultimaManutenzione.toIso8601String(),
        if (prossimaManutenzione != null)
          'prossimaManutenzione': prossimaManutenzione.toIso8601String(),
        'contrattoId': ?contrattoId,
        'externalId': ?externalId,
      },
    );
  }

  /// Hard-deletes a prodotto assistenza — mirrors `DELETE /api/prodottoassistenza/{id}`
  /// (`ProdottoAssistenzaController.Delete`), which has no soft-delete/undo path (Gap 5 of the
  /// feature audit — this action never existed on mobile before).
  Future<void> deleteProdottoAssistenza(String id) async {
    await _dio.delete('/api/prodottoassistenza/$id');
  }

  // ── Matricole (Gap 3 of the feature audit) ──────────────────────────────
  //
  // Real 1:N serial-number sub-resource replacing the deprecated scalar `serialNumber` field
  // (which stays on the entity/form, just no longer the only way to record a serial — see
  // ProdottoAssistenzaController.cs:253-313 and Matricola.cs). Soft-removed server-side
  // (IsActive=false), same shape as Materiale barcodes / cantiere contacts: list/add/remove under
  // the parent's id, no update route (the backend never added one — add a new matricola / remove
  // the wrong one instead of editing in place).

  Future<List<Map<String, dynamic>>> fetchMatricole(String prodottoId) async {
    final res = await _dio.get<List<dynamic>>('/api/prodottoassistenza/$prodottoId/matricole');
    return (res.data ?? const []).cast<Map<String, dynamic>>();
  }

  Future<String> addMatricola(String prodottoId, {required String numero, String? note}) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/api/prodottoassistenza/$prodottoId/matricole',
      data: {'numero': numero, 'note': ?note},
    );
    return res.data!['id'] as String;
  }

  Future<void> deleteMatricola(String prodottoId, String matricolaId) async {
    await _dio.delete('/api/prodottoassistenza/$prodottoId/matricole/$matricolaId');
  }

  // ── Contracts ────────────────────────────────────────────────────────────

  /// [customerId], when given, filters server-side via `ContractsController.GetAll`'s own
  /// `customerId` query param (Gap 7 of the feature audit — a customer's Contratti section needs
  /// this scoped, not a client-side filter over an unpaginated fetch that could miss rows past the
  /// default 20-item page).
  Future<List<Map<String, dynamic>>> fetchContracts({String? customerId}) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/api/contracts',
      queryParameters: {'customerId': ?customerId, 'pageSize': 100},
    );
    return pagedItems(res.data);
  }

  Future<String> createContract({
    required String name,
    required String customerId,
    required DateTime startDate,
    String? description,
    String? locationId,
    String? prodottoAssistenzaId,
    DateTime? endDate,
    double? price,
    int frequencyValue = 1,
    int frequencyUnit = 1,
    String? notes,
  }) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/api/contracts',
      data: {
        'name': name,
        'customerId': customerId,
        'startDate': startDate.toIso8601String(),
        if (description != null && description.isNotEmpty)
          'description': description,
        'locationId': ?locationId,
        'prodottoAssistenzaId': ?prodottoAssistenzaId,
        if (endDate != null) 'endDate': endDate.toIso8601String(),
        'price': ?price,
        'frequencyValue': frequencyValue,
        'frequencyUnit': frequencyUnit,
        if (notes != null && notes.isNotEmpty) 'notes': notes,
      },
    );
    return res.data!['id'] as String;
  }

  Future<void> updateContract(
    String id, {
    String? name,
    String? customerId,
    DateTime? startDate,
    String? description,
    String? locationId,
    String? prodottoAssistenzaId,
    DateTime? endDate,
    double? price,
    int? frequencyValue,
    int? frequencyUnit,
    String? notes,
    bool? isActive,
  }) async {
    await _dio.put(
      '/api/contracts/$id',
      data: {
        'name': ?name,
        'customerId': ?customerId,
        if (startDate != null) 'startDate': startDate.toIso8601String(),
        'description': ?description,
        'locationId': ?locationId,
        'prodottoAssistenzaId': ?prodottoAssistenzaId,
        if (endDate != null) 'endDate': endDate.toIso8601String(),
        'price': ?price,
        'frequencyValue': ?frequencyValue,
        'frequencyUnit': ?frequencyUnit,
        'notes': ?notes,
        'isActive': ?isActive,
      },
    );
  }

  // ── Squadre ─────────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> fetchSquadre() async {
    final res = await _dio.get<Map<String, dynamic>>('/api/squadre');
    return pagedItems(res.data);
  }

  Future<Map<String, dynamic>?> fetchSquadraDetail(String id) async {
    final res = await _dio.get<Map<String, dynamic>>('/api/squadre/$id');
    return res.data;
  }

  Future<String> createSquadra({
    required String nome,
    String? descrizione,
    String? specializzazione,
    String? coloreCalendario,
    String? note,
  }) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/api/squadre',
      data: {
        'nome': nome,
        if (descrizione != null && descrizione.isNotEmpty)
          'descrizione': descrizione,
        if (specializzazione != null && specializzazione.isNotEmpty)
          'specializzazione': specializzazione,
        if (coloreCalendario != null && coloreCalendario.isNotEmpty)
          'coloreCalendario': coloreCalendario,
        if (note != null && note.isNotEmpty) 'note': note,
      },
    );
    return res.data!['id'] as String;
  }

  Future<void> updateSquadra(
    String id, {
    String? nome,
    String? descrizione,
    String? specializzazione,
    String? coloreCalendario,
    String? note,
    bool? isActive,
  }) async {
    await _dio.put(
      '/api/squadre/$id',
      data: {
        'nome': ?nome,
        'descrizione': ?descrizione,
        'specializzazione': ?specializzazione,
        'coloreCalendario': ?coloreCalendario,
        'note': ?note,
        'isActive': ?isActive,
      },
    );
  }

  Future<void> addSquadraMember(
    String squadraId, {
    required String userId,
    int ruolo = SquadraRuolo.membro,
  }) async {
    await _dio.post(
      '/api/squadre/$squadraId/membri',
      data: {'userId': userId, 'ruolo': ruolo},
    );
  }

  Future<void> removeSquadraMember(String squadraId, String userId) async {
    await _dio.delete('/api/squadre/$squadraId/membri/$userId');
  }

  // ── Reports (admin read-only + state transitions) ────────────────────────

  Future<List<Map<String, dynamic>>> fetchReports({
    String? stato,
    // Rapportini documenting work on a cantiere (Gap 6) — `GET /api/reports?cantiereId=`, same
    // filter web's RapportiniSection uses (frontend/src/features/cantieri/api.ts).
    String? cantiereId,
    int page = 1,
    int pageSize = 50,
  }) async {
    // Read as an envelope here and as a bare list in ticket_detail_api_client until now — the
    // same endpoint, two shapes, one app. This was the broken one.
    final res = await _dio.get<Map<String, dynamic>>(
      '/api/reports',
      queryParameters: {'stato': ?stato, 'cantiereId': ?cantiereId, 'page': page, 'pageSize': pageSize},
    );
    return pagedItems(res.data);
  }

  Future<void> controllaReport(String reportId) async {
    await _dio.post('/api/reports/$reportId/controlla');
  }

  Future<void> fatturaReport(String reportId) async {
    await _dio.post('/api/reports/$reportId/fattura');
  }
}

final adminApiClientProvider = Provider<AdminApiClient>((ref) {
  return AdminApiClient(ref.watch(dioProvider));
});
