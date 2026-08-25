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

    // Gap 5 of the feature audit: mobile admin previously never let you deactivate a materiale.
    test('deleteMateriale DELETEs /api/materiali/{id} (soft-delete server-side)', () async {
      when(
        () => mockDio.delete<dynamic>('/api/materiali/mat-1'),
      ).thenAnswer((_) async => _okResponse(null, '/api/materiali/mat-1'));

      await client.deleteMateriale('mat-1');

      verify(() => mockDio.delete<dynamic>('/api/materiali/mat-1')).called(1);
    });
  });

  // Gap 5 of the feature audit: AliquotaIVA had no mobile field at all.
  group('materiale AliquotaIVA', () {
    test('createMateriale sends aliquotaIVA', () async {
      when(
        () => mockDio.post<Map<String, dynamic>>('/api/materiali', data: any(named: 'data')),
      ).thenAnswer((_) async => _okResponse({'id': 'mat-1'}, '/api/materiali'));

      await client.createMateriale(code: 'M1', name: 'Guarnizione', aliquotaIva: 22);

      final captured = verify(
        () => mockDio.post<Map<String, dynamic>>('/api/materiali', data: captureAny(named: 'data')),
      ).captured.single as Map;
      expect(captured['aliquotaIVA'], 22);
    });

    test('updateMateriale sends a 0.00 aliquotaIVA (reverse-charge/exempt), not omitting it', () async {
      when(
        () => mockDio.put<dynamic>('/api/materiali/mat-1', data: any(named: 'data')),
      ).thenAnswer((_) async => _okResponse(null, '/api/materiali/mat-1'));

      await client.updateMateriale('mat-1', aliquotaIva: 0);

      final captured = verify(
        () => mockDio.put<dynamic>('/api/materiali/mat-1', data: captureAny(named: 'data')),
      ).captured.single as Map;
      expect(captured['aliquotaIVA'], 0);
    });
  });

  group('materiale barcodes (Gap 5)', () {
    test('fetchMaterialeBarcodes reads the bare array GET returns', () async {
      when(() => mockDio.get<List<dynamic>>('/api/materiali/mat-1/barcodes')).thenAnswer(
        (_) async => _okResponse([
          {'id': 'b1', 'barcode': '123456', 'barcodeType': 'EAN13', 'isPrimary': true},
        ], '/api/materiali/mat-1/barcodes'),
      );

      final result = await client.fetchMaterialeBarcodes('mat-1');

      expect(result, hasLength(1));
      expect(result.single['barcode'], '123456');
    });

    test('addMaterialeBarcode posts barcode/type/isPrimary', () async {
      when(
        () => mockDio.post<dynamic>('/api/materiali/mat-1/barcodes', data: any(named: 'data')),
      ).thenAnswer((_) async => _okResponse(null, '/api/materiali/mat-1/barcodes'));

      await client.addMaterialeBarcode('mat-1', barcode: '999', barcodeType: 'EAN13', isPrimary: true);

      final captured = verify(
        () =>
            mockDio.post<dynamic>('/api/materiali/mat-1/barcodes', data: captureAny(named: 'data')),
      ).captured.single as Map;
      expect(captured['barcode'], '999');
      expect(captured['isPrimary'], isTrue);
    });

    test('deleteMaterialeBarcode DELETEs the barcode sub-resource', () async {
      when(
        () => mockDio.delete<dynamic>('/api/materiali/mat-1/barcodes/b1'),
      ).thenAnswer((_) async => _okResponse(null, '/api/materiali/mat-1/barcodes/b1'));

      await client.deleteMaterialeBarcode('mat-1', 'b1');

      verify(() => mockDio.delete<dynamic>('/api/materiali/mat-1/barcodes/b1')).called(1);
    });

    test('setPrimaryMaterialeBarcode PUTs the /primary sub-route', () async {
      when(
        () => mockDio.put<dynamic>('/api/materiali/mat-1/barcodes/b1/primary'),
      ).thenAnswer((_) async => _okResponse(null, '/api/materiali/mat-1/barcodes/b1/primary'));

      await client.setPrimaryMaterialeBarcode('mat-1', 'b1');

      verify(() => mockDio.put<dynamic>('/api/materiali/mat-1/barcodes/b1/primary')).called(1);
    });
  });

  group('materiale image (Gap 5)', () {
    test('uploadMaterialeImage reads contentUrl from the response', () async {
      when(
        () => mockDio.post<Map<String, dynamic>>(
          '/api/materiali/mat-1/image',
          data: any(named: 'data'),
          options: any(named: 'options'),
        ),
      ).thenAnswer(
        (_) async => _okResponse({
          'allegatoId': 'a1',
          'contentUrl': '/api/materiali/mat-1/image/content',
        }, '/api/materiali/mat-1/image'),
      );

      final url = await client.uploadMaterialeImage(
        'mat-1',
        bytes: [1, 2, 3],
        fileName: 'foto.jpg',
        contentType: 'image/jpeg',
      );

      expect(url, '/api/materiali/mat-1/image/content');
    });

    test('deleteMaterialeImage DELETEs /api/materiali/{id}/image', () async {
      when(
        () => mockDio.delete<dynamic>('/api/materiali/mat-1/image'),
      ).thenAnswer((_) async => _okResponse(null, '/api/materiali/mat-1/image'));

      await client.deleteMaterialeImage('mat-1');

      verify(() => mockDio.delete<dynamic>('/api/materiali/mat-1/image')).called(1);
    });
  });

  group('fetchMaterialeDetail (Gap 5 prefill)', () {
    test('reads the full MaterialeWithBarcodesDto envelope', () async {
      when(() => mockDio.get<Map<String, dynamic>>('/api/materiali/mat-1')).thenAnswer(
        (_) async => _okResponse({
          'id': 'mat-1',
          'code': 'M1',
          'name': 'Guarnizione',
          'aliquotaIVA': 22.0,
          'barcodes': <Map<String, dynamic>>[],
        }, '/api/materiali/mat-1'),
      );

      final detail = await client.fetchMaterialeDetail('mat-1');

      expect(detail?['aliquotaIVA'], 22.0);
    });
  });

  // Cantieri module #8, Gap 1: contacts CRUD (UpsertCantiereContactRequest fields — name/role/
  // phone/email/notes, camelCase per CantieriController.cs:386-393).
  group('cantiere contacts (Gap 1)', () {
    test('addCantiereContact posts to the contacts sub-route and reads "id"', () async {
      when(
        () => mockDio.post<Map<String, dynamic>>(
          '/api/cantieri/cant-1/contacts',
          data: any(named: 'data'),
        ),
      ).thenAnswer((_) async => _okResponse({'id': 'contact-1'}, '/api/cantieri/cant-1/contacts'));

      final id = await client.addCantiereContact('cant-1', name: 'Mario Rossi', phone: '333123');

      expect(id, 'contact-1');
      final captured = verify(
        () => mockDio.post<Map<String, dynamic>>(
          '/api/cantieri/cant-1/contacts',
          data: captureAny(named: 'data'),
        ),
      ).captured.single as Map;
      expect(captured['name'], 'Mario Rossi');
      expect(captured['phone'], '333123');
    });

    test('updateCantiereContact PUTs the contact sub-resource', () async {
      when(
        () => mockDio.put<dynamic>(
          '/api/cantieri/cant-1/contacts/contact-1',
          data: any(named: 'data'),
        ),
      ).thenAnswer(
        (_) async => _okResponse(null, '/api/cantieri/cant-1/contacts/contact-1'),
      );

      await client.updateCantiereContact('cant-1', 'contact-1', name: 'Mario Rossi', role: 'Titolare');

      final captured = verify(
        () => mockDio.put<dynamic>(
          '/api/cantieri/cant-1/contacts/contact-1',
          data: captureAny(named: 'data'),
        ),
      ).captured.single as Map;
      expect(captured['name'], 'Mario Rossi');
      expect(captured['role'], 'Titolare');
    });

    test('deleteCantiereContact DELETEs the contact sub-resource', () async {
      when(
        () => mockDio.delete<dynamic>('/api/cantieri/cant-1/contacts/contact-1'),
      ).thenAnswer((_) async => _okResponse(null, '/api/cantieri/cant-1/contacts/contact-1'));

      await client.deleteCantiereContact('cant-1', 'contact-1');

      verify(() => mockDio.delete<dynamic>('/api/cantieri/cant-1/contacts/contact-1')).called(1);
    });
  });

  // Cantieri module #8, Gap 2: crew/assignment CRUD (CreateCantiereAssignmentRequest — userId
  // (required)/role/startDate/endDate, CantieriController.cs:395-400).
  group('cantiere assignments (Gap 2)', () {
    test('addCantiereAssignment posts userId and reads "id"', () async {
      when(
        () => mockDio.post<Map<String, dynamic>>(
          '/api/cantieri/cant-1/assignments',
          data: any(named: 'data'),
        ),
      ).thenAnswer(
        (_) async => _okResponse({'id': 'assign-1'}, '/api/cantieri/cant-1/assignments'),
      );

      final id = await client.addCantiereAssignment('cant-1', userId: 'user-1', role: 'Elettricista');

      expect(id, 'assign-1');
      final captured = verify(
        () => mockDio.post<Map<String, dynamic>>(
          '/api/cantieri/cant-1/assignments',
          data: captureAny(named: 'data'),
        ),
      ).captured.single as Map;
      expect(captured['userId'], 'user-1');
      expect(captured['role'], 'Elettricista');
    });

    test('removeCantiereAssignment DELETEs the assignment sub-resource', () async {
      when(
        () => mockDio.delete<dynamic>('/api/cantieri/cant-1/assignments/assign-1'),
      ).thenAnswer((_) async => _okResponse(null, '/api/cantieri/cant-1/assignments/assign-1'));

      await client.removeCantiereAssignment('cant-1', 'assign-1');

      verify(
        () => mockDio.delete<dynamic>('/api/cantieri/cant-1/assignments/assign-1'),
      ).called(1);
    });
  });

  // Cantieri module #8, Gap 6: read-only linked-records sections (ore/interventi/rapportini) on
  // the cantiere detail screen — all live fetches, none of these are synced to Drift.
  group('cantiere linked records (Gap 6)', () {
    test('fetchCantiereDetail GETs /api/cantieri/{id} (contacts + assignments envelope)', () async {
      when(() => mockDio.get<Map<String, dynamic>>('/api/cantieri/cant-1')).thenAnswer(
        (_) async => _okResponse({
          'cantiere': {'id': 'cant-1', 'name': 'Cantiere A'},
          'contacts': <Map<String, dynamic>>[],
          'assignments': <Map<String, dynamic>>[],
        }, '/api/cantieri/cant-1'),
      );

      final detail = await client.fetchCantiereDetail('cant-1');

      expect(detail?['contacts'], isEmpty);
      expect(detail?['assignments'], isEmpty);
    });

    test('fetchCantiereTickets GETs /api/tickets filtered by cantiereId', () async {
      when(
        () => mockDio.get<Map<String, dynamic>>(
          '/api/tickets',
          queryParameters: any(named: 'queryParameters'),
        ),
      ).thenAnswer(
        (_) async => _okResponse({
          'items': [
            {'id': 't1', 'title': 'Guasto quadro'},
          ],
        }, '/api/tickets'),
      );

      final tickets = await client.fetchCantiereTickets('cant-1');

      expect(tickets, hasLength(1));
      final captured = verify(
        () => mockDio.get<Map<String, dynamic>>(
          '/api/tickets',
          queryParameters: captureAny(named: 'queryParameters'),
        ),
      ).captured.single as Map;
      expect(captured['cantiereId'], 'cant-1');
    });

    test('fetchCantiereWorkLogs GETs /api/cantiereworklog filtered by cantiereId', () async {
      when(
        () => mockDio.get<Map<String, dynamic>>(
          '/api/cantiereworklog',
          queryParameters: any(named: 'queryParameters'),
        ),
      ).thenAnswer(
        (_) async => _okResponse({
          'items': [
            {'id': 'wl1', 'workDate': '2026-08-20T00:00:00Z'},
          ],
        }, '/api/cantiereworklog'),
      );

      final logs = await client.fetchCantiereWorkLogs('cant-1');

      expect(logs, hasLength(1));
      final captured = verify(
        () => mockDio.get<Map<String, dynamic>>(
          '/api/cantiereworklog',
          queryParameters: captureAny(named: 'queryParameters'),
        ),
      ).captured.single as Map;
      expect(captured['cantiereId'], 'cant-1');
    });

    test('fetchReports sends cantiereId when provided, omits it otherwise', () async {
      when(
        () => mockDio.get<Map<String, dynamic>>(
          '/api/reports',
          queryParameters: any(named: 'queryParameters'),
        ),
      ).thenAnswer((_) async => _okResponse({'items': <Map<String, dynamic>>[]}, '/api/reports'));

      await client.fetchReports(cantiereId: 'cant-1');

      final captured = verify(
        () => mockDio.get<Map<String, dynamic>>(
          '/api/reports',
          queryParameters: captureAny(named: 'queryParameters'),
        ),
      ).captured.single as Map;
      expect(captured['cantiereId'], 'cant-1');
    });
  });

  // Cantieri module #8, Gap 5: Cantiere.CommessaId existed on the backend entity but neither
  // CreateCantiereRequest nor UpdateCantiereRequest accepted it (fixed backend-side in af9039c,
  // "Accept CommessaId on cantiere create/update") — until then a mobile field here would have
  // silently no-opped, so it was deliberately left unbuilt in the prior pass.
  group('cantiere commessa (Gap 5)', () {
    test('createCantiere sends commessaId when provided', () async {
      when(
        () => mockDio.post<Map<String, dynamic>>('/api/cantieri', data: any(named: 'data')),
      ).thenAnswer((_) async => _okResponse({'id': 'cant-1'}, '/api/cantieri'));

      await client.createCantiere(name: 'Cantiere A', commessaId: 'commessa-1');

      final captured = verify(
        () => mockDio.post<Map<String, dynamic>>('/api/cantieri', data: captureAny(named: 'data')),
      ).captured.single as Map;
      expect(captured['commessaId'], 'commessa-1');
    });

    test('createCantiere omits commessaId when not provided', () async {
      when(
        () => mockDio.post<Map<String, dynamic>>('/api/cantieri', data: any(named: 'data')),
      ).thenAnswer((_) async => _okResponse({'id': 'cant-1'}, '/api/cantieri'));

      await client.createCantiere(name: 'Cantiere A');

      final captured = verify(
        () => mockDio.post<Map<String, dynamic>>('/api/cantieri', data: captureAny(named: 'data')),
      ).captured.single as Map;
      expect(captured.containsKey('commessaId'), isFalse);
    });

    test('updateCantiere sends commessaId when provided', () async {
      when(
        () => mockDio.put<dynamic>('/api/cantieri/cant-1', data: any(named: 'data')),
      ).thenAnswer((_) async => _okResponse(null, '/api/cantieri/cant-1'));

      await client.updateCantiere('cant-1', name: 'Cantiere A', commessaId: 'commessa-1');

      final captured = verify(
        () => mockDio.put<dynamic>('/api/cantieri/cant-1', data: captureAny(named: 'data')),
      ).captured.single as Map;
      expect(captured['commessaId'], 'commessa-1');
    });

    test('fetchCommesse GETs /api/commesse and reads the paginated envelope', () async {
      when(
        () => mockDio.get<Map<String, dynamic>>('/api/commesse'),
      ).thenAnswer(
        (_) async => _okResponse({
          'items': [
            {'id': 'commessa-1', 'codice': 'COM-001', 'descrizione': 'Manutenzione annuale'},
          ],
        }, '/api/commesse'),
      );

      final commesse = await client.fetchCommesse();

      expect(commesse, hasLength(1));
      expect(commesse.single['codice'], 'COM-001');
    });
  });

  // Gap 3 of the feature audit: create/update already existed for Locations, delete did not.
  group('deleteLocation (Gap 3)', () {
    test('DELETEs /api/locations/{id}', () async {
      when(
        () => mockDio.delete<dynamic>('/api/locations/loc-1'),
      ).thenAnswer((_) async => _okResponse(null, '/api/locations/loc-1'));

      await client.deleteLocation('loc-1');

      verify(() => mockDio.delete<dynamic>('/api/locations/loc-1')).called(1);
    });
  });

  // Gap 7/8 of the feature audit: a customer's Contratti/Prodotti sections need the backend's own
  // customerId filter, not a client-side filter over an unpaginated (default 20-item) fetch.
  group('customer-scoped fetches (Gap 7/8)', () {
    test('fetchContracts sends customerId as a query param when given', () async {
      when(
        () => mockDio.get<Map<String, dynamic>>(
          '/api/contracts',
          queryParameters: any(named: 'queryParameters'),
        ),
      ).thenAnswer((_) async => _okResponse({'items': <dynamic>[]}, '/api/contracts'));

      await client.fetchContracts(customerId: 'cust-1');

      final captured = verify(
        () => mockDio.get<Map<String, dynamic>>(
          '/api/contracts',
          queryParameters: captureAny(named: 'queryParameters'),
        ),
      ).captured.single as Map;
      expect(captured['customerId'], 'cust-1');
    });

    test('fetchContracts omits customerId when not given', () async {
      when(
        () => mockDio.get<Map<String, dynamic>>(
          '/api/contracts',
          queryParameters: any(named: 'queryParameters'),
        ),
      ).thenAnswer((_) async => _okResponse({'items': <dynamic>[]}, '/api/contracts'));

      await client.fetchContracts();

      final captured = verify(
        () => mockDio.get<Map<String, dynamic>>(
          '/api/contracts',
          queryParameters: captureAny(named: 'queryParameters'),
        ),
      ).captured.single as Map;
      expect(captured.containsKey('customerId'), isFalse);
    });

    test('fetchProdottiAssistenza sends customerId as a query param when given', () async {
      when(
        () => mockDio.get<Map<String, dynamic>>(
          '/api/prodottoassistenza',
          queryParameters: any(named: 'queryParameters'),
        ),
      ).thenAnswer((_) async => _okResponse({'items': <dynamic>[]}, '/api/prodottoassistenza'));

      await client.fetchProdottiAssistenza(customerId: 'cust-1');

      final captured = verify(
        () => mockDio.get<Map<String, dynamic>>(
          '/api/prodottoassistenza',
          queryParameters: captureAny(named: 'queryParameters'),
        ),
      ).captured.single as Map;
      expect(captured['customerId'], 'cust-1');
    });
  });

  // Feature audit module #10 (Prodotti/Servizi), Gaps 1/2/7: mobile only ever sent the original
  // scaffold field set. The backend's commercial fields (W6b Task 6 migration
  // AddProdottoAssistenzaCommercialFields) and lifecycle fields (W6b Task 6) use Italian wire
  // names via [JsonPropertyName] that don't match their Dart param names — `marca` → "marchio",
  // `code` → "codice", `category` → "categoria", `unitOfMeasure` → "um", `purchasePrice` →
  // "prezzoAcquisto", `salePrice` → "prezzoVendita" — everything else (modello/tipo/
  // dataInstallazione/ultimaManutenzione/prossimaManutenzione/contrattoId/externalId) is already
  // camelCase-identical between Dart and wire. See ProdottoAssistenza.cs:23-89 and
  // ProdottoAssistenzaController.cs:318-391 (Create/UpdateProdottoAssistenzaRequest).
  group('ProdottoAssistenza commercial + lifecycle fields (Gaps 1/2/7)', () {
    test('createProdottoAssistenza sends every new field under its Italian wire name', () async {
      when(
        () => mockDio.post<Map<String, dynamic>>(
          '/api/prodottoassistenza',
          data: any(named: 'data'),
        ),
      ).thenAnswer((_) async => _okResponse({'id': 'prod-1'}, '/api/prodottoassistenza'));

      await client.createProdottoAssistenza(
        name: 'Caldaia',
        customerId: 'cust-1',
        locationId: 'loc-1',
        code: 'PROD-001',
        category: 'Riscaldamento',
        unitOfMeasure: 'pz',
        purchasePrice: 100.5,
        salePrice: 199.9,
        marca: 'Baxi',
        modello: 'ECO5',
        tipo: 'Caldaia',
        dataInstallazione: DateTime(2024, 1, 15),
        ultimaManutenzione: DateTime(2025, 6, 1),
        prossimaManutenzione: DateTime(2026, 6, 1),
        contrattoId: 'contr-1',
        externalId: 'EXT-42',
      );

      final captured = verify(
        () => mockDio.post<Map<String, dynamic>>(
          '/api/prodottoassistenza',
          data: captureAny(named: 'data'),
        ),
      ).captured.single as Map;
      expect(captured['codice'], 'PROD-001');
      expect(captured['categoria'], 'Riscaldamento');
      expect(captured['um'], 'pz');
      expect(captured['prezzoAcquisto'], 100.5);
      expect(captured['prezzoVendita'], 199.9);
      expect(captured['marchio'], 'Baxi');
      expect(captured['modello'], 'ECO5');
      expect(captured['tipo'], 'Caldaia');
      expect(captured['dataInstallazione'], DateTime(2024, 1, 15).toIso8601String());
      expect(captured['ultimaManutenzione'], DateTime(2025, 6, 1).toIso8601String());
      expect(captured['prossimaManutenzione'], DateTime(2026, 6, 1).toIso8601String());
      expect(captured['contrattoId'], 'contr-1');
      expect(captured['externalId'], 'EXT-42');
      // Never "marca" — that's the wire name for Materiale's brand field, not this entity's.
      expect(captured.containsKey('marca'), isFalse);
    });

    test('createProdottoAssistenza omits the new fields entirely when not given', () async {
      when(
        () => mockDio.post<Map<String, dynamic>>(
          '/api/prodottoassistenza',
          data: any(named: 'data'),
        ),
      ).thenAnswer((_) async => _okResponse({'id': 'prod-1'}, '/api/prodottoassistenza'));

      await client.createProdottoAssistenza(name: 'Caldaia', customerId: 'cust-1', locationId: 'loc-1');

      final captured = verify(
        () => mockDio.post<Map<String, dynamic>>(
          '/api/prodottoassistenza',
          data: captureAny(named: 'data'),
        ),
      ).captured.single as Map;
      for (final key in [
        'codice',
        'categoria',
        'um',
        'prezzoAcquisto',
        'prezzoVendita',
        'marchio',
        'modello',
        'tipo',
        'dataInstallazione',
        'ultimaManutenzione',
        'prossimaManutenzione',
        'contrattoId',
        'externalId',
      ]) {
        expect(captured.containsKey(key), isFalse, reason: '"$key" should be omitted');
      }
    });

    test('updateProdottoAssistenza sends isActive and every new field under its wire name', () async {
      when(
        () => mockDio.put<dynamic>('/api/prodottoassistenza/prod-1', data: any(named: 'data')),
      ).thenAnswer((_) async => _okResponse(null, '/api/prodottoassistenza/prod-1'));

      await client.updateProdottoAssistenza(
        'prod-1',
        isActive: false,
        code: 'PROD-001',
        category: 'Riscaldamento',
        unitOfMeasure: 'pz',
        purchasePrice: 100.5,
        salePrice: 199.9,
        marca: 'Baxi',
        modello: 'ECO5',
        tipo: 'Caldaia',
        contrattoId: 'contr-1',
        externalId: 'EXT-42',
      );

      final captured = verify(
        () => mockDio.put<dynamic>('/api/prodottoassistenza/prod-1', data: captureAny(named: 'data')),
      ).captured.single as Map;
      expect(captured['isActive'], isFalse);
      expect(captured['codice'], 'PROD-001');
      expect(captured['categoria'], 'Riscaldamento');
      expect(captured['um'], 'pz');
      expect(captured['prezzoAcquisto'], 100.5);
      expect(captured['prezzoVendita'], 199.9);
      expect(captured['marchio'], 'Baxi');
      expect(captured['modello'], 'ECO5');
      expect(captured['tipo'], 'Caldaia');
      expect(captured['contrattoId'], 'contr-1');
      expect(captured['externalId'], 'EXT-42');
    });
  });

  // Gap 5: ProdottoAssistenza had no delete anywhere on mobile despite the backend's hard-delete
  // endpoint existing (ProdottoAssistenzaController.cs:230-247).
  group('deleteProdottoAssistenza (Gap 5)', () {
    test('DELETEs /api/prodottoassistenza/{id}', () async {
      when(
        () => mockDio.delete<dynamic>('/api/prodottoassistenza/prod-1'),
      ).thenAnswer((_) async => _okResponse(null, '/api/prodottoassistenza/prod-1'));

      await client.deleteProdottoAssistenza('prod-1');

      verify(() => mockDio.delete<dynamic>('/api/prodottoassistenza/prod-1')).called(1);
    });
  });

  // Gap 3: Matricole — real 1:N serial-number sub-resource, previously entirely absent on mobile
  // (ProdottoAssistenzaController.cs:253-313: GET/POST .../matricole, DELETE .../matricole/{id}).
  group('Matricole (Gap 3)', () {
    test('fetchMatricole GETs the bare array the backend returns', () async {
      when(() => mockDio.get<List<dynamic>>('/api/prodottoassistenza/prod-1/matricole')).thenAnswer(
        (_) async => _okResponse([
          {'id': 'm1', 'numero': 'SN-001', 'note': null},
        ], '/api/prodottoassistenza/prod-1/matricole'),
      );

      final result = await client.fetchMatricole('prod-1');

      expect(result, hasLength(1));
      expect(result.single['numero'], 'SN-001');
    });

    test('addMatricola posts numero/note and reads "id"', () async {
      when(
        () => mockDio.post<Map<String, dynamic>>(
          '/api/prodottoassistenza/prod-1/matricole',
          data: any(named: 'data'),
        ),
      ).thenAnswer(
        (_) async =>
            _okResponse({'id': 'm1'}, '/api/prodottoassistenza/prod-1/matricole'),
      );

      final id = await client.addMatricola('prod-1', numero: 'SN-001', note: 'Unità esterna');

      expect(id, 'm1');
      final captured = verify(
        () => mockDio.post<Map<String, dynamic>>(
          '/api/prodottoassistenza/prod-1/matricole',
          data: captureAny(named: 'data'),
        ),
      ).captured.single as Map;
      expect(captured['numero'], 'SN-001');
      expect(captured['note'], 'Unità esterna');
    });

    test('addMatricola omits note when not given', () async {
      when(
        () => mockDio.post<Map<String, dynamic>>(
          '/api/prodottoassistenza/prod-1/matricole',
          data: any(named: 'data'),
        ),
      ).thenAnswer(
        (_) async =>
            _okResponse({'id': 'm1'}, '/api/prodottoassistenza/prod-1/matricole'),
      );

      await client.addMatricola('prod-1', numero: 'SN-001');

      final captured = verify(
        () => mockDio.post<Map<String, dynamic>>(
          '/api/prodottoassistenza/prod-1/matricole',
          data: captureAny(named: 'data'),
        ),
      ).captured.single as Map;
      expect(captured.containsKey('note'), isFalse);
    });

    test('deleteMatricola DELETEs the matricola sub-resource', () async {
      when(
        () => mockDio.delete<dynamic>('/api/prodottoassistenza/prod-1/matricole/m1'),
      ).thenAnswer(
        (_) async => _okResponse(null, '/api/prodottoassistenza/prod-1/matricole/m1'),
      );

      await client.deleteMatricola('prod-1', 'm1');

      verify(() => mockDio.delete<dynamic>('/api/prodottoassistenza/prod-1/matricole/m1')).called(1);
    });
  });
}
