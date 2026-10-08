import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/sync/sync_dto.dart';

void main() {
  // The full member set a current backend sends. Build this from sync_dto.dart's own required
  // members — if a new required member lands, this helper must be updated with it, which is the
  // point of writing it out rather than using `{}`.
  Map<String, dynamic> minimal() => {
    'syncedAt': '2026-10-08T08:00:00Z',
    'since': null,
    'schedules': <Object>[],
    'draftReports': <Object>[],
    'customers': <Object>[],
    'locations': <Object>[],
    'tickets': <Object>[],
    'materiali': <Object>[],
    'cantieri': <Object>[],
    'ticketStatuses': <Object>[],
    'ticketTypes': <Object>[],
    'colleagues': <Object>[],
  };

  test('the four reference members parse', () {
    final p = SyncResultDto.fromJson({
      ...minimal(),
      'contracts': [
        {
          'id': 'c1',
          'tenantId': 't',
          'createdAt': '2026-10-01T00:00:00Z',
          'updatedAt': null,
          'name': 'Manutenzione',
          'customerId': 'cu',
          'locationId': null,
          'startDate': '2026-01-01T00:00:00Z',
          'endDate': null,
          'isActive': true,
          'numero': 'N-1',
          'codice': null,
          'tipo': 0,
          'externalId': null,
        },
      ],
      'commesse': [
        {
          'id': 'm1',
          'tenantId': 't',
          'createdAt': '2026-10-01T00:00:00Z',
          'updatedAt': null,
          'codice': 'C-1',
          'descrizione': null,
          'customerId': 'cu',
          'isActive': true,
          'stato': null,
          'externalId': null,
        },
      ],
      'prodottiAssistenza': [
        {
          'id': 'p1',
          'tenantId': 't',
          'createdAt': '2026-10-01T00:00:00Z',
          'updatedAt': null,
          'name': 'Caldaia',
          'customerId': 'cu',
          'locationId': 'l',
          'isActive': true,
          'codice': 'P-1',
          'serialNumber': null,
          'categoria': null,
          'marchio': null,
          'externalId': null,
        },
      ],
      'agents': [
        {
          'id': 'a1',
          'tenantId': 't',
          'createdAt': '2026-10-01T00:00:00Z',
          'updatedAt': null,
          'nome': 'Rossi',
          'email': null,
          'cellulare': null,
          'isActive': true,
        },
      ],
    });

    expect(p.contracts.single.name, 'Manutenzione');
    expect(p.contracts.single.tipo, 0);
    expect(p.commesse.single.codice, 'C-1');
    expect(p.prodottiAssistenza.single.categoria, isNull);
    expect(p.agents.single.nome, 'Rossi');
    expect(
      [
        p.carriesContracts,
        p.carriesCommesse,
        p.carriesProdottiAssistenza,
        p.carriesAgents,
      ],
      [true, true, true, true],
    );
  });

  test('a numeric-string tipo parses, and an unparseable one is null and not 0', () {
    // int32 may arrive as a JSON number or a numeric string (see checklist_sync_dto.dart). The
    // contract test's sample() generator strips 'null' from the union and takes the first concrete
    // kind, so it generates only `tipo: 1` and would not catch an `as int?` cast.
    ContractSyncDto parse(Object? tipo) => ContractSyncDto.fromJson({
      'id': 'c1',
      'tenantId': 't',
      'createdAt': '2026-10-01T00:00:00Z',
      'updatedAt': null,
      'name': 'Manutenzione',
      'customerId': 'cu',
      'locationId': null,
      'startDate': '2026-01-01T00:00:00Z',
      'endDate': null,
      'isActive': true,
      'numero': 'N-1',
      'codice': null,
      'tipo': tipo,
      'externalId': null,
    });

    expect(parse('3').tipo, 3);
    expect(parse(null).tipo, isNull);
  });

  /// The discipline the checklist members already established, and the reason the scoped prune is
  /// safe: a backend that predates this feature sends none of the four keys, and the client must
  /// treat that as "nothing to say", not as "every reference row was deleted".
  test('an older backend leaves every carries flag false', () {
    final p = SyncResultDto.fromJson(minimal());

    expect(
      [
        p.carriesContracts,
        p.carriesCommesse,
        p.carriesProdottiAssistenza,
        p.carriesAgents,
      ],
      [false, false, false, false],
    );
    expect(p.contracts, isEmpty);
  });

  test(
    'a missing isActive defaults to active, matching the server default',
    () {
      final p = SyncResultDto.fromJson({
        ...minimal(),
        'agents': [
          {
            'id': 'a1',
            'tenantId': 't',
            'createdAt': '2026-10-01T00:00:00Z',
            'updatedAt': null,
            'nome': 'Rossi',
            'email': null,
            'cellulare': null,
          },
        ],
      });

      expect(p.agents.single.isActive, isTrue);
    },
  );
}
