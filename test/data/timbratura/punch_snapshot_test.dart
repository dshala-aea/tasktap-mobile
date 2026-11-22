// dart format width=100
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tasktap_mobile/data/timbratura/punch_pipeline_flag.dart';
import 'package:tasktap_mobile/data/timbratura/punch_snapshot.dart';
import 'package:tasktap_mobile/data/timbratura/punch_snapshot_providers.dart';
import 'package:tasktap_mobile/data/timbratura/worklog_api_client.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  final since = DateTime.utc(2026, 11, 22, 8, 5);
  final snapshot = PunchSnapshot(
    status: PunchStatus.onBreak,
    shiftStartedAtUtc: since,
    breakStartedAtUtc: DateTime.utc(2026, 11, 22, 12),
    headAtUtc: DateTime.utc(2026, 11, 22, 12),
  );

  group('PunchSnapshotStore', () {
    test('a snapshot survives a cold start', () async {
      await PunchSnapshotStore().write('u1', snapshot);

      final back = await PunchSnapshotStore().read('u1');

      expect(back?.status, PunchStatus.onBreak);
      expect(back?.shiftStartedAtUtc, since);
      expect(back?.breakStartedAtUtc, DateTime.utc(2026, 11, 22, 12));
      expect(back?.headAtUtc, DateTime.utc(2026, 11, 22, 12));
    });

    test('is kept per session: the next person on a shared device does not inherit it', () async {
      await PunchSnapshotStore().write('u1', snapshot);

      expect(await PunchSnapshotStore().read('u2'), isNull);
      expect(await PunchSnapshotStore().read(null), isNull);
    });

    test('a store that throws reads as nothing and never fails the caller', () async {
      final store = PunchSnapshotStore(prefs: () async => throw StateError('no prefs'));
      expect(await store.read('u1'), isNull);
      await store.write('u1', snapshot); // must not throw
    });

    test('an unknown status reads as idle, never as a running shift', () {
      expect(PunchSnapshot.fromJson({'status': 'Weird'}).status, PunchStatus.idle);
    });
  });

  group('PunchStateDto', () {
    test('turns the server state into a snapshot, head included', () {
      final dto = PunchStateDto.fromJson({
        'status': 'Working',
        'shiftStartedAtUtc': '2026-11-22T08:05:00Z',
        'headAtUtc': '2026-11-22T08:05:00Z',
      });

      final s = dto.toSnapshot();

      expect(s.status, PunchStatus.working);
      expect(s.shiftStartedAtUtc, since);
      expect(s.headAtUtc, since);
      expect(s.breakStartedAtUtc, isNull);
    });
  });

  group('PunchSnapshotRefresher', () {
    test('replaces the snapshot with what the server says', () async {
      PunchSnapshot? shown;
      final refresher = PunchSnapshotRefresher(
        fetch: () async => const PunchStateDto(status: 'Idle'),
        onSnapshot: (s) => shown = s,
      );

      await refresher.refresh();

      expect(shown?.status, PunchStatus.idle);
    });

    test('offline or failing: the last snapshot stays and nothing throws', () async {
      PunchSnapshot? shown;
      final refresher = PunchSnapshotRefresher(
        fetch: () async => throw StateError('offline'),
        onSnapshot: (s) => shown = s,
      );

      await refresher.refresh();

      expect(shown, isNull);
    });

    test('a refresh already running is not started twice', () async {
      var calls = 0;
      final refresher = PunchSnapshotRefresher(
        fetch: () async {
          calls++;
          await Future<void>.delayed(const Duration(milliseconds: 30));
          return const PunchStateDto(status: 'Idle');
        },
        onSnapshot: (_) {},
      );

      await Future.wait([refresher.refresh(), refresher.refresh()]);

      expect(calls, 1);
    });
  });

  group('PunchPipelineFlag.watch', () {
    test('gives the current answer, then follows /auth/me changes for that session only', () async {
      final flag = PunchPipelineFlag();
      final seen = <bool>[];
      final sub = flag.watch('u1').listen(seen.add);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      await flag.write('u1', true);
      await flag.write('u2', true); // another session: not ours
      await flag.write('u1', false);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await sub.cancel();

      expect(seen, [false, true, false]);
    });
  });
}
