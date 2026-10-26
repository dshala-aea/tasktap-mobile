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

    // Field-parity gap: Ticket.Tags is on the wire (same sync response every other field here
    // comes from), mobile never parsed it.
    test('TicketDto.fromJson parses tags', () {
      final json = {
        'id': 't1',
        'tenantId': 'tenant1',
        'createdAt': '2026-08-31T00:00:00Z',
        'title': 'Test',
        'customerId': 'c1',
        'locationId': 'l1',
        'statusId': 1,
        'typeId': 1,
        'tags': ['urgente', 'garanzia'],
      };

      final dto = TicketDto.fromJson(json);

      expect(dto.tags, ['urgente', 'garanzia']);
    });

    test('TicketDto.fromJson defaults tags to an empty list when missing', () {
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

      expect(dto.tags, isEmpty);
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

  group('ScheduleDto.isAssenza', () {
    Map<String, dynamic> json({Object? isAssenza = #absent}) => {
      'id': 's1',
      'tenantId': 'tenant1',
      'createdAt': '2026-10-24T00:00:00Z',
      'activityDate': '2026-10-24T00:00:00Z',
      'timeStart': '00:00:00',
      'timeEnd': '00:00:00',
      'userId': 'u1',
      'statusId': 1,
      'locationId': 'loc-1',
      'allDay': true,
      'title': 'ferie',
      'description': '',
      if (isAssenza != #absent) 'isAssenza': isAssenza,
    };

    test('parses an absence-owned row', () {
      expect(ScheduleDto.fromJson(json(isAssenza: true)).isAssenza, isTrue);
    });

    test('a job reads as a job', () {
      expect(ScheduleDto.fromJson(json(isAssenza: false)).isAssenza, isFalse);
    });

    // An older backend does not send the key at all. Reading every row as a job is the behaviour
    // the app had before the flag existed — a guess in the other direction would empty the day.
    test('is false when the key is absent (older backend)', () {
      expect(ScheduleDto.fromJson(json()).isAssenza, isFalse);
    });
  });

  group('CustomerDto.agentId', () {
    Map<String, dynamic> json({Object? agentId = #absent}) => {
      'id': 'c1',
      'tenantId': 'tenant1',
      'createdAt': '2026-10-16T00:00:00Z',
      'companyName': 'ACME Srl',
      if (agentId != #absent) 'agentId': agentId,
    };

    test('parses the agent when present', () {
      expect(CustomerDto.fromJson(json(agentId: 'ag-1')).agentId, 'ag-1');
    });

    test('is null when the key is absent (older backend)', () {
      expect(CustomerDto.fromJson(json()).agentId, isNull);
    });

    test('is null when the server sends an explicit null', () {
      expect(CustomerDto.fromJson(json(agentId: null)).agentId, isNull);
    });
  });
}
