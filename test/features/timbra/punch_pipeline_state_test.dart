// dart format width=100
// On the unified pipeline the Timbra screen shows the server's last answer with the taps it has not
// answered yet laid on top; on the legacy path, or before the server has answered once, it keeps
// deriving the shift from the local log exactly as before.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/timbratura/punch_pipeline_flag.dart';
import 'package:tasktap_mobile/data/timbratura/punch_snapshot.dart';
import 'package:tasktap_mobile/data/timbratura/punch_snapshot_providers.dart';
import 'package:tasktap_mobile/data/timbratura/work_session_repository.dart';
import 'package:tasktap_mobile/features/timbra/timbra_providers.dart';

class _FixedSnapshot extends PunchSnapshotNotifier {
  _FixedSnapshot(this._value);
  final PunchSnapshot? _value;
  @override
  PunchSnapshot? build() => _value;
}

WorkSession _row(String id, String type, DateTime t, {bool pending = true, String? notes}) =>
    WorkSession(id: id, eventType: type, eventTime: t, notes: notes, isPendingSync: pending);

ProviderContainer _container({
  required bool pipeline,
  PunchSnapshot? snapshot,
  required List<WorkSession> rows,
}) {
  final c = ProviderContainer(
    overrides: [
      punchPipelineActiveProvider.overrideWith((ref) => Stream.value(pipeline)),
      punchSnapshotProvider.overrideWith(() => _FixedSnapshot(snapshot)),
      todaySessionsProvider.overrideWith((ref) => Stream.value(rows)),
      allSessionsProvider.overrideWith((ref) => Stream.value(rows)),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

Future<void> _settle(ProviderContainer c) async {
  c.listen(punchPipelineActiveProvider, (_, _) {});
  c.listen(todaySessionsProvider, (_, _) {});
  c.listen(allSessionsProvider, (_, _) {});
  await Future<void>.delayed(const Duration(milliseconds: 20));
}

void main() {
  final t8 = DateTime.utc(2026, 11, 22, 8);
  final t12 = DateTime.utc(2026, 11, 22, 12);
  const working = PunchSnapshot(status: PunchStatus.working);
  final workingSince8 = PunchSnapshot(status: PunchStatus.working, shiftStartedAtUtc: t8);

  test('on the pipeline the shift comes from the server snapshot, not from the local log', () async {
    // The local log says "idle" (no rows), the server says a shift runs: the screen follows the server.
    final c = _container(pipeline: true, snapshot: workingSince8, rows: const []);
    await _settle(c);

    final shift = c.read(actionableShiftStateProvider);

    expect(shift.isOnShift, isTrue);
    expect(shift.shiftStartTime, t8);
    expect(c.read(timbraStateProvider).isOnShift, isTrue);
  });

  test('a tap the server has not answered yet is laid on top at once', () async {
    final c = _container(
      pipeline: true,
      snapshot: workingSince8,
      rows: [_row('p', 'pausa', t12)],
    );
    await _settle(c);

    final shift = c.read(actionableShiftStateProvider);

    expect(shift.isOnPause, isTrue);
    expect(shift.pauseStartTime, t12);
  });

  test('refused taps and legacy reconciler corrections never count as pending', () async {
    final c = _container(
      pipeline: true,
      snapshot: working,
      rows: [
        _row('refused', 'fine', t12, pending: false, notes: syncFailedMarker),
        _row('legacy', 'fine', t12, notes: reconciledOrphanMarker),
      ],
    );
    await _settle(c);

    expect(c.read(actionableShiftStateProvider).isOnShift, isTrue);
  });

  test('before the server has answered once, the local log is what is shown', () async {
    final c = _container(pipeline: true, snapshot: null, rows: [_row('a', 'ingresso', t8)]);
    await _settle(c);

    expect(c.read(actionableShiftStateProvider).isOnShift, isTrue);
  });

  test('on the legacy path the snapshot is ignored and the local log decides, as before', () async {
    final c = _container(pipeline: false, snapshot: workingSince8, rows: const []);
    await _settle(c);

    expect(c.read(actionableShiftStateProvider).isOnShift, isFalse);
  });
}
