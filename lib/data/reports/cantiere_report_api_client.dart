// dart format width=100
// ══════════════════════════════════════════════════════════════════════════════
// CantiereReportApiClient
//
// Thin Dio wrapper for the two report endpoints the cantiere-only rapportino flow needs:
//   POST /api/reports/from-cantiere-worklogs  — create a real Report seeded with hours from the
//                                               caller's own (and, if they are the squadra lead,
//                                               their whole team's) unconsumed CantiereWorkLog
//                                               entries for one cantiere
//   GET  /api/reports/{id}                    — used ONLY to read back the `staff` rows and the
//                                               resolved `locationId` the call above just seeded
//                                               server-side, so the local editor can hydrate a
//                                               matching draft with real hours (and a real
//                                               location) instead of opening blank
//
// Mirrors the style of CantiereWorklogApiClient / ReportSubmitApiClient — a small class scoped to
// exactly the calls one feature needs, rather than a do-everything reports client.
//
// Field names match CreateFromCantiereWorkLogsRequest / BasicPkResponse / the ReportStaff entity
// verbatim (PascalCase from C# → camelCase as serialised by ASP.NET's default
// JsonSerializerOptions). See ReportsController.CreateFromCantiereWorkLogs / GetById (backend).
// ══════════════════════════════════════════════════════════════════════════════

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/dio_client.dart';

/// One technician's seeded time/travel contribution, as read back from `GET /api/reports/{id}`'s
/// `staff` array. Only the fields the local editor actually hydrates are parsed — this DTO is not
/// a general-purpose mirror of the `ReportStaff` entity (see this file's own header comment).
class ReportStaffSeedDto {
  const ReportStaffSeedDto({
    required this.userId,
    this.hoursWorked,
    this.kmTraveled = 0,
    this.startTime,
    this.endTime,
  });

  final String userId;
  final double? hoursWorked;
  final double kmTraveled;
  final DateTime? startTime;
  final DateTime? endTime;

  factory ReportStaffSeedDto.fromJson(Map<String, dynamic> json) => ReportStaffSeedDto(
    userId: json['userId'] as String,
    hoursWorked: (json['hoursWorked'] as num?)?.toDouble(),
    kmTraveled: (json['kmTraveled'] as num?)?.toDouble() ?? 0,
    startTime: json['startTime'] != null ? DateTime.tryParse(json['startTime'] as String) : null,
    endTime: json['endTime'] != null ? DateTime.tryParse(json['endTime'] as String) : null,
  );
}

/// What `GET /api/reports/{id}` seeded server-side, the pieces the local editor hydrates after
/// [CantiereReportApiClient.createFromCantiereWorklogs]: the already-resolved `locationId`
/// (`ResolveLocationIdForCantiereAutoFillAsync`, backend — never blank, unlike the manual-entry
/// default) and the `staff` rows. Not a general-purpose mirror of the response — every other field
/// (title, signatures, etc.) is ignored (see this file's own header comment).
class ReportSeedDto {
  const ReportSeedDto({required this.locationId, required this.staff});

  final String? locationId;
  final List<ReportStaffSeedDto> staff;
}

class CantiereReportApiClient {
  CantiereReportApiClient(this._dio);

  final Dio _dio;

  /// POST /api/reports/from-cantiere-worklogs
  ///
  /// Always returns a created report id, even when the caller has zero unconsumed
  /// `CantiereWorkLog` entries for [cantiereId] — the backend creates the Report with zero
  /// `ReportStaff` rows in that case (a deliberate ruling; see
  /// `IReportService.CreateFromCantiereWorkLogsAsync`'s own doc comment). Throws [DioException] on
  /// network/server error.
  Future<String> createFromCantiereWorklogs(String cantiereId) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/reports/from-cantiere-worklogs',
      data: {'cantiereId': cantiereId},
    );
    final data = response.data;
    if (data == null) throw StateError('Empty response from from-cantiere-worklogs');
    return data['id'] as String;
  }

  /// GET /api/reports/{id}
  ///
  /// Only `locationId` and the `staff` array are consumed — every other field on the response
  /// (title, signatures, etc.) is ignored, since this call exists solely to hydrate the local
  /// draft after [createFromCantiereWorklogs]. Throws [DioException] on network/server error.
  Future<ReportSeedDto> fetchReportSeed(String reportId) async {
    final response = await _dio.get<Map<String, dynamic>>('/api/reports/$reportId');
    final data = response.data;
    if (data == null) return const ReportSeedDto(locationId: null, staff: []);
    final raw = data['staff'] as List<dynamic>? ?? [];
    return ReportSeedDto(
      locationId: data['locationId'] as String?,
      staff: raw.cast<Map<String, dynamic>>().map(ReportStaffSeedDto.fromJson).toList(),
    );
  }
}

// ── Provider ──────────────────────────────────────────────────────────────────

/// Provides [CantiereReportApiClient]. Override in tests with a fake.
final cantiereReportApiClientProvider = Provider<CantiereReportApiClient>((ref) {
  return CantiereReportApiClient(ref.watch(dioProvider));
});
