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

  group('generateDraft request body', () {
    test('omits scheduleId when absent and includes cantiereId when given', () async {
      RequestOptions? captured;
      final dio = Dio();
      dio.httpClientAdapter = _Adapter((options) {
        captured = options;
        throw DioException(requestOptions: options, type: DioExceptionType.cancel);
      });
      final client = AiApiClient(dio);

      await expectLater(
        () => client.generateDraft(cantiereId: 'cant-1', voiceTranscript: 'detto a voce'),
        throwsA(isA<AiFailure>()),
      );

      final body = captured!.data as Map<String, dynamic>;
      expect(body.containsKey('scheduleId'), isFalse);
      expect(body.containsKey('ticketId'), isFalse);
      expect(body['cantiereId'], 'cant-1');
      expect(body['voiceTranscript'], 'detto a voce');
    });

    test('includes scheduleId when given, still omitting the others', () async {
      RequestOptions? captured;
      final dio = Dio();
      dio.httpClientAdapter = _Adapter((options) {
        captured = options;
        throw DioException(requestOptions: options, type: DioExceptionType.cancel);
      });
      final client = AiApiClient(dio);

      await expectLater(
        () => client.generateDraft(scheduleId: 'sched-1'),
        throwsA(isA<AiFailure>()),
      );

      final body = captured!.data as Map<String, dynamic>;
      expect(body['scheduleId'], 'sched-1');
      expect(body.containsKey('ticketId'), isFalse);
      expect(body.containsKey('cantiereId'), isFalse);
      expect(body.containsKey('voiceTranscript'), isFalse);
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

  // ── AI Copilot conversation ──────────────────────────────────────────────────

  group('AiCopilotDraftDto', () {
    test('parses every draft section and flags a blocking open item', () {
      final draft = AiCopilotDraftDto.fromJson({
        'diagnosi': 'Valvola bloccata',
        'soluzione': 'Sostituita valvola',
        'customerSignoffText': 'Cliente ha accettato',
        'workers': [
          {'userId': 'u1', 'fullName': 'Marco Rossi', 'hours': 6.5, 'state': 'ResolvedBySystem'},
        ],
        'materials': [
          {'materialId': 'm1', 'name': 'Vite M8', 'quantity': 4, 'state': 'ResolvedBySystem'},
        ],
        'controlli': [
          {'ticketControlId': 'c1', 'boolValue': true, 'state': 'Unresolved'},
        ],
        'openItems': [
          {'field': 'materials[0].materialId', 'state': 'Ambiguous'},
        ],
      });

      expect(draft.diagnosi, 'Valvola bloccata');
      expect(draft.workers.single.fullName, 'Marco Rossi');
      expect(draft.workers.single.hours, 6.5);
      expect(draft.materials.single.quantity, 4);
      expect(draft.controlli.single.describe(), 'Sì');
      expect(draft.hasBlockingOpenItems, isTrue);
    });

    test('empty draft has no blocking open items', () {
      expect(AiCopilotDraftDto.empty.hasBlockingOpenItems, isFalse);
    });

    test('an Unresolved-only open item does not block', () {
      final draft = AiCopilotDraftDto.fromJson({
        'workers': [],
        'materials': [],
        'controlli': [],
        'openItems': [
          {'field': 'diagnosi', 'state': 'Unresolved'},
        ],
      });

      expect(draft.hasBlockingOpenItems, isFalse);
    });
  });

  group('conversation lifecycle', () {
    test('startConversation sends ticketId and parses the session', () async {
      RequestOptions? captured;
      final dio = Dio();
      dio.httpClientAdapter = _Adapter((options) async {
        captured = options;
        return ResponseBody.fromString(
          '{"sessionId":"sess-1","ticketId":"tkt-1","cantiereId":null}',
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
      });
      final client = AiApiClient(dio);

      final session = await client.startConversation(ticketId: 'tkt-1');

      expect(session.sessionId, 'sess-1');
      expect(session.ticketId, 'tkt-1');
      final body = captured!.data as Map<String, dynamic>;
      expect(body['ticketId'], 'tkt-1');
      expect(body.containsKey('cantiereId'), isFalse);
    });

    test('sendTurn posts the text and parses the draft', () async {
      final dio = Dio();
      dio.httpClientAdapter = _Adapter(
        (options) async => ResponseBody.fromString(
          '{"assistantReplyText":"Fatto.","draft":{"workers":[],"materials":[],"controlli":[],"openItems":[]}}',
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        ),
      );
      final client = AiApiClient(dio);

      final result = await client.sendTurn('sess-1', 'Ho sostituito la valvola');

      expect(result.assistantReplyText, 'Fatto.');
      expect(result.draft.workers, isEmpty);
    });

    test('confirmConversation sends the Idempotency-Key header', () async {
      RequestOptions? captured;
      final dio = Dio();
      dio.httpClientAdapter = _Adapter((options) async {
        captured = options;
        return ResponseBody.fromString(
          '{"reportId":"rpt-1","replayed":false}',
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
      });
      final client = AiApiClient(dio);

      final result = await client.confirmConversation('sess-1', idempotencyKey: 'key-1');

      expect(result.reportId, 'rpt-1');
      expect(result.replayed, isFalse);
      expect(captured!.headers['Idempotency-Key'], 'key-1');
    });

    test('a 409 on confirm becomes a stale-version conflict', () async {
      final client = _clientThrowing(_err(status: 409));

      await expectLater(
        () => client.confirmConversation('sess-1', idempotencyKey: 'key-1'),
        throwsA(isA<AiConversationException>().having((e) => e.isStaleVersionConflict, 'isStaleVersionConflict', isTrue)),
      );
    });

    test('a 404 on turn means the session is gone, not a generic error', () async {
      final client = _clientThrowing(_err(status: 404));

      await expectLater(
        () => client.sendTurn('sess-1', 'ciao'),
        throwsA(
          isA<AiConversationException>().having(
            (e) => e.message,
            'message',
            contains('scaduta'),
          ),
        ),
      );
    });

    test('abandonConversation swallows a failure — best-effort', () async {
      final client = _clientThrowing(_err(status: 404));

      await expectLater(client.abandonConversation('sess-1'), completes);
    });
  });
}
