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
import 'package:tasktap_mobile/core/time/business_time.dart';
import 'package:tasktap_mobile/data/timbratura/remote_shift.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/timbratura/timbra_sync_service.dart';
import 'package:tasktap_mobile/data/timbratura/work_session_repository.dart';
import 'package:tasktap_mobile/data/timbratura/worklog_api_client.dart';
import 'package:tasktap_mobile/features/timbra/timbra_providers.dart';

/// The repository window is the REAL Italian business day (BusinessTime.fallback(), fed by the
/// live clock), so every fixture must anchor to that same clock — but never to a bare
/// `now - N`: that lands in the PREVIOUS business day during the first N of the day, and
/// `getTodaySessions()` then returns nothing by design while the test expects an open shift.
/// [_earlierToday] clamps such a seed forward to the day's own start, the one instant that is
/// inside today and never after now.
DateTime _earlierToday(Duration ago) {
  final bt = BusinessTime.fallback();
  final start = bt.utcRangeForBusinessDate(bt.businessToday()).$1;
  final candidate = DateTime.now().toUtc().subtract(ago);
  return candidate.isAfter(start) ? candidate : start;
}

class _Api extends WorklogApiClient {
  _Api() : super(Dio());
  final calls = <String>[];
  @override
  Future<void> endWork({DateTime? deviceUtc}) async => calls.add('end');
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
    final start = _earlierToday(const Duration(hours: 1));
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
      eventTime: _earlierToday(const Duration(hours: 1)),
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
    // The opener must be (a) ahead of the phone's clock — that is the premise — and (b) inside
    // TODAY's business day, because `getTodaySessions()` is the window `local()`, `punch()` and
    // the assertion all read. Five minutes ahead breaks (b) in the last five minutes of the Rome
    // day: the fine then lands in tomorrow's window and the assertion finds no `fine` at all.
    // Two seconds is the same scenario at the precision the one-second floor works at, and only
    // the final three seconds of the day can still straddle midnight.
    final phoneNow = DateTime.now().toUtc();
    final opener = DateTime.utc(
      phoneNow.year,
      phoneNow.month,
      phoneNow.day,
      phoneNow.hour,
      phoneNow.minute,
      phoneNow.second,
    ).add(const Duration(seconds: 2)); // server ahead of phone
    await repo.addEvent(id: 'remote-i', eventTime: opener, eventType: 'ingresso');
    await repo.markReconciledOrphan('remote-i');
    final n = notifier();
    await n.punch(await local());

    final fine = (await repo.getTodaySessions()).firstWhere((s) => s.eventType == 'fine');
    expect(fine.eventTime.isAtSameMomentAs(opener.add(const Duration(seconds: 1))), isTrue);
    expect((await local()).isOnShift, isFalse);
  });
}
