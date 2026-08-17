import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/magazzino/magazzino_api_client.dart';

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
}
