// test/data/timbratura/worklog_api_client_kiosk_scan_test.dart
//
// Tests for WorklogApiClient.kioskScan — the technician-phone side of kiosk attendance
// (POST /api/worklog/kiosk/scan, WorkLogController.KioskScan). No real network: an interceptor
// resolves/rejects every request, same pattern as kiosk_api_client_test.dart.

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/timbratura/worklog_api_client.dart';

Dio _dioResolving(Map<String, dynamic> data) {
  final dio = Dio(BaseOptions(baseUrl: 'https://api.test'));
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        handler.resolve(Response(requestOptions: options, statusCode: 200, data: data));
      },
    ),
  );
  return dio;
}

Dio _dioRejectingWithStatus(int statusCode, {Object? data}) {
  final dio = Dio(BaseOptions(baseUrl: 'https://api.test'));
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        handler.reject(
          DioException(
            requestOptions: options,
            response: Response(requestOptions: options, statusCode: statusCode, data: data),
            type: DioExceptionType.badResponse,
          ),
        );
      },
    ),
  );
  return dio;
}

Dio _dioRejectingWithType(DioExceptionType type) {
  final dio = Dio(BaseOptions(baseUrl: 'https://api.test'));
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        handler.reject(DioException(requestOptions: options, type: type));
      },
    ),
  );
  return dio;
}

void main() {
  const args = (token: 'device-1:100:hmac', userId: 'user-1');

  test('kioskScan sends token+userId and parses a clock-in response', () async {
    Map<String, dynamic>? captured;
    final dio = Dio(BaseOptions(baseUrl: 'https://api.test'));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          captured = options.data as Map<String, dynamic>;
          handler.resolve(
            Response(
              requestOptions: options,
              statusCode: 200,
              data: {'action': 'in', 'workLogId': 'wl-1', 'startTime': '2026-09-16T08:00:00Z'},
            ),
          );
        },
      ),
    );
    final client = WorklogApiClient(dio);

    final result = await client.kioskScan(token: args.token, userId: args.userId);

    expect(captured, {'token': args.token, 'userId': args.userId});
    expect(result.action, 'in');
    expect(result.workLogId, 'wl-1');
    expect(result.endTime, isNull);
  });

  // The wire shape, not the one this test used to invent. `ClockResultToActionResult` answers
  // clock-out with `{action, workLogId, startTime, endTime}`, and both times come from
  // `ClockResult(string Action, Guid WorkLogId, TimeSpan StartTime, TimeSpan? EndTime)` — a
  // TimeSpan, which System.Text.Json writes in its invariant "c" format (`hh:mm:ss`, or
  // `d.hh:mm:ss` past a day), never as an ISO datetime. The previous fixture fed
  // `'2026-09-16T17:00:00Z'` and so pinned a shape the server has never produced: the real one
  // raised FormatException inside `kioskScan` on every clock-out, escaped the widget's only
  // `on KioskScanException` catch, and left the technician on a spinner forever. Clock-in
  // omits `endTime` entirely, which is why only ending a turn hung.
  test('kioskScan parses the TimeSpan clock-out response the server actually sends', () async {
    final client = WorklogApiClient(
      _dioResolving({
        'action': 'out',
        'workLogId': 'wl-2',
        'startTime': '08:00:00',
        'endTime': '17:00:00',
      }),
    );

    final result = await client.kioskScan(token: args.token, userId: args.userId);

    expect(result.action, 'out');
    expect(result.endTime, const Duration(hours: 17));
  });

  test('a TimeSpan past a day keeps its day part', () async {
    final client = WorklogApiClient(
      _dioResolving({
        'action': 'out',
        'workLogId': 'wl-3',
        'startTime': '00:00:00',
        'endTime': '1.08:12:34',
      }),
    );

    final result = await client.kioskScan(token: args.token, userId: args.userId);

    expect(result.endTime, const Duration(days: 1, hours: 8, minutes: 12, seconds: 34));
  });

  // The punch has already landed server-side by the time the body is parsed, so an echo the
  // client cannot read is worth less than a screen that keeps working: an unparseable endTime
  // must degrade to null, never throw. Throwing here is what turned a successful clock-out into
  // a frozen spinner.
  test('an unreadable endTime degrades to null instead of throwing', () async {
    for (final endTime in <Object?>[null, '', 'not-a-time', 42]) {
      final client = WorklogApiClient(
        _dioResolving({
          'action': 'out',
          'workLogId': 'wl-4',
          'startTime': '08:00:00',
          'endTime': endTime,
        }),
      );

      final result = await client.kioskScan(token: args.token, userId: args.userId);

      expect(result.action, 'out', reason: 'endTime was $endTime');
      expect(result.endTime, isNull, reason: 'endTime was $endTime');
    }
  });

  test('402 maps to notEntitled', () async {
    final client = WorklogApiClient(_dioRejectingWithStatus(402));

    await expectLater(
      client.kioskScan(token: args.token, userId: args.userId),
      throwsA(
        isA<KioskScanException>().having(
          (e) => e.reason,
          'reason',
          KioskScanFailureReason.notEntitled,
        ),
      ),
    );
  });

  test('403 maps to forbidden', () async {
    final client = WorklogApiClient(_dioRejectingWithStatus(403));

    await expectLater(
      client.kioskScan(token: args.token, userId: args.userId),
      throwsA(
        isA<KioskScanException>().having(
          (e) => e.reason,
          'reason',
          KioskScanFailureReason.forbidden,
        ),
      ),
    );
  });

  test('400 with a bare-string "Token scaduto" body maps to invalidOrExpiredToken', () async {
    // WorkLogController's BadRequest("...") results are plain strings, not ProblemDetails —
    // [ApiController]'s automatic problem-details rewrite only touches results with a null
    // Value, and these always set one. Confirms the client handles that shape, not a {detail,
    // title} object.
    final client = WorklogApiClient(_dioRejectingWithStatus(400, data: 'Token scaduto'));

    await expectLater(
      client.kioskScan(token: args.token, userId: args.userId),
      throwsA(
        isA<KioskScanException>()
            .having((e) => e.reason, 'reason', KioskScanFailureReason.invalidOrExpiredToken)
            .having((e) => e.message, 'message', 'Token scaduto'),
      ),
    );
  });

  test('400 with "Kiosk non piu attivo" maps to deviceRevoked, not invalidOrExpiredToken', () async {
    final client = WorklogApiClient(_dioRejectingWithStatus(400, data: 'Kiosk non piu attivo'));

    await expectLater(
      client.kioskScan(token: args.token, userId: args.userId),
      throwsA(
        isA<KioskScanException>().having(
          (e) => e.reason,
          'reason',
          KioskScanFailureReason.deviceRevoked,
        ),
      ),
    );
  });

  test('connection error maps to network', () async {
    final client = WorklogApiClient(_dioRejectingWithType(DioExceptionType.connectionError));

    await expectLater(
      client.kioskScan(token: args.token, userId: args.userId),
      throwsA(
        isA<KioskScanException>().having(
          (e) => e.reason,
          'reason',
          KioskScanFailureReason.network,
        ),
      ),
    );
  });

  test('5xx maps to unknown', () async {
    final client = WorklogApiClient(_dioRejectingWithStatus(500));

    await expectLater(
      client.kioskScan(token: args.token, userId: args.userId),
      throwsA(
        isA<KioskScanException>().having(
          (e) => e.reason,
          'reason',
          KioskScanFailureReason.unknown,
        ),
      ),
    );
  });
}
