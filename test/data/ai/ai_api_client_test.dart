import 'dart:convert';

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
        'activities': [
          {'description': 'Sostituzione valvola bloccata', 'hours': 2.5, 'state': 'ResolvedBySystem'},
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
      // Bug (2026-09-23): this field is what AiConversationsController.Confirm builds the
      // created Report's Title/Details from — until this parsed, a technician had no way to see
      // or verify that text before confirming.
      expect(draft.activities.single.description, 'Sostituzione valvola bloccata');
      expect(draft.activities.single.hours, 2.5);
      expect(draft.activities.single.state, AiResolutionState.resolvedBySystem);
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

    test('confirmConversation parses the resolved draft, not a created report', () async {
      RequestOptions? captured;
      final dio = Dio();
      dio.httpClientAdapter = _Adapter((options) async {
        captured = options;
        return ResponseBody.fromString(
          jsonEncode({
            'title': 'Sostituzione valvola',
            'details': 'Valvola bloccata',
            'materialiNotRequired': false,
            'customerSignoffText': 'accettato',
            'ticketId': '00000000-0000-0000-0000-000000000003',
            'cantiereId': null,
            'locationId': null, // null is legal on a 200 and must stay null
            'staff': [
              {
                'userId': '00000000-0000-0000-0000-000000000008',
                'hoursWorked': '6.5',
                'kmTraveled': '12',
                'vehicle': 'Fiat Panda',
              },
            ],
            'materials': [
              {
                'materialeId': null,
                'freeTextName': 'Guarnizione',
                'quantity': '2',
                'unitOfMeasure': 'pz',
                'notes': 'Da verificare: materiale non trovato a catalogo.',
              },
            ],
            'controlli': [
              {
                'ticketControlId': '00000000-0000-0000-0000-000000000009',
                'stringValue': null,
                'boolValue': true,
                'dateValue': null,
                'numberValue': null,
                'note': null,
              },
            ],
            'warnings': ['Un controllo della checklist non è stato registrato.'],
          }),
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
      });
      final client = AiApiClient(dio);

      final r = await client.confirmConversation('sess-1', idempotencyKey: 'key-1');

      expect(r.title, 'Sostituzione valvola');
      expect(r.ticketId, '00000000-0000-0000-0000-000000000003');
      expect(r.locationId, isNull, reason: 'the wire says null; nothing may invent a value for it');
      expect(r.staff.single.hoursWorked, 6.5, reason: 'numbers may arrive as strings');
      expect(r.materials.single.materialeId, isNull);
      expect(r.materials.single.freeTextName, 'Guarnizione');
      expect(r.materials.single.notes, contains('Da verificare'));
      expect(r.controlli.single.ticketControlId, '00000000-0000-0000-0000-000000000009');
      expect(r.controlli.single.boolValue, isTrue);
      expect(r.warnings, hasLength(1));
      expect(captured!.headers['Idempotency-Key'], 'key-1');
    });

    test('the draft shapes do not describe the confirm response', () async {
      final dio = Dio();
      dio.httpClientAdapter = _Adapter(
        (options) async => ResponseBody.fromString(
          jsonEncode({
            'reportId': 'rpt-1',
            'replayed': false,
            'materiali': [],
            'observations': [],
          }),
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        ),
      );
      final client = AiApiClient(dio);

      final r = await client.confirmConversation('sess-1', idempotencyKey: 'k');

      // The pre-I2 body parses without throwing — every field is simply absent. That silence is
      // why the inbound contract gate, not this test, is what pins the shape.
      expect(r.title, isEmpty);
      expect(r.materials, isEmpty);
      expect(r.controlli, isEmpty);
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

  group('live draft wire contract (Task 11)', () {
    Dio dioWith(Future<ResponseBody> Function(RequestOptions) f) {
      final dio = Dio();
      dio.httpClientAdapter = _Adapter(f);
      return dio;
    }

    ResponseBody json(Object body, [int status = 200]) => ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );

    test('resumeConversation returns the session id, or null on a 404', () async {
      RequestOptions? seen;
      final ok = AiApiClient(
        dioWith((o) async {
          seen = o;
          return json({'sessionId': 'sess-9'});
        }),
      );
      expect(await ok.resumeConversation('tkt-1'), 'sess-9');
      expect(seen!.method, 'GET');
      expect(seen!.queryParameters, {'ticketId': 'tkt-1'});

      final none = AiApiClient(dioWith((o) async => json({'title': 'Not Found'}, 404)));
      expect(await none.resumeConversation('tkt-1'), isNull);
    });

    test('postTurn sends the new fields and the Idempotency-Key header', () async {
      RequestOptions? seen;
      final client = AiApiClient(
        dioWith((o) async {
          seen = o;
          return json({'assistantReplyText': 'Ok', 'draft': <String, dynamic>{}});
        }),
      );
      await client.postTurn(
        'sess-1',
        text: 'Filtro olio',
        source: AiTurnSource.voice,
        audioRef: 'a-1',
        rawTranscript: 'filtro orio',
        replacesTurnId: 't-3',
        idempotencyKey: 'key-9',
      );
      expect(seen!.headers['Idempotency-Key'], 'key-9');
      expect(seen!.data, {
        'text': 'Filtro olio',
        'source': 'Voice',
        'audioRef': 'a-1',
        'rawTranscript': 'filtro orio',
        'replacesTurnId': 't-3',
      });

      await client.postTurn('sess-1', text: 'x', idempotencyKey: 'key-10');
      expect(seen!.data, {'text': 'x', 'source': 'Typed'});
    });

    test('syncEdits is an edits-only turn with the exact ConfirmedEditDto wire keys', () async {
      RequestOptions? seen;
      final client = AiApiClient(
        dioWith((o) async {
          seen = o;
          return json({'assistantReplyText': '', 'draft': <String, dynamic>{}});
        }),
      );
      await client.syncEdits(
        'sess-1',
        const [
          AiConfirmedEdit(kind: 'worker', id: 'u-1', property: 'hours', value: 5.5),
          AiConfirmedEdit(kind: 'material', name: 'Nastro teflon'),
          AiConfirmedEdit(kind: 'material', id: 'm-1', remove: true),
        ],
        idempotencyKey: 'batch-1',
      );
      expect(seen!.path, '/api/ai/conversations/sess-1/turns');
      expect(seen!.headers['Idempotency-Key'], 'batch-1');
      expect(seen!.data, {
        'text': '',
        'source': 'Typed',
        'confirmedEdits': [
          {'kind': 'worker', 'id': 'u-1', 'property': 'hours', 'value': 5.5, 'remove': false},
          {'kind': 'material', 'name': 'Nastro teflon', 'remove': false},
          {'kind': 'material', 'id': 'm-1', 'remove': true},
        ],
      });
      for (final e in (seen!.data as Map)['confirmedEdits'] as List) {
        expect(AiConfirmedEdit.wireKeys, containsAll((e as Map).keys));
      }
    });

    test('draft entries carry km, vehicle, unit, isFreeText and a control date; unknown '
        'strings never throw', () {
      final d = AiCopilotDraftDto.fromJson({
        'workers': [
          {'userId': 'u', 'fullName': 'A', 'km': 12, 'vehicle': 'Doblò', 'state': 'Nuovo'},
        ],
        'materials': [
          {'materialId': 'm', 'name': 'n', 'quantity': 1, 'unit': 'pz', 'isFreeText': true},
        ],
        'controlli': [
          {'ticketControlId': 'c', 'dateValue': '2026-10-20T00:00:00Z', 'state': 'X'},
        ],
      });
      expect(d.workers.single.km, 12);
      expect(d.workers.single.vehicle, 'Doblò');
      expect(d.workers.single.state, AiResolutionState.unresolved);
      expect(d.materials.single.unit, 'pz');
      expect(d.materials.single.isFreeText, isTrue);
      expect(d.controlli.single.dateValue, DateTime.utc(2026, 10, 20));
    });

    test('a 400 keeps the server\'s stable code (which edit refusal it was)', () async {
      final client = AiApiClient(
        dioWith((o) async => json({'error': 'edit_reference_not_found', 'message': 'x'}, 400)),
      );
      await expectLater(
        () => client.syncEdits(
          's',
          const [AiConfirmedEdit(kind: 'worker', id: 'u')],
          idempotencyKey: 'k',
        ),
        throwsA(
          isA<AiConversationException>()
              .having((e) => e.statusCode, 'status', 400)
              .having((e) => e.code, 'code', 'edit_reference_not_found'),
        ),
      );
    });

    test('409 codes are surfaced, not collapsed', () async {
      for (final code in [
        'turn_in_progress',
        'concurrent_update',
        'draft_too_large',
        'turn_limit_exceeded',
      ]) {
        final client = AiApiClient(dioWith((o) async => json({'code': code, 'title': 'x'}, 409)));
        await expectLater(
          () => client.postTurn('s', text: 't', idempotencyKey: 'k'),
          throwsA(isA<AiConversationException>().having((e) => e.code, 'code', code)),
        );
      }
    });

    test('a 429 on a turn is a quota exception and a lost connection is flagged offline', () async {
      final quota = AiApiClient(dioWith((o) async => json({'error': 'QuotaExceeded'}, 429)));
      await expectLater(
        () => quota.postTurn('s', text: 't', idempotencyKey: 'k'),
        throwsA(isA<AiQuotaExhaustedException>()),
      );
      final offline = _clientThrowing(_err(type: DioExceptionType.connectionError));
      await expectLater(
        () => offline.postTurn('s', text: 't', idempotencyKey: 'k'),
        throwsA(isA<AiConversationException>().having((e) => e.offline, 'offline', isTrue)),
      );
    });

    test('postTurn gives the server its full 45 s turn budget (per-request timeouts)', () async {
      RequestOptions? seen;
      final client = AiApiClient(
        dioWith((o) async {
          seen = o;
          return json({'assistantReplyText': 'Ok', 'draft': <String, dynamic>{}});
        }),
      );
      await client.postTurn('s', text: 'x', idempotencyKey: 'k');
      expect(seen!.receiveTimeout, const Duration(seconds: 60));
      expect(seen!.sendTimeout, const Duration(seconds: 60));
    });

    test('a 422 for an over-long text is a typed, Italian, shortenable refusal', () async {
      final client = AiApiClient(
        dioWith(
          (o) async => json({
            'code': 'validation_failed',
            'errors': {
              'Text': ['Text must not exceed 8000 characters.'],
            },
          }, 422),
        ),
      );
      await expectLater(
        () => client.postTurn('s', text: 't', idempotencyKey: 'k'),
        throwsA(
          isA<AiConversationException>()
              .having((e) => e.statusCode, 'status', 422)
              .having((e) => e.isTextTooLong, 'tooLong', isTrue)
              .having((e) => e.message, 'message', contains('troppo lungo')),
        ),
      );
    });

    test('any other 422 gets an honest Italian sentence, never the service-silent copy', () async {
      final client = AiApiClient(
        dioWith(
          (o) async => json({
            'code': 'validation_failed',
            'errors': {
              'Text': ['Text must not be empty.'],
            },
          }, 422),
        ),
      );
      await expectLater(
        () => client.postTurn('s', text: 't', idempotencyKey: 'k'),
        throwsA(
          isA<AiConversationException>()
              .having((e) => e.statusCode, 'status', 422)
              .having((e) => e.isTextTooLong, 'tooLong', isFalse)
              .having((e) => e.message, 'message', contains('rifiutato'))
              .having((e) => e.message, 'message', isNot(contains('validation_failed'))),
        ),
      );
    });

    test('a 400 with a code the app does not know never shows the raw code', () async {
      for (final code in ['audio_ref_invalid', 'something_new']) {
        final client = AiApiClient(dioWith((o) async => json({'error': code, 'message': 'x'}, 400)));
        await expectLater(
          () => client.postTurn('s', text: 't', idempotencyKey: 'k'),
          throwsA(
            isA<AiConversationException>()
                .having((e) => e.code, 'code', code)
                .having((e) => e.message, 'message', isNot(contains('_'))),
          ),
        );
      }
    });

    test('tryAbandonConversation reports whether the session is gone and never throws', () async {
      final ok = AiApiClient(dioWith((o) async => json({}, 204)));
      expect(await ok.tryAbandonConversation('s'), isTrue);
      final gone = AiApiClient(dioWith((o) async => json({'title': 'nf'}, 404)));
      expect(await gone.tryAbandonConversation('s'), isTrue);
      final down = _clientThrowing(_err(type: DioExceptionType.connectionError));
      expect(await down.tryAbandonConversation('s'), isFalse);
    });
  });
}
