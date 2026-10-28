// dart format width=100
// ══════════════════════════════════════════════════════════════════════════════
// SmartWorkingRequestApiClient — self-service smart working against
// SmartWorkingRequestsController (/api/smart-working-requests).
//
//   POST /api/smart-working-requests              — file a request for a day window
//   GET  /api/smart-working-requests              — list requests (self-scoped)
//   GET  /api/smart-working-requests/{id}         — one request
//   POST /api/smart-working-requests/{id}/cancel  — withdraw a pending request
//
// A smart-working request is a MARKER for a whole remote day, never hours. It does not reshape the
// technician's schedule, it does not move the day's expected hours, and nothing here computes a
// duration: the start/end pair is a civil-day window ("these days I work from home"), and the two
// dates carry the same weight as the single day they usually name. Anything that starts to look
// like a timesheet belongs in WorkLogs, not in this entity.
//
// Approve/reject belong to the office and are deliberately absent: this client serves the
// technician's own screen only.
//
// Filing and cancelling are online-only: both are writes the server must validate and decide, and
// an "inviata" that the server never saw is a lie the technician then waits on. There is no local
// mirror and no queue for this entity — an offline submit is refused visibly by the caller.
//
// The list returns the raw `SmartWorkingRequest` entity array: the snapshot declares no response
// schema for it (`content?: never`, because the controller returns the entity), so
// [SmartWorkingRequestDto] is hand-written against the entity's camelCase properties.
//
// `status` is `AbsenceRequestStatusEnum` (Pending=0/Approved=1/Rejected=2/Cancelled=3) — a bare int
// on the wire, no JsonStringEnumConverter — and its labels are the SAME map the ferie screens use
// ([kAbsenceStatusLabels] / [absenceStatusLabel]). Do not add a second status enum or a second
// label list here: the two screens decide the same four labels.
// ══════════════════════════════════════════════════════════════════════════════

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/time/business_time.dart' show formatDateOnly, parseDateOnlyOrThrow;
import '../../presentation/providers/auth_providers.dart' show internalUserIdProvider;
import '../api/dio_client.dart';
import '../ferie/absence_request_api_client.dart' show absenceStatusLabel;

/// One SmartWorkingRequest, as the server states it — raw entity JSON, camelCase.
class SmartWorkingRequestDto {
  const SmartWorkingRequestDto({
    required this.id,
    required this.requestedByUserId,
    required this.createdByUserId,
    required this.startDate,
    required this.endDate,
    this.reason,
    required this.status,
    this.decidedByUserId,
    this.decidedAt,
    this.decisionReason,
  });

  final String id;
  final String requestedByUserId;
  final String createdByUserId;

  /// The window's first and last day, inclusive, as civil dates: `DateTime.utc(y, m, d)` through
  /// the one date codec in `business_time.dart`. Read the y/m/d fields and nothing else — a
  /// `toLocal()` on the label would show the previous day west of UTC, and a smart-working marker
  /// that names a day early is exactly the mistake this screen cannot afford.
  final DateTime startDate;
  final DateTime endDate;

  final String? reason;

  /// `AbsenceRequestStatusEnum` ordinal — 0 Pending, 1 Approved, 2 Rejected, 3 Cancelled.
  final int status;

  final String? decidedByUserId;
  final DateTime? decidedAt;
  final String? decisionReason;

  /// The shared absence-status label ('In attesa' …), clamped so an ordinal this build does not
  /// know still renders instead of taking the list down.
  String get statusLabel => absenceStatusLabel(status);

  factory SmartWorkingRequestDto.fromJson(Map<String, dynamic> json) =>
      SmartWorkingRequestDto(
        id: json['id'] as String? ?? '',
        requestedByUserId: json['requestedByUserId'] as String? ?? '',
        createdByUserId: json['createdByUserId'] as String? ?? '',
        startDate: parseDateOnlyOrThrow(json['startDate']),
        endDate: parseDateOnlyOrThrow(json['endDate']),
        reason: json['reason'] as String?,
        status: (json['status'] as num?)?.toInt() ?? 0,
        decidedByUserId: json['decidedByUserId'] as String?,
        decidedAt: json['decidedAt'] is String
            ? DateTime.tryParse(json['decidedAt'] as String)
            : null,
        decisionReason: json['decisionReason'] as String?,
      );
}

/// Thrown on a 400 whose body carries `detail` (the server's Italian, actionable prose — e.g. "la
/// data di fine non può precedere la data di inizio"), rather than a generic "riprova" string.
///
/// Mirrors [AbsenceRequestValidationError] for the same reason: those messages are the whole
/// explanation of what to change, and the form can show them as they are.
class SmartWorkingValidationError implements Exception {
  const SmartWorkingValidationError(this.detail);
  final String detail;
  @override
  String toString() => detail;
}

class SmartWorkingRequestApiClient {
  SmartWorkingRequestApiClient(this._dio);

  final Dio _dio;

  Future<T> _guarded<T>(Future<T> Function() run) async {
    try {
      return await run();
    } on DioException catch (e) {
      final data = e.response?.data;
      if (e.response?.statusCode == 400 && data is Map && data['detail'] is String) {
        throw SmartWorkingValidationError(data['detail'] as String);
      }
      rethrow;
    }
  }

  /// GET /api/smart-working-requests.
  ///
  /// [userId] is sent only when supplied. Omitting it means "my own" for a non-Approve caller —
  /// but **everyone's** for a caller holding `PresenzeAbsenceApprove`. The technician's screen is
  /// titled "le mie richieste", so [mySmartWorkingRequestsProvider] always passes the caller's own
  /// id; the nullable parameter exists for a manager's queue, not for self-scope.
  Future<List<SmartWorkingRequestDto>> fetchMine({String? userId}) => _guarded(() async {
    final res = await _dio.get<List<dynamic>>(
      '/api/smart-working-requests',
      queryParameters: {if (userId != null && userId.isNotEmpty) 'userId': userId},
    );
    final list = res.data ?? [];
    return list.cast<Map<String, dynamic>>().map(SmartWorkingRequestDto.fromJson).toList();
  });

  /// POST /api/smart-working-requests. Returns the new request's id.
  ///
  /// `requestedByUserId` is never sent: null means "myself" and the server resolves it, explicitly
  /// not trusting a client-supplied self-id.
  Future<String> create({
    required DateTime startDate,
    required DateTime endDate,
    String? reason,
  }) => _guarded(() async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/api/smart-working-requests',
      data: {
        'startDate': formatDateOnly(startDate)!,
        'endDate': formatDateOnly(endDate)!,
        if (reason != null && reason.isNotEmpty) 'reason': reason,
      },
    );
    return res.data!['id'] as String;
  });

  /// POST /api/smart-working-requests/{id}/cancel.
  Future<void> cancel(String id) => _guarded(() async {
    await _dio.post('/api/smart-working-requests/$id/cancel');
  });
}

final smartWorkingRequestApiClientProvider = Provider<SmartWorkingRequestApiClient>((ref) {
  return SmartWorkingRequestApiClient(ref.watch(dioProvider));
});

/// The current user's own smart-working requests, newest-created first (the server's order).
///
/// The caller's own id goes on the wire every time. It is not decoration: with `userId` omitted the
/// server answers an approve-holder with the whole tenant's requests, and a screen titled "le mie
/// richieste" must never show those. The id comes from [internalUserIdProvider], which
/// `EntitlementService.refresh` persists from `/api/Auth/me`.
///
/// An UNKNOWN id (before this device has ever reached the server, or after sign-out) is not a
/// licence to ask anyway: an unknown caller cannot be self-scoped, and an omitted `userId` is
/// "everything" for an approve-holder — so "we do not know who you are" resolves to nothing, never
/// to everything. The provider answers `[]` and issues no request at all; there is no filter to
/// apply, and the unscoped answer is the one answer this screen must never display. The id will
/// arrive on the next entitlement refresh, which re-runs this provider.
///
/// Online-only, unlike [myAbsenceRequestsProvider]: there is no local mirror of this entity, so a
/// failed or offline read — identity known — throws and the screen says so. An empty list is
/// reserved for the unknown-id case above; it is never a stand-in for "the server did not answer".
final mySmartWorkingRequestsProvider = FutureProvider.autoDispose<List<SmartWorkingRequestDto>>((
  ref,
) async {
  final userId = await ref.watch(internalUserIdProvider.future);
  if (userId == null || userId.isEmpty) return const <SmartWorkingRequestDto>[];
  return ref.watch(smartWorkingRequestApiClientProvider).fetchMine(userId: userId);
});
