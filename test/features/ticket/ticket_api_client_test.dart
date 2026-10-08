// dart format width=100
// test/features/ticket/ticket_api_client_test.dart
//
// Covers two fixes to TicketApiClient.createTicket:
//   1. It sends `priorita` (a TicketPriorityEnum string — see TicketPriorityEnum.cs, which has
//      its own [JsonConverter(JsonStringEnumConverter)]) — the field mobile never sent at all.
//   2. It reads the created ticket's id from the response's actual `id` key
//      (`BasicPkResponse` — same shared type AdminApiClient's create* methods return), not the
//      `ticketId` key it used to read, which threw on every successful create.

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tasktap_mobile/features/ticket/ticket_api_client.dart';

class MockDio extends Mock implements Dio {}

Response<T> _okResponse<T>(T data, String path) => Response<T>(
  data: data,
  statusCode: 200,
  requestOptions: RequestOptions(path: path),
);

void main() {
  late MockDio mockDio;
  late TicketApiClient client;

  setUpAll(() {
    registerFallbackValue(RequestOptions(path: '/'));
  });

  setUp(() {
    mockDio = MockDio();
    client = TicketApiClient(mockDio);
  });

  group('createTicket', () {
    test('reads "id", not "ticketId", from the response', () async {
      when(
        () => mockDio.post<Map<String, dynamic>>('/api/tickets', data: any(named: 'data')),
      ).thenAnswer((_) async => _okResponse({'id': 'tick-1'}, '/api/tickets'));

      final id = await client.createTicket(
        title: 'Perdita idrica',
        customerId: 'cust-1',
        locationId: 'loc-1',
        statusId: 1,
        typeId: 2,
      );

      expect(id, 'tick-1');
    });

    test('sends priorita, defaulting to Media', () async {
      when(
        () => mockDio.post<Map<String, dynamic>>('/api/tickets', data: any(named: 'data')),
      ).thenAnswer((_) async => _okResponse({'id': 'tick-1'}, '/api/tickets'));

      await client.createTicket(
        title: 'Perdita idrica',
        customerId: 'cust-1',
        locationId: 'loc-1',
        statusId: 1,
        typeId: 2,
      );

      final captured = verify(
        () => mockDio.post<Map<String, dynamic>>('/api/tickets', data: captureAny(named: 'data')),
      ).captured;
      final body = captured.first as Map<String, dynamic>;
      expect(body['priorita'], 'Media');
    });

    test('sends an explicit priorita as a string, not an int', () async {
      when(
        () => mockDio.post<Map<String, dynamic>>('/api/tickets', data: any(named: 'data')),
      ).thenAnswer((_) async => _okResponse({'id': 'tick-1'}, '/api/tickets'));

      await client.createTicket(
        title: 'Guasto grave',
        customerId: 'cust-1',
        locationId: 'loc-1',
        statusId: 1,
        typeId: 2,
        priorita: 'Urgente',
      );

      final captured = verify(
        () => mockDio.post<Map<String, dynamic>>('/api/tickets', data: captureAny(named: 'data')),
      ).captured;
      final body = captured.first as Map<String, dynamic>;
      expect(body['priorita'], 'Urgente');
      expect(body['priorita'], isA<String>());
    });

    // Field-parity gap: web's TicketCreatePanel sends dueDate/technicianNotes/agentId/tags on
    // create, mobile sent none of them.
    test('sends dueDate/technicianNotes/agentId/tags when provided', () async {
      when(
        () => mockDio.post<Map<String, dynamic>>('/api/tickets', data: any(named: 'data')),
      ).thenAnswer((_) async => _okResponse({'id': 'tick-1'}, '/api/tickets'));

      await client.createTicket(
        title: 'Perdita idrica',
        customerId: 'cust-1',
        locationId: 'loc-1',
        statusId: 1,
        typeId: 2,
        dueDate: DateTime.utc(2026, 10, 1),
        technicianNotes: 'Verificare guarnizione',
        agentId: 'usr-agent-1',
        tags: const ['urgente', 'garanzia'],
      );

      final captured = verify(
        () => mockDio.post<Map<String, dynamic>>('/api/tickets', data: captureAny(named: 'data')),
      ).captured;
      final body = captured.first as Map<String, dynamic>;
      expect(body['dueDate'], '2026-10-01T00:00:00.000Z');
      expect(body['technicianNotes'], 'Verificare guarnizione');
      expect(body['agentId'], 'usr-agent-1');
      expect(body['tags'], ['urgente', 'garanzia']);
    });

    // Ticket parity with web's TicketCreatePanel: CreateTicketRequest carries contractId,
    // commessaId, cantiereId and prodottoAssistenzaIds (List<Guid>?) — the wire names the server
    // actually validates.
    test('sends contractId/commessaId/cantiereId/prodottoAssistenzaIds when provided', () async {
      when(
        () => mockDio.post<Map<String, dynamic>>('/api/tickets', data: any(named: 'data')),
      ).thenAnswer((_) async => _okResponse({'id': 'tick-1'}, '/api/tickets'));

      await client.createTicket(
        title: 'Perdita idrica',
        customerId: 'cust-1',
        locationId: 'loc-1',
        statusId: 1,
        typeId: 2,
        contractId: 'con-1',
        commessaId: 'com-1',
        cantiereId: 'can-1',
        prodottoAssistenzaIds: const ['prod-1', 'prod-2'],
      );

      final captured = verify(
        () => mockDio.post<Map<String, dynamic>>('/api/tickets', data: captureAny(named: 'data')),
      ).captured;
      final body = captured.first as Map<String, dynamic>;
      expect(body['contractId'], 'con-1');
      expect(body['commessaId'], 'com-1');
      expect(body['cantiereId'], 'can-1');
      expect(body['prodottoAssistenzaIds'], ['prod-1', 'prod-2']);
    });

    test('sends an empty prodottoAssistenzaIds as absent, never as []', () async {
      when(
        () => mockDio.post<Map<String, dynamic>>('/api/tickets', data: any(named: 'data')),
      ).thenAnswer((_) async => _okResponse({'id': 'tick-1'}, '/api/tickets'));

      await client.createTicket(
        title: 'Perdita idrica',
        customerId: 'cust-1',
        locationId: 'loc-1',
        statusId: 1,
        typeId: 2,
        prodottoAssistenzaIds: const [],
      );

      final captured = verify(
        () => mockDio.post<Map<String, dynamic>>('/api/tickets', data: captureAny(named: 'data')),
      ).captured;
      final body = captured.first as Map<String, dynamic>;
      // Null means "no coverage"; a non-null list — even empty — replaces it. A technician who
      // never opened the picker said neither, so the member is not sent at all.
      expect(body.containsKey('prodottoAssistenzaIds'), isFalse);
    });

    test('omits dueDate/technicianNotes/agentId/tags when not provided', () async {
      when(
        () => mockDio.post<Map<String, dynamic>>('/api/tickets', data: any(named: 'data')),
      ).thenAnswer((_) async => _okResponse({'id': 'tick-1'}, '/api/tickets'));

      await client.createTicket(
        title: 'Perdita idrica',
        customerId: 'cust-1',
        locationId: 'loc-1',
        statusId: 1,
        typeId: 2,
      );

      final captured = verify(
        () => mockDio.post<Map<String, dynamic>>('/api/tickets', data: captureAny(named: 'data')),
      ).captured;
      final body = captured.first as Map<String, dynamic>;
      expect(body.containsKey('dueDate'), isFalse);
      expect(body.containsKey('technicianNotes'), isFalse);
      expect(body.containsKey('agentId'), isFalse);
      expect(body.containsKey('tags'), isFalse);
      expect(body.containsKey('contractId'), isFalse);
      expect(body.containsKey('commessaId'), isFalse);
      expect(body.containsKey('cantiereId'), isFalse);
      expect(body.containsKey('prodottoAssistenzaIds'), isFalse);
    });
  });
}
