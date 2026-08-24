// dart format width=100
// test/data/reports/ticket_controls_cache_repository_test.dart
//
// The gap: GET /api/tickets/{ticketId}/controls (the rapportino Controlli checklist) had no
// offline cache, unlike materials/staff/photos/signatures/GPS, which all work offline. Going
// offline mid-draft meant TicketDetailOfflineException and nothing to show or answer.
//
// TicketControlsCacheRepository persists the checklist tree the first time it is fetched online;
// `cachedTicketControlsProvider` (same file) wraps the existing (unmodified)
// `ticketControlsProvider` with that cache as a fallback.
//
// Verifies:
//   - the repository round-trips a checklist tree (groups/subgroups/controls) through JSON.
//   - getCachedControls returns null when nothing was ever cached.
//   - cacheControls overwrites (not accumulates) on repeated calls for the same ticket.

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/reports/ticket_controls_cache_repository.dart';
import 'package:tasktap_mobile/features/ticket/ticket_detail_api_client.dart';

AppDatabase _makeDb() => AppDatabase(NativeDatabase.memory());

List<TicketControlGroupDto> _sampleGroups() => [
  TicketControlGroupDto(
    id: 'grp-1',
    name: 'Sezione A',
    description: 'Controlli elettrici',
    sortOrder: 0,
    subgroups: const [],
    controls: [
      TicketControlDto(
        id: 'tc-1',
        templateControlId: 'tpl-1',
        label: 'Pressione OK',
        type: ControlType.checkbox,
        isRequired: true,
        sortOrder: 0,
        status: 'Pending',
        boolValue: true,
      ),
      TicketControlDto(
        id: 'tc-2',
        templateControlId: 'tpl-2',
        label: 'Note aggiuntive',
        type: ControlType.freeText,
        isRequired: false,
        sortOrder: 1,
        status: 'Pending',
        stringValue: 'Tutto regolare',
      ),
    ],
  ),
];

void main() {
  late AppDatabase db;
  late TicketControlsCacheRepository repo;

  setUp(() {
    db = _makeDb();
    repo = TicketControlsCacheRepository(db);
  });

  tearDown(() async => db.close());

  group('cacheControls + getCachedControls', () {
    test('round-trips a checklist tree through JSON', () async {
      await repo.cacheControls('ticket-1', _sampleGroups());

      final cached = await repo.getCachedControls('ticket-1');
      expect(cached, isNotNull);
      expect(cached!.single.name, 'Sezione A');
      expect(cached.single.controls, hasLength(2));
      expect(cached.single.controls[0].label, 'Pressione OK');
      expect(cached.single.controls[0].type, ControlType.checkbox);
      expect(cached.single.controls[0].boolValue, isTrue);
      expect(cached.single.controls[1].type, ControlType.freeText);
      expect(cached.single.controls[1].stringValue, 'Tutto regolare');
    });

    test('returns null when nothing was ever cached for this ticket', () async {
      expect(await repo.getCachedControls('unknown-ticket'), isNull);
    });

    test('overwrites the previous cache for the same ticket rather than accumulating', () async {
      await repo.cacheControls('ticket-1', _sampleGroups());
      await repo.cacheControls('ticket-1', const []);

      final cached = await repo.getCachedControls('ticket-1');
      expect(cached, isEmpty);

      final rows = await db.select(db.cachedTicketControls).get();
      expect(rows, hasLength(1), reason: 'one row per ticket, not one per cache call');
    });

    test('caches for two different tickets independently', () async {
      await repo.cacheControls('ticket-1', _sampleGroups());
      await repo.cacheControls('ticket-2', const []);

      expect((await repo.getCachedControls('ticket-1'))!.length, 1);
      expect(await repo.getCachedControls('ticket-2'), isEmpty);
    });
  });
}
