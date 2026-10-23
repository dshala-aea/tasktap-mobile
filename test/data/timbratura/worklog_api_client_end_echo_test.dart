// test/data/timbratura/worklog_api_client_end_echo_test.dart
//
// WorklogApiClient.endWork's half of the clock-disagreement contract (POST /api/worklog/end):
// the server answers with the gap it judged a disagreement, or nothing at all, and the phone
// only relays — it never compares the clocks itself. No real network: an interceptor resolves
// every request, same pattern as worklog_api_client_kiosk_scan_test.dart.

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/timbratura/worklog_api_client.dart';

Dio _dioResolving(Object? data) {
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

void main() {
  test('endWork returns the disagreement the server echoes', () async {
    final client = WorklogApiClient(
      _dioResolving(<String, dynamic>{
        'message': 'Work ended successfully',
        'clockDisagreementSeconds': 900,
      }),
    );

    expect(await client.endWork(deviceUtc: DateTime.utc(2026, 10, 23, 8)), 900);
  });

  test('endWork returns null when the server judged the clocks close enough', () async {
    final client = WorklogApiClient(
      _dioResolving(<String, dynamic>{'message': 'Work ended successfully'}),
    );

    expect(await client.endWork(), isNull);
  });

  test('endWork returns null against an older backend that answers a bare body', () async {
    final client = WorklogApiClient(_dioResolving(null));

    expect(await client.endWork(), isNull);
  });
}
