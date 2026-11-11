// dart format width=100
// ══════════════════════════════════════════════════════════════════════════════
// TrasfertaRequestApiClient — self-service Trasferta (travel time recognised as worked time)
// against TrasfertaRequestsController (/api/trasferta-requests).
//
//   POST /api/trasferta-requests              — file a trasferta for a day (born Approved)
//   GET  /api/trasferta-requests?userId=…     — list requests
//   POST /api/trasferta-requests/{id}/cancel  — withdraw one the technician filed for themselves
//
// A trasferta is a day, a start time and a number of hours; the server writes the worklog itself.
// There is no approval step for the technician and no update call here (the office edits).
//
// Online-only, like smart working: filing and cancelling are writes the server must decide (payroll
// lock, one trasferta per day, approved absences), so there is no local mirror and no queue — an
// offline attempt is refused visibly by the caller.
//
// Wire shapes (api snapshot): `date` is `yyyy-MM-dd`, `startTime` is `HH:mm` (TimeOnly), `hours`
// is a decimal number, `status` is the bare `AbsenceRequestStatusEnum` int shared with ferie.
// ══════════════════════════════════════════════════════════════════════════════

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/time/business_time.dart' show formatDateOnly, parseDateOnlyOrThrow;
import '../api/dio_client.dart';
import '../entitlements/entitlement_service.dart' show internalUserIdPrefsKey;
import '../ferie/absence_request_api_client.dart' show absenceStatusLabel;

/// The server's hours rule, verbatim (`TrasfertaRequestService.ValidateHours`).
const String kTrasfertaHoursInvalid =
    'Le ore devono essere maggiori di 0, al massimo 24 e multiple di 0,25.';

/// The server's midnight rule, verbatim (`MapWriterFailure`).
const String kTrasfertaCrossesMidnight =
    'La trasferta non può superare la mezzanotte del giorno scelto.';

/// Parses a typed hours value: accepts `1,5` and `1.5`. Null when it is not a number at all.
double? parseTrasfertaHours(String raw) {
  final text = raw.trim().replaceAll(',', '.');
  if (text.isEmpty) return null;
  final value = double.tryParse(text);
  if (value == null || value.isNaN || value.isInfinite) return null;
  return value;
}

/// Client-side mirror of the server's two hour rules, in the server's own sentences. Null = valid.
///
/// [startMinutes] is minutes from midnight. The 0.25 step is checked on integer quarter-hours so
/// binary float noise never refuses a legitimate 0.75.
String? trasfertaRulesError({required double? hours, required int? startMinutes}) {
  if (hours == null || hours <= 0 || hours > 24) return kTrasfertaHoursInvalid;
  final quarters = hours * 4;
  if ((quarters - quarters.roundToDouble()).abs() > 1e-9) return kTrasfertaHoursInvalid;
  if (startMinutes != null && startMinutes + (quarters.round() * 15) > 24 * 60) {
    return kTrasfertaCrossesMidnight;
  }
  return null;
}

String _requireId(Object? raw) {
  if (raw is String && raw.isNotEmpty) return raw;
  throw FormatException('TrasfertaRequestDto.id is required', raw);
}

int _requireStatus(Object? raw) {
  if (raw is num) return raw.toInt();
  throw FormatException('TrasfertaRequestDto.status is required', raw);
}

/// One trasferta, as `TrasfertaRequestDto` states it.
class TrasfertaRequestDto {
  const TrasfertaRequestDto({
    required this.id,
    required this.requestedByUserId,
    required this.createdByUserId,
    required this.date,
    required this.startTime,
    required this.hours,
    this.reason,
    required this.status,
    this.workLogId,
  });

  final String id;
  final String requestedByUserId;
  final String createdByUserId;

  /// Civil date as `DateTime.utc(y, m, d)`; read y/m/d only, never `toLocal()`.
  final DateTime date;

  /// `HH:mm`, as the server states it (seconds dropped).
  final String startTime;
  final double hours;
  final String? reason;

  /// `AbsenceRequestStatusEnum` ordinal — 0 Pending, 1 Approved, 2 Rejected, 3 Cancelled.
  final int status;
  final String? workLogId;

  String get statusLabel => absenceStatusLabel(status);

  /// The technician may withdraw only a live trasferta they filed for themselves (the list is
  /// already scoped to their own id); the server refuses the rest (`trasferta_not_yours`,
  /// `trasferta_not_active`), so one the office filed for them offers no button.
  bool get cancellable => status != 3 && createdByUserId == requestedByUserId;

  factory TrasfertaRequestDto.fromJson(Map<String, dynamic> json) {
    final rawStart = json['startTime'];
    final start = rawStart is String && rawStart.length >= 5 ? rawStart.substring(0, 5) : '';
    final rawHours = json['hours'];
    return TrasfertaRequestDto(
      id: _requireId(json['id']),
      requestedByUserId: json['requestedByUserId'] as String? ?? '',
      createdByUserId: json['createdByUserId'] as String? ?? '',
      date: parseDateOnlyOrThrow(json['date']),
      startTime: start,
      hours: rawHours is num ? rawHours.toDouble() : (parseTrasfertaHours('$rawHours') ?? 0),
      reason: json['reason'] as String?,
      status: _requireStatus(json['status']),
      workLogId: json['workLogId'] as String?,
    );
  }
}

/// A 400 or 409 whose body carries `detail` — the server's actionable Italian ("Esiste già una
/// trasferta per questa persona in questa data."), shown to the technician as it is.
class TrasfertaRuleError implements Exception {
  const TrasfertaRuleError(this.detail);
  final String detail;
  @override
  String toString() => detail;
}

class TrasfertaRequestApiClient {
  TrasfertaRequestApiClient(this._dio);

  final Dio _dio;

  Future<T> _guarded<T>(Future<T> Function() run) async {
    try {
      return await run();
    } on DioException catch (e) {
      final data = e.response?.data;
      final code = e.response?.statusCode;
      if ((code == 400 || code == 409 || code == 403) && data is Map && data['detail'] is String) {
        throw TrasfertaRuleError(data['detail'] as String);
      }
      rethrow;
    }
  }

  /// GET /api/trasferta-requests. [userId] is always sent by the provider: omitted, an approver
  /// would receive the whole tenant's rows.
  Future<List<TrasfertaRequestDto>> fetchMine({String? userId}) => _guarded(() async {
    final res = await _dio.get<List<dynamic>>(
      '/api/trasferta-requests',
      queryParameters: {if (userId != null && userId.isNotEmpty) 'userId': userId},
    );
    final list = res.data;
    if (list == null) {
      throw const FormatException('GET /api/trasferta-requests answered 200 with no body');
    }
    return list.cast<Map<String, dynamic>>().map(TrasfertaRequestDto.fromJson).toList();
  });

  /// POST /api/trasferta-requests. `requestedByUserId` is never sent: null means "myself".
  /// Returns nothing on purpose (a parse failure after the server created the row would invite a
  /// duplicate retry).
  Future<void> create({
    required DateTime date,
    required int startHour,
    required int startMinute,
    required double hours,
    String? reason,
  }) => _guarded(() async {
    await _dio.post<dynamic>(
      '/api/trasferta-requests',
      data: {
        'date': formatDateOnly(date)!,
        'startTime':
            '${startHour.toString().padLeft(2, '0')}:${startMinute.toString().padLeft(2, '0')}',
        'hours': hours,
        if (reason != null && reason.isNotEmpty) 'reason': reason,
      },
    );
  });

  /// POST /api/trasferta-requests/{id}/cancel.
  Future<void> cancel(String id) => _guarded(() async {
    await _dio.post<dynamic>('/api/trasferta-requests/$id/cancel');
  });
}

final trasfertaRequestApiClientProvider = Provider<TrasfertaRequestApiClient>((ref) {
  return TrasfertaRequestApiClient(ref.watch(dioProvider));
});

/// The signed-in user's internal id, read fresh from prefs (same reasoning as
/// `mySmartWorkingRequestsProvider`: the cached provider can belong to the previous user).
Future<String?> currentTrasfertaUserId() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString(internalUserIdPrefsKey);
}

/// The caller's own trasferte, newest day first (the server's order). Unknown caller → `[]` with no
/// request (never an unscoped list); an unreachable server throws and the screen says so.
final myTrasfertaRequestsProvider = FutureProvider.autoDispose<List<TrasfertaRequestDto>>((
  ref,
) async {
  final userId = await currentTrasfertaUserId();
  if (userId == null || userId.isEmpty) return const <TrasfertaRequestDto>[];
  return ref.watch(trasfertaRequestApiClientProvider).fetchMine(userId: userId);
});
