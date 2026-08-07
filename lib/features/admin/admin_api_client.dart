import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api/dio_client.dart';

// ══════════════════════════════════════════════════════════════════════════════
// AdminApiClient
//
// Shared Dio wrapper for admin CRUD operations across all entities.
// All methods POST/PUT/DELETE to the backend; reads still come from the
// local Drift cache for offline-first behavior.
// ══════════════════════════════════════════════════════════════════════════════

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
        if (postalCode != null && postalCode.isNotEmpty) 'postalCode': postalCode,
        if (country != null && country.isNotEmpty) 'country': country,
        if (phone != null && phone.isNotEmpty) 'phone': phone,
        if (email != null && email.isNotEmpty) 'email': email,
        if (contactPerson != null && contactPerson.isNotEmpty)
          'contactPerson': contactPerson,
        if (notes != null && notes.isNotEmpty) 'notes': notes,
      },
    );
    return res.data!['customerId'] as String;
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
        if (postalCode != null && postalCode.isNotEmpty) 'postalCode': postalCode,
        if (country != null && country.isNotEmpty) 'country': country,
        'latitude': ?latitude,
        'longitude': ?longitude,
        if (phone != null && phone.isNotEmpty) 'phone': phone,
        if (notes != null && notes.isNotEmpty) 'notes': notes,
      },
    );
    return res.data!['locationId'] as String;
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
  }) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/api/cantieri',
      data: {
        'name': name,
        if (address != null && address.isNotEmpty) 'address': address,
        if (city != null && city.isNotEmpty) 'city': city,
        if (postalCode != null && postalCode.isNotEmpty) 'postalCode': postalCode,
        if (notes != null && notes.isNotEmpty) 'notes': notes,
        if (startDate != null) 'startDate': startDate.toIso8601String(),
        if (endDate != null) 'endDate': endDate.toIso8601String(),
        'status': status,
        'customerId': ?customerId,
      },
    );
    return res.data!['cantiereId'] as String;
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
      },
    );
  }

  // ── Schedules ────────────────────────────────────────────────────────────

  Future<String> createSchedule({
    required DateTime activityDate,
    required int timeStartMinutes,
    required int timeEndMinutes,
    required String userId,
    required int statusId,
    required String locationId,
    String? ticketId,
    bool allDay = false,
    String? title,
    String? description,
    String? teamLeadId,
    String? staffIds,
    String? squadraId,
  }) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/api/schedules',
      data: {
        'activityDate': activityDate.toIso8601String(),
        'timeStart':
            '${(timeStartMinutes ~/ 60).toString().padLeft(2, '0')}:${(timeStartMinutes % 60).toString().padLeft(2, '0')}:00',
        'timeEnd':
            '${(timeEndMinutes ~/ 60).toString().padLeft(2, '0')}:${(timeEndMinutes % 60).toString().padLeft(2, '0')}:00',
        'userId': userId,
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
    return res.data!['scheduleId'] as String;
  }

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
  }) async {
    await _dio.put(
      '/api/schedules/$id',
      data: {
        if (activityDate != null) 'activityDate': activityDate.toIso8601String(),
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
      },
    );
  }

  // ── Tickets ─────────────────────────────────────────────────────────────

  Future<void> assignTicket(String ticketId, String? userId) async {
    await _dio.put(
      '/api/tickets/$ticketId',
      data: {
        'assignedUserId': ?userId,
      },
    );
  }

  Future<List<Map<String, dynamic>>> fetchTechnicians() async {
    final res = await _dio.get<List<dynamic>>(
      '/api/users',
      queryParameters: {'role': 'Technician', 'isActive': 'true'},
    );
    return (res.data ?? []).cast<Map<String, dynamic>>();
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
      },
    );
    return res.data!['materialId'] as String;
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
        'isActive': ?isActive,
      },
    );
  }

  // ── ProdottoAssistenza ──────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> fetchProdottiAssistenza() async {
    final res = await _dio.get<List<dynamic>>('/api/prodottoassistenza');
    return (res.data ?? []).cast<Map<String, dynamic>>();
  }

  Future<String> createProdottoAssistenza({
    required String name,
    required String customerId,
    required String locationId,
    String? description,
    String? serialNumber,
    DateTime? warrantyExpiryDate,
    String? notes,
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
      },
    );
    return res.data!['prodottoAssistenzaId'] as String;
  }

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
      },
    );
  }

  // ── Contracts ────────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> fetchContracts() async {
    final res = await _dio.get<List<dynamic>>('/api/contracts');
    return (res.data ?? []).cast<Map<String, dynamic>>();
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
    return res.data!['contractId'] as String;
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
    final res = await _dio.get<List<dynamic>>('/api/squadre');
    return (res.data ?? []).cast<Map<String, dynamic>>();
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
    return res.data!['squadraId'] as String;
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
    String ruolo = 'Membro',
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
    int page = 1,
    int pageSize = 50,
  }) async {
    final res = await _dio.get<List<dynamic>>(
      '/api/reports',
      queryParameters: {
        'stato': ?stato,
        'page': page,
        'pageSize': pageSize,
      },
    );
    return (res.data ?? []).cast<Map<String, dynamic>>();
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
