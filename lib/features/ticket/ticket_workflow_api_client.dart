import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api/dio_client.dart';

/// The writes a technician performs on a ticket from the field: take it, move its status, and
/// time the work.
///
/// Every route here has been live on the backend with no client call site, which is why a
/// technician could open a ticket in this app, read everything about it, and change nothing.
///
/// ## Online-only, and that is a real constraint
///
/// Unlike rapportini and timbrature — which queue locally and reconcile — none of these have an
/// idempotent upsert or a client-supplied dedup key, so there is nothing safe to retry against.
/// `POST .../worklogs/start` in particular creates a row per call: replaying a request whose reply
/// was lost would open a second timer. So these are attempted once, online, and their failure is
/// reported rather than swallowed into a queue that would double-write on reconnect.
///
/// [TicketWorkflowFailure] carries the reason in Italian, naming the recovery where the backend
/// gave us one to name.
class TicketWorkflowApiClient {
  TicketWorkflowApiClient(this._dio);

  final Dio _dio;

  /// PUT /api/Tickets/{id}/status
  Future<void> updateStatus({required String ticketId, required int statusId}) async {
    await _run(
      () => _dio.put<dynamic>('/api/Tickets/$ticketId/status', data: {'statusId': statusId}),
      fallback: 'Impossibile aggiornare lo stato del ticket.',
    );
  }

  /// POST /api/Tickets/{id}/self-assign — takes the ticket for the calling user.
  ///
  /// The backend refuses a closed ticket with a 400.
  Future<void> selfAssign(String ticketId) async {
    await _run(
      () => _dio.post<dynamic>('/api/Tickets/$ticketId/self-assign'),
      fallback: 'Impossibile assegnarsi il ticket.',
    );
  }

  /// GET /api/Tickets/{id}/history — the field-by-field audit trail, newest first.
  Future<List<TicketHistoryEntryDto>> fetchHistory(String ticketId) async {
    final response = await _dio.get<List<dynamic>>('/api/Tickets/$ticketId/history');
    return (response.data ?? const [])
        .cast<Map<String, dynamic>>()
        .map(TicketHistoryEntryDto.fromJson)
        .toList();
  }

  /// GET /api/tickets/{ticketId}/worklogs — every entry booked against this ticket.
  Future<List<TicketWorkLogDto>> fetchWorklogs(String ticketId) async {
    final response = await _dio.get<List<dynamic>>('/api/tickets/$ticketId/worklogs');
    return (response.data ?? const [])
        .cast<Map<String, dynamic>>()
        .map(TicketWorkLogDto.fromJson)
        .toList();
  }

  /// POST /api/tickets/{ticketId}/worklogs/start
  ///
  /// The backend refuses when the caller already has **any** open ticket timer — not just one on
  /// this ticket. Its own message ("You already have an active ticket work log. Stop it first.")
  /// is mapped in [_italianFor] to say which recovery is meant, because "stop it first" is not
  /// actionable if the technician is looking at a ticket whose timer is not the one running.
  Future<void> startTimer(String ticketId) async {
    await _run(
      () => _dio.post<dynamic>('/api/tickets/$ticketId/worklogs/start'),
      fallback: 'Impossibile avviare il timer.',
    );
  }

  /// POST /api/tickets/{ticketId}/worklogs/stop
  Future<void> stopTimer(String ticketId) async {
    await _run(
      () => _dio.post<dynamic>('/api/tickets/$ticketId/worklogs/stop'),
      fallback: 'Impossibile fermare il timer.',
    );
  }

  /// POST /api/tickets/{ticketId}/worklogs/manual
  ///
  /// [workDate] is a calendar day; [start] and [end] are times of day on it. The server stores
  /// them as a date plus two TimeSpans, so they are sent in those shapes rather than as instants.
  Future<void> addManual({
    required String ticketId,
    required DateTime workDate,
    required Duration start,
    Duration? end,
    String? description,
  }) async {
    await _run(
      () => _dio.post<dynamic>(
        '/api/tickets/$ticketId/worklogs/manual',
        data: {
          'workDate': _dateOnly(workDate),
          'startTime': _hms(start),
          'endTime': ?(end == null ? null : _hms(end)),
          'description': ?description,
        },
      ),
      fallback: 'Impossibile salvare le ore.',
    );
  }

  // ── Plumbing ───────────────────────────────────────────────────────────────

  Future<void> _run(Future<Response<dynamic>> Function() call, {required String fallback}) async {
    try {
      await call();
    } on DioException catch (e) {
      throw TicketWorkflowFailure(_italianFor(e, fallback), cause: e);
    }
  }

  /// Turns a DioException into something a technician can act on.
  ///
  /// The backend answers these routes with a bare string body on 400/404 (`BadRequest("...")`),
  /// not a ProblemDetails envelope, so the message is read from the body when it is a string and
  /// matched against the handful the controllers actually produce. An unmatched server message is
  /// *not* shown raw — it is English, written for an API consumer, and putting it in front of a
  /// technician in the field is worse than the specific fallback the call site supplied.
  static String _italianFor(DioException e, String fallback) {
    final status = e.response?.statusCode;
    final body = e.response?.data;
    final raw = body is String ? body : (body is Map ? body['message']?.toString() : null);

    if (e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.sendTimeout ||
        e.type == DioExceptionType.receiveTimeout) {
      return 'Nessuna connessione. Questa operazione richiede la rete: '
          'riprova quando hai segnale.';
    }

    if (status == 403) {
      return 'Non hai i permessi per questa operazione.';
    }

    if (raw != null) {
      final m = raw.toLowerCase();
      if (m.contains('already have an active ticket work log')) {
        // Deliberately names the other ticket rather than this one: the open timer is on some
        // ticket, not necessarily the one on screen, and "stop it first" sends the technician
        // looking in the wrong place.
        return 'Hai già un timer avviato su un altro intervento. '
            'Fermalo prima di avviarne uno nuovo.';
      }
      if (m.contains('no active timer')) {
        return 'Nessun timer attivo su questo intervento.';
      }
      if (m.contains('cannot assign a closed ticket')) {
        return 'Il ticket è chiuso e non può essere assegnato.';
      }
      if (m.contains('ticket not found')) {
        return 'Ticket non trovato. Potrebbe essere stato eliminato.';
      }
    }

    return fallback;
  }

  static String _dateOnly(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  static String _hms(Duration d) {
    final h = d.inHours.toString().padLeft(2, '0');
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }
}

/// A workflow write that did not happen, with a reason worth showing.
class TicketWorkflowFailure implements Exception {
  const TicketWorkflowFailure(this.message, {this.cause});

  final String message;
  final DioException? cause;

  @override
  String toString() => message;
}

// ── DTOs ──────────────────────────────────────────────────────────────────────

/// One entry booked against a ticket.
class TicketWorkLogDto {
  const TicketWorkLogDto({
    required this.id,
    required this.ticketId,
    required this.userId,
    required this.workDate,
    required this.startTime,
    required this.isManualEntry,
    this.endTime,
    this.description,
    this.approvalStatus,
  });

  final String id;
  final String ticketId;
  final String userId;
  final DateTime workDate;
  final Duration startTime;

  /// Null while the timer is still running — which is what makes this entry the live one.
  final Duration? endTime;

  final bool isManualEntry;
  final String? description;
  final String? approvalStatus;

  bool get isRunning => endTime == null;

  /// Elapsed time for a closed entry, or null while it is still open.
  ///
  /// A running entry has no duration yet, and returning `Duration.zero` for one would render a
  /// stopped-looking `0:00` next to a timer that is actually counting — the same fabrication the
  /// dashboard hero used to make.
  Duration? get duration => endTime == null ? null : endTime! - startTime;

  factory TicketWorkLogDto.fromJson(Map<String, dynamic> json) => TicketWorkLogDto(
    id: json['id'] as String? ?? '',
    ticketId: json['ticketId'] as String? ?? '',
    userId: json['userId'] as String? ?? '',
    workDate:
        DateTime.tryParse(json['workDate'] as String? ?? '')?.toUtc() ?? DateTime.now().toUtc(),
    startTime: _parseHms(json['startTime']),
    endTime: json['endTime'] == null ? null : _parseHms(json['endTime']),
    isManualEntry: json['isManualEntry'] as bool? ?? false,
    description: json['description'] as String?,
    approvalStatus: json['approvalStatus']?.toString(),
  );
}

/// One field change on a ticket.
class TicketHistoryEntryDto {
  const TicketHistoryEntryDto({
    required this.id,
    required this.ticketId,
    required this.fieldName,
    required this.changedByUserId,
    required this.changedAt,
    this.oldValue,
    this.newValue,
  });

  final String id;
  final String ticketId;
  final String fieldName;
  final String changedByUserId;
  final DateTime changedAt;
  final String? oldValue;
  final String? newValue;

  factory TicketHistoryEntryDto.fromJson(Map<String, dynamic> json) => TicketHistoryEntryDto(
    id: json['id'] as String? ?? '',
    ticketId: json['ticketId'] as String? ?? '',
    fieldName: json['fieldName'] as String? ?? '',
    changedByUserId: json['changedByUserId'] as String? ?? '',
    changedAt:
        DateTime.tryParse(json['changedAt'] as String? ?? '')?.toUtc() ?? DateTime.now().toUtc(),
    oldValue: json['oldValue'] as String?,
    newValue: json['newValue'] as String?,
  );
}

/// `TimeSpan` arrives as `HH:MM:SS`, and as `D.HH:MM:SS` once it passes 24 hours.
///
/// The day component is not hypothetical here: a timer left running overnight — the exact failure
/// the dashboard's multi-tracker section exists to make visible — comes back with one.
Duration _parseHms(Object? value) {
  if (value is! String || value.isEmpty) return Duration.zero;

  var rest = value;
  var days = 0;
  final dot = rest.indexOf('.');
  final colon = rest.indexOf(':');
  if (dot > 0 && (colon < 0 || dot < colon)) {
    days = int.tryParse(rest.substring(0, dot)) ?? 0;
    rest = rest.substring(dot + 1);
  }

  final parts = rest.split(':');
  if (parts.length < 2) return Duration.zero;
  final h = int.tryParse(parts[0]) ?? 0;
  final m = int.tryParse(parts[1]) ?? 0;
  final s = parts.length > 2 ? double.tryParse(parts[2])?.floor() ?? 0 : 0;
  return Duration(days: days, hours: h, minutes: m, seconds: s);
}

final ticketWorkflowApiClientProvider = Provider<TicketWorkflowApiClient>((ref) {
  return TicketWorkflowApiClient(ref.watch(dioProvider));
});
