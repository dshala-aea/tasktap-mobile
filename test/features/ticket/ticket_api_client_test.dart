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

Response<T> _okResponse<T>(T data, String path) =>
    Response<T>(data: data, statusCode: 200, requestOptions: RequestOptions(path: path));

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
  });
}
