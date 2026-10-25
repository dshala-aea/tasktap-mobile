// dart format width=100
import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/time/business_time.dart' show parseDateOnlyOrThrow;
import '../../core/utils/error_message.dart' show isTransportOrServerFault;
import '../api/dio_client.dart';
import '../sync/connectivity_provider.dart';
import '../sync/sync_service.dart' show appDatabaseProvider;

// ══════════════════════════════════════════════════════════════════════════════
// AbsenceRequestApiClient — self-service ferie/permessi against
// AbsenceRequestsController (/api/absence-requests), already complete and tested server-side.
//
// Filing and cancelling are online-only: they are writes the server must validate and decide, and
// a queued "request sent" that the server never saw would be a lie the technician then waits on.
// Reading is not: the sync mirrors the caller's own requests into `absence_requests`, so the list
// answers with no signal (see myAbsenceRequestsProvider).
//
// AbsenceTypeEnum (Ferie=0/Permesso=1/Malattia=2, then Rol=3, ExFestivita=4, PermessoRetribuito=5,
// PermessoNonRetribuito=6, Legge104=7, CongedoParentale=8, AltriCongediPermessi=9) and
// AbsenceRequestStatusEnum (Pending=0/Approved=1/Rejected=2/Cancelled=3) are bare ints on the wire
// — no [JsonStringEnumConverter] server-side.
// ══════════════════════════════════════════════════════════════════════════════

/// `AbsenceTypeEnum` display names, indexed by the wire ordinal — all ten, including the legacy
/// [Permesso] (1) that rows filed before 2026-09 still carry.
///
/// The list used to stop at Malattia and clamp: a ROL request then rendered as "Malattia", which is
/// the one wrong label this screen cannot afford. Never index it by hand — go through
/// [absenceTypeLabel].
const List<String> kAbsenceTypeLabels = [
  'Ferie', // 0
  'Permesso', // 1 — legacy, kept for old rows
  'Malattia', // 2
  'ROL', // 3
  'Ex festività', // 4
  'Permesso retribuito', // 5
  'Permesso non retribuito', // 6
  'Legge 104', // 7
  'Congedo parentale', // 8
  'Altri congedi/permessi', // 9
];

/// The types a NEW request may carry: the nine the client asked for. Index 1 ([kAbsenceTypeLabels]
/// `Permesso`) is a legacy value kept so old rows render — offering it would let someone file a
/// request the office form can no longer express.
const List<int> kSelectableAbsenceTypes = [0, 2, 3, 4, 5, 6, 7, 8, 9];

/// The "permesso" variants that may carry a same-day time window — mirrors the server's own
/// `IsPermessoType`, so the form never offers a pairing `CreateAsync` would reject.
const Set<int> kPermessoAbsenceTypes = {1, 5, 6};

/// `AbsenceTypeEnum.AltriCongediPermessi` — a catch-all whose Reason the server requires, because
/// it is the only place such a request says what it actually is.
const int kAltriCongediPermessiType = 9;

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
///
/// Online this is the server's answer. With no signal — or when the request never arrived, or the
/// server faulted — it answers from the device's own mirror of the caller's requests
/// (`absence_requests`, filled by the sync), because "was my request approved" is a question whose
/// answer was decided days ago and does not need a radio. Filing and cancelling stay online: both
/// need the server's validation and its decision to mean anything.
///
/// A 4xx still throws. That is the server saying something about THIS request (a permission, a
/// malformed query), not a statement about the technician's history, and swallowing it would show
/// them a stale list as if it were current.
/// The answer plus where it came from.
///
/// A bare list cannot tell "the server says you have filed nothing" from "this device has never
/// downloaded your history", and the list screen must say different things in those two cases: an
/// empty mirror is a missing download, never a fact about the technician. So the source travels
/// with the rows instead of being guessed from the connectivity flag afterwards — a request that
/// was attempted online and then fell back to the mirror is exactly the case a guess gets wrong.
typedef MyAbsenceRequests = ({List<AbsenceRequestDto> items, bool fromDevice});

final myAbsenceRequestsProvider = FutureProvider.autoDispose<MyAbsenceRequests>((ref) async {
  Future<MyAbsenceRequests> fromDevice() async =>
      (items: await _readMirror(ref), fromDevice: true);

  if (!ref.watch(isOnlineProvider)) return fromDevice();

  try {
    return (
      items: await ref.watch(absenceRequestApiClientProvider).fetchMine(),
      fromDevice: false,
    );
  } catch (e) {
    if (!isTransportOrServerFault(e)) rethrow;
    return fromDevice();
  }
});

/// The device's own copy of the caller's requests, shaped exactly like the wire rows so the list
/// cannot tell a mirrored request from a fetched one.
///
/// [startDate]/[endDate] are parsed back to `DateTime.utc(y, m, d)` — a civil day. Never run them
/// through a zone conversion: west of UTC that shows the previous day, and a ferie request that
/// starts a day early is exactly the mistake this screen cannot afford.
Future<List<AbsenceRequestDto>> _readMirror(Ref ref) async {
  final db = ref.watch(appDatabaseProvider);
  final rows = await (db.select(db.absenceRequests)..orderBy([
        (r) => OrderingTerm.desc(r.createdAt),
        (r) => OrderingTerm.asc(r.id),
      ]))
      .get();

  return [
    for (final r in rows)
      AbsenceRequestDto(
        id: r.id,
        requestedByUserId: r.requestedByUserId,
        createdByUserId: r.createdByUserId,
        type: r.type,
        startDate: parseDateOnlyOrThrow(r.startDate),
        endDate: parseDateOnlyOrThrow(r.endDate),
        startTime: r.startTime,
        endTime: r.endTime,
        reason: r.reason,
        status: r.status,
        decidedByUserId: r.decidedByUserId,
        decidedAt: r.decidedAt,
        decisionReason: r.decisionReason,
      ),
  ];
}
