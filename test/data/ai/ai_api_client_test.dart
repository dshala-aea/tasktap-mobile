import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/ai/ai_api_client.dart';

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

AiApiClient _clientThrowing(DioException e) {
  final dio = Dio();
  dio.httpClientAdapter = _Adapter((_) => throw e);
  return AiApiClient(dio);
}

DioException _err({int? status, Object? body, DioExceptionType? type}) => DioException(
  requestOptions: RequestOptions(path: '/api/ai/reports/draft'),
  type: type ?? DioExceptionType.badResponse,
  response: status == null
      ? null
      : Response<dynamic>(
          requestOptions: RequestOptions(path: '/api/ai/reports/draft'),
          statusCode: status,
          data: body,
        ),
);

void main() {
  group('AiQuotaDto', () {
    test('reads the allowance and knows when it is gone', () {
      final dto = AiQuotaDto.fromJson({
        'monthlyLimit': 100,
        'used': 100,
        'remaining': 0,
        'resetsAt': '2026-09-01T00:00:00Z',
      });

      expect(dto.exhausted, isTrue);
      expect(dto.resetsAt, DateTime.utc(2026, 9, 1));
    });

    test('counts survive being sent as strings', () {
      final dto = AiQuotaDto.fromJson({'monthlyLimit': '100', 'used': '40', 'remaining': '60'});

      expect(dto.remaining, 60);
      expect(dto.exhausted, isFalse);
    });
  });

  group('draft failures', () {
    test('a 429 becomes a quota exception carrying the reset date', () async {
      final client = _clientThrowing(
        _err(
          status: 429,
          body: {
            'error': 'Quota mensile AI esaurita.',
            'monthlyLimit': 100,
            'used': 100,
            'remaining': 0,
            'resetsAt': '2026-09-01T00:00:00Z',
          },
        ),
      );

      // The screen needs the date: "esaurita" alone leaves a technician with no idea whether to
      // wait an hour or three weeks.
      await expectLater(
        () => client.generateDraft(scheduleId: 's1'),
        throwsA(
          isA<AiQuotaExhaustedException>()
              .having((e) => e.resetsAt, 'resetsAt', DateTime.utc(2026, 9, 1))
              .having((e) => e.monthlyLimit, 'monthlyLimit', 100),
        ),
      );
    });

    test('a 429 without a body still reports the quota, not a generic error', () async {
      final client = _clientThrowing(_err(status: 429, body: null));

      await expectLater(
        () => client.generateDraft(scheduleId: 's1'),
        throwsA(isA<AiQuotaExhaustedException>()),
      );
    });

    test('no connection says so, and points at the manual path', () async {
      final client = _clientThrowing(_err(type: DioExceptionType.connectionError));

      await expectLater(
        () => client.generateDraft(scheduleId: 's1'),
        throwsA(
          isA<AiFailure>().having(
            (e) => e.message,
            'message',
            allOf(contains('Nessuna connessione'), contains('a mano')),
          ),
        ),
      );
    });

    test('a 400 is not shown raw', () async {
      final client = _clientThrowing(_err(status: 400, body: 'Schedule has no linked ticket'));

      await expectLater(
        () => client.generateDraft(scheduleId: 's1'),
        throwsA(
          isA<AiFailure>()
              // The controller's 400 bodies are English domain messages written for an API
              // consumer, not for someone standing in a plant room.
              .having((e) => e.message, 'message', isNot(contains('Schedule')))
              .having((e) => e.message, 'message', contains('informazioni sull\'intervento')),
        ),
      );
    });
  });

  group('AiReportDraftDto', () {
    test('carries the model so the suggestion can admit what it is', () {
      final dto = AiReportDraftDto.fromJson({
        'title': 'Sostituzione valvola',
        'details': 'Sostituita la valvola di zona.',
        'technicianNotes': 'Consigliata revisione pompa.',
        'modelUsed': 'gpt-4o-mini',
        'inputTokens': 900,
        'outputTokens': 120,
      });

      expect(dto.title, 'Sostituzione valvola');
      expect(dto.modelUsed, 'gpt-4o-mini');
      expect(dto.technicianNotes, 'Consigliata revisione pompa.');
    });
  });
}
