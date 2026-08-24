// dart format width=100
// ══════════════════════════════════════════════════════════════════════════════
// CantiereWorklogApiClient
//
// Thin Dio wrapper for the cantiere work-log backend endpoints:
//   POST /api/cantiereworklog/start  — arrive at site (open log)
//   POST /api/cantiereworklog/end    — leave site (close log)
//   GET  /api/cantiereworklog        — list logs (filtered to open ones for
//                                      the current user)
//
// Mirrors the style of WorklogApiClient / ReportSubmitApiClient.
// Field names match StartCantiereWorkLogRequest / EndCantiereWorkLogRequest
// in CantiereWorkLogController.cs verbatim (PascalCase from C# → camelCase
// as serialised by ASP.NET default JsonSerializerOptions).
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
}

// ── Provider ──────────────────────────────────────────────────────────────────

/// Provides [CantiereWorklogApiClient]. Override in tests with a fake.
final cantiereWorklogApiClientProvider = Provider<CantiereWorklogApiClient>((ref) {
  return CantiereWorklogApiClient(ref.watch(dioProvider));
});
