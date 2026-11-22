import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/api/app_version_interceptor.dart';

/// Completes every request with an empty 200 and records what it was sent.
class _Capture extends Interceptor {
  RequestOptions? seen;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    seen = options;
    handler.resolve(Response(requestOptions: options, statusCode: 200));
  }
}

Future<RequestOptions> _send(Future<String?> Function() version) async {
  final dio = Dio();
  final capture = _Capture();
  dio.interceptors
    ..add(AppVersionInterceptor(version))
    ..add(capture);
  await dio.get<void>('http://localhost/api/worklog/punches');
  return capture.seen!;
}

void main() {
  test('stamps the request with the app version', () async {
    final sent = await _send(() async => '1.0.11+42');
    expect(sent.headers[appVersionHeader], '1.0.11+42');
  });

  test('sends the request without the header when the version is unknown', () async {
    final sent = await _send(() async => null);
    expect(sent.headers.containsKey(appVersionHeader), isFalse);
  });

  test('a version that cannot be read never blocks the request', () async {
    final sent = await _send(() async => throw StateError('no plugin'));
    expect(sent.headers.containsKey(appVersionHeader), isFalse);
  });
}
