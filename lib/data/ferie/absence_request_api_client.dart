// dart format width=100
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/dio_client.dart';

// ══════════════════════════════════════════════════════════════════════════════
// AbsenceRequestApiClient — self-service ferie/permessi against
// AbsenceRequestsController (/api/absence-requests), already complete and tested server-side.
// Online-only: this is data typed by the same person who reads it back, not a field-capture
// write that must survive a dead signal.
//
// AbsenceTypeEnum (Ferie=0/Permesso=1/Malattia=2) and AbsenceRequestStatusEnum
// (Pending=0/Approved=1/Rejected=2/Cancelled=3) are bare ints on the wire — no
// [JsonStringEnumConverter] server-side.
// ══════════════════════════════════════════════════════════════════════════════

const List<String> kAbsenceTypeLabels = ['Ferie', 'Permesso', 'Malattia'];
const List<String> kAbsenceStatusLabels = ['In attesa', 'Approvata', 'Rifiutata', 'Annullata'];

String absenceTypeLabel(int type) =>
    kAbsenceTypeLabels[type.clamp(0, kAbsenceTypeLabels.length - 1)];
String absenceStatusLabel(int status) =>
    kAbsenceStatusLabels[status.clamp(0, kAbsenceStatusLabels.length - 1)];

/// `date` as `yyyy-MM-dd` — the wire format .NET's `DateOnly` converter both writes and accepts.
String formatDateOnly(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime _parseDateOnly(Object? v) {
  if (v is! String || v.isEmpty) return DateTime.now();
  final parts = v.split('-');
  if (parts.length != 3) return DateTime.tryParse(v) ?? DateTime.now();
  final y = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  final d = int.tryParse(parts[2]);
  if (y == null || m == null || d == null) return DateTime.tryParse(v) ?? DateTime.now();
  return DateTime(y, m, d);
}

/// One AbsenceRequest, as the server states it — raw entity JSON, camelCase.
class AbsenceRequestDto {
  const AbsenceRequestDto({
    required this.id,
    required this.requestedByUserId,
    required this.createdByUserId,
    required this.type,
    required this.startDate,
    required this.endDate,
    this.startTime,
    this.endTime,
    this.reason,
    required this.status,
    this.decidedByUserId,
    this.decidedAt,
    this.decisionReason,
  });

  final String id;
  final String requestedByUserId;
  final String createdByUserId;
  final int type;
  final DateTime startDate;
  final DateTime endDate;
  final String? startTime; // "HH:MM:SS", straight off the wire
  final String? endTime;
  final String? reason;
  final int status;
  final String? decidedByUserId;
  final DateTime? decidedAt;
  final String? decisionReason;

  factory AbsenceRequestDto.fromJson(Map<String, dynamic> json) => AbsenceRequestDto(
    id: json['id'] as String? ?? '',
    requestedByUserId: json['requestedByUserId'] as String? ?? '',
    createdByUserId: json['createdByUserId'] as String? ?? '',
    type: (json['type'] as num?)?.toInt() ?? 0,
    startDate: _parseDateOnly(json['startDate']),
    endDate: _parseDateOnly(json['endDate']),
    startTime: json['startTime'] as String?,
    endTime: json['endTime'] as String?,
    reason: json['reason'] as String?,
    status: (json['status'] as num?)?.toInt() ?? 0,
    decidedByUserId: json['decidedByUserId'] as String?,
    decidedAt: json['decidedAt'] is String ? DateTime.tryParse(json['decidedAt'] as String) : null,
    decisionReason: json['decisionReason'] as String?,
  );
}

/// Thrown on a 400 from the server, carrying its own `detail` message (already safe, Italian
/// prose — see AbsenceRequestsController's DomainRuleException codes) rather than a generic
/// "riprova" string, since these messages are genuinely actionable (e.g. "la data di fine non
/// può precedere la data di inizio").
class AbsenceRequestValidationError implements Exception {
  const AbsenceRequestValidationError(this.detail);
  final String detail;
  @override
  String toString() => detail;
}

class AbsenceRequestApiClient {
  AbsenceRequestApiClient(this._dio);

  final Dio _dio;

  Future<T> _guarded<T>(Future<T> Function() run) async {
    try {
      return await run();
    } on DioException catch (e) {
      final data = e.response?.data;
      if (e.response?.statusCode == 400 && data is Map && data['detail'] is String) {
        throw AbsenceRequestValidationError(data['detail'] as String);
      }
      rethrow;
    }
  }

  /// GET /api/absence-requests — no userId means "my own" for a non-Approve caller
  /// (server-enforced; this client never sends userId).
  Future<List<AbsenceRequestDto>> fetchMine() => _guarded(() async {
    final res = await _dio.get<List<dynamic>>('/api/absence-requests');
    final list = res.data ?? [];
    return list.cast<Map<String, dynamic>>().map(AbsenceRequestDto.fromJson).toList();
  });

  /// POST /api/absence-requests. Returns the new request's id.
  Future<String> create({
    required int type,
    required DateTime startDate,
    required DateTime endDate,
    String? startTime,
    String? endTime,
    String? reason,
  }) => _guarded(() async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/api/absence-requests',
      data: {
        'type': type,
        'startDate': formatDateOnly(startDate),
        'endDate': formatDateOnly(endDate),
        'startTime': ?startTime,
        'endTime': ?endTime,
        if (reason != null && reason.isNotEmpty) 'reason': reason,
      },
    );
    return res.data!['id'] as String;
  });

  /// POST /api/absence-requests/{id}/cancel.
  Future<void> cancel(String id) => _guarded(() async {
    await _dio.post('/api/absence-requests/$id/cancel');
  });
}

final absenceRequestApiClientProvider = Provider<AbsenceRequestApiClient>((ref) {
  return AbsenceRequestApiClient(ref.watch(dioProvider));
});

/// The current user's own requests, most relevant first (server sorts newest-created-first).
final myAbsenceRequestsProvider = FutureProvider.autoDispose<List<AbsenceRequestDto>>((ref) {
  return ref.watch(absenceRequestApiClientProvider).fetchMine();
});
