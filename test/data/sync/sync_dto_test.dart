import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/sync/sync_dto.dart';

void main() {
  group('TicketDto', () {
    test('TicketDto.fromJson parses cantiereId', () {
      final json = {
        'id': 't1',
        'tenantId': 'tenant1',
        'createdAt': '2026-08-31T00:00:00Z',
        'title': 'Test',
        'customerId': 'c1',
        'locationId': 'l1',
        'statusId': 1,
        'typeId': 1,
        'cantiereId': 'cantiere-1',
      };

      final dto = TicketDto.fromJson(json);

      expect(dto.cantiereId, 'cantiere-1');
    });

    test('TicketDto.fromJson tolerates a missing cantiereId', () {
      final json = {
        'id': 't1',
        'tenantId': 'tenant1',
        'createdAt': '2026-08-31T00:00:00Z',
        'title': 'Test',
        'customerId': 'c1',
        'locationId': 'l1',
        'statusId': 1,
        'typeId': 1,
      };

      final dto = TicketDto.fromJson(json);

      expect(dto.cantiereId, isNull);
    });
  });

  group('SyncTicketMaterialeDto.fromJson', () {
    test('parses a catalog-referenced item', () {
      final json = {
        'id': 'tm1',
        'tenantId': 'tenant1',
        'createdAt': '2026-08-31T00:00:00Z',
        'ticketId': 'ticket1',
        'materialeId': 'mat1',
        'quantity': 2.5,
        'unitOfMeasure': 'pz',
        'isAvailable': true,
      };

      final dto = SyncTicketMaterialeDto.fromJson(json);

      expect(dto.ticketId, 'ticket1');
      expect(dto.materialeId, 'mat1');
      expect(dto.quantity, 2.5);
      expect(dto.isAvailable, isTrue);
    });

    test('parses a free-text item and tolerates missing optional fields', () {
      final json = {
        'id': 'tm2',
        'tenantId': 'tenant1',
        'createdAt': '2026-08-31T00:00:00Z',
        'ticketId': 'ticket1',
        'freeTextName': 'Guarnizione generica',
        'quantity': 1,
      };

      final dto = SyncTicketMaterialeDto.fromJson(json);

      expect(dto.materialeId, isNull);
      expect(dto.freeTextName, 'Guarnizione generica');
      expect(dto.isAvailable, isFalse);
    });
  });
}
