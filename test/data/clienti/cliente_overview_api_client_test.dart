import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/clienti/cliente_overview_api_client.dart';

void main() {
  group('ClienteOverviewDto', () {
    test('reads the fields the local mirror has no columns for', () {
      final dto = ClienteOverviewDto.fromJson({
        'id': 'cust-1',
        'ragioneSociale': 'ACME Srl',
        'attivo': true,
        'partitaIva': '01234567890',
        'codiceFiscale': 'CMEACM80A01F205X',
        'pec': 'acme@pec.it',
        'sdiCode': 'ABCDEF1',
        'provincia': 'MI',
        'sediAttive': 3,
        'contratti': 1,
        'interventiTotali': 42,
        'interventiAperti': 5,
      });

      // These four are the point of the endpoint: none of them exists on the synced customers
      // table, so before this they were simply unanswerable on the device.
      expect(dto.codiceFiscale, 'CMEACM80A01F205X');
      expect(dto.pec, 'acme@pec.it');
      expect(dto.sdiCode, 'ABCDEF1');
      expect(dto.provincia, 'MI');
      expect(dto.interventiAperti, 5);
    });

    test('counts survive being sent as strings', () {
      final dto = ClienteOverviewDto.fromJson({
        'id': 'cust-1',
        'ragioneSociale': 'ACME Srl',
        'attivo': true,
        'sediAttive': '3',
        'contratti': '1',
        'interventiTotali': '42',
        'interventiAperti': '5',
      });

      expect(dto.sediAttive, 3);
      expect(dto.interventiTotali, 42);
    });

    test('a missing count reads as zero rather than throwing', () {
      final dto = ClienteOverviewDto.fromJson({
        'id': 'cust-1',
        'ragioneSociale': 'ACME Srl',
        'attivo': true,
      });

      // Zero is the honest reading here — unlike stockMinimo, where absent means "no minimum
      // configured" and zero would be a different claim.
      expect(dto.sediAttive, 0);
      expect(dto.interventiAperti, 0);
      expect(dto.pec, isNull);
    });

    test('an inactive customer is carried through', () {
      final dto = ClienteOverviewDto.fromJson({
        'id': 'cust-1',
        'ragioneSociale': 'ACME Srl',
        'attivo': false,
        'sediAttive': 0,
        'contratti': 0,
        'interventiTotali': 0,
        'interventiAperti': 0,
      });

      // The mirror's own isActive can lag; a technician about to book work against a deactivated
      // customer should find out on the screen.
      expect(dto.attivo, isFalse);
    });

    test('defaults to active when the server omits the flag', () {
      final dto = ClienteOverviewDto.fromJson({'id': 'c', 'ragioneSociale': 'X'});

      // Erring the other way would paint an inactive warning on every customer the moment the
      // field is renamed.
      expect(dto.attivo, isTrue);
    });
  });
}
