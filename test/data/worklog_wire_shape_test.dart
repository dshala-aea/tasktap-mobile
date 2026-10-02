import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/timbratura/cantiere_worklog_api_client.dart';
import 'package:tasktap_mobile/data/timbratura/worklog_api_client.dart';
import 'package:tasktap_mobile/features/ticket/ticket_workflow_api_client.dart';

/// Pins what the server receives. The business-time work must not change a
/// byte of these bodies (the backend binds them with System.Text.Json, whose
/// TimeSpan format is `[d.]hh:mm:ss`).
class _RecordingAdapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString(
      '{}',
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }
}

void main() {
  test('MobileSessionDto.toJson is ISO-Z strings', () {
    final dto = MobileSessionDto(
      clientId: 'c1',
      startTime: DateTime.utc(2026, 7, 10, 6),
      endTime: DateTime.utc(2026, 7, 10, 14, 30),
      latitude: 45.5,
      longitude: 9.1,
      gpsAccuracyMeters: 12.5,
    );
    expect(dto.toJson(), {
      'clientId': 'c1',
      'startTime': '2026-07-10T06:00:00.000Z',
      'endTime': '2026-07-10T14:30:00.000Z',
      'latitude': 45.5,
      'longitude': 9.1,
      'gpsAccuracyMeters': 12.5,
    });
  });

  test('CantiereMobileSessionDto.toJson is ISO-Z strings', () {
    final dto = CantiereMobileSessionDto(
      clientId: 'c1',
      cantiereId: 'cant',
      customerId: 'cust',
      ticketId: 't1',
      description: 'd',
      startTime: DateTime.utc(2026, 7, 10, 6),
      endTime: DateTime.utc(2026, 7, 10, 14, 30),
      latitude: 45.5,
      longitude: 9.1,
    );
    expect(dto.toJson(), {
      'clientId': 'c1',
      'cantiereId': 'cant',
      'customerId': 'cust',
      'ticketId': 't1',
      'description': 'd',
      'startTime': '2026-07-10T06:00:00.000Z',
      'endTime': '2026-07-10T14:30:00.000Z',
      'latitude': 45.5,
      'longitude': 9.1,
      'workLogType': 0,
    });
  });

  group('TicketWorkflowApiClient.addManual', () {
    late _RecordingAdapter adapter;
    late TicketWorkflowApiClient client;

    setUp(() {
      adapter = _RecordingAdapter();
      client = TicketWorkflowApiClient(Dio()..httpClientAdapter = adapter);
    });

    test('posts date-only workDate and HH:mm:ss times', () async {
      await client.addManual(
        ticketId: 't1',
        workDate: DateTime.utc(2026, 7, 10),
        start: const Duration(hours: 8),
        end: const Duration(hours: 16, minutes: 30),
      );
      expect(adapter.requests.single.path, '/api/tickets/t1/worklogs/manual');
      expect(adapter.requests.single.data, {
        'workDate': '2026-07-10',
        'startTime': '08:00:00',
        'endTime': '16:30:00',
      });
    });

    test('omits endTime and description when absent', () async {
      await client.addManual(
        ticketId: 't1',
        workDate: DateTime(2026, 7, 10),
        start: const Duration(hours: 8, minutes: 5, seconds: 9),
      );
      expect(adapter.requests.single.data, {
        'workDate': '2026-07-10',
        'startTime': '08:05:09',
      });
    });

    // The only deliberate difference from the old `_hms` helper, which wrote
    // `26:00:00`. That is not a valid .NET TimeSpan ("c" format needs a day
    // part from 24 h up), so the server rejected it (400); `1.02:00:00` is
    // what it parses. Not reachable from the UI today (times of day < 24 h).
    test('an end of 26 h posts the .NET day form', () async {
      await client.addManual(
        ticketId: 't1',
        workDate: DateTime.utc(2026, 7, 10),
        start: const Duration(hours: 8),
        end: const Duration(hours: 26),
        description: 'x',
      );
      expect(adapter.requests.single.data, {
        'workDate': '2026-07-10',
        'startTime': '08:00:00',
        'endTime': '1.02:00:00',
        'description': 'x',
      });
    });
  });

  group('TicketWorkLogDto.fromJson TimeSpan tolerance', () {
    Map<String, dynamic> json(Object? start, Object? end) => {
      'id': 'w1',
      'ticketId': 't1',
      'userId': 'u1',
      'workDate': '2026-07-10',
      'startTime': start,
      'endTime': end,
    };

    test('maps 1.02:03:04 to 26 h 3 min 4 s', () {
      final dto = TicketWorkLogDto.fromJson(json('08:00:00', '1.02:03:04'));
      expect(dto.endTime, const Duration(hours: 26, minutes: 3, seconds: 4));
    });

    test('maps garbage and null start to zero, keeps a null end', () {
      final dto = TicketWorkLogDto.fromJson(json('abc', null));
      expect(dto.startTime, Duration.zero);
      expect(dto.endTime, isNull);
      expect(
        TicketWorkLogDto.fromJson(json(null, 'abc')).endTime,
        Duration.zero,
      );
    });
  });
}
