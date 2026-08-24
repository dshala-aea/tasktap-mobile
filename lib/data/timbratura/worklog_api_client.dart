// dart format width=100
// ══════════════════════════════════════════════════════════════════════════════
// WorklogApiClient
//
// Thin Dio wrapper for the two timbra backend endpoints:
//   POST /api/worklog/mobile/sessions  — idempotent upsert of work intervals
//   GET  /api/worklog/mobile/today     — today's WorkLogs for the current user
//
// Mirrors the style of ReportSubmitApiClient.
// ══════════════════════════════════════════════════════════════════════════════

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/dio_client.dart';

// ── Request DTO ───────────────────────────────────────────────────────────────

class MobileSessionDto {
  const MobileSessionDto({
    required this.clientId,
    required this.startTime,
    this.endTime,
    this.latitude,
    this.longitude,
    this.gpsAccuracyMeters,
  });

  final String clientId;
  final DateTime startTime; // UTC
  final DateTime? endTime; // UTC, null if active
  final double? latitude; // null for simple timbra
  final double? longitude; // null for simple timbra

  /// Device-reported GPS accuracy radius, in meters, at the moment [latitude]/[longitude] were
  /// captured. Capture-only, mirrors `WorkLog.GpsAccuracyMeters` server-side.
  final double? gpsAccuracyMeters;

  Map<String, dynamic> toJson() => {
    'clientId': clientId,
    'startTime': startTime.toUtc().toIso8601String(),
    'endTime': endTime?.toUtc().toIso8601String(),
    'latitude': latitude,
    'longitude': longitude,
    'gpsAccuracyMeters': gpsAccuracyMeters,
  };
}

// ── Response DTOs ─────────────────────────────────────────────────────────────

class UpsertSessionResponse {
  const UpsertSessionResponse({
    required this.clientId,
    required this.workLogId,
    required this.startTime,
    this.endTime,
    this.tipoOra,
    required this.isActive,
  });

  final String clientId;
  final String workLogId;
  final DateTime startTime;
  final DateTime? endTime;
  final String? tipoOra;
  final bool isActive;

  factory UpsertSessionResponse.fromJson(Map<String, dynamic> json) => UpsertSessionResponse(
    clientId: json['clientId'] as String,
    workLogId: json['workLogId'] as String,
    startTime: DateTime.parse(json['startTime'] as String),
    endTime: json['endTime'] != null ? DateTime.parse(json['endTime'] as String) : null,
    tipoOra: json['tipoOra'] as String?,
    isActive: json['isActive'] as bool? ?? false,
  );
}

class TodayWorkLogDto {
  const TodayWorkLogDto({
    required this.id,
    required this.clientId,
    required this.startTime,
    this.endTime,
    required this.isActive,
    this.tipoOra,
  });

  final String id;
  final String clientId;
  final DateTime startTime;
  final DateTime? endTime;
  final bool isActive;
  final String? tipoOra;

  factory TodayWorkLogDto.fromJson(Map<String, dynamic> json) => TodayWorkLogDto(
    id: json['id'] as String,
    clientId: json['clientId'] as String,
    startTime: DateTime.parse(json['startTime'] as String),
    endTime: json['endTime'] != null ? DateTime.parse(json['endTime'] as String) : null,
    isActive: json['isActive'] as bool? ?? false,
    tipoOra: json['tipoOra'] as String?,
  );
}

// ── Giornata (GET /api/WorkLog/today) ─────────────────────────────────────────

/// One action the server may offer, and why it does not (backend ADR-0013 §C.5).
///
/// [reasonCode] is the contract; [reason] is Italian prose the server sent for a client that
/// has no string for that code yet. Unknown codes must fall through to [reason] rather than
/// render blank — a reason added server-side has to keep explaining itself on an app build
/// that predates it.
class GiornataActionDto {
  const GiornataActionDto({
    required this.action,
    required this.enabled,
    this.reasonCode,
    this.reason,
  });

  final String action; // ClockIn | ClockOut | StartBreak | EndBreak | Submit
  final bool enabled;
  final String? reasonCode;
  final String? reason;

  factory GiornataActionDto.fromJson(Map<String, dynamic> json) => GiornataActionDto(
    action: json['action'] as String,
    enabled: json['enabled'] as bool? ?? false,
    reasonCode: json['reasonCode'] as String?,
    reason: json['reason'] as String?,
  );
}

/// The server's view of the signed-in user's day.
class GiornataDto {
  const GiornataDto({
    required this.status,
    required this.workedMinutes,
    required this.breakMinutes,
    required this.isPayrollLocked,
    required this.actions,
  });

  final String status; // ClockedOut | Working | OnBreak
  final int workedMinutes;
  final int breakMinutes;
  final bool isPayrollLocked;
  final List<GiornataActionDto> actions;

  /// The availability of [action], or null when the server did not mention it.
  GiornataActionDto? action(String action) {
    for (final a in actions) {
      if (a.action == action) return a;
    }
    return null;
  }

  factory GiornataDto.fromJson(Map<String, dynamic> json) => GiornataDto(
    status: json['status'] as String? ?? 'ClockedOut',
    workedMinutes: (json['workedMinutes'] as num?)?.toInt() ?? 0,
    breakMinutes: (json['breakMinutes'] as num?)?.toInt() ?? 0,
    isPayrollLocked: json['isPayrollLocked'] as bool? ?? false,
    actions: (json['availableActions'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>()
        .map(GiornataActionDto.fromJson)
        .toList(),
  );
}

// ── Client ────────────────────────────────────────────────────────────────────

class WorklogApiClient {
  WorklogApiClient(this._dio);

  final Dio _dio;

  /// POST /api/worklog/mobile/sessions
  ///
  /// Idempotent upsert: the server matches on (tenant, user, clientId) and
  /// updates the row (e.g. fills endTime) without creating duplicates.
  /// Throws [DioException] on network / server error.
  Future<List<UpsertSessionResponse>> upsertSessions(List<MobileSessionDto> sessions) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/worklog/mobile/sessions',
      data: {'sessions': sessions.map((s) => s.toJson()).toList()},
    );

    final data = response.data;
    if (data == null) throw StateError('Risposta vuota da upsertSessions');

    final list = data['sessions'] as List<dynamic>? ?? [];
    return list.cast<Map<String, dynamic>>().map(UpsertSessionResponse.fromJson).toList();
  }

  /// GET /api/worklog/mobile/today
  ///
  /// Returns the current user's WorkLogs for today.
  /// Throws [DioException] on network / server error.
  Future<List<TodayWorkLogDto>> getToday() async {
    final response = await _dio.get<List<dynamic>>('/api/worklog/mobile/today');

    final list = response.data ?? [];
    return list.cast<Map<String, dynamic>>().map(TodayWorkLogDto.fromJson).toList();
  }

  /// GET /api/WorkLog/today
  ///
  /// The server's own view of the day, including which actions it will accept right now and
  /// why it will refuse the others. Distinct from [getToday], which hits a separate endpoint
  /// (`GET mobile/today`, `WorkLogController.MobileToday`) and returns the raw per-session
  /// WorkLog entries for the day (id, clientId, start/end, tipoOra) with no aggregate status or
  /// available actions. Reconciliation (`WorkLogReconciler`) and sync (`TimbraSyncService`) both
  /// use this method, not [getToday] — [getToday] has no call site in the app today.
  ///
  /// Throws [DioException] on network / server error — including offline, which is a normal
  /// state here and not an error the user should see.
  Future<GiornataDto> getGiornata() async {
    final response = await _dio.get<Map<String, dynamic>>('/api/worklog/today');

    final data = response.data;
    if (data == null) throw StateError('Risposta vuota da getGiornata');
    return GiornataDto.fromJson(data);
  }

  /// POST /api/worklog/today/submit
  ///
  /// Sends the caller's finished hours for the day for approval (the day-level counterpart to
  /// the `Submit` action `getGiornata` offers — see `WorkLogController.SubmitToday`). Returns the
  /// day as it now stands, same shape as [getGiornata].
  Future<GiornataDto> submitToday() async {
    final response = await _dio.post<Map<String, dynamic>>('/api/worklog/today/submit');

    final data = response.data;
    if (data == null) throw StateError('Risposta vuota da submitToday');
    return GiornataDto.fromJson(data);
  }
}

// ── Provider ──────────────────────────────────────────────────────────────────

/// Provides [WorklogApiClient]. Override in tests with a fake.
final worklogApiClientProvider = Provider<WorklogApiClient>((ref) {
  return WorklogApiClient(ref.watch(dioProvider));
});
