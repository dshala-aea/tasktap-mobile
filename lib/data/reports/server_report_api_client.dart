// dart format width=100
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/dio_client.dart';
import 'server_report_dto.dart';

/// `GET /api/Reports/{id}` — the full report (header + staff + materiali + observations).
///
/// Needs RapportiniReportRead, the same permission `CantiereReportApiClient.fetchReportSeed`
/// already relies on. Throws [DioException] on transport/HTTP errors.
class ServerReportApiClient {
  ServerReportApiClient(this._dio);

  final Dio _dio;

  Future<ServerReportDto> fetchReport(String reportId) async {
    final response = await _dio.get<Map<String, dynamic>>('/api/Reports/$reportId');
    final data = response.data;
    if (data == null) {
      throw StateError('Empty response from GET /api/Reports/$reportId');
    }
    return ServerReportDto.fromJson(data);
  }
}

final serverReportApiClientProvider = Provider<ServerReportApiClient>((ref) {
  return ServerReportApiClient(ref.watch(dioProvider));
});
