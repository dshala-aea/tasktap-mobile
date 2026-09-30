// dart format width=100
// Fine / Pausa / Ripresa on a shift started on another device are ONLINE-ONLY: the server stamps
// its own clock, so an offline tap would be recorded at delivery time (paid time / midnight
// WorkDate wrong). Offline they are refused with an Italian message and local state is unchanged.
// A locally started shift keeps working offline.
import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' show AsyncData, AsyncError;
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/timbratura/remote_shift.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/timbratura/timbra_sync_service.dart';
import 'package:tasktap_mobile/data/timbratura/work_session_repository.dart';
import 'package:tasktap_mobile/data/timbratura/worklog_api_client.dart';
import 'package:tasktap_mobile/features/timbra/timbra_providers.dart';

class _Api extends WorklogApiClient {
  _Api() : super(Dio());
  final calls = <String>[];
  @override
  Future<void> endWork() async => calls.add('end');
  @override
  Future<void> startBreak() async => calls.add('break/start');
  @override
  Future<void> endBreak() async => calls.add('break/end');
  @override
  Future<List<UpsertSessionResponse>> upsertSessions(List<MobileSessionDto> s) async {
    calls.add('batch');
    return [];
  }
}

void main() {
  late AppDatabase db;
  late WorkSessionRepository repo;
  late _Api api;
  var online = true;

  PunchNotifier notifier() => PunchNotifier(
    repo,
    TimbraSyncService(repo: repo, apiClient: api),
    null,
    () async => online,
  );

  Future<TimbraState> local() async => deriveShiftState(await repo.getTodaySessions());

  Future<void> seedRemoteShift() async {
    final start = DateTime.now().toUtc().subtract(const Duration(hours: 1));
    await repo.addEvent(id: 'remote-i', eventTime: start, eventType: 'ingresso');
    await repo.markReconciledOrphan('remote-i');
  }

  setUp(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    db = AppDatabase(NativeDatabase.memory());
    repo = WorkSessionRepository(db);
    api = _Api();
    online = true;
  });
  tearDown(() => db.close());

  test('offline Fine on a remote shift: refused, nothing recorded, state unchanged', () async {
    await seedRemoteShift();
    online = false;
    final n = notifier();
    await n.punch(await local());

    expect(n.state, isA<AsyncError<void>>());
    expect((n.state as AsyncError).error, isA<OfflineRemoteShiftException>());
    expect(
      (n.state as AsyncError).error.toString(),
      'Sei offline: per fermare o mettere in pausa un turno avviato su un altro dispositivo '
      'serve la connessione',
    );
    expect((await repo.getTodaySessions()), hasLength(1));
    expect((await local()).isOnShift, isTrue);
  });

  test('offline Pausa on a remote shift is refused too', () async {
    await seedRemoteShift();
    online = false;
    final n = notifier();
    await n.togglePause(await local());
    expect((n.state as AsyncError).error, isA<OfflineRemoteShiftException>());
    expect((await local()).isOnPause, isFalse);
  });

  test('online, the tap is recorded and executed at once against the server', () async {
    await seedRemoteShift();
    final n = notifier();
    await n.togglePause(await local());
    await pumpEventQueue();

    expect((await local()).isOnPause, isTrue);
    expect(api.calls, ['break/start']);
  });

  test('a locally started shift still works fully offline (queued for the batch)', () async {
    await repo.addEvent(
      id: 'own-i',
      eventTime: DateTime.now().toUtc().subtract(const Duration(hours: 1)),
      eventType: 'ingresso',
    );
    online = false;
    final n = notifier();
    await n.punch(await local());

    expect(n.state, isA<AsyncData<void>>());
    expect((await local()).isOnShift, isFalse);
  });

  test('starting a shift offline is not gated', () async {
    online = false;
    final n = notifier();
    await n.punch(await local());
    expect(n.state, isA<AsyncData<void>>());
    expect((await local()).isOnShift, isTrue);
  });

  test('a Fine on a remote shift is never stamped before its opener (phone clock behind the server)', () async {
    final n0 = DateTime.now().toUtc().add(const Duration(minutes: 5)); // server ahead of phone
    final opener = DateTime.utc(n0.year, n0.month, n0.day, n0.hour, n0.minute, n0.second);
    await repo.addEvent(id: 'remote-i', eventTime: opener, eventType: 'ingresso');
    await repo.markReconciledOrphan('remote-i');
    final n = notifier();
    await n.punch(await local());

    final fine = (await repo.getTodaySessions()).firstWhere((s) => s.eventType == 'fine');
    expect(fine.eventTime.isAtSameMomentAs(opener.add(const Duration(seconds: 1))), isTrue);
    expect((await local()).isOnShift, isFalse);
  });
}
