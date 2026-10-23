// Unit tests for TicketTimerSyncService — the upload half of the offline ticket timer.
//
// The repository is the real one over an in-memory Drift database; only the network is faked, so
// these tests cover the whole path from "technician tapped Avvia offline" to "the server echoes the
// row back". The failure classification is the point: a transient failure must keep the hours
// queued and a refusal must say why instead of retrying forever.

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/core/time/business_time.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/timbratura/ticket_timer_api_client.dart';
import 'package:tasktap_mobile/data/timbratura/ticket_timer_repository.dart';
import 'package:tasktap_mobile/data/timbratura/ticket_timer_sync_service.dart';

AppDatabase _makeDb() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  return AppDatabase(NativeDatabase.memory());
}

/// Answers however the test needs and remembers the body it was sent.
class _Adapter implements HttpClientAdapter {
  _Adapter(this.respond);

  final Future<ResponseBody> Function(RequestOptions options) respond;
  Map<String, dynamic>? sentBody;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) {
    final data = options.data;
    sentBody = data is Map<String, dynamic>
        ? data
        : jsonDecode(jsonEncode(data)) as Map<String, dynamic>;
    return respond(options);
  }
}

const _json = {Headers.contentTypeHeader: [Headers.jsonContentType]};

/// A successful echo: one result per sent session, carrying the server's own id.
Future<ResponseBody> _echoAll(RequestOptions options) async {
  final sent = (options.data as Map<String, dynamic>)['sessions'] as List<dynamic>;
  final results = sent.map((s) {
    final session = s as Map<String, dynamic>;
    return {
      'clientId': session['clientId'],
      'ticketWorkLogId': 'server-${session['clientId']}',
      'ticketId': session['ticketId'],
      'startTime': session['startTime'],
      'endTime': session['endTime'],
      'isActive': session['endTime'] == null,
    };
  }).toList();
  return ResponseBody.fromString(
    jsonEncode({'sessions': results}),
    200,
    headers: _json,
  );
}

void main() {
  late AppDatabase db;
  late TicketTimerRepository repo;
  late _Adapter adapter;

  final now = DateTime.utc(2026, 8, 16, 8, 30); // 10:30 Rome (CEST)

  TicketTimerSyncService serviceFor() => TicketTimerSyncService(
    repo: repo,
    apiClient: TicketTimerApiClient(Dio()..httpClientAdapter = adapter),
    businessTime: BusinessTime.fallback(),
    clock: () => now,
  );

  setUp(() {
    db = _makeDb();
    repo = TicketTimerRepository(
      db,
      businessTime: BusinessTime.fallback(),
      clock: () => now,
    );
    adapter = _Adapter(_echoAll);
  });

  tearDown(() async => db.close());

  test('uploads a device session and adopts the id the server echoed', () async {
    final started = await repo.start(ticketId: 't1', userId: 'u1');
    await repo.stop('t1', now: now.add(const Duration(hours: 2)));

    await serviceFor().syncNow();

    expect(await repo.pending(), isEmpty);
    final rows = await repo.forTicket('t1');
    expect(rows.single.id, 'server-${started.clientId}');
    expect(rows.single.isPendingSync, isFalse);
  });

  test('sends the UTC instants, never the Rome labels', () async {
    await repo.start(ticketId: 't1', userId: 'u1');

    await serviceFor().syncNow();

    final session = (adapter.sentBody!['sessions'] as List<dynamic>).single as Map<String, dynamic>;
    expect(
      DateTime.parse(session['startTime'] as String),
      now,
      reason: 'the server books hours from the instant; a 10:30 Rome label sent as 10:30 UTC '
          'would move the work two hours',
    );
    expect(session['ticketId'], 't1');
    expect(session['endTime'], isNull, reason: 'still running: no end to send');
  });

  test('stamps the send-time clock reading, not the tap instant', () async {
    // Queued at 08:30 and sent two hours later, from a phone whose clock may have been corrected in
    // between: the reading the server can honestly compare with its receipt is "now", and it is the
    // same for every session in the batch (O-10 plan §2).
    await repo.start(ticketId: 't1', userId: 'u1');
    final sentAt = now.add(const Duration(hours: 2));

    await TicketTimerSyncService(
      repo: repo,
      apiClient: TicketTimerApiClient(Dio()..httpClientAdapter = adapter),
      businessTime: BusinessTime.fallback(),
      clock: () => sentAt,
    ).syncNow();

    final session = (adapter.sentBody!['sessions'] as List<dynamic>).single as Map<String, dynamic>;
    expect(
      DateTime.parse(session['deviceUtc'] as String),
      sentAt,
      reason: 'a tap-time reading would measure how long the queue sat and call it clock skew',
    );
    expect(
      DateTime.parse(session['startTime'] as String),
      now,
      reason: 'the recorded start must stay the instant the technician tapped',
    );
  });

  test('a session the server never echoes stays queued', () async {
    await repo.start(ticketId: 't1', userId: 'u1');
    adapter = _Adapter(
      (options) async => ResponseBody.fromString(
        jsonEncode({'sessions': <dynamic>[]}),
        200,
        headers: _json,
      ),
    );

    await serviceFor().syncNow();

    expect(
      await repo.pending(),
      hasLength(1),
      reason: 'guessing it landed would log the hours twice',
    );
  });

  test('a transient failure keeps the rows pending and sets no sync error', () async {
    await repo.start(ticketId: 't1', userId: 'u1');
    adapter = _Adapter(
      (options) async => throw DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
        error: 'no route to host',
      ),
    );

    await serviceFor().syncNow();

    final pending = await repo.pending();
    expect(pending, hasLength(1));
    expect(pending.single.syncError, isNull, reason: 'nothing was decided server-side');
  });

  test('a 5xx is transient too', () async {
    await repo.start(ticketId: 't1', userId: 'u1');
    adapter = _Adapter(
      (options) async => ResponseBody.fromString('', 503),
    );

    await serviceFor().syncNow();

    expect((await repo.pending()).single.syncError, isNull);
  });

  test('a 400 is a refusal: the rows are held with a message, not dropped', () async {
    await repo.start(ticketId: 't1', userId: 'u1');
    adapter = _Adapter(
      (options) async => ResponseBody.fromString(
        jsonEncode({'error': 'ticket_not_found'}),
        400,
        headers: _json,
      ),
    );

    await serviceFor().syncNow();

    final pending = await repo.pending();
    expect(pending, hasLength(1), reason: 'hours are never discarded');
    expect(pending.single.syncError, isNotNull);
    expect(pending.single.syncError, isNotEmpty);
  });

  test('a manual sync retries the rows a refusal held', () async {
    await repo.start(ticketId: 't1', userId: 'u1');
    adapter = _Adapter(
      (options) async => ResponseBody.fromString('', 400),
    );
    await serviceFor().syncNow();
    expect((await repo.pending()).single.syncError, isNotNull);

    // The reason is gone (the ticket was restored in the office): the next manual sync tries again.
    adapter = _Adapter(_echoAll);
    await serviceFor().syncNow(manual: true);

    expect(await repo.pending(), isEmpty);
  });

  test('nothing pending means no request at all', () async {
    var called = false;
    adapter = _Adapter((options) async {
      called = true;
      return _echoAll(options);
    });

    await serviceFor().syncNow();

    expect(called, isFalse);
  });
}
