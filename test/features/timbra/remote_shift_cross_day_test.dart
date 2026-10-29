// dart format width=100
// Fine / Pausa / Ripresa on a shift whose opener is from a PREVIOUS business day.
//
// `punch()` is documented to act on `actionableShiftStateProvider` (the whole local log), so its
// remote-shift guards must read the same horizon. Read day-scoped, an opener recorded at 22:00
// before midnight is invisible by 00:10: the offline tap is not refused, and the anti-negative
// clamp has no opener to hold the `fine` after — a phone clock behind the server then stamps the
// stop before the opener, the interval sorts shut, and the shift still reads as running.
import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' show AsyncData, AsyncError;
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/core/time/business_time.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/timbratura/remote_shift.dart';
import 'package:tasktap_mobile/data/timbratura/timbra_sync_service.dart';
import 'package:tasktap_mobile/data/timbratura/work_session_repository.dart';
import 'package:tasktap_mobile/data/timbratura/worklog_api_client.dart';
import 'package:tasktap_mobile/features/timbra/timbra_providers.dart';

class _Api extends WorklogApiClient {
  _Api() : super(Dio());
  final calls = <String>[];
  @override
  Future<int?> endWork({DateTime? deviceUtc}) async {
    calls.add('end');
    return null;
  }

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

  final bt = BusinessTime.fallback();

  PunchNotifier notifier() => PunchNotifier(
    repo,
    TimbraSyncService(repo: repo, apiClient: api),
    null,
    () async => online,
  );

  /// The state the control is DRAWN from, and the one `punch()` is documented to receive.
  Future<TimbraState> wide() async => deriveShiftState(await repo.getAllSessions());

  /// 22:00 on the business day before today: outside `getTodaySessions()`, inside the whole log.
  DateTime lastNightAt2200() => bt.todayRangeUtc().$1.subtract(const Duration(hours: 2));

  Future<void> seedRemoteOpener(DateTime at) async {
    await repo.addEvent(id: 'remote-i', eventTime: at, eventType: 'ingresso');
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

  test('offline Fine on a shift opened before midnight: refused, nothing recorded', () async {
    await seedRemoteOpener(lastNightAt2200());
    expect(await repo.getTodaySessions(), isEmpty, reason: 'sanity: the opener is not today');
    online = false;
    final n = notifier();

    await n.punch(await wide());

    expect(n.state, isA<AsyncError<void>>());
    expect((n.state as AsyncError).error, isA<OfflineRemoteShiftException>());
    expect(await repo.getAllSessions(), hasLength(1), reason: 'no stray fine was recorded');
    expect((await wide()).isOnShift, isTrue, reason: 'the shift stays finishable once online');
  });

  test('a Fine on a shift opened before midnight is never stamped before its opener', () async {
    // The opener carries the SERVER's start (the reconciler backfilled it), so a phone clock behind
    // it is the premise of the clamp. For that opener also to sit outside `getTodaySessions()` —
    // the state this finding describes — the repository's business calendar has to have rolled
    // over while the opener is still ahead of the device clock; that is what the shifted clock
    // models. What the assertions pin is which read the clamp uses.
    repo = WorkSessionRepository(
      db,
      businessTime: BusinessTime(
        kDefaultBusinessZoneId,
        clock: () => DateTime.now().toUtc().add(const Duration(days: 2)),
      ),
    );
    final phoneNow = DateTime.now().toUtc();
    // Second precision: `eventTime` is stored as unix seconds, so a sub-second opener would never
    // compare equal to the value read back.
    final nowSecond = DateTime.utc(
      phoneNow.year,
      phoneNow.month,
      phoneNow.day,
      phoneNow.hour,
      phoneNow.minute,
      phoneNow.second,
    );
    // A wide margin costs nothing here (no business-day boundary is in play under the shifted
    // clock) and keeps a loaded machine from reaching the opener before the clamp is asked for.
    final opener = nowSecond.add(const Duration(seconds: 30)); // server ahead of phone
    await seedRemoteOpener(opener);
    expect(await repo.getTodaySessions(), isEmpty, reason: 'sanity: previous business day');

    final n = notifier();
    await n.punch(await wide());
    await pumpEventQueue();

    expect(n.state, isA<AsyncData<void>>());
    final fine = (await repo.getAllSessions()).firstWhere((s) => s.eventType == 'fine');
    expect(fine.eventTime.isAtSameMomentAs(opener.add(const Duration(seconds: 1))), isTrue);
    expect((await wide()).isOnShift, isFalse);
  });
}
