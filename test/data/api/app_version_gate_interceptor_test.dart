import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/core/update/update_required_state.dart';
import 'package:tasktap_mobile/data/api/app_version_interceptor.dart';

/// Completes every request with the canned [reply] (or fails with [fail]) and records what it
/// was sent.
class _Server extends Interceptor {
  _Server({this.reply, this.fail});

  final Response<dynamic> Function(RequestOptions)? reply;
  final DioException Function(RequestOptions)? fail;
  RequestOptions? seen;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    seen = options;
    if (fail != null) {
      handler.reject(fail!(options), true);
    } else if (reply != null) {
      handler.resolve(reply!(options));
    } else {
      handler.resolve(Response(requestOptions: options, statusCode: 200));
    }
  }
}

DioException _status(
  RequestOptions o,
  int code, {
  Object? body,
  Map<String, List<String>>? headers,
}) => DioException(
  requestOptions: o,
  type: DioExceptionType.badResponse,
  response: Response<dynamic>(
    requestOptions: o,
    statusCode: code,
    data: body,
    headers: Headers.fromMap(headers ?? {}),
  ),
);

class _Gate {
  int required = 0;
  int available = 0;
}

Dio _dio(_Server server, _Gate gate, {String platform = 'android'}) {
  final dio = Dio();
  dio.interceptors
    ..add(AppVersionInterceptor(() async => '1.0.11+42', platform: platform))
    ..add(
      AppUpdateGateInterceptor(
        onUpdateRequired: () => gate.required++,
        onUpdateAvailable: () => gate.available++,
      ),
    )
    ..add(server);
  return dio;
}

const _url = 'http://localhost/api/worklog/punches';

void main() {
  group('platform header', () {
    test('stamps ios', () async {
      final server = _Server();
      await _dio(server, _Gate(), platform: 'ios').get<void>(_url);
      expect(server.seen!.headers[appPlatformHeader], 'ios');
    });

    test('stamps android', () async {
      final server = _Server();
      await _dio(server, _Gate()).get<void>(_url);
      expect(server.seen!.headers[appPlatformHeader], 'android');
    });

    test('still sends the platform when the version cannot be read', () async {
      final server = _Server();
      final dio = Dio();
      dio.interceptors
        ..add(
          AppVersionInterceptor(
            () async => throw StateError('no plugin'),
            platform: 'ios',
          ),
        )
        ..add(server);
      await dio.get<void>(_url);
      expect(server.seen!.headers[appPlatformHeader], 'ios');
      expect(server.seen!.headers.containsKey(appVersionHeader), isFalse);
    });
  });

  group('update-required signal', () {
    test('a 200 with X-App-Update-Required: true sets the state', () async {
      final gate = _Gate();
      final server = _Server(
        reply: (o) => Response(
          requestOptions: o,
          statusCode: 200,
          headers: Headers.fromMap({
            'X-App-Update-Required': ['true'],
          }),
        ),
      );
      final res = await _dio(server, gate).get<void>(_url);
      expect(res.statusCode, 200);
      expect(gate.required, 1);
    });

    test('a plain 200 does not set the state', () async {
      final gate = _Gate();
      await _dio(_Server(), gate).get<void>(_url);
      expect(gate.required, 0);
      expect(gate.available, 0);
    });

    test('X-App-Update-Available sets only the soft state', () async {
      final gate = _Gate();
      final server = _Server(
        reply: (o) => Response(
          requestOptions: o,
          statusCode: 200,
          headers: Headers.fromMap({
            'X-App-Update-Available': ['true'],
          }),
        ),
      );
      await _dio(server, gate).get<void>(_url);
      expect(gate.required, 0);
      expect(gate.available, 1);
    });

    test('a 426 app_update_required sets the state and still throws', () async {
      final gate = _Gate();
      final server = _Server(
        fail: (o) => _status(
          o,
          426,
          body: {
            'code': 'app_update_required',
            'minimumVersion': '1.0.12',
            'storeUrl': 'https://example.test/store',
          },
        ),
      );
      Object? caught;
      try {
        await _dio(server, gate).get<void>(_url);
      } catch (e) {
        caught = e;
      }
      expect(caught, isA<DioException>());
      expect(isUpdateRequiredError(caught), isTrue);
      expect(gate.required, 1);
    });

    test('a 426 with a JSON string body is recognised', () async {
      final gate = _Gate();
      final server = _Server(
        fail: (o) => _status(o, 426, body: '{"code":"app_update_required"}'),
      );
      await expectLater(
        _dio(server, gate).get<void>(_url),
        throwsA(isA<DioException>()),
      );
      expect(gate.required, 1);
    });

    test('an ordinary 500 does not set the state and is not an update error', () async {
      final gate = _Gate();
      final server = _Server(fail: (o) => _status(o, 500, body: {'code': 'boom'}));
      Object? caught;
      try {
        await _dio(server, gate).get<void>(_url);
      } catch (e) {
        caught = e;
      }
      expect(caught, isA<DioException>());
      expect(isUpdateRequiredError(caught), isFalse);
      expect(gate.required, 0);
    });

    test('a 426 without the code (a proxy) is not an update error', () async {
      final gate = _Gate();
      final server = _Server(fail: (o) => _status(o, 426, body: 'Upgrade Required'));
      Object? caught;
      try {
        await _dio(server, gate).get<void>(_url);
      } catch (e) {
        caught = e;
      }
      expect(isUpdateRequiredError(caught), isFalse);
      expect(gate.required, 0);
    });
  });

  group('isUpdateRequiredError', () {
    test('false for non-Dio errors and null', () {
      expect(isUpdateRequiredError(null), isFalse);
      expect(isUpdateRequiredError(StateError('x')), isFalse);
    });

    test('false for a Dio error with no response (timeout)', () {
      final e = DioException(
        requestOptions: RequestOptions(path: '/'),
        type: DioExceptionType.connectionTimeout,
      );
      expect(isUpdateRequiredError(e), isFalse);
    });
  });

  group('notifier', () {
    test('markRequired is sticky', () {
      final n = UpdateRequiredNotifier();
      expect(n.state, isFalse);
      n.markRequired();
      n.markRequired();
      expect(n.state, isTrue);
    });
  });
}
