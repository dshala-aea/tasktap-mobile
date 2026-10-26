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

  group('TicketDto.prodottoAssistenzaIds', () {
    Map<String, dynamic> json({Object? ids = #absent}) => {
      'id': 't1',
      'tenantId': 'tenant1',
      'createdAt': '2026-08-31T00:00:00Z',
      'title': 'Test',
      'customerId': 'c1',
      'locationId': 'l1',
      'statusId': 1,
      'typeId': 1,
      if (ids != #absent) 'prodottoAssistenzaIds': ids,
    };

    test('parses the units the ticket covers', () {
      expect(
        TicketDto.fromJson(json(ids: ['pa-1', 'pa-2'])).prodottoAssistenzaIds,
        ['pa-1', 'pa-2'],
      );
    });

    test('defaults to an empty list, not null, when the key is absent', () {
      // The server has always sent it (the entity fills it from the join table), so an absent key
      // means an older backend. Empty keeps one shape for the writer, which encodes it as `[]`.
      expect(TicketDto.fromJson(json()).prodottoAssistenzaIds, isEmpty);
    });

    test('keeps an empty list as an empty list', () {
      expect(TicketDto.fromJson(json(ids: <String>[])).prodottoAssistenzaIds, isEmpty);
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

  group('ReportDto.numero', () {
    Map<String, dynamic> json({Object? numero = #absent}) => {
      'id': 'r1',
      'tenantId': 'tenant1',
      'createdAt': '2026-10-24T00:00:00Z',
      'title': 'Rapportino caldaia',
      'insertedUserId': 'u1',
      'locationId': 'l1',
      'stato': 'Bozza',
      if (numero != #absent) 'numero': numero,
    };

    test('parses the human number when the server has assigned one', () {
      expect(ReportDto.fromJson(json(numero: 'RAP-2026-0042')).numero, 'RAP-2026-0042');
    });

    test('is null for a draft the server has not numbered yet', () {
      expect(ReportDto.fromJson(json()).numero, isNull);
      expect(ReportDto.fromJson(json(numero: null)).numero, isNull);
    });
  });
}
