// test/features/rapportino/steps/recent_work_log_provider_test.dart
//
// recentWorkLogProvider (StepOre's third suggestion tier) fetches the last 30 days of the user's
// plain timbrature. The window is a pair of date labels in the legacy (Rome) frame, so it must
// follow the business clock and never the device zone: run under TZ=America/Los_Angeles or
// Pacific/Auckland (tool/test_tz_matrix.sh) the assertions below are identical.

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tasktap_mobile/core/time/business_time_providers.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/sync/connectivity_provider.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart' show appDatabaseProvider;
import 'package:tasktap_mobile/data/timbratura/worklog_api_client.dart';
import 'package:tasktap_mobile/features/rapportino/steps/step_ore.dart';
import 'package:tasktap_mobile/presentation/providers/auth_providers.dart'
    show internalUserIdProvider;

class _RecordingApi extends WorklogApiClient {
  _RecordingApi() : super(Dio());

  final List<({String userId, DateTime from, DateTime to})> calls = [];

  @override
  Future<List<UserWorkLogDto>> fetchForUser({
    required String userId,
    required DateTime dateFrom,
    required DateTime dateTo,
  }) async {
    calls.add((userId: userId, from: dateFrom, to: dateTo));
    return const [];
  }
}

({_RecordingApi api, ProviderContainer container}) _setup({
  required DateTime clock,
  String zone = 'Europe/Rome',
  bool online = true,
  AppDatabase? db,
  String? signedInUserId,
}) {
  final api = _RecordingApi();
  final container = ProviderContainer(
    overrides: [
      worklogApiClientProvider.overrideWithValue(api),
      isOnlineProvider.overrideWithValue(online),
      clockProvider.overrideWithValue(() => clock),
      businessZoneIdProvider.overrideWith(() => _FixedZone(zone)),
      if (db != null) appDatabaseProvider.overrideWithValue(db),
      // Always overridden, even with null: the real provider reads
      // SharedPreferences, which has no plugin implementation under
      // `flutter test`, so leaving it in place would throw
      // MissingPluginException instead of exercising "no user yet".
      internalUserIdProvider.overrideWith((ref) async => signedInUserId),
    ],
  );
  addTearDown(container.dispose);
  return (api: api, container: container);
}

/// This device's own punch, as the timbra screen writes it.
Future<void> _punch(
  AppDatabase db, {
  required String id,
  required String eventType,
  required DateTime at,
}) => db
    .into(db.workSessions)
    .insert(
      WorkSessionsCompanion.insert(id: id, eventTime: at, eventType: eventType),
    );

class _FixedZone extends BusinessZoneIdNotifier {
  _FixedZone(this._zone);
  final String _zone;

  @override
  String build() => _zone;
}

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  test('window is the 30 days ending on the Rome date', () async {
    final s = _setup(clock: DateTime.utc(2026, 7, 10, 12));
    await s.container.read(recentWorkLogProvider('user-1').future);

    expect(s.api.calls, hasLength(1));
    final call = s.api.calls.single;
    expect(call.userId, 'user-1');
    expect((call.to.year, call.to.month, call.to.day), (2026, 7, 10));
    expect((call.from.year, call.from.month, call.from.day), (2026, 6, 10));
  });

  test('just after Rome midnight the window already ends on the next Rome date', () async {
    // 22:30Z on 10 July is 00:30 on 11 July in Rome but still 10 July in Los Angeles (15:30) and
    // 11 July in Auckland (10:30): only the Rome reading is right.
    final s = _setup(clock: DateTime.utc(2026, 7, 10, 22, 30));
    await s.container.read(recentWorkLogProvider('user-1').future);

    final call = s.api.calls.single;
    expect((call.to.year, call.to.month, call.to.day), (2026, 7, 11));
    expect((call.from.year, call.from.month, call.from.day), (2026, 6, 11));
  });

  test('just before Rome midnight the window still ends on the current Rome date', () async {
    // 21:30Z on 10 July is 23:30 on 10 July in Rome, already 11 July 09:30 in Auckland.
    final s = _setup(clock: DateTime.utc(2026, 7, 10, 21, 30));
    await s.container.read(recentWorkLogProvider('user-1').future);

    final call = s.api.calls.single;
    expect((call.to.year, call.to.month, call.to.day), (2026, 7, 10));
    expect((call.from.year, call.from.month, call.from.day), (2026, 6, 10));
  });

  test('the legacy frame is Rome even when the tenant zone is elsewhere', () async {
    // 22:30Z on 10 July is 18:30 on 10 July in New York but already 11 July in Rome.
    final s = _setup(clock: DateTime.utc(2026, 7, 10, 22, 30), zone: 'America/New_York');
    await s.container.read(recentWorkLogProvider('user-1').future);

    final call = s.api.calls.single;
    expect((call.to.year, call.to.month, call.to.day), (2026, 7, 11));
  });

  test('offline: no request, empty list', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final s = _setup(
      clock: DateTime.utc(2026, 7, 10, 12),
      online: false,
      db: db,
      signedInUserId: 'user-1',
    );
    final result = await s.container.read(recentWorkLogProvider('user-1').future);

    expect(result, isEmpty);
    expect(s.api.calls, isEmpty);
  });

  // ── Offline: this phone's own open timbratura ────────────────────────────────
  //
  // The technician clocks in, loses signal, and writes the rapportino. The tier exists to turn
  // "you are clocked in right now" into suggested hours; going dark must not delete that fact,
  // and `work_sessions` already holds it.

  group('offline, from the device\'s own punches', () {
    test('a still-open ingresso becomes one open entry in the Rome label frame', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      // 08:00Z is 10:00 in Rome (CEST) — the label the backend's columns would carry.
      await _punch(
        db,
        id: 'w1',
        eventType: 'ingresso',
        at: DateTime.utc(2026, 7, 10, 8),
      );

      final s = _setup(
        clock: DateTime.utc(2026, 7, 10, 12),
        online: false,
        db: db,
        signedInUserId: 'user-1',
      );
      final result = await s.container.read(recentWorkLogProvider('user-1').future);

      expect(result, hasLength(1));
      expect(result.single.userId, 'user-1');
      expect(result.single.startTime, '10:00:00');
      expect((result.single.workDate.year, result.single.workDate.month, result.single.workDate.day),
          (2026, 7, 10));
      expect(result.single.endTime, isNull);
      expect(s.api.calls, isEmpty);
    });

    test('a punch already clocked out suggests nothing', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await _punch(db, id: 'w1', eventType: 'ingresso', at: DateTime.utc(2026, 7, 10, 8));
      await _punch(db, id: 'w2', eventType: 'fine', at: DateTime.utc(2026, 7, 10, 11));

      final s = _setup(
        clock: DateTime.utc(2026, 7, 10, 12),
        online: false,
        db: db,
        signedInUserId: 'user-1',
      );

      expect(await s.container.read(recentWorkLogProvider('user-1').future), isEmpty);
    });

    // `work_sessions` has no user column: they are this device's punches, so they belong to
    // whoever is signed in. Anyone else gets nothing rather than someone else's shift.
    test('another technician gets nothing', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await _punch(db, id: 'w1', eventType: 'ingresso', at: DateTime.utc(2026, 7, 10, 8));

      final s = _setup(
        clock: DateTime.utc(2026, 7, 10, 12),
        online: false,
        db: db,
        signedInUserId: 'user-1',
      );

      expect(await s.container.read(recentWorkLogProvider('user-2').future), isEmpty);
    });

    test('before the first entitlement refresh there is no user to match, so nothing', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await _punch(db, id: 'w1', eventType: 'ingresso', at: DateTime.utc(2026, 7, 10, 8));

      final s = _setup(
        clock: DateTime.utc(2026, 7, 10, 12),
        online: false,
        db: db,
      );

      expect(await s.container.read(recentWorkLogProvider('user-1').future), isEmpty);
    });
  });
}
