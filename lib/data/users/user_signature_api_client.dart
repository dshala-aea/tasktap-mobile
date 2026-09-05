// dart format width=100
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/dio_client.dart';

// ══════════════════════════════════════════════════════════════════════════════
// UserSignatureApiClient
//
// Lets a technician save their own drawn signature once and reuse it across every rapportino
// afterwards, instead of redrawing it every single time (a small but real friction point — a
// signature is drawn per rapportino today, even though the technician's own signature does not
// change between jobs the way a customer's does).
//
//   POST /api/users/me/signature          — save/replace the technician's own signature
//   GET  /api/users/me/signature/content  — fetch it back, to pre-fill a new rapportino
//
// See `UsersController` (backend repo, `src/TaskTapAPI.Api/Controllers/UsersController.cs`) for
// the server side of both endpoints.
// ══════════════════════════════════════════════════════════════════════════════

/// Result of a successful [UserSignatureApiClient.uploadSignature] call.
///
/// Mirrors the backend's `UserSignatureResponse(Guid AllegatoId, string ContentUrl)` record.
class UserSignatureUploadResult {
  const UserSignatureUploadResult({required this.allegatoId, required this.contentUrl});

  final String allegatoId;
  final String contentUrl;

  factory UserSignatureUploadResult.fromJson(Map<String, dynamic> json) =>
      UserSignatureUploadResult(
        allegatoId: json['allegatoId'] as String? ?? '',
        contentUrl: json['contentUrl'] as String? ?? '',
      );
}

class UserSignatureApiClient {
  UserSignatureApiClient(this._dio);

  final Dio _dio;

  /// POST /api/users/me/signature
  ///
  /// Uploads [bytes] (a signature PNG, the same bytes just saved for this rapportino) as the
  /// technician's own reusable signature. Multipart field name is `file`, matching every other
  /// upload in this app (see [ReportSubmitApiClient.uploadAttachment]).
  ///
  /// Throws [DioException] on network/server error — unlike [fetchSavedSignatureContent], this is
  /// a deliberate technician action ("save this signature for next time"), so a failure here is
  /// meant to be surfaced, not swallowed.
  Future<UserSignatureUploadResult> uploadSignature(Uint8List bytes) async {
    final formData = FormData.fromMap({
      'file': MultipartFile.fromBytes(bytes, filename: 'signature.png'),
    });

    final response = await _dio.post<Map<String, dynamic>>(
      '/api/users/me/signature',
      data: formData,
      options: Options(headers: {'Content-Type': 'multipart/form-data'}),
    );

    final data = response.data;
    if (data == null) {
      throw StateError('Risposta vuota da upload firma tecnico');
    }
    return UserSignatureUploadResult.fromJson(data);
  }

  /// GET /api/users/me/signature/content
  ///
  /// Fetches the technician's previously saved signature, to pre-fill a new rapportino's "Firma
  /// tecnico" block. The backend responds either with a 404 (no saved signature yet — the common
  /// case for most technicians) or a 302 redirect to a short-lived storage URL; Dio follows
  /// redirects for GET by default, so `ResponseType.bytes` hands back the final file's raw bytes
  /// directly.
  ///
  /// Never throws: a missing saved signature is a normal case, not an error, and any other
  /// failure (network error, 500, ...) must not block the rapportino editor from opening either —
  /// pre-filling a signature is a convenience, not a requirement. Both cases return `null`, the
  /// same "never blocks" contract as the GPS pre-capture in `ReportEditorNotifier
  /// ._captureGpsSilently`.
  Future<Uint8List?> fetchSavedSignatureContent() async {
    try {
      final response = await _dio.get<List<int>>(
        '/api/users/me/signature/content',
        options: Options(responseType: ResponseType.bytes),
      );
      final data = response.data;
      if (data == null) return null;
      return Uint8List.fromList(data);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      // Any other failure — swallow rather than surface. See doc comment above.
      return null;
    } catch (_) {
      return null;
    }
  }
}

final userSignatureApiClientProvider = Provider<UserSignatureApiClient>((ref) {
  return UserSignatureApiClient(ref.watch(dioProvider));
});
