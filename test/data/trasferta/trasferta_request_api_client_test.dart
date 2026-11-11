// dart format width=100
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/timbratura/worklog_api_client.dart';
import 'package:tasktap_mobile/data/trasferta/trasferta_request_api_client.dart';
import 'package:tasktap_mobile/features/timbra/day_rail_view.dart' show railSorgenteLabel;

class _Adapter implements HttpClientAdapter {
  _Adapter({this.status = 200, this.body = '{}'});
  final int status;
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
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }
}

TrasfertaRequestApiClient _client(_Adapter a) =>
    TrasfertaRequestApiClient(Dio()..httpClientAdapter = a);

void main() {
  group('hours rules', () {
    test('accepts quarter-hour steps up to 24', () {
      for (final h in [0.25, 0.5, 0.75, 1.0, 1.5, 7.25, 24.0]) {
        expect(trasfertaRulesError(hours: h, startMinutes: 0), isNull, reason: '$h');
      }
    });

    test('refuses zero, negative, over 24 and off-step values with the server sentence', () {
      for (final h in [0.0, -1.0, 24.25, 25.0, 0.1, 1.3, null]) {
        expect(trasfertaRulesError(hours: h, startMinutes: 0), kTrasfertaHoursInvalid, reason: '$h');
      }
    });

    test('start + hours must stay inside the day', () {
      // 22:00 + 2h ends exactly at midnight: allowed. 22:15 + 2h crosses it.
      expect(trasfertaRulesError(hours: 2, startMinutes: 22 * 60), isNull);
      expect(trasfertaRulesError(hours: 2, startMinutes: 22 * 60 + 15), kTrasfertaCrossesMidnight);
      expect(trasfertaRulesError(hours: 24, startMinutes: 0), isNull);
      expect(trasfertaRulesError(hours: 24, startMinutes: 1), kTrasfertaCrossesMidnight);
    });

    test('parses a decimal comma and a point', () {
      expect(parseTrasfertaHours('1,5'), 1.5);
      expect(parseTrasfertaHours(' 2.25 '), 2.25);
      expect(parseTrasfertaHours(''), isNull);
      expect(parseTrasfertaHours('abc'), isNull);
    });
  });

  group('request body', () {
    test('create sends day as yyyy-MM-dd, start as HH:mm, hours as a decimal, no requester', () async {
      final a = _Adapter(status: 201);
      await _client(a).create(
        date: DateTime(2026, 11, 3),
        startHour: 7,
        startMinute: 5,
        hours: 1.5,
        reason: 'Cantiere Rossi',
      );
      expect(a.captured!.method, 'POST');
      expect(a.captured!.path, '/api/trasferta-requests');
      final data = a.captured!.data as Map<String, dynamic>;
      expect(data, {
        'date': '2026-11-03',
        'startTime': '07:05',
        'hours': 1.5,
        'reason': 'Cantiere Rossi',
      });
      expect(data.containsKey('requestedByUserId'), isFalse);
      expect(jsonEncode(data), contains('"hours":1.5'));
    });

    test('an empty reason is omitted', () async {
      final a = _Adapter(status: 201);
      await _client(a).create(
        date: DateTime(2026, 11, 3),
        startHour: 8,
        startMinute: 0,
        hours: 2,
      );
      expect((a.captured!.data as Map).containsKey('reason'), isFalse);
    });

    test('cancel posts to the cancel route', () async {
      final a = _Adapter();
      await _client(a).cancel('abc');
      expect(a.captured!.path, '/api/trasferta-requests/abc/cancel');
    });

    test('list sends the caller id', () async {
      final a = _Adapter(body: '[]');
      await _client(a).fetchMine(userId: 'u1');
      expect(a.captured!.queryParameters, {'userId': 'u1'});
    });
  });

  group('errors', () {
    test('409 duplicate day surfaces the server sentence readably', () async {
      final a = _Adapter(
        status: 409,
        body: jsonEncode({
          'title': 'Conflict',
          'status': 409,
          'detail': 'Esiste già una trasferta per questa persona in questa data.',
          'code': 'trasferta_duplicate_day',
        }),
      );
      await expectLater(
        _client(a).create(date: DateTime(2026, 11, 3), startHour: 8, startMinute: 0, hours: 1),
        throwsA(
          isA<TrasfertaRuleError>().having(
            (e) => e.toString(),
            'message',
            'Esiste già una trasferta per questa persona in questa data.',
          ),
        ),
      );
    });

    test('a 500 stays a DioException', () async {
      final a = _Adapter(status: 500, body: '{}');
      await expectLater(
        _client(a).create(date: DateTime(2026, 11, 3), startHour: 8, startMinute: 0, hours: 1),
        throwsA(isA<DioException>()),
      );
    });
  });

  group('dto', () {
    test('parses the wire row (HH:mm:ss start, decimal hours, int status)', () {
      final dto = TrasfertaRequestDto.fromJson({
        'id': 't1',
        'requestedByUserId': 'u1',
        'createdByUserId': 'u1',
        'date': '2026-11-03',
        'startTime': '07:30:00',
        'hours': 1.5,
        'reason': null,
        'status': 1,
        'workLogId': 'w1',
      });
      expect(dto.startTime, '07:30');
      expect(dto.hours, 1.5);
      expect(dto.date, DateTime.utc(2026, 11, 3));
      expect(dto.cancellable, isTrue);
      expect(dto.statusLabel, isNotEmpty);
    });

    test('a trasferta the office filed, or a cancelled one, has no cancel', () {
      Map<String, dynamic> row(String created, int status) => {
        'id': 't1',
        'requestedByUserId': 'u1',
        'createdByUserId': created,
        'date': '2026-11-03',
        'startTime': '07:30:00',
        'hours': 1,
        'status': status,
      };
      expect(TrasfertaRequestDto.fromJson(row('office', 1)).cancellable, isFalse);
      expect(TrasfertaRequestDto.fromJson(row('u1', 3)).cancellable, isFalse);
    });
  });

  group('sorgente labels', () {
    test('Trasferta and SmartWorking map and render their labels', () {
      expect(DayWorkLogEntry.sorgenteOfForTest(4), 'trasferta');
      expect(DayWorkLogEntry.sorgenteOfForTest(5), 'smartworking');
      expect(railSorgenteLabel(DayWorkLogEntry.sorgenteOfForTest(4)), 'trasferta');
      expect(railSorgenteLabel(DayWorkLogEntry.sorgenteOfForTest(5)), 'smart working');
      expect(railSorgenteLabel(DayWorkLogEntry.sorgenteOfForTest('SmartWorking')), 'smart working');
    });

    test('existing members are unchanged', () {
      expect(railSorgenteLabel(DayWorkLogEntry.sorgenteOfForTest(0)), 'ufficio');
      expect(railSorgenteLabel(DayWorkLogEntry.sorgenteOfForTest(1)), 'totem');
      expect(railSorgenteLabel(DayWorkLogEntry.sorgenteOfForTest(2)), 'QR');
      expect(railSorgenteLabel(DayWorkLogEntry.sorgenteOfForTest(3)), 'altro dispositivo');
    });

    test('an unknown Sorgente is the neutral label and never throws', () {
      for (final raw in [99, -1, 'Boh', 4.5, null, <String, dynamic>{}]) {
        late String label;
        expect(() => label = railSorgenteLabel(DayWorkLogEntry.sorgenteOfForTest(raw)), returnsNormally);
        expect(label, 'server', reason: '$raw');
      }
    });
  });
}
