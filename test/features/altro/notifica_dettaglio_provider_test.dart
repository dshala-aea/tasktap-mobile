// The by-id provider's classification: a notification that is gone (404) or not ours (403) is
// the same "non disponibile" answer the page renders; everything else propagates so the page can
// offer a retry. Coverage for the five lines every detail-page failure state rests on.

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tasktap_mobile/data/api/dio_client.dart';
import 'package:tasktap_mobile/features/altro/notifiche_provider.dart';

class MockDio extends Mock implements Dio {}

DioException _error(int status) {
  final options = RequestOptions(path: '/api/notifications/n1');
  return DioException(
    requestOptions: options,
    response: Response<dynamic>(requestOptions: options, statusCode: status),
    type: DioExceptionType.badResponse,
  );
}

ProviderContainer _container(MockDio dio) {
  final container = ProviderContainer(
    overrides: [dioProvider.overrideWithValue(dio)],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  test('a 404 becomes NotificaNonDisponibile', () async {
    final dio = MockDio();
    when(() => dio.get<dynamic>('/api/notifications/n1')).thenThrow(_error(404));

    await expectLater(
      _container(dio).read(notificaDettaglioProvider('n1').future),
      throwsA(isA<NotificaNonDisponibile>()),
    );
  });

  test("a 403 (another user's notification) becomes NotificaNonDisponibile", () async {
    final dio = MockDio();
    when(() => dio.get<dynamic>('/api/notifications/n1')).thenThrow(_error(403));

    await expectLater(
      _container(dio).read(notificaDettaglioProvider('n1').future),
      throwsA(isA<NotificaNonDisponibile>()),
    );
  });

  test('a 500 propagates so the page can retry', () async {
    final dio = MockDio();
    when(() => dio.get<dynamic>('/api/notifications/n1')).thenThrow(_error(500));

    await expectLater(
      _container(dio).read(notificaDettaglioProvider('n1').future),
      throwsA(isA<DioException>()),
    );
  });
}
