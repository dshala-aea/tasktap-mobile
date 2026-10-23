// ══════════════════════════════════════════════════════════════════════════════
// TicketTimerApiClient
//
// The offline counterpart to the ticket timer bar's start/stop pair:
//   POST /api/tickets/worklogs/mobile/sessions
//
// The online routes (`POST /api/tickets/{id}/worklogs/start|stop`) are check-then-act: a re-sent
// start answers 400 "you already have an active ticket work log", which is indistinguishable from
// any other 400, so a phone could neither retry safely nor tell a lost session from a delivered
// one. This endpoint keys on a client-generated id and upserts, so the same payload can be sent
// again and again. Hours logged on a ticket are what the customer is billed from.
//
// Field names match TicketMobileSessionDto on the backend verbatim (camelCase as ASP.NET's default
// serializer writes them) — see the OpenAPI snapshot's TicketMobileSessionDto schema.
// ══════════════════════════════════════════════════════════════════════════════

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/dio_client.dart';

/// One ticket timer session as the device recorded it, ready for the batch upsert.
class TicketMobileSessionDto {
  const TicketMobileSessionDto({
    required this.clientId,
    required this.ticketId,
    required this.startTime,
    this.endTime,
    this.description,
    this.deviceUtc,
  });

  final String clientId;
  final String ticketId;

  /// UTC instant the timer was started on the device.
  final DateTime startTime;

  /// UTC instant it was stopped; null while the timer is still running.
  final DateTime? endTime;

  final String? description;

  /// This phone's own clock reading at the moment this batch was sent.
  ///
  /// Deliberately not [startTime]: a queued session can be hours old and the phone's clock may have
  /// been corrected in between, so comparing the start with the server's receipt would measure how
  /// long the queue sat rather than how far the clock was off (O-10 plan §2). The server records the
  /// difference beside the row and never moves the recorded instants because of it.
  final DateTime? deviceUtc;

  Map<String, dynamic> toJson() => {
    'clientId': clientId,
    'ticketId': ticketId,
    'startTime': startTime.toUtc().toIso8601String(),
    'endTime': endTime?.toUtc().toIso8601String(),
    if (description != null) 'description': description,
    if (deviceUtc != null) 'deviceUtc': deviceUtc!.toUtc().toIso8601String(),
  };
}

/// What the server holds for one session after the upsert.
class TicketMobileSessionResult {
  const TicketMobileSessionResult({
    required this.clientId,
    required this.ticketWorkLogId,
    required this.ticketId,
    required this.startTime,
    this.endTime,
    required this.isActive,
    this.clockDisagreementSeconds,
  });

  final String clientId;
  final String ticketWorkLogId;
  final String ticketId;
  final DateTime startTime;
  final DateTime? endTime;
  final bool isActive;

  /// How far this phone's clock was from the server's at the moment this batch was sent, signed —
  /// **only when the server judged it a disagreement** (its own ten-minute threshold). Null for
  /// ordinary drift, for a batch sent without a device clock, and for a backend that predates the
  /// field.
  ///
  /// This is the answer to a question the phone cannot answer itself: it never sees the server's
  /// receipt instant. So it travels back with the session it concerns, and it is rendered rather
  /// than re-judged — the threshold lives in exactly one place (`WorkLogClocks`).
  final int? clockDisagreementSeconds;

  factory TicketMobileSessionResult.fromJson(Map<String, dynamic> json) =>
      TicketMobileSessionResult(
        clientId: json['clientId'] as String,
        ticketWorkLogId: json['ticketWorkLogId'] as String,
        ticketId: json['ticketId'] as String,
        startTime: DateTime.parse(json['startTime'] as String),
        endTime: json['endTime'] != null
            ? DateTime.parse(json['endTime'] as String)
            : null,
        isActive: json['isActive'] as bool? ?? false,
        clockDisagreementSeconds:
            (json['clockDisagreementSeconds'] as num?)?.toInt(),
      );
}

class TicketTimerApiClient {
  TicketTimerApiClient(this._dio);

  final Dio _dio;

  /// Idempotent batch upsert. The server matches on (tenant, user, clientId) and only ever CLOSES
  /// a session it already holds — a stale queued copy can never move a start the office corrected.
  /// Throws [DioException] on network or server error.
  Future<List<TicketMobileSessionResult>> upsertSessions(
    List<TicketMobileSessionDto> sessions,
  ) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/tickets/worklogs/mobile/sessions',
      data: {'sessions': sessions.map((s) => s.toJson()).toList()},
    );

    final data = response.data;
    if (data == null) throw StateError('Risposta vuota da upsertSessions');

    final list = data['sessions'] as List<dynamic>? ?? [];
    return list
        .cast<Map<String, dynamic>>()
        .map(TicketMobileSessionResult.fromJson)
        .toList();
  }
}

/// Provides [TicketTimerApiClient]. Override in tests with a fake.
final ticketTimerApiClientProvider = Provider<TicketTimerApiClient>((ref) {
  return TicketTimerApiClient(ref.watch(dioProvider));
});
