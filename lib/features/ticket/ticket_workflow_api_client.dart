import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/time/business_time.dart';
import '../../core/time/work_time.dart';
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
  Future<void> updateStatus({
    required String ticketId,
    required int statusId,
  }) async {
    await _run(
      () => _dio.put<dynamic>(
        '/api/Tickets/$ticketId/status',
        data: {'statusId': statusId},
      ),
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
    final response = await _dio.get<List<dynamic>>(
      '/api/Tickets/$ticketId/history',
    );
    return (response.data ?? const [])
        .cast<Map<String, dynamic>>()
        .map(TicketHistoryEntryDto.fromJson)
        .toList();
  }

  /// GET /api/tickets/{ticketId}/worklogs — every entry booked against this ticket.
  Future<List<TicketWorkLogDto>> fetchWorklogs(String ticketId) async {
    final response = await _dio.get<List<dynamic>>(
      '/api/tickets/$ticketId/worklogs',
    );
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
  /// [clientId] is this device's idempotency key for the session it is starting. A phone that
  /// never saw the reply to its own start sends the same value again and is answered with the row
  /// it already owns, instead of a 400 or — worse — a second timer with the same hours booked
  /// twice. Optional so a server that does not know it yet still serves the request.
  ///
  /// [deviceUtc] is this device's own clock reading at the moment of the tap. The server uses it
  /// as the session's start instant and records the gap from its own receipt time as the clock
  /// disagreement — the flag the office reviews, never a silent correction.
  ///
  /// Returns the row the server holds. [TicketTimerStart.isActive] is false when that row is
  /// already closed, which happens when the reply was lost long enough for the office to end the
  /// session: the caller must not paint a running clock over it.
  Future<TicketTimerStart> startTimer(
    String ticketId, {
    String? clientId,
    DateTime? deviceUtc,
  }) async {
    final response = await _run(
      () => _dio.post<dynamic>(
        '/api/tickets/$ticketId/worklogs/start',
        queryParameters: {
          'clientId': ?clientId,
          ...?_deviceQuery(deviceUtc),
        },
      ),
      fallback: 'Impossibile avviare il timer.',
    );
    final body = response.data;
    if (body is! Map<String, dynamic>) {
      throw const TicketWorkflowFailure('Impossibile avviare il timer.');
    }
    return TicketTimerStart.fromJson(body);
  }

  /// POST /api/tickets/{ticketId}/worklogs/stop — same [deviceUtc] contract as [startTimer].
  Future<void> stopTimer(String ticketId, {DateTime? deviceUtc}) async {
    await _run(
      () => _dio.post<dynamic>(
        '/api/tickets/$ticketId/worklogs/stop',
        queryParameters: _deviceQuery(deviceUtc),
      ),
      fallback: 'Impossibile fermare il timer.',
    );
  }

  /// The endpoints bind `deviceUtc` from the query string, not a body: a null value must send no
  /// key at all, so the server stamps its own clock exactly as it did before this field existed.
  static Map<String, dynamic>? _deviceQuery(DateTime? deviceUtc) =>
      deviceUtc == null ? null : {'deviceUtc': deviceUtc.toUtc().toIso8601String()};

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
          'startTime': formatTimeSpan(start),
          'endTime': ?(end == null ? null : formatTimeSpan(end)),
          'description': ?description,
        },
      ),
      fallback: 'Impossibile salvare le ore.',
    );
  }

  /// DELETE /api/Tickets/{id} — permanently removes the ticket server-side.
  ///
  /// The backend gates this route on `sistema.tenant.admin` (`TicketsController.Delete`); the
  /// client hides the action behind that same capability, so a 403 reaching here means the two
  /// disagreed — see [_serverMessage] for why the server's own sentence is surfaced.
  ///
  /// A **404 is success, not failure**: the ticket is already gone server-side (deleted from
  /// another device, or by the office), which is exactly the state the caller asked for. Treating
  /// it as an error would be worse than useless — it would leave the local row behind for a ticket
  /// that no longer exists anywhere.
  ///
  /// Deliberately does not go through [_run]/[_italianFor]. Those replace the backend's message
  /// with a curated Italian one, which is right for the workflow writes (whose server sentences are
  /// English API prose) but wrong here: the caller must show *why* the server refused a delete.
  Future<void> deleteTicket(String ticketId) async {
    try {
      await _dio.delete<void>('/api/tickets/$ticketId');
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return; // already gone — success
      throw TicketWorkflowFailure(
        _serverMessage(e) ?? 'Impossibile eliminare il ticket.',
        cause: e,
      );
    }
  }

  // ── Plumbing ───────────────────────────────────────────────────────────────

  Future<Response<dynamic>> _run(
    Future<Response<dynamic>> Function() call, {
    required String fallback,
  }) async {
    try {
      return await call();
    } on DioException catch (e) {
      throw TicketWorkflowFailure(_italianFor(e, fallback), cause: e);
    }
  }

  /// The backend's own sentence for a failure, when it wrote one worth showing.
  ///
  /// The DELETE route answers with a bare string body (`NotFound(result.Message)`,
  /// `BadRequest("Tenant context is required")`) rather than a ProblemDetails envelope, so a string
  /// body is read directly; a map body (the permission filter's `application/problem+json`) is read
  /// through its `detail`/`title`/`message` members. Null when the server said nothing usable, so
  /// the caller falls back to a generic line rather than showing an empty toast.
  static String? _serverMessage(DioException e) {
    final body = e.response?.data;
    if (body is String) {
      final text = body.trim();
      return text.isEmpty ? null : text;
    }
    if (body is Map) {
      for (final key in const ['detail', 'title', 'message']) {
        final value = body[key];
        if (value is String && value.trim().isNotEmpty) return value.trim();
      }
    }
    return null;
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
    final raw = body is String
        ? body
        : (body is Map ? body['message']?.toString() : null);

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

/// The row the server holds after a ticket timer start.
class TicketTimerStart {
  const TicketTimerStart({required this.id, required this.isActive});

  /// The server's id for the session — what the mirror row is keyed on so "Ferma" works without a
  /// round trip.
  final String id;

  /// Whether that row is still running. False means the office ended it between a lost reply and
  /// this retry.
  final bool isActive;

  /// A server that does not know the `clientId` key yet answers with a bare `{id}`, and a row that
  /// call just created is running — so the absent flag defaults to true rather than to a stopped
  /// timer that never started.
  factory TicketTimerStart.fromJson(Map<String, dynamic> json) => TicketTimerStart(
    id: json['id'] as String,
    isActive: json['isActive'] as bool? ?? true,
  );
}

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
    Duration? duration,
  }) : _duration = duration;

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

  /// The backend's own computed duration (`TicketWorkLog.DurationHours`), when known — see
  /// [duration]'s doc comment for why this must be preferred over a client-side subtraction.
  final Duration? _duration;

  bool get isRunning => endTime == null;

  /// Elapsed time for a closed entry, or null while it is still open.
  ///
  /// A running entry has no duration yet, and returning `Duration.zero` for one would render a
  /// stopped-looking `0:00` next to a timer that is actually counting — the same fabrication the
  /// dashboard hero used to make.
  ///
  /// Prefers the backend's own `durationHours` (parsed into [_duration] by [fromJson]) over a
  /// naive `endTime - startTime` subtraction: [startTime]/[endTime] are bare time-of-day values
  /// with no date attached, so for an overnight session (e.g. start 20:02, end 06:10 the next day)
  /// that subtraction gives a negative duration instead of the correct positive one. The server
  /// entity already handles the day rollover correctly — trust it rather than re-deriving it here.
  /// Falls back to the naive subtraction only when constructed directly without an explicit
  /// [duration] (tests, or a payload that genuinely omits `durationHours`) — correct for same-day
  /// sessions, which covers the fallback's only real callers.
  Duration? get duration =>
      endTime == null ? null : (_duration ?? endTime! - startTime);

  /// An unreadable `startTime`/`endTime` falls back to [Duration.zero] (00:00:00): a tolerance so
  /// one bad row does not fail the whole list, not a meaningful value.
  factory TicketWorkLogDto.fromJson(Map<String, dynamic> json) =>
      TicketWorkLogDto(
        id: json['id'] as String? ?? '',
        ticketId: json['ticketId'] as String? ?? '',
        userId: json['userId'] as String? ?? '',
        workDate: parseDateOnlyOrThrow(json['workDate']),
        startTime: parseTimeSpan(json['startTime']) ?? Duration.zero,
        endTime: json['endTime'] == null
            ? null
            : (parseTimeSpan(json['endTime']) ?? Duration.zero),
        isManualEntry: json['isManualEntry'] as bool? ?? false,
        description: json['description'] as String?,
        approvalStatus: json['approvalStatus']?.toString(),
        duration: _parseDurationHours(json['durationHours']),
      );
}

/// `durationHours` arrives as a JSON number (decimal hours) — `TicketWorkLog.DurationHours`
/// server-side. Null when absent (older/malformed payload) or when the entry is still running.
Duration? _parseDurationHours(Object? value) {
  if (value == null) return null;
  final hours = value is num
      ? value.toDouble()
      : double.tryParse(value.toString());
  if (hours == null) return null;
  return Duration(milliseconds: (hours * Duration.millisecondsPerHour).round());
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

  factory TicketHistoryEntryDto.fromJson(Map<String, dynamic> json) =>
      TicketHistoryEntryDto(
        id: json['id'] as String? ?? '',
        ticketId: json['ticketId'] as String? ?? '',
        fieldName: json['fieldName'] as String? ?? '',
        changedByUserId: json['changedByUserId'] as String? ?? '',
        changedAt:
            DateTime.tryParse(json['changedAt'] as String? ?? '')?.toUtc() ??
            DateTime.now().toUtc(),
        oldValue: json['oldValue'] as String?,
        newValue: json['newValue'] as String?,
      );
}

final ticketWorkflowApiClientProvider = Provider<TicketWorkflowApiClient>((
  ref,
) {
  return TicketWorkflowApiClient(ref.watch(dioProvider));
});
