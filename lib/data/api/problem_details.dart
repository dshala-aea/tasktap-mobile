// dart format width=100
import 'package:dio/dio.dart';

// ══════════════════════════════════════════════════════════════════════════════
// ProblemDetails
//
// The one place that knows the shape of this backend's RFC 7807 problem bodies.
//
// Pure enough to unit-test without a Dio, a database or a queue: a caught error
// in, a machine member out.
// ══════════════════════════════════════════════════════════════════════════════

/// The machine-readable members of this backend's RFC 7807 problem bodies.
///
/// `ErrorResponse : ProblemDetails` keeps these in `ProblemDetails.Extensions`, which is
/// `[JsonExtensionData]` — on the wire they are members of the ROOT object (`{"title":…,
/// "code":"not_found", "field":"customerId"}`), never nested under an `extensions` key. Keys are
/// written literally and lowercase. See `ErrorHandlingMiddleware.MapException`.
///
/// A non-2xx arrives as a raw [DioException] — `dioProvider` installs no error mapper — so this takes
/// the caught error, not a `Response`.
class ProblemDetails {
  static Map<String, dynamic>? bodyOf(Object error) {
    if (error is! DioException) return null;
    final data = error.response?.data;
    return data is Map<String, dynamic> ? data : null;
  }

  static int? statusOf(Object error) => error is DioException ? error.response?.statusCode : null;

  /// The request field a `not_found` named, or null. Read from the body, never from the message:
  /// the message is human prose that changes.
  static String? fieldOf(Object error) {
    if (statusOf(error) != 404) return null;
    final field = bodyOf(error)?['field'];
    return field is String && field.isNotEmpty ? field : null;
  }
}
