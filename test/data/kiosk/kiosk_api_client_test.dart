// Tests for KioskApiClient — the X-Api-Key-authenticated client kiosk mode uses to fetch the
// rotating attendance QR from GET /api/WorkLog/kiosk/qr (see WorkLogController.GetKioskQr).
//
// No real network: an interceptor rejects/resolves every request before it reaches an HTTP
// adapter, so the tests exercise exactly the status-code-to-KioskApiFailureReason mapping this
// class owns.

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/kiosk/kiosk_api_client.dart';

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

Dio _dioRejectingWithStatus(int statusCode) {
  final dio = Dio(BaseOptions(baseUrl: 'https://api.test'));
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        handler.reject(
          DioException(
            requestOptions: options,
            response: Response(requestOptions: options, statusCode: statusCode),
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
  test('fetchQr returns the token and expiry on 200', () async {
    final client = KioskApiClient(dio: _dioResolving({'token': 'abc:123:xyz', 'expiresInSeconds': 60}));

    final result = await client.fetchQr('sp_test');

    expect(result.token, 'abc:123:xyz');
    expect(result.expiresInSeconds, 60);
  });

  test('fetchQr sends the raw key as X-Api-Key, never Authorization', () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://api.test'));
    Map<String, dynamic>? capturedHeaders;
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          capturedHeaders = options.headers;
          handler.resolve(
            Response(requestOptions: options, statusCode: 200, data: {'token': 't', 'expiresInSeconds': 60}),
          );
        },
      ),
    );
    final client = KioskApiClient(dio: dio);

    await client.fetchQr('sp_the_raw_key');

    expect(capturedHeaders!['X-Api-Key'], 'sp_the_raw_key');
    expect(capturedHeaders!.containsKey('Authorization'), isFalse);
  });

  test('401 maps to invalidOrRevoked', () async {
    final client = KioskApiClient(dio: _dioRejectingWithStatus(401));

    await expectLater(
      client.fetchQr('sp_bad'),
      throwsA(
        isA<KioskApiException>().having((e) => e.reason, 'reason', KioskApiFailureReason.invalidOrRevoked),
      ),
    );
  });

  test('402 maps to notEntitled', () async {
    final client = KioskApiClient(dio: _dioRejectingWithStatus(402));

    await expectLater(
      client.fetchQr('sp_test'),
      throwsA(isA<KioskApiException>().having((e) => e.reason, 'reason', KioskApiFailureReason.notEntitled)),
    );
  });

  test('a connection error maps to network, not invalidOrRevoked', () async {
    final client = KioskApiClient(dio: _dioRejectingWithType(DioExceptionType.connectionError));

    await expectLater(
      client.fetchQr('sp_test'),
      throwsA(isA<KioskApiException>().having((e) => e.reason, 'reason', KioskApiFailureReason.network)),
    );
  });

  test('a 500 maps to unknown', () async {
    final client = KioskApiClient(dio: _dioRejectingWithStatus(500));

    await expectLater(
      client.fetchQr('sp_test'),
      throwsA(isA<KioskApiException>().having((e) => e.reason, 'reason', KioskApiFailureReason.unknown)),
    );
  });
}
