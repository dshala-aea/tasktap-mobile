// dart format width=100
// ══════════════════════════════════════════════════════════════════════════════
// CantiereWorklogApiClient
//
// Thin Dio wrapper for the cantiere work-log backend endpoints:
//   POST /api/cantiereworklog/start        — arrive at site (open log)
//   POST /api/cantiereworklog/end          — leave site (close log)
//   GET  /api/cantiereworklog              — list logs (filtered to open ones
//                                            for the current user)
//   GET  /api/cantieri/{id}/assegnazioni   — crew assignments for a cantiere
//                                            (lead + teammates)
//   POST /api/cantiereworklog/batch-start  — a lead clocking in on behalf of
//                                            one or more assigned teammates
//
// Mirrors the style of WorklogApiClient / ReportSubmitApiClient.
// Field names match StartCantiereWorkLogRequest / EndCantiereWorkLogRequest
// in CantiereWorkLogController.cs verbatim (PascalCase from C# → camelCase
// as serialised by ASP.NET default JsonSerializerOptions).
//
// `getAssegnazioni`/`batchStart` live here rather than on a dedicated
// CantieriApiClient: they exist purely to serve this screen's own lead/batch
// flow (cantiere_timbra_screen.dart), so they follow this file's existing
// no-try/catch convention and share its Dio instance rather than adding a new
// client class for two methods.
// ══════════════════════════════════════════════════════════════════════════════

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/dio_client.dart';

// ── Mobile batch upsert DTOs (offline-first) ────────────────────────────────
//
// Mirrors MobileSessionDto/upsertSessions in worklog_api_client.dart, hitting the cantiere
// module's own idempotent batch endpoint (CantiereWorkLogController.MobileSessions). Field names
// match CantiereMobileSessionDto (backend) verbatim — see test/contract/openapi.snapshot.json's
// CantiereMobileSessionDto schema, which is what request_body_contract_test.dart checks this
// against. Deliberately narrower than [StartCantiereRequest]: the backend's batch DTO does not
// (yet) carry workOrderNumber/equipmentUsed/teamSize/weatherConditions/safetyNotes, so those rich
// fields only reach the server via the online start/end path; see cantiere_timbra_screen.dart's
// online-first-with-local-fallback comment for how the two paths are reconciled.

/// One cantiere punch as the device recorded it, ready for the batch upsert.
class CantiereMobileSessionDto {
  const CantiereMobileSessionDto({
    required this.clientId,
    required this.cantiereId,
    required this.customerId,
    this.ticketId,
    this.description,
    required this.startTime,
    this.endTime,
    this.latitude,
    this.longitude,
    this.workLogType = 0, // 0 = Site (default)
  });

  final String clientId;
  final String cantiereId;
  final String customerId;
  final String? ticketId;
  final String? description;
  final DateTime startTime; // UTC
  final DateTime? endTime; // UTC, null if active
  final double? latitude;
  final double? longitude;

  /// CantiereWorkLogTypeEnum: Site=0, Travel=1, Setup=2.
  final int workLogType;

  Map<String, dynamic> toJson() => {
    'clientId': clientId,
    'cantiereId': cantiereId,
    'customerId': customerId,
    if (ticketId != null) 'ticketId': ticketId,
    if (description != null) 'description': description,
    'startTime': startTime.toUtc().toIso8601String(),
    'endTime': endTime?.toUtc().toIso8601String(),
    if (latitude != null) 'latitude': latitude,
    if (longitude != null) 'longitude': longitude,
    'workLogType': workLogType,
  };
}

/// What the server holds for one punch after the upsert.
class CantiereMobileSessionResult {
  const CantiereMobileSessionResult({
    required this.clientId,
    required this.cantiereWorkLogId,
    required this.startTime,
    this.endTime,
    required this.isActive,
  });

  final String clientId;
  final String cantiereWorkLogId;
  final DateTime startTime;
  final DateTime? endTime;
  final bool isActive;

  factory CantiereMobileSessionResult.fromJson(Map<String, dynamic> json) =>
      CantiereMobileSessionResult(
        clientId: json['clientId'] as String,
        cantiereWorkLogId: json['cantiereWorkLogId'] as String,
        startTime: DateTime.parse(json['startTime'] as String),
        endTime: json['endTime'] != null ? DateTime.parse(json['endTime'] as String) : null,
        isActive: json['isActive'] as bool? ?? false,
      );
}

// ── DTOs ─────────────────────────────────────────────────────────────────────

/// Mirrors StartCantiereWorkLogRequest (backend).
class StartCantiereRequest {
  const StartCantiereRequest({
    required this.cantiereId,
    required this.customerId,
    this.ticketId,
    this.description,
    this.workOrderNumber,
    this.equipmentUsed,
    this.teamSize,
    this.latitude,
    this.longitude,
    this.arrivalLatitude,
    this.arrivalLongitude,
    this.weatherConditions,
    this.workLogType = 0, // 0 = Site (default)
  });

  final String cantiereId;
  final String customerId;
  final String? ticketId;
  final String? description;
  final String? workOrderNumber;
  final String? equipmentUsed;
  final int? teamSize;
  final double? latitude;
  final double? longitude;
  final double? arrivalLatitude;
  final double? arrivalLongitude;
  final String? weatherConditions;

  /// CantiereWorkLogTypeEnum: Site=0, Travel=1, Setup=2.
  final int workLogType;

  Map<String, dynamic> toJson() => {
    'cantiereId': cantiereId,
    'customerId': customerId,
    if (ticketId != null) 'ticketId': ticketId,
    if (description != null) 'description': description,
    if (workOrderNumber != null) 'workOrderNumber': workOrderNumber,
    if (equipmentUsed != null) 'equipmentUsed': equipmentUsed,
    if (teamSize != null) 'teamSize': teamSize,
    if (latitude != null) 'latitude': latitude,
    if (longitude != null) 'longitude': longitude,
    if (arrivalLatitude != null) 'arrivalLatitude': arrivalLatitude,
    if (arrivalLongitude != null) 'arrivalLongitude': arrivalLongitude,
    if (weatherConditions != null) 'weatherConditions': weatherConditions,
    'workLogType': workLogType,
  };
}

/// Mirrors EndCantiereWorkLogRequest (backend — all fields optional).
class EndCantiereRequest {
  const EndCantiereRequest({
    this.description,
    this.departureLatitude,
    this.departureLongitude,
    this.safetyNotes,
  });

  final String? description;
  final double? departureLatitude;
  final double? departureLongitude;
  final String? safetyNotes;

  Map<String, dynamic> toJson() => {
    if (description != null) 'description': description,
    if (departureLatitude != null) 'departureLatitude': departureLatitude,
    if (departureLongitude != null) 'departureLongitude': departureLongitude,
    if (safetyNotes != null) 'safetyNotes': safetyNotes,
  };
}

/// Represents one CantiereWorkLog record returned by GET /api/cantiereworklog.
class CantiereWorkLogDto {
  const CantiereWorkLogDto({
    required this.id,
    required this.cantiereId,
    required this.customerId,
    this.ticketId,
    required this.workDate,
    required this.startTime,
    this.endTime,
    this.description,
  });

  final String id;
  final String cantiereId;
  final String customerId;
  final String? ticketId;
  final DateTime workDate;

  /// StartTime from backend (TimeSpan → string "HH:mm:ss").
  final String startTime;

  /// EndTime — null when the session is still open.
  final String? endTime;

  final String? description;

  bool get isActive => endTime == null;

  factory CantiereWorkLogDto.fromJson(Map<String, dynamic> json) => CantiereWorkLogDto(
    id: json['id'] as String,
    cantiereId: json['cantiereId'] as String,
    customerId: json['customerId'] as String,
    ticketId: json['ticketId'] as String?,
    workDate: DateTime.parse(json['workDate'] as String),
    startTime: json['startTime'] as String,
    endTime: json['endTime'] as String?,
    description: json['description'] as String?,
  );
}

// ── Crew assignments / batch-start DTOs ─────────────────────────────────────
//
// The *new* lead/teammate assignment concept (backend entity CantiereCrewAssignment), distinct
// from the older Role/StartDate/EndDate scheduling "assignments" already surfaced as a raw Map on
// GET /api/cantieri/{id} and consumed by admin_cantiere_detail_screen.dart's
// _CrewSection/_AddAssignmentSheet via AdminApiClient's own `/api/cantieri/$id/assignments`
// endpoint. Named CrewAssignment (not a bare CantiereAssignment) specifically to avoid colliding
// with that unrelated concept — do not touch or extend the older one from here.

/// One crew assignment row from GET /api/cantieri/{id}/assegnazioni.
class CantiereCrewAssignmentDto {
  const CantiereCrewAssignmentDto({required this.id, required this.userId, required this.isLead});

  final String id;
  final String userId;

  /// Whether this person is the lead for the cantiere — the current user's own row's `isLead`
  /// gates the three-way choice on CantiereTimbraScreen (see isLeadForCantiereProvider there).
  final bool isLead;

  factory CantiereCrewAssignmentDto.fromJson(Map<String, dynamic> json) =>
      CantiereCrewAssignmentDto(
        id: json['id'] as String,
        userId: json['userId'] as String,
        isLead: json['isLead'] as bool? ?? false,
      );
}

/// Mirrors the batch-start request body (CantiereWorkLogController.BatchStart, backend) —
/// [StartCantiereRequest]'s optional field set, but `userIds` replaces the single implicit "self"
/// the online single-person start assumes.
class BatchStartCantiereRequest {
  const BatchStartCantiereRequest({
    required this.cantiereId,
    required this.customerId,
    required this.userIds,
    this.description,
    this.workOrderNumber,
    this.equipmentUsed,
    this.teamSize,
    this.latitude,
    this.longitude,
    this.arrivalLatitude,
    this.arrivalLongitude,
    this.weatherConditions,
    this.workLogType = 0, // 0 = Site (default)
  });

  final String cantiereId;
  final String customerId;
  final List<String> userIds;
  final String? description;
  final String? workOrderNumber;
  final String? equipmentUsed;
  final int? teamSize;
  final double? latitude;
  final double? longitude;
  final double? arrivalLatitude;
  final double? arrivalLongitude;
  final String? weatherConditions;

  /// CantiereWorkLogTypeEnum: Site=0, Travel=1, Setup=2.
  final int workLogType;

  Map<String, dynamic> toJson() => {
    'cantiereId': cantiereId,
    'customerId': customerId,
    'userIds': userIds,
    if (description != null) 'description': description,
    if (workOrderNumber != null) 'workOrderNumber': workOrderNumber,
    if (equipmentUsed != null) 'equipmentUsed': equipmentUsed,
    if (teamSize != null) 'teamSize': teamSize,
    if (latitude != null) 'latitude': latitude,
    if (longitude != null) 'longitude': longitude,
    if (arrivalLatitude != null) 'arrivalLatitude': arrivalLatitude,
    if (arrivalLongitude != null) 'arrivalLongitude': arrivalLongitude,
    if (weatherConditions != null) 'weatherConditions': weatherConditions,
    'workLogType': workLogType,
  };
}

/// One person's outcome from a batch-start call — never dropped silently, per the endpoint's
/// "name every offender" contract (see BatchStartResponse.fromJson).
class BatchStartResult {
  const BatchStartResult({required this.userId, required this.success, this.workLogId, this.error});

  final String userId;
  final bool success;
  final String? workLogId;

  /// "NotAssigned" or "AlreadyOpen" when [success] is false, else null.
  final String? error;

  factory BatchStartResult.fromJson(Map<String, dynamic> json) => BatchStartResult(
    userId: json['userId'] as String,
    success: json['success'] as bool? ?? false,
    workLogId: json['workLogId'] as String?,
    error: json['error'] as String?,
  );
}

/// Response envelope from POST /api/cantiereworklog/batch-start.
class BatchStartResponse {
  const BatchStartResponse({required this.results});

  final List<BatchStartResult> results;

  factory BatchStartResponse.fromJson(Map<String, dynamic> json) {
    final raw = json['results'] as List<dynamic>? ?? [];
    return BatchStartResponse(
      results: raw.cast<Map<String, dynamic>>().map(BatchStartResult.fromJson).toList(),
    );
  }
}

// ── Client ────────────────────────────────────────────────────────────────────

class CantiereWorklogApiClient {
  CantiereWorklogApiClient(this._dio);

  final Dio _dio;

  /// POST /api/cantiereworklog/start
  ///
  /// Creates an open cantiere session. Throws [DioException] on error (including
  /// 400 when a session is already active — the caller should surface this).
  Future<void> startCantiere(StartCantiereRequest request) async {
    await _dio.post<dynamic>('/api/cantiereworklog/start', data: request.toJson());
  }

  /// POST /api/cantiereworklog/end
  ///
  /// Closes the current user's open cantiere session.
  /// Throws [DioException] on error (404 = no active session).
  Future<void> endCantiere([EndCantiereRequest? request]) async {
    await _dio.post<dynamic>('/api/cantiereworklog/end', data: request?.toJson() ?? {});
  }

  /// POST /api/cantiereworklog/mobile/sessions
  ///
  /// Idempotent batch upsert: the server matches on (tenant, user, clientId) and updates the row
  /// (e.g. fills endTime) without creating duplicates — see CantiereWorkLogController.MobileSessions.
  /// The offline counterpart to [startCantiere]/[endCantiere]; used by CantiereTimbraSyncService to
  /// push punches recorded while offline. Throws [DioException] on network / server error.
  Future<List<CantiereMobileSessionResult>> upsertSessions(
    List<CantiereMobileSessionDto> sessions,
  ) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/cantiereworklog/mobile/sessions',
      data: {'sessions': sessions.map((s) => s.toJson()).toList()},
    );

    final data = response.data;
    if (data == null) throw StateError('Risposta vuota da upsertSessions');

    final list = data['sessions'] as List<dynamic>? ?? [];
    return list.cast<Map<String, dynamic>>().map(CantiereMobileSessionResult.fromJson).toList();
  }

  /// GET /api/cantiereworklog
  ///
  /// Returns the current user's open cantiere log (endTime == null), or an
  /// empty list if none is active.
  ///
  /// The backend does not expose a dedicated /active endpoint, so we fetch
  /// a small page and filter client-side on [CantiereWorkLogDto.isActive].
  Future<List<CantiereWorkLogDto>> getActive() async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/cantiereworklog',
      // `-createdAt`, not `createdAt desc`. The backend's sort grammar is a leading minus for
      // descending (WorkLogService.ResolveSort), and anything else is read as the whole column
      // name, misses the allowlist and 400s — which is exactly what this call did on every
      // dashboard load, so the cantiere clock never appeared.
      queryParameters: {'pageSize': 20, 'page': 1, 'sort': '-createdAt'},
    );

    final data = response.data;
    if (data == null) return [];

    // Backend returns a paginated envelope { items: [...], total: n }.
    final raw = data['items'] as List<dynamic>? ?? [];
    return raw
        .cast<Map<String, dynamic>>()
        .map(CantiereWorkLogDto.fromJson)
        .where((log) => log.isActive)
        .toList();
  }

  /// GET /api/cantieri/{id}/assegnazioni
  ///
  /// Every crew assignment for a cantiere — used to derive whether the current user is lead and
  /// to populate the teammate picker (see cantiere_timbra_screen.dart). Returns a bare JSON array
  /// (no pagination envelope), unlike [getActive]. Throws [DioException] on error, including
  /// offline — callers fall back to today's single-button flow in that case rather than blocking.
  Future<List<CantiereCrewAssignmentDto>> getAssegnazioni(String cantiereId) async {
    final response = await _dio.get<List<dynamic>>('/api/cantieri/$cantiereId/assegnazioni');
    final data = response.data ?? [];
    return data.cast<Map<String, dynamic>>().map(CantiereCrewAssignmentDto.fromJson).toList();
  }

  /// POST /api/cantiereworklog/batch-start
  ///
  /// A lead's clock-in on behalf of one or more assigned teammates at once. Never fails the whole
  /// batch for one person's failure — per-person outcomes come back inside the 200 response (see
  /// [BatchStartResult.error]). Throws [DioException] only on a request-level error (e.g. the
  /// device cannot reach the server at all) — this endpoint is online-only, with no offline queue
  /// fallback, per the plan's Global Constraints.
  Future<BatchStartResponse> batchStart(BatchStartCantiereRequest request) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/cantiereworklog/batch-start',
      data: request.toJson(),
    );
    final data = response.data;
    if (data == null) throw StateError('Risposta vuota da batchStart');
    return BatchStartResponse.fromJson(data);
  }
}

// ── Provider ──────────────────────────────────────────────────────────────────

/// Provides [CantiereWorklogApiClient]. Override in tests with a fake.
final cantiereWorklogApiClientProvider = Provider<CantiereWorklogApiClient>((ref) {
  return CantiereWorklogApiClient(ref.watch(dioProvider));
});
