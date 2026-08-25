import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tasktap_mobile/data/magazzino/magazzino_api_client.dart';

class MockDio extends Mock implements Dio {}

Response<T> _okResponse<T>(T data, String path) =>
    Response<T>(data: data, statusCode: 200, requestOptions: RequestOptions(path: path));

/// The backend declares every decimal on these endpoints as `number|string` in the OpenAPI
/// snapshot, and it does serialise both shapes depending on the path. A client that casts rather
/// than parses throws on the first `"4.0"` and takes the whole stock list with it — on the one
/// screen a technician opens to decide whether to drive to the depot.
void main() {
  group('GiacenzaDto parses either wire shape', () {
    test('numeric quantities', () {
      final dto = GiacenzaDto.fromJson({
        'id': 'g1',
        'magazzinoId': 'm1',
        'materialeId': 'x1',
        'quantita': 4.5,
        'stockMinimo': 2,
        'sottoScorta': false,
        'materialeNome': 'Guarnizione',
        'unitOfMeasure': 'pz',
      });

      expect(dto.quantita, 4.5);
      expect(dto.stockMinimo, 2);
      expect(dto.sottoScorta, isFalse);
      expect(dto.materialeNome, 'Guarnizione');
    });

    test('string quantities', () {
      final dto = GiacenzaDto.fromJson({
        'id': 'g1',
        'magazzinoId': 'm1',
        'materialeId': 'x1',
        'quantita': '4.5',
        'stockMinimo': '2',
        'sottoScorta': true,
      });

      expect(dto.quantita, 4.5);
      expect(dto.stockMinimo, 2);
      expect(dto.sottoScorta, isTrue);
    });

    test('a missing stockMinimo stays null rather than becoming zero', () {
      final dto = GiacenzaDto.fromJson({
        'id': 'g1',
        'magazzinoId': 'm1',
        'materialeId': 'x1',
        'quantita': 1,
        'sottoScorta': false,
      });

      // Zero would read as "the minimum is zero", which is a different and wrong claim from
      // "no minimum is configured" — and it would render as "min 0" beside the quantity.
      expect(dto.stockMinimo, isNull);
    });

    test('sottoScorta is the server verdict, never re-derived', () {
      // Quantity above the minimum, but the server says it is short. The server wins: the
      // threshold rule lives there, and a client that recomputes will drift from the office app.
      final dto = GiacenzaDto.fromJson({
        'id': 'g1',
        'magazzinoId': 'm1',
        'materialeId': 'x1',
        'quantita': 10,
        'stockMinimo': 2,
        'sottoScorta': true,
      });

      expect(dto.sottoScorta, isTrue);
    });
  });

  group('MovimentoDto', () {
    test('parses a transfer with both warehouse ends', () {
      final dto = MovimentoDto.fromJson({
        'id': 'mv1',
        'data': '2026-08-14T09:30:00Z',
        'tipo': 'Trasferimento',
        'materialeId': 'x1',
        'materialeNome': 'Guarnizione',
        'quantita': '3',
        'userId': 'u1',
        'userNome': 'M. Rossi',
        'magazzinoOrigineNome': 'Deposito',
        'magazzinoDestinazioneNome': 'Furgone 1',
      });

      expect(dto.quantita, 3);
      expect(dto.data.toUtc(), DateTime.utc(2026, 8, 14, 9, 30));
      expect(dto.magazzinoOrigineNome, 'Deposito');
      expect(dto.magazzinoDestinazioneNome, 'Furgone 1');
    });

    test('an unparseable date does not take the row down', () {
      final dto = MovimentoDto.fromJson({
        'id': 'mv1',
        'data': 'not-a-date',
        'tipo': 'Carico',
        'materialeId': 'x1',
        'quantita': 1,
        'userId': 'u1',
      });

      expect(dto.id, 'mv1');
    });
  });

  group('PagedResult', () {
    test('reports whether more pages exist', () {
      final page = PagedResult.fromJson({
        'elementi': [
          {'id': 'g1', 'magazzinoId': 'm', 'materialeId': 'x', 'quantita': 1, 'sottoScorta': false},
        ],
        'pagina': 1,
        'dimensionePagina': 50,
        'totaleElementi': 120,
        'totalePagine': 3,
      }, GiacenzaDto.fromJson);

      expect(page.elementi, hasLength(1));
      expect(page.totaleElementi, 120);
      expect(page.hasMore, isTrue);
    });

    test('paging counts survive being sent as strings', () {
      final page = PagedResult.fromJson({
        'elementi': <Map<String, dynamic>>[],
        'pagina': '3',
        'dimensionePagina': '50',
        'totaleElementi': '120',
        'totalePagine': '3',
      }, GiacenzaDto.fromJson);

      expect(page.pagina, 3);
      expect(page.hasMore, isFalse);
    });

    test('an absent elementi list yields an empty page, not a crash', () {
      final page = PagedResult.fromJson({'pagina': 1, 'totalePagine': 0}, GiacenzaDto.fromJson);
      expect(page.elementi, isEmpty);
      expect(page.hasMore, isFalse);
    });
  });

  group('MagazzinoDto.fromJson', () {
    test('parses a furgone', () {
      final dto = MagazzinoDto.fromJson({
        'id': 'm1',
        'nome': 'Furgone Mario',
        'tipo': 'Furgone',
        'assegnatoUserId': 'u1',
        'isActive': true,
      });

      expect(dto.nome, 'Furgone Mario');
      expect(dto.isFurgone, isTrue);
      expect(dto.assegnatoUserId, 'u1');
    });

    test('a Sede is not a furgone', () {
      final dto = MagazzinoDto.fromJson({'id': 'm2', 'nome': 'Sede', 'tipo': 'Sede', 'isActive': true});
      expect(dto.isFurgone, isFalse);
    });
  });

  group('MagazzinoApiClient', () {
    late MockDio mockDio;
    late MagazzinoApiClient client;

    setUpAll(() {
      registerFallbackValue(RequestOptions(path: '/'));
    });

    setUp(() {
      mockDio = MockDio();
      client = MagazzinoApiClient(mockDio);
    });

    test('getFurgoneByUser returns the parsed warehouse when found', () async {
      when(
        () => mockDio.get<Map<String, dynamic>>('/api/magazzino/furgone/u1'),
      ).thenAnswer(
        (_) async => _okResponse({
          'id': 'm1',
          'nome': 'Furgone Mario',
          'tipo': 'Furgone',
          'assegnatoUserId': 'u1',
          'isActive': true,
        }, '/api/magazzino/furgone/u1'),
      );

      final result = await client.getFurgoneByUser('u1');

      expect(result, isNotNull);
      expect(result!.id, 'm1');
      expect(result.nome, 'Furgone Mario');
    });

    // Gap 1's whole fix hinges on this: a technician with no van assigned must not see the
    // rapportino materiali step break — the 404 the backend answers with is a normal outcome
    // (office-only technician), not an error.
    test('getFurgoneByUser returns null on a 404 (no furgone assigned)', () async {
      when(() => mockDio.get<Map<String, dynamic>>('/api/magazzino/furgone/u2')).thenThrow(
        DioException(
          requestOptions: RequestOptions(path: '/api/magazzino/furgone/u2'),
          response: Response(
            statusCode: 404,
            requestOptions: RequestOptions(path: '/api/magazzino/furgone/u2'),
          ),
        ),
      );

      final result = await client.getFurgoneByUser('u2');

      expect(result, isNull);
    });

    test('getFurgoneByUser rethrows on a non-404 failure', () async {
      when(() => mockDio.get<Map<String, dynamic>>('/api/magazzino/furgone/u3')).thenThrow(
        DioException(
          requestOptions: RequestOptions(path: '/api/magazzino/furgone/u3'),
          response: Response(
            statusCode: 403,
            requestOptions: RequestOptions(path: '/api/magazzino/furgone/u3'),
          ),
        ),
      );

      expect(() => client.getFurgoneByUser('u3'), throwsA(isA<DioException>()));
    });

    test('getMagazzini reads the {items: [...]} envelope', () async {
      when(
        () => mockDio.get<Map<String, dynamic>>(
          '/api/magazzino',
          queryParameters: any(named: 'queryParameters'),
        ),
      ).thenAnswer(
        (_) async => _okResponse({
          'items': [
            {'id': 'm1', 'nome': 'Sede centrale', 'tipo': 'Sede', 'isActive': true},
          ],
          'page': 1,
          'pageSize': 200,
          'totalItems': 1,
          'totalPages': 1,
        }, '/api/magazzino'),
      );

      final result = await client.getMagazzini();

      expect(result, hasLength(1));
      expect(result.single.nome, 'Sede centrale');
    });

    test('createMagazzino reads "id", not "magazzinoId"', () async {
      when(
        () => mockDio.post<Map<String, dynamic>>('/api/magazzino', data: any(named: 'data')),
      ).thenAnswer((_) async => _okResponse({'id': 'm9'}, '/api/magazzino'));

      final id = await client.createMagazzino(nome: 'Furgone 2', tipo: 'Furgone');

      expect(id, 'm9');
    });

    test('carico posts materialeId/quantita to the warehouse id in the path', () async {
      when(
        () => mockDio.post<dynamic>('/api/magazzino/m1/carico', data: any(named: 'data')),
      ).thenAnswer((_) async => _okResponse({'message': 'ok'}, '/api/magazzino/m1/carico'));

      await client.carico(magazzinoId: 'm1', materialeId: 'mat1', quantita: 5);

      final captured = verify(
        () => mockDio.post<dynamic>('/api/magazzino/m1/carico', data: captureAny(named: 'data')),
      ).captured.single as Map;
      expect(captured['materialeId'], 'mat1');
      expect(captured['quantita'], 5);
    });

    // Gap 3: an insufficient-stock scarico must surface the server's own error, not be swallowed.
    test('scarico rethrows the DioException on insufficient stock', () async {
      when(
        () => mockDio.post<dynamic>('/api/magazzino/m1/scarico', data: any(named: 'data')),
      ).thenThrow(
        DioException(
          requestOptions: RequestOptions(path: '/api/magazzino/m1/scarico'),
          response: Response(
            statusCode: 400,
            data: 'Stock insufficiente: disponibili 2, richiesti 5',
            requestOptions: RequestOptions(path: '/api/magazzino/m1/scarico'),
          ),
        ),
      );

      expect(
        () => client.scarico(magazzinoId: 'm1', materialeId: 'mat1', quantita: 5),
        throwsA(
          isA<DioException>().having(
            (e) => e.response?.data,
            'data',
            'Stock insufficiente: disponibili 2, richiesti 5',
          ),
        ),
      );
    });

    test('trasferimento posts source, destination and quantity', () async {
      when(
        () => mockDio.post<dynamic>('/api/magazzino/m1/trasferimento', data: any(named: 'data')),
      ).thenAnswer((_) async => _okResponse({'message': 'ok'}, '/api/magazzino/m1/trasferimento'));

      await client.trasferimento(
        magazzinoId: 'm1',
        materialeId: 'mat1',
        quantita: 3,
        magazzinoDestinazioneId: 'm2',
      );

      final captured = verify(
        () => mockDio.post<dynamic>(
          '/api/magazzino/m1/trasferimento',
          data: captureAny(named: 'data'),
        ),
      ).captured.single as Map;
      expect(captured['magazzinoDestinazioneId'], 'm2');
    });

    test('setStockMinimo PUTs to the stock row id, not the warehouse id', () async {
      when(
        () => mockDio.put<dynamic>('/api/magazzino/stock/stock1/stock-minimo', data: any(named: 'data')),
      ).thenAnswer(
        (_) async => _okResponse({'message': 'ok'}, '/api/magazzino/stock/stock1/stock-minimo'),
      );

      await client.setStockMinimo(stockId: 'stock1', stockMinimo: 4);

      final captured = verify(
        () => mockDio.put<dynamic>(
          '/api/magazzino/stock/stock1/stock-minimo',
          data: captureAny(named: 'data'),
        ),
      ).captured.single as Map;
      expect(captured['stockMinimo'], 4);
    });

    test('clearStockMinimo DELETEs the stock row id', () async {
      when(
        () => mockDio.delete<dynamic>('/api/magazzino/stock/stock1/stock-minimo'),
      ).thenAnswer(
        (_) async => _okResponse({'message': 'ok'}, '/api/magazzino/stock/stock1/stock-minimo'),
      );

      await client.clearStockMinimo(stockId: 'stock1');

      verify(() => mockDio.delete<dynamic>('/api/magazzino/stock/stock1/stock-minimo')).called(1);
    });
  });
}
