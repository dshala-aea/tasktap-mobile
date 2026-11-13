import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tasktap_mobile/data/access_requests/access_request_api_client.dart';

class MockDio extends Mock implements Dio {}

void main() {
  late MockDio dio;
  late AccessRequestApiClient client;

  setUp(() {
    dio = MockDio();
    client = AccessRequestApiClient(dio);
  });

  void stubAccepted() {
    when(() => dio.post<void>('/api/access-requests', data: any(named: 'data'))).thenAnswer(
      (_) async => Response<void>(
        statusCode: 202,
        requestOptions: RequestOptions(path: '/api/access-requests'),
      ),
    );
  }

  test('posts every supplied field, trimmed', () async {
    stubAccepted();

    await client.submit(
      email: '  tech@tasktap.io ',
      name: '  Mario Rossi ',
      company: ' ACME ',
      phone: ' 333 1234567 ',
      message: ' Vorrei provare TaskTap. ',
    );

    final body =
        verify(
              () => dio.post<void>('/api/access-requests', data: captureAny(named: 'data')),
            ).captured.single
            as Map<String, dynamic>;

    expect(body, {
      'email': 'tech@tasktap.io',
      'name': 'Mario Rossi',
      'company': 'ACME',
      'phone': '333 1234567',
      'message': 'Vorrei provare TaskTap.',
    });
  });

  test('omits optional fields that are empty or whitespace', () async {
    stubAccepted();

    await client.submit(
      email: 'tech@tasktap.io',
      name: '',
      company: '   ',
      phone: null,
      message: '',
    );

    final body =
        verify(
              () => dio.post<void>('/api/access-requests', data: captureAny(named: 'data')),
            ).captured.single
            as Map<String, dynamic>;

    expect(body, {'email': 'tech@tasktap.io'});
  });

  test('accepts the 202 contract response', () async {
    stubAccepted();

    await expectLater(client.submit(email: 'tech@tasktap.io'), completes);
  });

  test('rethrows a 503 so the caller can show the unavailable message', () async {
    when(() => dio.post<void>('/api/access-requests', data: any(named: 'data'))).thenThrow(
      DioException(
        requestOptions: RequestOptions(path: '/api/access-requests'),
        response: Response(
          statusCode: 503,
          requestOptions: RequestOptions(path: '/api/access-requests'),
        ),
      ),
    );

    await expectLater(client.submit(email: 'tech@tasktap.io'), throwsA(isA<DioException>()));
  });
}
