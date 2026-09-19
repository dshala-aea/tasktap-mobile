// test/data/timbratura/cantiere_worklog_api_client_test.dart
//
// Unit tests for CantiereWorklogApiClient request mapping.
// Uses mocktail to mock Dio — no real network calls.

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tasktap_mobile/data/timbratura/cantiere_worklog_api_client.dart';

class MockDio extends Mock implements Dio {}

// Helper: build a Dio Response for a given status code + data.
Response<T> _okResponse<T>(T data, String path) => Response<T>(
  data: data,
  statusCode: 200,
  requestOptions: RequestOptions(path: path),
);

void main() {
  late MockDio mockDio;
  late CantiereWorklogApiClient client;

  setUpAll(() {
    registerFallbackValue(RequestOptions(path: '/'));
  });

  setUp(() {
    mockDio = MockDio();
    client = CantiereWorklogApiClient(mockDio);
  });

  group('startCantiere', () {
    test('POSTs to /api/cantiereworklog/start with correct body', () async {
      when(
        () => mockDio.post<dynamic>('/api/cantiereworklog/start', data: any(named: 'data')),
      ).thenAnswer((_) async => _okResponse(null, '/api/cantiereworklog/start'));

      await client.startCantiere(
        const StartCantiereRequest(
          cantiereId: 'cant-1',
          customerId: 'cust-1',
          ticketId: 'tick-1',
          arrivalLatitude: 45.47,
          arrivalLongitude: 9.19,
        ),
      );

      final captured = verify(
        () => mockDio.post<dynamic>('/api/cantiereworklog/start', data: captureAny(named: 'data')),
      ).captured;

      final body = captured.first as Map<String, dynamic>;
      expect(body['cantiereId'], 'cant-1');
      expect(body['customerId'], 'cust-1');
      expect(body['ticketId'], 'tick-1');
      expect(body['arrivalLatitude'], 45.47);
      expect(body['arrivalLongitude'], 9.19);
    });

    test('omits null optional fields from body', () async {
      when(
        () => mockDio.post<dynamic>('/api/cantiereworklog/start', data: any(named: 'data')),
      ).thenAnswer((_) async => _okResponse(null, '/api/cantiereworklog/start'));

      await client.startCantiere(
        const StartCantiereRequest(cantiereId: 'cant-1', customerId: 'cust-1'),
      );

      final captured = verify(
        () => mockDio.post<dynamic>('/api/cantiereworklog/start', data: captureAny(named: 'data')),
      ).captured;

      final body = captured.first as Map<String, dynamic>;
      expect(body.containsKey('ticketId'), isFalse);
      expect(body.containsKey('arrivalLatitude'), isFalse);
      expect(body.containsKey('arrivalLongitude'), isFalse);
    });

    test('propagates DioException on server error', () async {
      when(
        () => mockDio.post<dynamic>('/api/cantiereworklog/start', data: any(named: 'data')),
      ).thenThrow(
        DioException(
          requestOptions: RequestOptions(path: '/api/cantiereworklog/start'),
          response: Response(
            statusCode: 400,
            data: 'already active',
            requestOptions: RequestOptions(path: '/api/cantiereworklog/start'),
          ),
          type: DioExceptionType.badResponse,
        ),
      );

      expect(
        () => client.startCantiere(const StartCantiereRequest(cantiereId: 'c', customerId: 'u')),
        throwsA(isA<DioException>()),
      );
    });
  });

  group('endCantiere', () {
    test('POSTs to /api/cantiereworklog/end with departure coords', () async {
      when(
        () => mockDio.post<dynamic>('/api/cantiereworklog/end', data: any(named: 'data')),
      ).thenAnswer((_) async => _okResponse(null, '/api/cantiereworklog/end'));

      await client.endCantiere(
        const EndCantiereRequest(departureLatitude: 45.47, departureLongitude: 9.19),
      );

      final captured = verify(
        () => mockDio.post<dynamic>('/api/cantiereworklog/end', data: captureAny(named: 'data')),
      ).captured;

      final body = captured.first as Map<String, dynamic>;
      expect(body['departureLatitude'], 45.47);
      expect(body['departureLongitude'], 9.19);
    });

    test('sends empty map when no request provided', () async {
      when(
        () => mockDio.post<dynamic>('/api/cantiereworklog/end', data: any(named: 'data')),
      ).thenAnswer((_) async => _okResponse(null, '/api/cantiereworklog/end'));

      await client.endCantiere();

      final captured = verify(
        () => mockDio.post<dynamic>('/api/cantiereworklog/end', data: captureAny(named: 'data')),
      ).captured;

      expect(captured.first, isEmpty);
    });
  });

  group('upsertSessions', () {
    test('sends clientId/cantiereId/customerId/startTime and omits null optional fields',
        () async {
      when(
        () => mockDio.post<Map<String, dynamic>>(
          '/api/cantiereworklog/mobile/sessions',
          data: any(named: 'data'),
        ),
      ).thenAnswer(
        (_) async =>
            _okResponse({'sessions': <dynamic>[]}, '/api/cantiereworklog/mobile/sessions'),
      );

      await client.upsertSessions([
        CantiereMobileSessionDto(
          clientId: 'client-1',
          cantiereId: 'cant-1',
          customerId: 'cust-1',
          startTime: DateTime.utc(2026, 8, 16, 7),
        ),
      ]);

      final captured = verify(
        () => mockDio.post<Map<String, dynamic>>(
          '/api/cantiereworklog/mobile/sessions',
          data: captureAny(named: 'data'),
        ),
      ).captured;

      final body = captured.first as Map<String, dynamic>;
      final sessions = body['sessions'] as List<dynamic>;
      expect(sessions, hasLength(1));
      final session = sessions.first as Map<String, dynamic>;
      expect(session['clientId'], 'client-1');
      expect(session['cantiereId'], 'cant-1');
      expect(session['customerId'], 'cust-1');
      expect(session.containsKey('ticketId'), isFalse);
      expect(session.containsKey('description'), isFalse);
      expect(session['endTime'], isNull);
    });

    test('parses the response into CantiereMobileSessionResult', () async {
      when(
        () => mockDio.post<Map<String, dynamic>>(
          '/api/cantiereworklog/mobile/sessions',
          data: any(named: 'data'),
        ),
      ).thenAnswer(
        (_) async => _okResponse({
          'sessions': [
            {
              'clientId': 'client-1',
              'cantiereWorkLogId': 'wl-1',
              'startTime': '2026-08-16T07:00:00Z',
              'endTime': '2026-08-16T16:00:00Z',
              'isActive': false,
            },
          ],
        }, '/api/cantiereworklog/mobile/sessions'),
      );

      final result = await client.upsertSessions([
        CantiereMobileSessionDto(
          clientId: 'client-1',
          cantiereId: 'cant-1',
          customerId: 'cust-1',
          startTime: DateTime.utc(2026, 8, 16, 7),
          endTime: DateTime.utc(2026, 8, 16, 16),
        ),
      ]);

      expect(result, hasLength(1));
      expect(result.first.clientId, 'client-1');
      expect(result.first.cantiereWorkLogId, 'wl-1');
      expect(result.first.isActive, isFalse);
    });
  });

  group('getActive', () {
    test('returns only logs with null endTime', () async {
      final paginatedResponse = {
        'items': [
          {
            'id': 'log-1',
            'cantiereId': 'cant-1',
            'customerId': 'cust-1',
            'workDate': '2026-06-23T00:00:00Z',
            'startTime': '08:00:00',
            'endTime': null, // active
          },
          {
            'id': 'log-2',
            'cantiereId': 'cant-2',
            'customerId': 'cust-2',
            'workDate': '2026-06-22T00:00:00Z',
            'startTime': '09:00:00',
            'endTime': '17:00:00', // closed — should be excluded
          },
        ],
        'total': 2,
      };

      when(
        () => mockDio.get<Map<String, dynamic>>(
          '/api/cantiereworklog',
          queryParameters: any(named: 'queryParameters'),
        ),
      ).thenAnswer((_) async => _okResponse(paginatedResponse, '/api/cantiereworklog'));

      final result = await client.getActive();
      expect(result.length, 1);
      expect(result.first.id, 'log-1');
      expect(result.first.isActive, isTrue);
    });

    test('returns empty list when backend returns empty items', () async {
      when(
        () => mockDio.get<Map<String, dynamic>>(
          '/api/cantiereworklog',
          queryParameters: any(named: 'queryParameters'),
        ),
      ).thenAnswer((_) async => _okResponse({'items': [], 'total': 0}, '/api/cantiereworklog'));

      final result = await client.getActive();
      expect(result, isEmpty);
    });

    test('returns empty list on null response body', () async {
      when(
        () => mockDio.get<Map<String, dynamic>>(
          '/api/cantiereworklog',
          queryParameters: any(named: 'queryParameters'),
        ),
      ).thenAnswer(
        (_) async => Response<Map<String, dynamic>>(
          data: null,
          statusCode: 200,
          requestOptions: RequestOptions(path: '/api/cantiereworklog'),
        ),
      );

      final result = await client.getActive();
      expect(result, isEmpty);
    });
  });
}
