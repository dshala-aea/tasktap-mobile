import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/reports/submit_report_request.dart';

/// Checks what the app actually puts on the wire against the API's own OpenAPI snapshot.
///
/// **Why this file exists.** Mobile sent `controlId` where the server reads `ticketControlId` for
/// months. Nothing caught it: the app compiled, the analyzer was clean, and the unit test named
/// "mirrors backend SubmitReportControlloDto fields" asserted the Dart class against itself. A
/// field name is invisible to every check that only looks at one side of the wire.
///
/// The office web has had this gate since it started generating its client from the snapshot.
/// Mobile hand-writes its DTOs, so it had nothing — and that is exactly where the break happened.
///
/// **What it can and cannot prove.** An unknown key is a real break: the server binds a missing
/// non-nullable field to its default (`Guid.Empty` for an id), which either fails validation or,
/// worse, binds something meaningless. That direction is asserted hard.
///
/// A key the app *omits* is usually just a feature it does not have yet, so that direction is
/// reported rather than failed — but it is reported, because "the app silently never sends this"
/// is how a field quietly stays unimplemented. Types are not checked; this catches names.
///
/// **Refreshing:** `cp ../docs/api/openapi.snapshot.json test/contract/openapi.snapshot.json`.
/// A diff here after an API change is the point — it means a rename reached the client.
void main() {
  late Map<String, dynamic> schemas;

  setUpAll(() {
    final file = File('test/contract/openapi.snapshot.json');
    expect(
      file.existsSync(),
      isTrue,
      reason: 'run from the mobile/ root; see the refresh command in this file’s header',
    );
    final doc = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    schemas = (doc['components'] as Map<String, dynamic>)['schemas'] as Map<String, dynamic>;
  });

  Set<String> propertiesOf(String schemaName) {
    final schema = schemas[schemaName] as Map<String, dynamic>?;
    expect(
      schema,
      isNotNull,
      reason:
          'no schema "$schemaName" in the snapshot — renamed on the server, or the snapshot is stale',
    );
    return ((schema!['properties'] as Map<String, dynamic>?) ?? {}).keys.toSet();
  }

  /// Every key the app sends must exist on the server's schema.
  void expectNoUnknownKeys(String schemaName, Map<String, dynamic> payload) {
    final known = propertiesOf(schemaName);
    final unknown = payload.keys.where((k) => !known.contains(k)).toList()..sort();
    expect(
      unknown,
      isEmpty,
      reason:
          'sent to $schemaName but not in its schema. The server ignores these and binds its '
          'own fields to defaults — a non-nullable Guid becomes Guid.Empty, which belongs to '
          'nothing and fails ownership checks. Known: ${(known.toList()..sort()).join(', ')}',
    );
  }

  /// Not a failure — a ledger of fields the app never sends, so a gap is visible rather than assumed.
  void reportUnsentFields(String schemaName, Map<String, dynamic> payload) {
    final unsent = propertiesOf(schemaName).where((k) => !payload.containsKey(k)).toList()..sort();
    if (unsent.isNotEmpty) {
      printOnFailure('$schemaName: app never sends ${unsent.join(', ')}');
    }
  }

  group('rapportino submission matches the API schema', () {
    /// Every optional field populated — an all-nulls payload would assert nothing, because
    /// `toJson` drops what it has no value for and the unknown-key check would see an empty map.
    final fullRequest = SubmitReportRequest(
      id: '00000000-0000-0000-0000-000000000001',
      scheduleId: '00000000-0000-0000-0000-000000000002',
      ticketId: '00000000-0000-0000-0000-000000000003',
      locationId: '00000000-0000-0000-0000-000000000004',
      title: 'Manutenzione',
      details: 'dettagli',
      technicianNotes: 'note',
      startedAt: DateTime.utc(2026, 6, 15, 8),
      endedAt: DateTime.utc(2026, 6, 15, 12),
      customerSignatureAllegatoId: '00000000-0000-0000-0000-000000000005',
      technicianSignatureAllegatoId: '00000000-0000-0000-0000-000000000006',
      customerSignoffText: 'accettato',
      materialiNotRequired: false,
      photoAllegatoIds: const ['00000000-0000-0000-0000-000000000007'],
      staff: const [SubmitReportStaffDto(userId: '00000000-0000-0000-0000-000000000008')],
      materiali: const [SubmitReportMaterialeDto(quantity: 2)],
      controlli: const [SubmitReportControlloDto(ticketControlId: 'ctrl-1', boolValue: true)],
    );

    test('SubmitReportRequest sends no field the server does not have', () {
      final json = fullRequest.toJson();
      expectNoUnknownKeys('SubmitReportRequest', json);
      reportUnsentFields('SubmitReportRequest', json);
    });

    test('SubmitReportControlloDto sends no field the server does not have', () {
      final json = (fullRequest.toJson()['controlli'] as List).first as Map<String, dynamic>;
      expectNoUnknownKeys('SubmitReportControlloDto', json);
    });

    test('SubmitReportMaterialeDto sends no field the server does not have', () {
      final json = (fullRequest.toJson()['materiali'] as List).first as Map<String, dynamic>;
      expectNoUnknownKeys('SubmitReportMaterialeDto', json);
    });

    test('SubmitReportStaffDto sends no field the server does not have', () {
      final json = (fullRequest.toJson()['staff'] as List).first as Map<String, dynamic>;
      expectNoUnknownKeys('SubmitReportStaffDto', json);
    });

    /// The regression itself, stated against the server's schema rather than against our own class.
    test('the control answer names the ticket control the server reads', () {
      expect(propertiesOf('SubmitReportControlloDto'), contains('ticketControlId'));
      final json = (fullRequest.toJson()['controlli'] as List).first as Map<String, dynamic>;
      expect(json.keys, contains('ticketControlId'));
    });
  });
}
