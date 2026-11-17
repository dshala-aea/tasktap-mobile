// dart format width=100
// Reachability: what "online" means. The radio's answer is not enough — a captive portal, a Wi-Fi
// whose upstream is down and a hotel network nobody paid for all look connected to
// `connectivity_plus`. These tests pin what the probe accepts and what it refuses, and that the
// cache does not turn a dead network into one request per watched provider.

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/sync/reachability.dart';

class _Adapter implements HttpClientAdapter {
  _Adapter(this.onFetch);
  final Future<ResponseBody> Function(RequestOptions) onFetch;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) => onFetch(options);
}

ResponseBody _body(String contents, int status, String contentType) => ResponseBody.fromString(
  contents,
  status,
  headers: {
    Headers.contentTypeHeader: [contentType],
  },
);

HealthEndpointProbe _probe(Future<ResponseBody> Function(RequestOptions) f) {
  final dio = Dio()..httpClientAdapter = _Adapter(f);
  return HealthEndpointProbe(dio: dio, baseUrl: 'https://api.example.test');
}

/// A probe with a settable answer and a call counter, for the cache tests.
class _FakeProbe implements ReachabilityProbe {
  _FakeProbe(this.answer);
  bool answer;
  int calls = 0;

  @override
  Future<bool> isReachable() async {
    calls++;
    return answer;
  }
}

void main() {
  group('HealthEndpointProbe', () {
    test('asks /health on the configured base and accepts the API payload', () async {
      Uri? asked;
      final probe = _probe((options) async {
        asked = options.uri;
        return _body('{"status":"healthy"}', 200, 'application/json');
      });

      expect(await probe.isReachable(), isTrue);
      expect(asked.toString(), 'https://api.example.test/health');
    });

    // The whole reason this class exists: a portal answers 200 on every address it intercepts.
    test('a 200 that is not our payload counts as unreachable', () async {
      final probe = _probe(
        (_) async => _body('<html><body>Accedi al Wi-Fi</body></html>', 200, 'text/html'),
      );

      expect(await probe.isReachable(), isFalse);
    });

    test('a 5xx counts as unreachable', () async {
      final probe = _probe((_) async => _body('{"status":"healthy"}', 503, 'application/json'));

      expect(await probe.isReachable(), isFalse);
    });

    test('a connection error counts as unreachable, not as a crash', () async {
      final probe = _probe(
        (options) async => throw DioException(
          requestOptions: options,
          type: DioExceptionType.connectionError,
        ),
      );

      expect(await probe.isReachable(), isFalse);
    });

    test('an unconfigured build is unreachable without asking anyone', () async {
      var asked = false;
      final dio = Dio()
        ..httpClientAdapter = _Adapter((_) async {
          asked = true;
          return _body('{}', 200, 'application/json');
        });

      expect(await HealthEndpointProbe(dio: dio, baseUrl: '').isReachable(), isFalse);
      expect(asked, isFalse);
    });
  });

  group('CachedReachabilityProbe', () {
    test('answers from the cache inside the window instead of probing again', () async {
      final inner = _FakeProbe(true);
      final now = DateTime.utc(2026, 6, 23, 9);
      final probe = CachedReachabilityProbe(
        inner,
        ttl: const Duration(seconds: 10),
        clock: () => now,
      );

      expect(await probe.isReachable(), isTrue);
      expect(await probe.isReachable(), isTrue);
      expect(inner.calls, 1);
    });

    test('probes again once the window has passed, picking up the new answer', () async {
      final inner = _FakeProbe(false);
      var now = DateTime.utc(2026, 6, 23, 9);
      final probe = CachedReachabilityProbe(
        inner,
        ttl: const Duration(seconds: 10),
        clock: () => now,
      );

      expect(await probe.isReachable(), isFalse);
      now = now.add(const Duration(seconds: 11));
      inner.answer = true;

      expect(await probe.isReachable(), isTrue);
      expect(inner.calls, 2);
    });

    test('a negative answer is cached too, so a dead network is one probe not many', () async {
      final inner = _FakeProbe(false);
      final probe = CachedReachabilityProbe(inner, clock: () => DateTime.utc(2026, 6, 23, 9));

      await probe.isReachable();
      await probe.isReachable();
      await probe.isReachable();

      expect(inner.calls, 1);
    });
  });
}
