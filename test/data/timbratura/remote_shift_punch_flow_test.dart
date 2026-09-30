// dart format width=100
// End to end on a real Drift DB: a shift started elsewhere is backfilled, then the technician taps
// Pausa / Ripresa / Fine on THIS phone. Buttons update optimistically from local events, the taps
// go to the REST endpoints, and a following reconcile leaves everything consistent.
import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/timbratura/timbra_sync_service.dart';
import 'package:tasktap_mobile/data/timbratura/work_log_reconciler.dart';
import 'package:tasktap_mobile/data/timbratura/work_session_repository.dart';
import 'package:tasktap_mobile/data/timbratura/worklog_api_client.dart';
import 'package:tasktap_mobile/data/worklogs/active_tracker_api_client.dart';
import 'package:tasktap_mobile/features/timbra/timbra_providers.dart';

class _Api extends WorklogApiClient {
  _Api() : super(Dio());
  final calls = <String>[];
  Object? error;
  @override
  Future<void> endWork() async {
    calls.add('end');
    if (error != null) throw error!;
  }

  @override
  Future<void> startBreak() async {
    calls.add('break/start');
    if (error != null) throw error!;
  }

  @override
  Future<void> endBreak() async {
    calls.add('break/end');
    if (error != null) throw error!;
  }

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
  late TimbraSyncService sync;
  late PunchNotifier punch;
  var server = <ActiveTracker>[];

  Future<TimbraState> local() async => deriveShiftState(await repo.getTodaySessions());

  setUp(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    db = AppDatabase(NativeDatabase.memory());
    repo = WorkSessionRepository(db);
    api = _Api();
    sync = TimbraSyncService(repo: repo, apiClient: api);
    punch = PunchNotifier(repo, sync);
    final started = DateTime.now().toUtc().subtract(const Duration(hours: 1));
    server = [
      ActiveTracker(
        kind: ActiveTrackerKind.attendance,
        id: 'wl-web',
        startedAtUtc: started,
        state: ActiveTrackerState.working,
        shiftStartedAtUtc: started,
      ),
    ];
    await WorkLogReconciler(repo: repo, fetchActive: () async => server).reconcile();
  });

  tearDown(() => db.close());

  test('backfilled shift: Pausa is optimistic locally and hits break/start', () async {
    expect((await local()).isOnShift, isTrue, reason: 'sanity: shift backfilled');
    await punch.togglePause(await local());
    expect((await local()).isOnPause, isTrue);
    await pumpEventQueue();
    expect(api.calls, ['break/start']);
  });

  test('backfilled shift: Fine is optimistic locally, hits /end, and stays stopped after reconcile', () async {
    await punch.punch(await local());
    expect((await local()).isOnShift, isFalse);
    await pumpEventQueue();
    expect(api.calls, ['end']);

    server = const []; // the server now agrees
    await WorkLogReconciler(repo: repo, fetchActive: () async => server).reconcile();
    expect((await local()).isOnShift, isFalse);
    expect(api.calls, ['end']);
  });

  test('offline Fine: local stopped at once, queued, delivered later, never batch-uploaded', () async {
    api.error = DioException(requestOptions: RequestOptions(), type: DioExceptionType.connectionError);
    await punch.punch(await local());
    await pumpEventQueue();
    expect((await local()).isOnShift, isFalse);

    // Reconcile while still pending must not undo the tap even though the server says Working.
    await WorkLogReconciler(repo: repo, fetchActive: () async => server).reconcile();
    expect((await local()).isOnShift, isFalse);

    api.error = null;
    await sync.syncNow();
    expect(api.calls.where((c) => c == 'end').length, 2);
    expect(api.calls, isNot(contains('batch')));
  });
}
