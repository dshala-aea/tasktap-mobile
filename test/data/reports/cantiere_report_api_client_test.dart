// dart format width=100
// test/data/reports/cantiere_report_api_client_test.dart
//
// Unit tests for CantiereReportApiClient request/response mapping.
// Uses mocktail to mock Dio — no real network calls.

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tasktap_mobile/data/reports/cantiere_report_api_client.dart';

class MockDio extends Mock implements Dio {}

Response<T> _okResponse<T>(T data, String path) => Response<T>(
  data: data,
  statusCode: 201,
  requestOptions: RequestOptions(path: path),
);

void main() {
  late MockDio mockDio;
  late CantiereReportApiClient client;

  setUpAll(() {
    registerFallbackValue(RequestOptions(path: '/'));
  });

  setUp(() {
    mockDio = MockDio();
    client = CantiereReportApiClient(mockDio);
  });

  group('createFromCantiereWorklogs', () {
    test('POSTs to /api/reports/from-cantiere-worklogs with the cantiereId body', () async {
      when(
        () => mockDio.post<Map<String, dynamic>>(
          '/api/reports/from-cantiere-worklogs',
          data: any(named: 'data'),
        ),
      ).thenAnswer(
        (_) async => _okResponse({'id': 'report-1'}, '/api/reports/from-cantiere-worklogs'),
      );

      final id = await client.createFromCantiereWorklogs('cant-1');

      expect(id, 'report-1');
      final captured = verify(
        () => mockDio.post<Map<String, dynamic>>(
          '/api/reports/from-cantiere-worklogs',
          data: captureAny(named: 'data'),
        ),
      ).captured;
      final body = captured.first as Map<String, dynamic>;
      expect(body, {'cantiereId': 'cant-1'});
    });

    test('throws StateError on an empty response body', () async {
      when(
        () => mockDio.post<Map<String, dynamic>>(
          '/api/reports/from-cantiere-worklogs',
          data: any(named: 'data'),
        ),
      ).thenAnswer(
        (_) async => Response<Map<String, dynamic>>(
          data: null,
          statusCode: 201,
          requestOptions: RequestOptions(path: '/api/reports/from-cantiere-worklogs'),
        ),
      );

      expect(() => client.createFromCantiereWorklogs('cant-1'), throwsA(isA<StateError>()));
    });

    test('propagates DioException on server error', () async {
      when(
        () => mockDio.post<Map<String, dynamic>>(
          '/api/reports/from-cantiere-worklogs',
          data: any(named: 'data'),
        ),
      ).thenThrow(
        DioException(
          requestOptions: RequestOptions(path: '/api/reports/from-cantiere-worklogs'),
          response: Response(
            statusCode: 403,
            data: 'forbidden',
            requestOptions: RequestOptions(path: '/api/reports/from-cantiere-worklogs'),
          ),
        ),
      );

      expect(() => client.createFromCantiereWorklogs('cant-1'), throwsA(isA<DioException>()));
    });
  });

  group('fetchReportSeed', () {
    test('GETs /api/reports/{id} and parses locationId + the staff array', () async {
      when(() => mockDio.get<Map<String, dynamic>>('/api/reports/report-1')).thenAnswer(
        (_) async => _okResponse({
          'id': 'report-1',
          'title': '',
          'locationId': 'loc-resolved-1',
          'staff': [
            {
              'userId': 'user-1',
              'hoursWorked': 4.5,
              'kmTraveled': 0,
              'startTime': '2026-08-16T07:00:00Z',
              'endTime': '2026-08-16T11:30:00Z',
            },
            {'userId': 'user-2'},
          ],
        }, '/api/reports/report-1'),
      );

      final seed = await client.fetchReportSeed('report-1');

      expect(seed.locationId, 'loc-resolved-1');
      expect(seed.staff, hasLength(2));
      expect(seed.staff[0].userId, 'user-1');
      expect(seed.staff[0].hoursWorked, 4.5);
      expect(seed.staff[0].kmTraveled, 0);
      expect(seed.staff[0].startTime, DateTime.utc(2026, 8, 16, 7));
      expect(seed.staff[0].endTime, DateTime.utc(2026, 8, 16, 11, 30));
      // A staff row with no hours/times seeded at all — the zero-worklogs-per-user edge case for
      // one member of an otherwise non-empty batch — must not throw parsing a missing field.
      expect(seed.staff[1].userId, 'user-2');
      expect(seed.staff[1].hoursWorked, isNull);
      expect(seed.staff[1].startTime, isNull);
    });

    test(
      'returns an empty staff list and null locationId when the response has neither key',
      () async {
        when(
          () => mockDio.get<Map<String, dynamic>>('/api/reports/report-1'),
        ).thenAnswer((_) async => _okResponse({'id': 'report-1'}, '/api/reports/report-1'));

        final seed = await client.fetchReportSeed('report-1');

        expect(seed.locationId, isNull);
        expect(seed.staff, isEmpty);
      },
    );

    test('returns an empty seed on an empty response body', () async {
      when(() => mockDio.get<Map<String, dynamic>>('/api/reports/report-1')).thenAnswer(
        (_) async => Response<Map<String, dynamic>>(
          data: null,
          statusCode: 200,
          requestOptions: RequestOptions(path: '/api/reports/report-1'),
        ),
      );

      final seed = await client.fetchReportSeed('report-1');

      expect(seed.locationId, isNull);
      expect(seed.staff, isEmpty);
    });

    test('propagates DioException on server error', () async {
      when(() => mockDio.get<Map<String, dynamic>>('/api/reports/report-1')).thenThrow(
        DioException(
          requestOptions: RequestOptions(path: '/api/reports/report-1'),
          response: Response(
            statusCode: 404,
            data: 'not found',
            requestOptions: RequestOptions(path: '/api/reports/report-1'),
          ),
        ),
      );

      expect(() => client.fetchReportSeed('report-1'), throwsA(isA<DioException>()));
    });
  });
}
