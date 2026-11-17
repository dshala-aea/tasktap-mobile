import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/badge/badge_api_client.dart';
import 'package:tasktap_mobile/data/badge/badge_models.dart';

/// Answers with a fixed status/body, or throws [error], and keeps the request it was handed.
class _Adapter implements HttpClientAdapter {
  _Adapter({this.status = 200, this.body = '{}', this.error});

  final int status;
  final String body;
  final DioException? error;
  RequestOptions? captured;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    captured = options;
    if (error != null) throw error!;
    return ResponseBody.fromString(
      body,
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }
}

BadgeApiClient _client(_Adapter a) => BadgeApiClient(Dio()..httpClientAdapter = a);

void main() {
  test('getMyBadge_SetsShortPerRequestTimeouts', () async {
    final a = _Adapter(
      body: jsonEncode({
        'badgeId': 'b',
        'token': 't',
        'expiresInSeconds': 60,
        'displayName': 'n',
        'employerName': 'e',
        'status': 'Active',
      }),
    );
    await _client(a).getMyBadge();
    expect(a.captured!.receiveTimeout, const Duration(seconds: 10));
    expect(a.captured!.sendTimeout, const Duration(seconds: 10));
  });

  test('getMyBadge_409_BadgeRevoked_IsRevoked', () async {
    final c = _client(
      _Adapter(status: 409, body: jsonEncode({'code': 'badge_revoked', 'detail': 'revoked'})),
    );
    await expectLater(
      c.getMyBadge(),
      throwsA(
        isA<BadgeApiException>()
            .having((e) => e.isRevoked, 'isRevoked', isTrue)
            .having((e) => e.isInactive, 'isInactive', isFalse)
            .having((e) => e.isOffline, 'isOffline', isFalse),
      ),
    );
  });

  test('getMyBadge_409_UserInactive_IsInactive', () async {
    final c = _client(_Adapter(status: 409, body: jsonEncode({'error': 'user_inactive'})));
    await expectLater(
      c.getMyBadge(),
      throwsA(
        isA<BadgeApiException>()
            .having((e) => e.isInactive, 'isInactive', isTrue)
            .having((e) => e.isRevoked, 'isRevoked', isFalse),
      ),
    );
  });

  test('getMyBadge_Timeout_IsOffline', () async {
    final c = _client(
      _Adapter(
        error: DioException(
          requestOptions: RequestOptions(path: '/api/badge/me'),
          type: DioExceptionType.connectionTimeout,
        ),
      ),
    );
    await expectLater(
      c.getMyBadge(),
      throwsA(isA<BadgeApiException>().having((e) => e.isOffline, 'isOffline', isTrue)),
    );
  });

  test('getMyBadge_200_ParsesCard', () async {
    final a = _Adapter(
      body: jsonEncode({
        'badgeId': 'b',
        'token': 't',
        'expiresInSeconds': 60,
        'displayName': 'M',
        'photoUrl': null,
        'employerName': 'E',
        'status': 'Active',
      }),
    );
    final card = await _client(a).getMyBadge();
    expect(card.token, 't');
    expect(a.captured!.method, 'GET');
    expect(a.captured!.path, '/api/badge/me');
  });

  test('scan_SendsClientScanIdAndToken_ToCantiereRoute', () async {
    final a = _Adapter(
      body: jsonEncode({'result': 'Accepted', 'action': 'Opened', 'workLogId': 'w', 'worker': null}),
    );
    final o = await _client(a).scan(cantiereId: 'cant-1', token: 'tok', clientScanId: 'scan-1');
    expect(a.captured!.method, 'POST');
    expect(a.captured!.path, '/api/cantieri/cant-1/badge-scan');
    expect(a.captured!.data, {'token': 'tok', 'clientScanId': 'scan-1'});
    expect(o.result, BadgeScanResult.accepted);
    expect(o.action, BadgeScanAction.opened);
  });

  test('scan_403_NotLead_IsNotLead', () async {
    final c = _client(
      _Adapter(status: 403, body: jsonEncode({'error': 'NotLead', 'message': 'Only the lead'})),
    );
    await expectLater(
      c.scan(cantiereId: 'c', token: 't', clientScanId: 's'),
      throwsA(
        isA<BadgeApiException>()
            .having((e) => e.isNotLead, 'isNotLead', isTrue)
            .having((e) => e.statusCode, 'statusCode', 403),
      ),
    );
  });
}
