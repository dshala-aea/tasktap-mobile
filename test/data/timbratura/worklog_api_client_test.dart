// dart format width=100
// test/data/timbratura/worklog_api_client_test.dart
//
// WorklogApiClient.submitToday() — the mobile counterpart of the "Submit" action GiornataDto
// already advertises. Backend `POST /api/worklog/today/submit` (WorkLogController.SubmitToday)
// existed with no mobile call site.

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tasktap_mobile/data/timbratura/worklog_api_client.dart';

class MockDio extends Mock implements Dio {}

Response<T> _okResponse<T>(T data, String path) =>
    Response<T>(data: data, statusCode: 200, requestOptions: RequestOptions(path: path));

void main() {
  late MockDio mockDio;
  late WorklogApiClient client;

  setUp(() {
    mockDio = MockDio();
    client = WorklogApiClient(mockDio);
  });

  group('submitToday', () {
    test('POSTs /api/worklog/today/submit and parses the returned GiornataDto', () async {
      when(() => mockDio.post<Map<String, dynamic>>('/api/worklog/today/submit')).thenAnswer(
        (_) async => _okResponse({
          'status': 'ClockedOut',
          'workedMinutes': 480,
          'breakMinutes': 30,
          'isPayrollLocked': false,
          'availableActions': [
            {
              'action': 'Submit',
              'enabled': false,
              'reasonCode': 'already_submitted',
              'reason': 'Le ore di oggi sono già state inviate.',
            },
          ],
        }, '/api/worklog/today/submit'),
      );

      final giornata = await client.submitToday();

      verify(() => mockDio.post<Map<String, dynamic>>('/api/worklog/today/submit')).called(1);
      expect(giornata.workedMinutes, 480);
      expect(giornata.action('Submit')?.enabled, isFalse);
      expect(giornata.action('Submit')?.reasonCode, 'already_submitted');
    });

    test('throws StateError on an empty response body', () {
      when(() => mockDio.post<Map<String, dynamic>>('/api/worklog/today/submit')).thenAnswer(
        (_) async => Response<Map<String, dynamic>>(
          data: null,
          statusCode: 200,
          requestOptions: RequestOptions(path: '/api/worklog/today/submit'),
        ),
      );

      expect(() => client.submitToday(), throwsA(isA<StateError>()));
    });
  });
}
