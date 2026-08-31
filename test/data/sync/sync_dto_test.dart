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
}
