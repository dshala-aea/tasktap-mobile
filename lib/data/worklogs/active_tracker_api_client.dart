// dart format width=100
import 'package:dio/dio.dart';

// ══════════════════════════════════════════════════════════════════════════════
// ActiveTrackerApiClient
//
// GET /api/worklog/active — everything the signed-in user is currently tracking.
//
// One call for all three kinds. They live in three tables with three independent "is one already
// running" checks, so more than one can be running at once: clocked in, on a site, with a ticket
// timer going. That is why this returns a list and why the dashboard shows every row rather than
// picking one.
// ══════════════════════════════════════════════════════════════════════════════

/// What kind of time this is. The three are not interchangeable: attendance is the working day,
/// cantiere is time on a site, ticket is time against a job.
enum ActiveTrackerKind { attendance, cantiere, ticket }

/// One running tracker.
class ActiveTracker {
  const ActiveTracker({
    required this.kind,
    required this.id,
    required this.startedAtUtc,
    this.label,
    this.entityId,
  });

  final ActiveTrackerKind kind;
  final String id;

  /// The instant it started, assembled server-side and already UTC.
  ///
  /// Never rebuild this from a worklog's own columns: they hold a date and a time-of-day
  /// separately, with no zone, and reading either alone gives a timer wrong by the offset — an
  /// hour of work nobody did, on a number somebody bills from.
  final DateTime startedAtUtc;

  /// The cantiere's name or the ticket's title. Null for attendance, which is against the day.
  final String? label;

  /// The cantiere or ticket, so a tap can open it. Null for attendance.
  final String? entityId;

  Duration elapsedAt(DateTime nowUtc) {
    final elapsed = nowUtc.difference(startedAtUtc);
    // Clock skew between phone and server can put the start slightly ahead. A negative timer
    // would read as a countdown; zero is the honest floor.
    return elapsed.isNegative ? Duration.zero : elapsed;
  }

  /// Reads the start instant as UTC even when the string carries no designator.
  ///
  /// The field is `StartedAtUtc` and the server marks it Kind=Utc, so it normally serializes with
  /// a trailing Z. Without one, `DateTime.parse` reads it as DEVICE-LOCAL and `.toUtc()` then
  /// shifts it by the offset — on a phone in Italy in August, a timer two hours out. The contract
  /// says UTC; the absence of a Z does not make it local.
  static DateTime _parseUtc(String raw) {
    final hasZone = raw.endsWith('Z') || RegExp(r'[+-]\d{2}:?\d{2}$').hasMatch(raw);
    return DateTime.parse(hasZone ? raw : '${raw}Z').toUtc();
  }

  static ActiveTrackerKind _kindFrom(Object? raw) {
    // The API serializes this enum as its name; tolerate the integer form in case that ever
    // changes, since the whole row is worth showing either way.
    switch (raw) {
      case 'Cantiere':
      case 1:
        return ActiveTrackerKind.cantiere;
      case 'Ticket':
      case 2:
        return ActiveTrackerKind.ticket;
      default:
        return ActiveTrackerKind.attendance;
    }
  }

  factory ActiveTracker.fromJson(Map<String, dynamic> json) {
    return ActiveTracker(
      kind: _kindFrom(json['kind']),
      id: json['id'] as String,
      startedAtUtc: _parseUtc(json['startedAtUtc'] as String),
      label: json['label'] as String?,
      entityId: json['entityId'] as String?,
    );
  }
}

class ActiveTrackerApiClient {
  ActiveTrackerApiClient(this._dio);

  final Dio _dio;

  Future<List<ActiveTracker>> getActive() async {
    final response = await _dio.get('/api/worklog/active');

    final data = response.data;
    final items = data is List ? data : (data is Map ? data['items'] as List? ?? const [] : const []);

    return items
        .whereType<Map<String, dynamic>>()
        .map(ActiveTracker.fromJson)
        .toList(growable: false);
  }
}
