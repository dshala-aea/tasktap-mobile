// dart format width=100
// Reconciler-mirrored events (server already has them) are pending by construction but never
// uploaded; they must not read as "Non sincronizzato" nor feed the punch/pause guards.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/timbratura/work_session_repository.dart';
import 'package:tasktap_mobile/features/timbra/timbra_providers.dart';

WorkSession _s(String id, String type, {String? notes, bool pending = true}) => WorkSession(
  id: id,
  eventType: type,
  eventTime: DateTime.utc(2026, 11, 5, 9),
  isPendingSync: pending,
  notes: notes,
);

Future<bool> _hasPending(List<WorkSession> sessions) async {
  final c = ProviderContainer(
    overrides: [todaySessionsProvider.overrideWith((ref) => Stream.value(sessions))],
  );
  addTearDown(c.dispose);
  c.listen(todaySessionsProvider, (_, __) {});
  await c.read(todaySessionsProvider.future);
  return c.read(hasPendingSyncProvider);
}

void main() {
  test('reconciler-marked pausa/ripresa do not count as pending sync', () async {
    final r = await _hasPending([
      _s('a', 'ingresso', pending: false),
      _s('b', 'pausa', notes: reconciledOrphanMarker),
      _s('c', 'ripresa', notes: reconciledOrphanMarker),
    ]);
    expect(r, isFalse);
  });

  test('a genuinely unsent event still counts as pending', () async {
    expect(await _hasPending([_s('a', 'pausa')]), isTrue);
  });
}
