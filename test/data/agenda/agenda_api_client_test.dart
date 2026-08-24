// test/data/agenda/agenda_api_client_test.dart
//
// AgendaApiClient covers /api/agenda (AgendaController.cs), which had zero client callers before
// this feature — see the file doc in lib/data/agenda/agenda_api_client.dart for the full contract
// notes. These tests exist to catch the two ways that contract is easy to get wrong from a client
// that has never talked to it before:
//   1. DateOnly/TimeOnly parse — the only entity in this backend using either type.
//   2. The bare-list vs paginated-envelope split between GET /api/agenda and GET /api/agenda/range.

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/agenda/agenda_api_client.dart';

class _RecordingAdapter implements HttpClientAdapter {
  _RecordingAdapter(this.onFetch);

  final Future<ResponseBody> Function(RequestOptions) onFetch;
  final List<RequestOptions> requests = [];

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) {
    requests.add(options);
    return onFetch(options);
  }
}

(AgendaApiClient, _RecordingAdapter) _client(Future<ResponseBody> Function(RequestOptions) onFetch) {
  final adapter = _RecordingAdapter(onFetch);
  final dio = Dio()..httpClientAdapter = adapter;
  return (AgendaApiClient(dio), adapter);
}

void main() {
  group('AgendaItemDto.fromJson', () {
    test('parses a DateOnly date and TimeOnly times off the wire', () {
      final dto = AgendaItemDto.fromJson({
        'id': 'a1',
        'date': '2026-08-24',
        'timeStart': '13:45:00',
        'timeEnd': '14:30:00',
        'title': 'Richiama il fornitore',
        'priority': 2,
        'isCompleted': false,
      });

      expect(dto.date, DateTime(2026, 8, 24));
      expect(dto.timeStart, '13:45:00');
      expect(dto.timeEnd, '14:30:00');
      expect(dto.title, 'Richiama il fornitore');
      expect(dto.priority, 2);
      expect(dto.isCompleted, isFalse);
    });

    test('a null timeStart is "no time set", not parsed as midnight', () {
      final dto = AgendaItemDto.fromJson({
        'id': 'a1',
        'date': '2026-08-24',
        'timeStart': null,
        'title': 'Nota veloce',
      });

      expect(dto.timeStart, isNull);
    });

    test('priority survives being sent as a numeric string', () {
      final dto = AgendaItemDto.fromJson({
        'id': 'a1',
        'date': '2026-08-24',
        'title': 'x',
        'priority': '3',
      });

      expect(dto.priority, 3);
    });

    test('a missing priority defaults to 0 (Bassa), matching the backend default', () {
      final dto = AgendaItemDto.fromJson({'id': 'a1', 'date': '2026-08-24', 'title': 'x'});

      expect(dto.priority, 0);
    });

    test('reads isCompleted and completedAt once done', () {
      final dto = AgendaItemDto.fromJson({
        'id': 'a1',
        'date': '2026-08-24',
        'title': 'x',
        'isCompleted': true,
        'completedAt': '2026-08-24T09:00:00Z',
      });

      expect(dto.isCompleted, isTrue);
      expect(dto.completedAt, DateTime.utc(2026, 8, 24, 9));
    });
  });

  group('agendaPriorityLabel', () {
    test('maps 0-3 to the Italian labels used across the rest of the app', () {
      expect(agendaPriorityLabel(0), 'Bassa');
      expect(agendaPriorityLabel(3), 'Urgente');
    });

    test('clamps an out-of-range value instead of throwing', () {
      expect(agendaPriorityLabel(99), 'Urgente');
      expect(agendaPriorityLabel(-1), 'Bassa');
    });
  });

  group('fetchAgenda', () {
    test('calls GET /api/agenda/range with a from/to window and unwraps the paginated envelope', () async {
      final (client, adapter) = _client((options) async {
        return ResponseBody.fromString(
          '{"items":[{"id":"a1","date":"2026-08-24","title":"x","priority":1}],'
          '"page":1,"pageSize":100,"totalItems":1,"totalPages":1}',
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
      });

      final items = await client.fetchAgenda(from: DateTime(2026, 8, 1), to: DateTime(2026, 9, 1));

      expect(items, hasLength(1));
      expect(items.single.title, 'x');

      final req = adapter.requests.single;
      expect(req.path, '/api/agenda/range');
      expect(req.method, 'GET');
      expect(req.queryParameters['from'], '2026-08-01');
      expect(req.queryParameters['to'], '2026-09-01');
    });

    test('also tolerates a bare array (the shape GET /api/agenda itself uses)', () async {
      final (client, _) = _client((options) async {
        return ResponseBody.fromString(
          '[{"id":"a1","date":"2026-08-24","title":"x"}]',
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
      });

      final items = await client.fetchAgenda(from: DateTime(2026, 8, 1), to: DateTime(2026, 9, 1));
      expect(items, hasLength(1));
    });
  });

  group('createAgendaItem', () {
    test('POSTs to /api/agenda with the title/date/priority and no userId', () async {
      final (client, adapter) = _client((options) async {
        return ResponseBody.fromString(
          '{"id":"new-1"}',
          201,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
      });

      final id = await client.createAgendaItem(
        date: DateTime(2026, 8, 24),
        timeStart: '09:00:00',
        title: 'Ordina i ricambi',
        priority: 1,
      );

      expect(id, 'new-1');
      final req = adapter.requests.single;
      expect(req.path, '/api/agenda');
      expect(req.method, 'POST');
      final body = req.data as Map<String, dynamic>;
      expect(body['title'], 'Ordina i ricambi');
      expect(body['date'], '2026-08-24');
      expect(body['timeStart'], '09:00:00');
      expect(body['priority'], 1);
      expect(body.containsKey('userId'), isFalse);
    });
  });

  group('updateAgendaItem', () {
    test('PUTs to /api/agenda/{id} with the full replacement payload', () async {
      final (client, adapter) = _client((options) async {
        return ResponseBody.fromString(
          '{"message":"Agenda item updated"}',
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
      });

      await client.updateAgendaItem(
        'a1',
        date: DateTime(2026, 8, 25),
        timeStart: '10:00:00',
        timeEnd: '11:00:00',
        title: 'Ordina i ricambi (aggiornato)',
        priority: 2,
      );

      final req = adapter.requests.single;
      expect(req.path, '/api/agenda/a1');
      expect(req.method, 'PUT');
      final body = req.data as Map<String, dynamic>;
      expect(body['title'], 'Ordina i ricambi (aggiornato)');
      expect(body['timeEnd'], '11:00:00');
      expect(body['priority'], 2);
    });
  });

  group('completeAgendaItem', () {
    test('POSTs to /api/agenda/{id}/complete', () async {
      final (client, adapter) = _client((options) async {
        return ResponseBody.fromString(
          '{"message":"Agenda item completed"}',
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
      });

      await client.completeAgendaItem('a1');

      final req = adapter.requests.single;
      expect(req.path, '/api/agenda/a1/complete');
      expect(req.method, 'POST');
    });
  });

  group('deleteAgendaItem', () {
    test('DELETEs /api/agenda/{id}', () async {
      final (client, adapter) = _client((options) async {
        return ResponseBody.fromString(
          '{"message":"Agenda item deleted"}',
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
      });

      await client.deleteAgendaItem('a1');

      final req = adapter.requests.single;
      expect(req.path, '/api/agenda/a1');
      expect(req.method, 'DELETE');
    });
  });
}
