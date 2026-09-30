// dart format width=100
// visibleTrackersProvider: the server is the authority for a clock started on ANOTHER device;
// this device's local state wins only while it holds events the server has not seen yet.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/worklogs/active_tracker_api_client.dart';
import 'package:tasktap_mobile/features/dashboard/active_trackers_provider.dart';
import 'package:tasktap_mobile/features/timbra/timbra_providers.dart';

import '../../support/active_tracker_fixtures.dart';

WorkSession _s(String id, String type, DateTime t, {bool pending = false}) =>
    WorkSession(id: id, eventType: type, eventTime: t, isPendingSync: pending);

final _shift = DateTime.utc(2026, 9, 30, 8, 23, 45);
final _break = DateTime.utc(2026, 9, 30, 11, 2, 10);

Future<List<ActiveTracker>> _visible({
  required List<ActiveTracker> server,
  required List<WorkSession> local,
}) async {
  final c = ProviderContainer(
    overrides: [
      activeTrackersProvider.overrideWith((ref) => Stream.value(server)),
      todaySessionsProvider.overrideWith((ref) => Stream.value(local)),
    ],
  );
  addTearDown(c.dispose);
  c.listen(visibleTrackersProvider, (_, _) {});
  await c.read(activeTrackersProvider.future);
  await c.read(todaySessionsProvider.future);
  await pumpEventQueue();
  return c.read(visibleTrackersProvider);
}

void main() {
  test('local off + server Working => the attendance tracker is visible (other device)', () async {
    final v = await _visible(server: trackersFromWire([attendanceWorkingJson]), local: const []);

    final att = v.singleWhere((t) => t.kind == ActiveTrackerKind.attendance);
    expect(att.state, ActiveTrackerState.working);
    expect(att.startedAtUtc.difference(_shift).inSeconds.abs(), lessThan(1));
  });

  test('server OnBreak => tracker carries OnBreak and ticks from the break start', () async {
    final v = await _visible(server: trackersFromWire([attendanceOnBreakJson]), local: const []);

    final att = v.single;
    expect(att.state, ActiveTrackerState.onBreak);
    expect(att.startedAtUtc, _break);
    expect(att.elapsedAt(DateTime.utc(2026, 9, 30, 11, 12, 10)), const Duration(minutes: 10));
  });

  test('local on shift with unsynced events wins over a stale server view', () async {
    final localStart = DateTime.utc(2026, 9, 30, 10);
    final v = await _visible(
      server: trackersFromWire([attendanceOnBreakJson]),
      local: [_s('i', 'ingresso', localStart, pending: true)],
    );

    final att = v.single;
    expect(att.state, ActiveTrackerState.working);
    expect(att.startedAtUtc, localStart);
  });

  test('local off with a pending stop hides the server row (offline clock-out)', () async {
    final v = await _visible(
      server: trackersFromWire([attendanceWorkingJson]),
      local: [
        _s('i', 'ingresso', _shift),
        _s('f', 'fine', DateTime.utc(2026, 9, 30, 12), pending: true),
      ],
    );
    expect(v.where((t) => t.kind == ActiveTrackerKind.attendance), isEmpty);
  });

  test('a synced local stop newer than the server row hides it until the server catches up', () async {
    final v = await _visible(
      server: trackersFromWire([attendanceWorkingJson]),
      local: [_s('i', 'ingresso', _shift), _s('f', 'fine', DateTime.utc(2026, 9, 30, 12))],
    );
    expect(v.where((t) => t.kind == ActiveTrackerKind.attendance), isEmpty);
  });

  test('a shift started elsewhere AFTER a local stop is shown', () async {
    final v = await _visible(
      server: trackersFromWire([attendanceWorkingJson]),
      local: [
        _s('i', 'ingresso', DateTime.utc(2026, 9, 30, 6)),
        _s('f', 'fine', DateTime.utc(2026, 9, 30, 7)),
      ],
    );
    expect(v.single.kind, ActiveTrackerKind.attendance);
  });

  test('offline (server list empty) a locally running synced shift stays visible', () async {
    final v = await _visible(server: const [], local: [_s('i', 'ingresso', _shift)]);
    expect(v.single.kind, ActiveTrackerKind.attendance);
    expect(v.single.startedAtUtc, _shift);
  });

  test('local OnBreak yields an OnBreak tracker timed from the local pause start', () async {
    final v = await _visible(
      server: const [],
      local: [_s('i', 'ingresso', _shift), _s('p', 'pausa', _break)],
    );
    expect(v.single.state, ActiveTrackerState.onBreak);
    expect(v.single.startedAtUtc, _break);
  });

  test('cantiere rows are untouched', () async {
    final v = await _visible(server: trackersFromWire([cantiereJson]), local: const []);
    expect(v.single.kind, ActiveTrackerKind.cantiere);
  });
}
