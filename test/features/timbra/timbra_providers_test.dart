// Tests for Timbra providers and domain logic.
//
// Uses an in-memory Drift DB — no network, no file system.
// Verifies:
//   - deriveShiftState: correctly tracks isOnShift / isOnPause
//   - computeTotalWorked: sums working segments excluding pauses
//   - PunchNotifier: toggles shift on/off and records sessions
//   - todaySessionsProvider: returns only today's sessions
//   - timbraStateProvider: reflects punch state
//   - pauseGuardProvider: forwards StartBreak/EndBreak to resolveGuard

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart';
import 'package:tasktap_mobile/data/timbratura/timbra_sync_service.dart';
import 'package:tasktap_mobile/data/timbratura/work_session_repository.dart';
import 'package:tasktap_mobile/data/timbratura/worklog_api_client.dart';
import 'package:tasktap_mobile/features/timbra/timbra_providers.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

AppDatabase _makeDb() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  return AppDatabase(NativeDatabase.memory());
}

// No-op stub repo and API client so timbraSyncServiceProvider never hits Dio.
class _StubRepo implements IWorkSessionRepository {
  @override
  Future<void> addEvent({
    required String id,
    required DateTime eventTime,
    required String eventType,
  }) async {}
  @override
  Stream<List<WorkSession>> watchTodaySessions() => const Stream.empty();
  @override
  Future<List<WorkSession>> getTodaySessions() async => [];
  @override
  Future<void> markSynced(List<String> ids) async {}
  @override
  Future<void> clearToday() async {}
}

class _NoopApiClient extends WorklogApiClient {
  _NoopApiClient() : super(Dio());
  @override
  Future<List<UpsertSessionResponse>> upsertSessions(List<MobileSessionDto> sessions) async => [];
  @override
  Future<List<TodayWorkLogDto>> getToday() async => [];
}

TimbraSyncService _noopSyncService() =>
    TimbraSyncService(repo: _StubRepo(), apiClient: _NoopApiClient());

// ── deriveShiftState unit tests ───────────────────────────────────────────────

void main() {
  group('deriveShiftState', () {
    test('empty sessions → not on shift', () {
      final state = deriveShiftState([]);
      expect(state.isOnShift, isFalse);
      expect(state.isOnPause, isFalse);
    });

    test('ingresso → on shift', () {
      final sessions = [
        WorkSession(
          id: '1',
          eventTime: DateTime(2026, 6, 22, 8),
          eventType: 'ingresso',
          isPendingSync: true,
        ),
      ];
      final state = deriveShiftState(sessions);
      expect(state.isOnShift, isTrue);
      expect(state.isOnPause, isFalse);
      expect(state.shiftStartTime, equals(DateTime(2026, 6, 22, 8)));
    });

    test('ingresso then fine → not on shift', () {
      final sessions = [
        WorkSession(
          id: '1',
          eventTime: DateTime(2026, 6, 22, 8),
          eventType: 'ingresso',
          isPendingSync: true,
        ),
        WorkSession(
          id: '2',
          eventTime: DateTime(2026, 6, 22, 17),
          eventType: 'fine',
          isPendingSync: true,
        ),
      ];
      final state = deriveShiftState(sessions);
      expect(state.isOnShift, isFalse);
    });

    test('ingresso then pausa → on pause', () {
      final sessions = [
        WorkSession(
          id: '1',
          eventTime: DateTime(2026, 6, 22, 8),
          eventType: 'ingresso',
          isPendingSync: true,
        ),
        WorkSession(
          id: '2',
          eventTime: DateTime(2026, 6, 22, 12),
          eventType: 'pausa',
          isPendingSync: true,
        ),
      ];
      final state = deriveShiftState(sessions);
      expect(state.isOnShift, isTrue);
      expect(state.isOnPause, isTrue);
    });

    test('ingresso, pausa, ripresa → on shift not paused', () {
      final sessions = [
        WorkSession(
          id: '1',
          eventTime: DateTime(2026, 6, 22, 8),
          eventType: 'ingresso',
          isPendingSync: true,
        ),
        WorkSession(
          id: '2',
          eventTime: DateTime(2026, 6, 22, 12),
          eventType: 'pausa',
          isPendingSync: true,
        ),
        WorkSession(
          id: '3',
          eventTime: DateTime(2026, 6, 22, 13),
          eventType: 'ripresa',
          isPendingSync: true,
        ),
      ];
      final state = deriveShiftState(sessions);
      expect(state.isOnShift, isTrue);
      expect(state.isOnPause, isFalse);
    });
  });

  // ── computeTotalWorked unit tests ──────────────────────────────────────────

  group('computeTotalWorked', () {
    test('no sessions → zero', () {
      final total = computeTotalWorked([], DateTime(2026, 6, 22, 10));
      expect(total, Duration.zero);
    });

    test('ingresso at 08:00, no fine, now=12:00 → 4h', () {
      final sessions = [
        WorkSession(
          id: '1',
          eventTime: DateTime.utc(2026, 6, 22, 8),
          eventType: 'ingresso',
          isPendingSync: true,
        ),
      ];
      final now = DateTime.utc(2026, 6, 22, 12);
      final total = computeTotalWorked(sessions, now);
      expect(total.inMinutes, equals(240));
    });

    test('ingresso 08:00, fine 17:00 → 9h', () {
      final sessions = [
        WorkSession(
          id: '1',
          eventTime: DateTime.utc(2026, 6, 22, 8),
          eventType: 'ingresso',
          isPendingSync: true,
        ),
        WorkSession(
          id: '2',
          eventTime: DateTime.utc(2026, 6, 22, 17),
          eventType: 'fine',
          isPendingSync: true,
        ),
      ];
      final total = computeTotalWorked(sessions, DateTime.utc(2026, 6, 22, 17));
      expect(total.inMinutes, equals(540));
    });

    test('pausa excluded: 08:00–12:00 work, 12:00–13:00 pausa, 13:00–17:00 work → 8h', () {
      final sessions = [
        WorkSession(
          id: '1',
          eventTime: DateTime.utc(2026, 6, 22, 8),
          eventType: 'ingresso',
          isPendingSync: true,
        ),
        WorkSession(
          id: '2',
          eventTime: DateTime.utc(2026, 6, 22, 12),
          eventType: 'pausa',
          isPendingSync: true,
        ),
        WorkSession(
          id: '3',
          eventTime: DateTime.utc(2026, 6, 22, 13),
          eventType: 'ripresa',
          isPendingSync: true,
        ),
        WorkSession(
          id: '4',
          eventTime: DateTime.utc(2026, 6, 22, 17),
          eventType: 'fine',
          isPendingSync: true,
        ),
      ];
      final total = computeTotalWorked(sessions, DateTime.utc(2026, 6, 22, 17));
      expect(total.inMinutes, equals(480));
    });
  });

  // ── Repository + Riverpod provider integration ────────────────────────────

  group('WorkSessionRepository + todaySessionsProvider', () {
    late AppDatabase db;
    late ProviderContainer container;

    setUp(() {
      db = _makeDb();
      container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          timbraSyncServiceProvider.overrideWithValue(_noopSyncService()),
        ],
      );
    });

    tearDown(() async {
      container.dispose();
      await db.close();
    });

    test('todaySessionsProvider emits empty list when db empty', () async {
      final result = await container.read(todaySessionsProvider.future);
      expect(result, isEmpty);
    });

    test('addEvent then todaySessionsProvider returns the event', () async {
      final repo = container.read(workSessionRepositoryProvider);
      final now = DateTime.now().toUtc();
      await repo.addEvent(id: 'test-1', eventTime: now, eventType: 'ingresso');

      final result = await container.read(todaySessionsProvider.future);
      expect(result.length, equals(1));
      expect(result.first.eventType, equals('ingresso'));
    });

    test('PunchNotifier: punch-in creates ingresso event', () async {
      final notifier = container.read(punchNotifierProvider.notifier);
      const initialState = TimbraState();

      await notifier.punch(initialState);

      final sessions = await container.read(todaySessionsProvider.future);
      expect(sessions.length, equals(1));
      expect(sessions.first.eventType, equals('ingresso'));
    });

    test('PunchNotifier: punch-in then punch-out creates fine event', () async {
      final notifier = container.read(punchNotifierProvider.notifier);

      // First punch → ingresso
      await notifier.punch(const TimbraState());

      // Second punch → fine (shift is now active)
      await notifier.punch(const TimbraState(isOnShift: true));

      final sessions = await container.read(todaySessionsProvider.future);
      expect(sessions.length, equals(2));
      expect(sessions[0].eventType, equals('ingresso'));
      expect(sessions[1].eventType, equals('fine'));
    });

    test('timbraStateProvider: sessions after punch derive correct state', () async {
      final notifier = container.read(punchNotifierProvider.notifier);
      await notifier.punch(const TimbraState());

      // Wait for DB to emit the new session.
      final sessions = await container.read(todaySessionsProvider.future);
      final state = deriveShiftState(sessions);
      expect(state.isOnShift, isTrue);
    });

    test('clearToday removes all sessions', () async {
      final repo = container.read(workSessionRepositoryProvider);
      final now = DateTime.now().toUtc();
      await repo.addEvent(id: 'a', eventTime: now, eventType: 'ingresso');
      await repo.addEvent(id: 'b', eventTime: now.add(const Duration(hours: 4)), eventType: 'fine');
      await repo.clearToday();

      final sessions = await container.read(todaySessionsProvider.future);
      expect(sessions, isEmpty);
    });
  });

  // ── pauseGuardProvider ──────────────────────────────────────────────────────
  //
  // Mirrors punchGuardProvider's contract, just with the break action pair.
  // resolveGuard's own decision logic is exhaustively covered in
  // timbra_guard_test.dart; this only checks the provider forwards the right
  // action name for each shift state.

  group('pauseGuardProvider', () {
    late AppDatabase db;
    late ProviderContainer container;

    setUp(() {
      db = _makeDb();
    });

    tearDown(() async {
      container.dispose();
      await db.close();
    });

    GiornataDto giornataWith(List<GiornataActionDto> actions) => GiornataDto(
      status: 'Working',
      workedMinutes: 0,
      breakMinutes: 0,
      isPayrollLocked: false,
      actions: actions,
    );

    test('requests StartBreak when not currently on a break', () async {
      container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          timbraSyncServiceProvider.overrideWithValue(_noopSyncService()),
          giornataProvider.overrideWith(
            (ref) async => giornataWith([
              const GiornataActionDto(
                action: 'StartBreak',
                enabled: false,
                reasonCode: 'not_clocked_in',
                reason: 'Non risulti in servizio.',
              ),
            ]),
          ),
        ],
      );

      final guard = await container
          .read(giornataProvider.future)
          .then((_) => container.read(pauseGuardProvider));

      expect(guard.blocked, isTrue);
      expect(guard.reason, contains('servizio'));
    });

    test('requests EndBreak when currently on a break', () async {
      container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          timbraSyncServiceProvider.overrideWithValue(_noopSyncService()),
          giornataProvider.overrideWith(
            (ref) async => giornataWith([
              const GiornataActionDto(
                action: 'EndBreak',
                enabled: false,
                reasonCode: 'not_on_break',
                reason: 'Non risulti in pausa.',
              ),
            ]),
          ),
        ],
      );

      // Put the derived shift state into "on pause" by seeding events, then
      // mark them synced — resolveGuard deliberately ignores a stale server
      // refusal while events are still pending (see timbra_guard_test.dart),
      // so an unsynced seed here would pass for the wrong reason.
      final sessionRepo = container.read(workSessionRepositoryProvider);
      final now = DateTime.now().toUtc();
      await sessionRepo.addEvent(id: 'a', eventTime: now, eventType: 'ingresso');
      await sessionRepo.addEvent(
        id: 'b',
        eventTime: now.add(const Duration(minutes: 5)),
        eventType: 'pausa',
      );
      await sessionRepo.markSynced(['a', 'b']);
      await container.read(todaySessionsProvider.future);
      await container.read(giornataProvider.future);

      final guard = container.read(pauseGuardProvider);

      expect(guard.blocked, isTrue);
      expect(guard.reason, contains('pausa'));
    });
  });
}
