import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
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

  final readKeys = <String, Set<String>>{
    'SyncControlGroupDto': SyncControlGroupDto.wireKeys,
    'SyncTicketControlDto': SyncTicketControlDto.wireKeys,
    'SyncTicketAssetDto': SyncTicketAssetDto.wireKeys,
    'SyncAssetDto': SyncAssetDto.wireKeys,
    'SyncStrumentoDto': SyncStrumentoDto.wireKeys,
    'SyncReportStrumentoDto': SyncReportStrumentoDto.wireKeys,
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
    },
  );

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

    SyncTicketAssetDto.fromJson(instance('SyncTicketAssetDto'));
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
      });
      expect(full.carriesChecklist, isTrue);
      expect(full.carriesStrumenti, isTrue);
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
