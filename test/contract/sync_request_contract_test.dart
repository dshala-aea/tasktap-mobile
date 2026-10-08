import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Pins the REQUEST side of `GET /api/Sync/mobile`. `checklistTicketIds` is the backend
/// prerequisite of plan 5b (Task 0): until the snapshot declares it, the batched re-request cannot
/// be verified against a real backend and this test says so instead of silently passing.
Map<String, dynamic> _syncGet() {
  final doc = jsonDecode(File('test/contract/openapi.snapshot.json').readAsStringSync())
      as Map<String, dynamic>;
  final path = (doc['paths'] as Map<String, dynamic>)['/api/Sync/mobile'] as Map<String, dynamic>;
  return path['get'] as Map<String, dynamic>;
}

List<Map<String, dynamic>> _params() =>
    (_syncGet()['parameters'] as List).cast<Map<String, dynamic>>();

void main() {
  final shipped = _params().any((p) => p['name'] == 'checklistTicketIds');

  test('GET /api/Sync/mobile still declares since', () {
    expect(_params().map((p) => p['name']), contains('since'));
  });

  test(
    'GET /api/Sync/mobile declares checklistTicketIds as a repeatable query parameter',
    () {
      final param = _params().firstWhere((p) => p['name'] == 'checklistTicketIds');
      expect(param['in'], 'query');
      expect((param['schema'] as Map<String, dynamic>)['type'], 'array');
    },
    skip: shipped
        ? false
        : 'backend prerequisite (plan 5b Task 0) not merged yet: the batched re-request is '
              'unverified against a real backend; the per-ticket REST backfill still works',
  );
}
