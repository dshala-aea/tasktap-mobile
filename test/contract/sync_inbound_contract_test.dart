import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/ai/ai_api_client.dart';
import 'package:tasktap_mobile/data/sync/checklist_sync_dto.dart';
import 'package:tasktap_mobile/data/sync/sync_dto.dart';
import 'package:tasktap_mobile/domain/checklist/control_type.dart';

/// The inbound half of the contract gate.
///
/// `openapi_contract_test.dart` proves what the app SENDS. Nothing proved what it READS: a
/// server-side rename of `controlLineageId` would compile, analyse clean and silently parse to
/// null on the phone. Each DTO therefore publishes the exact keys its `fromJson` reads
/// (`wireKeys`); this test compares them with the snapshot in BOTH directions and then parses an
/// instance generated from the snapshot schema itself.
void main() {
  late Map<String, dynamic> schemas;

  setUpAll(() {
    final file = File('test/contract/openapi.snapshot.json');
    expect(file.existsSync(), isTrue, reason: 'run from the mobile/ root');
    final doc = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    schemas =
        (doc['components'] as Map<String, dynamic>)['schemas']
            as Map<String, dynamic>;
  });

  Set<String> props(String name) {
    final s = schemas[name] as Map<String, dynamic>?;
    expect(
      s,
      isNotNull,
      reason:
          'no schema "$name": renamed on the server or the snapshot is stale',
    );
    return ((s!['properties'] as Map<String, dynamic>?) ?? {}).keys.toSet();
  }

  /// A minimal valid instance of a snapshot schema (first enum value, 1, true, a uuid, ...).
  Object? sample(Map<String, dynamic> schema) {
    final ref = schema[r'$ref'] as String?;
    if (ref != null) {
      return sample(schemas[ref.split('/').last] as Map<String, dynamic>);
    }
    if (schema['allOf'] is List) {
      return sample((schema['allOf'] as List).first as Map<String, dynamic>);
    }
    if (schema['enum'] is List) return (schema['enum'] as List).first;
    final type = schema['type'];
    final kinds = (type is List ? type : [type])
        .where((t) => t != 'null')
        .toList();
    switch (kinds.isEmpty ? 'object' : kinds.first) {
      case 'object':
        final p = (schema['properties'] as Map<String, dynamic>?) ?? {};
        return {
          for (final e in p.entries)
            e.key: sample(e.value as Map<String, dynamic>),
        };
      case 'array':
        return [sample(schema['items'] as Map<String, dynamic>)];
      case 'integer':
        return 1;
      case 'number':
        return 1.5;
      case 'boolean':
        return true;
      default:
        return switch (schema['format']) {
          'uuid' => '00000000-0000-0000-0000-000000000001',
          'date-time' => '2026-10-07T08:00:00Z',
          'date' => '2026-10-07',
          _ => 'x',
        };
    }
  }

  Map<String, dynamic> instance(String name) =>
      sample({r'$ref': '#/components/schemas/$name'}) as Map<String, dynamic>;

  // The four reference `Sync*Dto` schemas below (`SyncContractDto`, `SyncCommessaDto`,
  // `SyncProdottoAssistenzaDto`, `SyncAgentDto`) are ahead of `origin/master` in the snapshot.
  // They were produced by backend commit `1950b3d7` on branch `feat/offline-reference-sync`,
  // which is on no origin ref — `origin/master`'s `MobileUserSyncResult` does not declare the
  // `agents`/`commesse`/`contracts`/`prodottiAssistenza` properties these back. When that branch
  // lands, this file's copy becomes a plain fast-forward and the merge procedure in
  // `openapi_contract_test.dart`'s header can go back to a copy. Until then, a refresh must merge
  // (that gate fails by name on either a dropped or a stale side), and this comment is the only
  // record that the contract in the snapshot exists on one unpushed branch.
  // `SyncMaintenanceTemplateDto` and `MaintenanceTemplateOrigin` used to be in the same position,
  // carrying the maintenance-template catalogue behind `MobileUserSyncResult.maintenanceTemplates`;
  // they landed on `origin/master` and the 2026-10-14 re-sync took them from there.
  final readKeys = <String, Set<String>>{
    'SyncControlGroupDto': SyncControlGroupDto.wireKeys,
    'SyncTicketControlDto': SyncTicketControlDto.wireKeys,
    'SyncTicketAssetDto': SyncTicketAssetDto.wireKeys,
    'SyncAssetDto': SyncAssetDto.wireKeys,
    'SyncStrumentoDto': SyncStrumentoDto.wireKeys,
    'SyncReportStrumentoDto': SyncReportStrumentoDto.wireKeys,
    'SyncContractDto': ContractSyncDto.wireKeys,
    'SyncCommessaDto': CommessaSyncDto.wireKeys,
    'SyncProdottoAssistenzaDto': ProdottoAssistenzaSyncDto.wireKeys,
    'SyncAgentDto': AgentSyncDto.wireKeys,
    'SyncMaintenanceTemplateDto': SyncMaintenanceTemplateDto.wireKeys,
    'SyncCantiereCrewAssignmentDto': SyncCantiereCrewAssignmentDto.wireKeys,
    // The I2 confirm response. The draft and resolved shapes are different DTOs, so these are
    // pinned here rather than inferred from the draft summary's classes.
    'AiConversationConfirmResponse': AiConversationConfirmResponse.wireKeys,
    'AiResolvedStaff': AiResolvedStaff.wireKeys,
    'AiResolvedMaterial': AiResolvedMaterial.wireKeys,
    'AiResolvedControl': AiResolvedControl.wireKeys,
  };

  for (final entry in readKeys.entries) {
    test(
      '${entry.key}: the keys fromJson reads are exactly the snapshot properties',
      () {
        final declared = props(entry.key);
        expect(
          entry.value.difference(declared),
          isEmpty,
          reason: 'the app reads keys the server does not declare',
        );
        expect(
          declared.difference(entry.value),
          isEmpty,
          reason:
              'the server declares fields the app never reads: add them or consciously drop them',
        );
      },
    );
  }

  test(
    'MobileUserSyncResult declares every checklist member the app reads',
    () {
      final declared = props('MobileUserSyncResult');
      expect(SyncResultDto.checklistWireKeys.difference(declared), isEmpty);
      expect(SyncResultDto.referenceWireKeys.difference(declared), isEmpty);
    },
  );

  test('the confirm response uses the array names the server declares', () {
    final declared = props('AiConversationConfirmResponse');
    expect(declared, containsAll(['materials', 'controlli']));
    expect(declared, isNot(contains('materiali')));
    expect(declared, isNot(contains('observations')));
    expect(
      declared,
      isNot(contains('isAiAssisted')),
      reason: 'the client owns provenance; a server field that is always absent is a trap',
    );
  });

  test('the confirm response parses an instance generated from the snapshot schema', () {
    final r = AiConversationConfirmResponse.fromJson(
      instance('AiConversationConfirmResponse'),
    );
    expect(r.title, isNotEmpty);
    expect(r.staff, hasLength(1));
    expect(r.materials, hasLength(1));
    expect(r.controlli, hasLength(1));
    expect(r.warnings, hasLength(1));

    // The resolved shapes are the ones the editor's apply path reads, and the free-text material
    // path is the one that reaches a real technician (nothing matched a catalogue).
    final m = AiResolvedMaterial.fromJson(instance('AiResolvedMaterial'));
    expect(m.freeTextName, isNotEmpty);
    final c = AiResolvedControl.fromJson(instance('AiResolvedControl'));
    expect(c.ticketControlId, isNotEmpty);
  });

  test('every DTO parses an instance generated from the snapshot schema', () {
    final g = SyncControlGroupDto.fromJson(instance('SyncControlGroupDto'));
    expect(g.id, isNotEmpty);

    final c = SyncTicketControlDto.fromJson(instance('SyncTicketControlDto'));
    expect(
      c.type,
      ControlType.text,
      reason: 'first enum value of ControlTypeEnum',
    );
    expect(c.controlLineageId, isNotEmpty);

    final a = SyncAssetDto.fromJson(instance('SyncAssetDto'));
    expect(a.librettoIds, hasLength(1));

    final s = SyncStrumentoDto.fromJson(instance('SyncStrumentoDto'));
    expect(s.calibrationExpiry, DateTime.utc(2026, 10, 7));

    final rs = SyncReportStrumentoDto.fromJson(
      instance('SyncReportStrumentoDto'),
    );
    expect(rs.calibrationExpiry, DateTime.utc(2026, 10, 7));
    // The two per-instrument notes are read off the snapshot sample, not just listed in wireKeys.
    expect(rs.usageDescription, isA<String>());
    expect(rs.outcome, isA<String>());

    SyncTicketAssetDto.fromJson(instance('SyncTicketAssetDto'));

    final ct = ContractSyncDto.fromJson(instance('SyncContractDto'));
    expect(ct.tipo, 1);

    final cm = CommessaSyncDto.fromJson(instance('SyncCommessaDto'));
    expect(cm.codice, isNotEmpty);

    final pa = ProdottoAssistenzaSyncDto.fromJson(
      instance('SyncProdottoAssistenzaDto'),
    );
    expect(pa.locationId, isNotEmpty);

    final ag = AgentSyncDto.fromJson(instance('SyncAgentDto'));
    expect(ag.nome, isNotEmpty);

    final mt = SyncMaintenanceTemplateDto.fromJson(
      instance('SyncMaintenanceTemplateDto'),
    );
    expect(mt.id, isNotEmpty);
    expect(mt.origin, 'System', reason: 'first enum value of MaintenanceTemplateOrigin');
    expect(mt.latestPublishedVersion, 1);
  });

  test(
    'the sync result parses the checklist members, and keeps older payloads distinguishable',
    () {
      // Only the new members are generated: `Report`/`Ticket` samples are entity graphs the other
      // tests in this repo already cover with real fixtures.
      final full = SyncResultDto.fromJson({
        'syncedAt': '2026-10-07T08:00:00Z',
        'since': null,
        'controlGroups': [instance('SyncControlGroupDto')],
        'ticketControls': [instance('SyncTicketControlDto')],
        'ticketAssets': [instance('SyncTicketAssetDto')],
        'assets': [instance('SyncAssetDto')],
        'strumenti': [instance('SyncStrumentoDto')],
        'reportStrumenti': [instance('SyncReportStrumentoDto')],
        'checklistTruncated': true,
        'checklistOmittedTicketIds': ['00000000-0000-0000-0000-000000000001'],
        'contracts': [instance('SyncContractDto')],
        'commesse': [instance('SyncCommessaDto')],
        'prodottiAssistenza': [instance('SyncProdottoAssistenzaDto')],
        'agents': [instance('SyncAgentDto')],
        'maintenanceTemplates': [instance('SyncMaintenanceTemplateDto')],
        // Present-but-empty is enough for the flag: what the applier does with the rows is
        // covered in test/data/sync/sync_ticket_materiali_test.dart.
        'ticketMateriali': <Object>[],
      });
      expect(full.carriesChecklist, isTrue);
      expect(full.carriesStrumenti, isTrue);
      expect(full.carriesContracts, isTrue);
      expect(full.carriesCommesse, isTrue);
      expect(full.carriesProdottiAssistenza, isTrue);
      expect(full.carriesAgents, isTrue);
      expect(full.carriesMaintenanceTemplates, isTrue);
      expect(full.carriesTicketMateriali, isTrue);
      expect(full.ticketControls, hasLength(1));
      expect(full.checklistTruncated, isTrue);
      expect(full.checklistOmittedTicketIds, [
        '00000000-0000-0000-0000-000000000001',
      ]);

      final older = SyncResultDto.fromJson({
        'syncedAt': '2026-10-07T08:00:00Z',
        'since': null,
      });
      expect(
        older.carriesChecklist,
        isFalse,
        reason: 'an older backend must NOT look like "the checklist is empty"',
      );
      expect(older.carriesStrumenti, isFalse);
      expect(older.checklistTruncated, isFalse);
      expect(older.checklistOmittedTicketIds, isEmpty);
      expect(
        older.carriesContracts,
        isFalse,
        reason:
            'an older backend must NOT look like "every contract was deleted"',
      );
      expect(older.carriesCommesse, isFalse);
      expect(older.carriesProdottiAssistenza, isFalse);
      expect(older.carriesAgents, isFalse);
      expect(
        older.carriesMaintenanceTemplates,
        isFalse,
        reason:
            'an older backend must NOT look like "every maintenance template was deleted"',
      );
      expect(
        older.carriesTicketMateriali,
        isFalse,
        reason:
            'an older backend must NOT look like "every fabbisogno was cleared"',
      );
    },
  );

  test(
    'numbers the server may send as strings (int32 / decimal) still parse',
    () {
      final json = instance('SyncTicketControlDto')
        ..['sortOrder'] = '3'
        ..['numberValue'] = '2.5';
      final c = SyncTicketControlDto.fromJson(json);
      expect(c.sortOrder, 3);
      expect(c.numberValue, 2.5);
    },
  );
}
