// NOT RUN when written: the authoring machine has no Flutter toolchain. CI is the first run.
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/settings/notification_preferences_api_client.dart';

/// Answers every request with a canned status/body and records the last request.
class _StubAdapter implements HttpClientAdapter {
  _StubAdapter({this.status = 200, this.body});

  final int status;
  final Object? body;
  RequestOptions? last;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    last = options;
    return ResponseBody.fromString(
      jsonEncode(body ?? const {}),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

NotificationPreferencesApiClient _client(_StubAdapter adapter) {
  final dio = Dio(BaseOptions(baseUrl: 'https://t.test', validateStatus: (s) => s != null && s < 400))
    ..httpClientAdapter = adapter;
  return NotificationPreferencesApiClient(dio);
}

void main() {
  test('fetch GETs /api/notifications/preferences and parses ordinal, key, enabled, default', () async {
    final adapter = _StubAdapter(
      body: {
        'items': [
          {'type': 0, 'key': 'TicketAssigned', 'enabled': true, 'default': true},
          {'type': 25, 'key': 'ReportSubmitted', 'enabled': false, 'default': true},
        ],
      },
    );

    final items = await _client(adapter).fetch();

    expect(adapter.last!.method, 'GET');
    expect(adapter.last!.path, '/api/notifications/preferences');
    expect(items.map((i) => i.type), [0, 25]);
    expect(items[1].key, 'ReportSubmitted');
    expect(items[1].enabled, isFalse);
    expect(items[1].defaultEnabled, isTrue);
  });

  test('an ordinal this build does not know is kept, not dropped or thrown on', () async {
    final adapter = _StubAdapter(
      body: {
        'items': [
          {'type': 99, 'key': 'SomethingNew', 'enabled': true, 'default': true},
        ],
      },
    );

    final items = await _client(adapter).fetch();

    expect(items, hasLength(1));
    expect(items.single.type, 99);
    expect(items.single.key, 'SomethingNew');
  });

  test('malformed rows are skipped and a missing items array is an empty list', () {
    expect(NotificationPreferenceDto.parseList({'nope': 1}), isEmpty);
    expect(NotificationPreferenceDto.parseList(null), isEmpty);
    final parsed = NotificationPreferenceDto.parseList({
      'items': [
        'garbage',
        {'key': 'NoOrdinal', 'enabled': false},
        {'type': 3, 'enabled': false},
      ],
    });
    expect(parsed, hasLength(1));
    expect(parsed.single.type, 3);
    // No `key` on the wire: a printable fallback, never null.
    expect(parsed.single.key, 'Type3');
    expect(parsed.single.enabled, isFalse);
  });

  test('update PUTs {items:[{type,enabled}]} with the ordinal, and returns the full list', () async {
    final adapter = _StubAdapter(
      body: {
        'items': [
          {'type': 25, 'key': 'ReportSubmitted', 'enabled': false, 'default': true},
          {'type': 0, 'key': 'TicketAssigned', 'enabled': true, 'default': true},
        ],
      },
    );

    final items = await _client(adapter).update({25: false});

    expect(adapter.last!.method, 'PUT');
    expect(adapter.last!.path, '/api/notifications/preferences');
    expect(adapter.last!.data, {
      'items': [
        {'type': 25, 'enabled': false},
      ],
    });
    expect(items, hasLength(2));
  });

  test('a locked-type 400 maps to its Italian sentence', () async {
    final adapter = _StubAdapter(status: 400, body: {'code': 'notification_type_locked'});

    await expectLater(
      _client(adapter).update({7: false}),
      throwsA(
        isA<NotificationPreferencesFailure>()
            .having((f) => f.message, 'message', contains('obbligatoria'))
            .having((f) => f.offline, 'offline', isFalse),
      ),
    );
  });

  test('an unknown-type 400 maps to its Italian sentence', () async {
    final adapter = _StubAdapter(status: 400, body: {'code': 'notification_type_unknown'});

    await expectLater(
      _client(adapter).update({99: false}),
      throwsA(
        isA<NotificationPreferencesFailure>().having(
          (f) => f.message,
          'message',
          contains('non è più disponibile'),
        ),
      ),
    );
  });

  test('a 403 and an unrecognised 500 are both failures that are not offline', () async {
    await expectLater(
      _client(_StubAdapter(status: 403)).fetch(),
      throwsA(isA<NotificationPreferencesFailure>().having((f) => f.offline, 'offline', isFalse)),
    );
    await expectLater(
      _client(_StubAdapter(status: 500)).fetch(),
      throwsA(isA<NotificationPreferencesFailure>().having((f) => f.offline, 'offline', isFalse)),
    );
  });

  test('a request that never reaches the server is reported as offline', () async {
    final dio = Dio()..httpClientAdapter = _ThrowingAdapter();
    await expectLater(
      NotificationPreferencesApiClient(dio).fetch(),
      throwsA(isA<NotificationPreferencesFailure>().having((f) => f.offline, 'offline', isTrue)),
    );
  });
}

class _ThrowingAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) {
    throw DioException(requestOptions: options, type: DioExceptionType.connectionError);
  }

  @override
  void close({bool force = false}) {}
}
