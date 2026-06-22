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

// ── Request DTO ───────────────────────────────────────────────────────────────

class MobileSessionDto {
  const MobileSessionDto({
    required this.clientId,
    required this.startTime,
    this.endTime,
    this.latitude,
    this.longitude,
  });

  final String clientId;
  final DateTime startTime; // UTC
  final DateTime? endTime; // UTC, null if active
  final double? latitude; // null for simple timbra
  final double? longitude; // null for simple timbra

  Map<String, dynamic> toJson() => {
        'clientId': clientId,
        'startTime': startTime.toUtc().toIso8601String(),
        'endTime': endTime?.toUtc().toIso8601String(),
        'latitude': latitude,
        'longitude': longitude,
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

  factory UpsertSessionResponse.fromJson(Map<String, dynamic> json) =>
      UpsertSessionResponse(
        clientId: json['clientId'] as String,
        workLogId: json['workLogId'] as String,
        startTime: DateTime.parse(json['startTime'] as String),
        endTime: json['endTime'] != null
            ? DateTime.parse(json['endTime'] as String)
            : null,
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

  factory TodayWorkLogDto.fromJson(Map<String, dynamic> json) =>
      TodayWorkLogDto(
        id: json['id'] as String,
        clientId: json['clientId'] as String,
        startTime: DateTime.parse(json['startTime'] as String),
        endTime: json['endTime'] != null
            ? DateTime.parse(json['endTime'] as String)
            : null,
        isActive: json['isActive'] as bool? ?? false,
        tipoOra: json['tipoOra'] as String?,
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
  Future<List<UpsertSessionResponse>> upsertSessions(
    List<MobileSessionDto> sessions,
  ) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/worklog/mobile/sessions',
      data: {
        'sessions': sessions.map((s) => s.toJson()).toList(),
      },
    );

    final data = response.data;
    if (data == null) throw StateError('Risposta vuota da upsertSessions');

    final list = data['sessions'] as List<dynamic>? ?? [];
    return list
        .cast<Map<String, dynamic>>()
        .map(UpsertSessionResponse.fromJson)
        .toList();
  }

  /// GET /api/worklog/mobile/today
  ///
  /// Returns the current user's WorkLogs for today.
  /// Throws [DioException] on network / server error.
  Future<List<TodayWorkLogDto>> getToday() async {
    final response = await _dio.get<List<dynamic>>(
      '/api/worklog/mobile/today',
    );

    final list = response.data ?? [];
    return list
        .cast<Map<String, dynamic>>()
        .map(TodayWorkLogDto.fromJson)
        .toList();
  }
}
