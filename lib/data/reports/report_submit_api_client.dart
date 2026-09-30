// dart format width=100
import 'dart:io';

import 'package:dio/dio.dart';

import 'submit_report_request.dart';

// ══════════════════════════════════════════════════════════════════════════════
// ReportSubmitApiClient
//
// Thin Dio wrapper for the mobile-submit endpoints:
//   POST /api/reports/{id}/attachments   — upload one media file (photos, and signatures
//                                          via the optional `kind` form field)
//   POST /api/reports/submit             — atomic submit with idempotency
//
// Signatures use the attachments endpoint with `kind` = signature-customer |
// signature-technician so the server classifies them as SystemArtifact (out of the
// report's Foto list) while capturing the same GPS/timestamp provenance. They must NOT
// use the firma-cliente/firma-tecnico endpoints: those require the report row to exist,
// which it does not until submit, so they 404 for a draft that was never sent.
//
// Does NOT own connectivity logic; that lives in SubmissionQueue.
// ══════════════════════════════════════════════════════════════════════════════

class ReportSubmitApiClient {
  ReportSubmitApiClient(this._dio);

  final Dio _dio;

  /// Upload a single attachment (photo or signature PNG).
  ///
  /// [kind] — omit for photos. `signature-customer` / `signature-technician` stage a signature
  /// through this same endpoint (it works before the report row exists, unlike firma-*): the
  /// server stores kind-tagged uploads as SystemArtifact, keeping them out of the Foto list.
  /// Any other value is a 400.
  ///
  /// [reportId] — the client-supplied report UUID (the report need not exist yet).
  /// [localPath] — absolute path to the local file.
  /// [fileName] — original file name (e.g. "firma_cliente.png").
  /// [contentType] — MIME type (e.g. "image/png", "image/jpeg").
  /// [capturedLatitude]/[capturedLongitude]/[capturedAt] — GPS position + UTC timestamp taken
  /// when this file was captured (signatures only). All optional and sent only when non-null:
  /// GPS must never block capture, so a denied/unavailable position is a normal, unsent case,
  /// not an error.
  ///
  /// Returns the server-assigned Allegato id on success.
  /// Throws [DioException] on network/server error.
  Future<ReportAttachmentUploadResponse> uploadAttachment({
    required String reportId,
    required String localPath,
    required String fileName,
    required String contentType,
    String? kind,
    double? capturedLatitude,
    double? capturedLongitude,
    DateTime? capturedAt,
  }) async {
    final file = File(localPath);
    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(
        file.path,
        filename: fileName,
        contentType: DioMediaType.parse(contentType),
      ),
      if (kind != null) 'kind': kind,
      if (capturedLatitude != null) 'capturedLatitude': capturedLatitude.toString(),
      if (capturedLongitude != null) 'capturedLongitude': capturedLongitude.toString(),
      if (capturedAt != null) 'capturedAt': capturedAt.toUtc().toIso8601String(),
    });

    final response = await _dio.post<Map<String, dynamic>>(
      '/api/reports/$reportId/attachments',
      data: formData,
      options: Options(headers: {'Content-Type': 'multipart/form-data'}),
    );

    final data = response.data;
    if (data == null) {
      throw StateError('Empty response from attachment upload');
    }
    return ReportAttachmentUploadResponse.fromJson(data);
  }

  /// Submit the full rapportino atomically.
  ///
  /// [idempotencyKey] — stable UUID string; reuse across retries so the server
  ///   deduplicates the submit (matching the B6 contract).
  ///
  /// Throws [DioException] on network/server error.
  Future<SubmitReportResponse> submitReport({
    required SubmitReportRequest request,
    required String idempotencyKey,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/reports/submit',
      data: request.toJson(),
      options: Options(
        headers: {'Idempotency-Key': idempotencyKey, 'Content-Type': 'application/json'},
      ),
    );

    final data = response.data;
    if (data == null) {
      throw StateError('Empty response from submit');
    }
    return SubmitReportResponse.fromJson(data);
  }
}
