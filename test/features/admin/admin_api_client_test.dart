// test/features/admin/admin_api_client_test.dart
//
// Every create*/update* method in AdminApiClient that expects a created-entity id back from the
// backend must read the actual response shape. The backend's shared `BasicPkResponse` (and the
// one hand-rolled `Ok(new { id = ... })` in SquadreController.Create) both serialize as
// `{"id": "..."}` — never `{"<entityName>Id": "..."}`. Reading the wrong key doesn't just return
// a wrong value, it throws (`null is not a subtype of String`) on every successful create, so the
// technician/admin sees "save failed" for a write that actually succeeded server-side.
//
// This file pins the correct key for every create method that parses an id out of the response,
// so a future copy-paste of this same wrong-key mistake fails a test instead of shipping.
//
// Also covers AdminApiClient.addSquadraMember: backend `SquadraRuoloEnum` (WorkEnums.cs) has no
// [JsonStringEnumConverter] and no `TeamLead` value — it deserializes as a bare integer
// (Membro = 0, Capo = 1). Sending `ruolo` as a JSON string fails deserialization for every
// add-member/change-role call.

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tasktap_mobile/features/admin/admin_api_client.dart';

class MockDio extends Mock implements Dio {}

Response<T> _okResponse<T>(T data, String path) =>
    Response<T>(data: data, statusCode: 200, requestOptions: RequestOptions(path: path));

void main() {
  late MockDio mockDio;
  late AdminApiClient client;

  setUpAll(() {
    registerFallbackValue(RequestOptions(path: '/'));
  });

  setUp(() {
    mockDio = MockDio();
    client = AdminApiClient(mockDio);
  });

  group('create* methods read the backend\'s actual `{"id": ...}` response shape', () {
    test('createCustomer reads "id", not "customerId"', () async {
      when(
        () => mockDio.post<Map<String, dynamic>>('/api/customers', data: any(named: 'data')),
      ).thenAnswer((_) async => _okResponse({'id': 'cust-1'}, '/api/customers'));

      final id = await client.createCustomer(companyName: 'Acme');

      expect(id, 'cust-1');
    });

    test('createLocation reads "id", not "locationId"', () async {
      when(
        () => mockDio.post<Map<String, dynamic>>('/api/locations', data: any(named: 'data')),
      ).thenAnswer((_) async => _okResponse({'id': 'loc-1'}, '/api/locations'));

      final id = await client.createLocation(customerId: 'cust-1', name: 'Sede');

      expect(id, 'loc-1');
    });

    test('createCantiere reads "id", not "cantiereId"', () async {
      when(
        () => mockDio.post<Map<String, dynamic>>('/api/cantieri', data: any(named: 'data')),
      ).thenAnswer((_) async => _okResponse({'id': 'cant-1'}, '/api/cantieri'));

      final id = await client.createCantiere(name: 'Cantiere A');

      expect(id, 'cant-1');
    });

    test('createSchedule reads "id", not "scheduleId"', () async {
      when(
        () => mockDio.post<Map<String, dynamic>>('/api/schedules', data: any(named: 'data')),
      ).thenAnswer((_) async => _okResponse({'id': 'sched-1'}, '/api/schedules'));

      final id = await client.createSchedule(
        activityDate: DateTime(2026, 8, 24),
        timeStartMinutes: 480,
        timeEndMinutes: 600,
        userId: 'u1',
        statusId: 1,
        locationId: 'loc-1',
      );

      expect(id, 'sched-1');
    });

    test('createMateriale reads "id", not "materialId"', () async {
      when(
        () => mockDio.post<Map<String, dynamic>>('/api/materiali', data: any(named: 'data')),
      ).thenAnswer((_) async => _okResponse({'id': 'mat-1'}, '/api/materiali'));

      final id = await client.createMateriale(code: 'M1', name: 'Guarnizione');

      expect(id, 'mat-1');
    });

    test('createProdottoAssistenza reads "id", not "prodottoAssistenzaId"', () async {
      when(
        () => mockDio.post<Map<String, dynamic>>(
          '/api/prodottoassistenza',
          data: any(named: 'data'),
        ),
      ).thenAnswer((_) async => _okResponse({'id': 'prod-1'}, '/api/prodottoassistenza'));

      final id = await client.createProdottoAssistenza(
        name: 'Caldaia',
        customerId: 'cust-1',
        locationId: 'loc-1',
      );

      expect(id, 'prod-1');
    });

    test('createContract reads "id", not "contractId"', () async {
      when(
        () => mockDio.post<Map<String, dynamic>>('/api/contracts', data: any(named: 'data')),
      ).thenAnswer((_) async => _okResponse({'id': 'contr-1'}, '/api/contracts'));

      final id = await client.createContract(
        name: 'Manutenzione annuale',
        customerId: 'cust-1',
        startDate: DateTime(2026, 1, 1),
      );

      expect(id, 'contr-1');
    });

    test('createSquadra reads "id", not "squadraId"', () async {
      when(
        () => mockDio.post<Map<String, dynamic>>('/api/squadre', data: any(named: 'data')),
      ).thenAnswer((_) async => _okResponse({'id': 'sq-1'}, '/api/squadre'));

      final id = await client.createSquadra(nome: 'Squadra Nord');

      expect(id, 'sq-1');
    });
  });

  group('addSquadraMember sends "ruolo" as the integer the backend enum expects', () {
    test('defaults to Membro (0), not a string', () async {
      when(
        () => mockDio.post<dynamic>(any(that: contains('/membri')), data: any(named: 'data')),
      ).thenAnswer((_) async => _okResponse(null, '/api/squadre/sq-1/membri'));

      await client.addSquadraMember('sq-1', userId: 'u1');

      final captured = verify(
        () => mockDio.post<dynamic>(
          '/api/squadre/sq-1/membri',
          data: captureAny(named: 'data'),
        ),
      ).captured;

      final body = captured.first as Map<String, dynamic>;
      expect(body['userId'], 'u1');
      expect(body['ruolo'], 0);
      expect(body['ruolo'], isA<int>());
    });

    test('sends Capo as integer 1', () async {
      when(
        () => mockDio.post<dynamic>('/api/squadre/sq-1/membri', data: any(named: 'data')),
      ).thenAnswer((_) async => _okResponse(null, '/api/squadre/sq-1/membri'));

      await client.addSquadraMember('sq-1', userId: 'u1', ruolo: SquadraRuolo.capo);

      final captured = verify(
        () => mockDio.post<dynamic>(
          '/api/squadre/sq-1/membri',
          data: captureAny(named: 'data'),
        ),
      ).captured;

      final body = captured.first as Map<String, dynamic>;
      expect(body['ruolo'], 1);
    });
  });

  group('updateSquadra', () {
    test('sends isActive so a squadra can be deactivated/reactivated', () async {
      when(
        () => mockDio.put<dynamic>('/api/squadre/sq-1', data: any(named: 'data')),
      ).thenAnswer((_) async => _okResponse(null, '/api/squadre/sq-1'));

      await client.updateSquadra('sq-1', nome: 'Squadra Nord', isActive: false);

      final captured = verify(
        () => mockDio.put<dynamic>('/api/squadre/sq-1', data: captureAny(named: 'data')),
      ).captured;
      final body = captured.first as Map<String, dynamic>;
      expect(body['isActive'], isFalse);
    });
  });

  group('delete* methods', () {
    test('deleteCustomer DELETEs /api/customers/{id}', () async {
      when(
        () => mockDio.delete<dynamic>('/api/customers/cust-1'),
      ).thenAnswer((_) async => _okResponse(null, '/api/customers/cust-1'));

      await client.deleteCustomer('cust-1');

      verify(() => mockDio.delete<dynamic>('/api/customers/cust-1')).called(1);
    });

    test('deleteCantiere DELETEs /api/cantieri/{id}', () async {
      when(
        () => mockDio.delete<dynamic>('/api/cantieri/cant-1'),
      ).thenAnswer((_) async => _okResponse(null, '/api/cantieri/cant-1'));

      await client.deleteCantiere('cant-1');

      verify(() => mockDio.delete<dynamic>('/api/cantieri/cant-1')).called(1);
    });
  });
}
