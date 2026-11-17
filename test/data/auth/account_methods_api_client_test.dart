import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/auth/account_methods_api_client.dart';

class _Adapter implements HttpClientAdapter {
  _Adapter({this.body = '{}'});

  final String body;
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
    return ResponseBody.fromString(
      body,
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }
}

AccountMethodsApiClient _client(_Adapter adapter) =>
    AccountMethodsApiClient(Dio()..httpClientAdapter = adapter);

void main() {
  test('posts the login name to the anonymous methods endpoint', () async {
    final adapter = _Adapter(
      body: jsonEncode({'hasPasskey': true, 'hasPassword': false}),
    );

    await _client(adapter).fetch('tech@tasktap.io');

    expect(adapter.captured!.method, 'POST');
    expect(adapter.captured!.path, '/api/MobileAuth/methods');
    expect(adapter.captured!.data, {'loginName': 'tech@tasktap.io'});
    expect(adapter.captured!.headers.containsKey('Authorization'), isFalse);
  });

  test('parses both method flags', () async {
    final adapter = _Adapter(
      body: jsonEncode({'hasPasskey': true, 'hasPassword': true}),
    );

    final methods = await _client(adapter).fetch('tech@tasktap.io');

    expect(methods.hasPasskey, isTrue);
    expect(methods.hasPassword, isTrue);
  });

  test('a missing flag is false, not a crash', () async {
    final adapter = _Adapter(body: jsonEncode({'hasPassword': true}));

    final methods = await _client(adapter).fetch('tech@tasktap.io');

    expect(methods.hasPasskey, isFalse);
    expect(methods.hasPassword, isTrue);
  });
}
