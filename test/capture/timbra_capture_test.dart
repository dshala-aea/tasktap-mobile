// Render-tree captures for the Timbra surface review.
//
// These are not device screenshots and do not pretend to be: they are the widget tree rasterised
// at 390×844 dp on a 2× device pixel ratio, with the app's real fonts loaded, written to
// `.impeccable/review/`. They exist so the surface can be reviewed against its direction contract
// on a machine with no emulator; the owner's device run remains the authority on field conditions
// (sunlight, gloves, system text scale beyond 1.3).
//
// Run: flutter test test/capture/timbra_capture_test.dart
// The captures are written next to the surface brief, not committed as a gate — nothing here
// compares images, so a restyle never fails this file.

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/core/location/location_service.dart';
import 'package:tasktap_mobile/core/theme/app_theme.dart';
import 'package:tasktap_mobile/core/time/business_time.dart';
import 'package:tasktap_mobile/core/time/business_time_providers.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart';
import 'package:tasktap_mobile/data/timbratura/timbra_sync_service.dart';
import 'package:tasktap_mobile/data/timbratura/work_session_repository.dart';
import 'package:tasktap_mobile/data/timbratura/worklog_api_client.dart';
import 'package:tasktap_mobile/features/dashboard/active_trackers_provider.dart' show nowProvider;
import 'package:tasktap_mobile/features/timbra/timbra_providers.dart'
    show
        TimbraGuard,
        pauseGuardProvider,
        punchGuardProvider,
        serverDayProvider,
        todaySessionsProvider,
        workSessionRepositoryProvider;
import 'package:tasktap_mobile/features/timbra/timbra_screen.dart';

const _kReviewDir = '.impeccable/review';

// ── Fixtures ──────────────────────────────────────────────────────────────────

/// Rome is UTC+2 in July, so these UTC instants print as the wall clock in the comment.
DateTime _utc(int h, int m) => DateTime.utc(2026, 7, 10, h - 2, m);

WorkSession _event(String id, DateTime at, String type, {bool pending = false}) =>
    WorkSession(id: id, eventTime: at, eventType: type, isPendingSync: pending);

DayWorkLogEntry _row(
  String id, {
  required DateTime start,
  DateTime? end,
  DayWorkLogKind kind = DayWorkLogKind.ordinary,
  String? sorgente,
}) => DayWorkLogEntry(
  id: id,
  clientId: null,
  start: start,
  end: end,
  kind: kind,
  sorgente: sorgente,
);

/// A repository that answers every read with the scenario's own sessions, so the day rail and the
/// shift state are derived from one list instead of disagreeing.
class _FakeRepo implements IWorkSessionRepository {
  _FakeRepo(this.sessions);

  final List<WorkSession> sessions;

  @override
  Stream<List<WorkSession>> watchTodaySessions() => Stream.value(sessions);

  @override
  Stream<List<WorkSession>> watchAllSessions() => Stream.value(sessions);

  @override
  Stream<List<WorkSession>> watchSyncFailedSessions({
    Duration within = const Duration(days: 7),
  }) => Stream.value(const <WorkSession>[]);

  @override
  Future<List<WorkSession>> getTodaySessions() async => sessions;

  @override
  Future<List<WorkSession>> getAllSessions() async => sessions;

  @override
  Future<List<WorkSession>> getPendingSessions() async =>
      sessions.where((s) => s.isPendingSync).toList();

  @override
  Future<int> getPendingCount() async => sessions.where((s) => s.isPendingSync).length;

  @override
  Future<void> addEvent({
    required String id,
    required DateTime eventTime,
    required String eventType,
    double? latitude,
    double? longitude,
    double? gpsAccuracyMeters,
  }) async {}

  @override
  Future<void> markSynced(List<String> ids) async {}

  @override
  Future<void> markSyncFailed(String id) async {}

  @override
  Future<void> clearToday() async {}

  @override
  Future<void> markReconciledOrphan(String id) async {}
}

class _NoopApiClient extends WorklogApiClient {
  _NoopApiClient() : super(Dio());

  @override
  Future<List<UpsertSessionResponse>> upsertSessions(
    List<MobileSessionDto> sessions, {
    List<MobileSessionDto> breaks = const [],
  }) async => [];

  @override
  Future<List<TodayWorkLogDto>> getToday() async => [];

  @override
  Future<List<DayWorkLogEntry>> fetchDayEntries({
    required String userId,
    required DateTime day,
    BusinessTime? businessTime,
  }) async => [];
}

// ── Harness ───────────────────────────────────────────────────────────────────

/// Loads the app's real fonts so the captures read like the shipped screen rather than Ahem.
Future<void> _loadFonts() async {
  final manifest = await rootBundle.loadString('FontManifest.json');
  for (final family in json.decode(manifest) as List) {
    final entry = family as Map<String, dynamic>;
    final loader = FontLoader(entry['family'] as String);
    for (final font in entry['fonts'] as List) {
      loader.addFont(rootBundle.load((font as Map<String, dynamic>)['asset'] as String));
    }
    await loader.load();
  }
}

Future<void> _capture(WidgetTester tester, String name) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('capture')),
  );
  late Uint8List bytes;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    bytes = data!.buffer.asUint8List();
  });
  Directory(_kReviewDir).createSync(recursive: true);
  File('$_kReviewDir/$name.png').writeAsBytesSync(bytes);
}

/// Pumps the screen in the given state and writes one capture.
Future<void> _render(
  WidgetTester tester,
  String name, {
  required List<WorkSession> sessions,
  required DateTime now,
  List<DayWorkLogEntry> serverRows = const [],
  /// The server's day does not answer (no signal, a 5xx). Distinct from [serverRows] being empty:
  /// an unanswered day may not read as "nothing happened today".
  bool serverFailed = false,
  /// This phone's own session table cannot be read. A different failure from [serverFailed]: here
  /// nobody knows what today holds, so the rail may not claim the day is empty.
  bool localReadFails = false,
  List<Override> overrides = const [],
  double textScale = 1,
  Brightness brightness = Brightness.light,
}) async {
  final db = AppDatabase(NativeDatabase.memory());
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  tester.view.physicalSize = const Size(390 * 2, 844 * 2);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        workSessionRepositoryProvider.overrideWithValue(_FakeRepo(sessions)),
        timbraSyncServiceProvider.overrideWithValue(
          TimbraSyncService(repo: _FakeRepo(sessions), apiClient: _NoopApiClient()),
        ),
        worklogApiClientProvider.overrideWithValue(_NoopApiClient()),
        locationServiceProvider.overrideWithValue(const DisabledLocationService()),
        businessTimeProvider.overrideWithValue(BusinessTime('Europe/Rome', clock: () => now)),
        nowProvider.overrideWith((ref) => Stream.value(now)),
        todaySessionsProvider.overrideWith(
          (ref) => localReadFails
              ? Stream.error(StateError('database is locked'))
              : Stream.value(sessions),
        ),
        serverDayProvider.overrideWith(
          (ref) async => serverFailed ? throw StateError('no signal') : serverRows,
        ),
        ...overrides,
      ],
      child: RepaintBoundary(
        key: const ValueKey('capture'),
        child: MediaQuery(
          data: MediaQueryData(
            size: const Size(390, 844),
            devicePixelRatio: 2,
            padding: const EdgeInsets.only(top: 28, bottom: 24),
            textScaler: TextScaler.linear(textScale),
          ),
          child: MaterialApp(
            theme: buildAppTheme(brightness: brightness),
            // A capture is evidence, not a debug session: the banner would sit in every frame.
            debugShowCheckedModeBanner: false,
            home: const TimbraScreen(),
          ),
        ),
      ),
    ),
  );
  // Two frames: one to settle the async providers, one to draw what they produced.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));

  await _capture(tester, name);

  await tester.pumpWidget(const MaterialApp(home: SizedBox()));
  await tester.pump(const Duration(seconds: 2));
  await db.close();
}

void main() {
  setUpAll(_loadFonts);

  testWidgets('phone — an open shift, counted to now', (tester) async {
    await _render(
      tester,
      'phone-open-shift',
      sessions: [_event('a', _utc(8, 0), 'ingresso')],
      now: _utc(12, 30),
    );
  });

  testWidgets('phone — the base viewport', (tester) async {
    await _render(
      tester,
      'phone',
      sessions: [
        _event('a', _utc(8, 0), 'ingresso'),
        _event('b', _utc(12, 0), 'pausa'),
        _event('c', _utc(13, 0), 'ripresa'),
      ],
      now: _utc(16, 40),
    );
  });

  testWidgets('phone — text scale 1.3', (tester) async {
    await _render(
      tester,
      'phone-textscale-130',
      sessions: [
        _event('a', _utc(8, 0), 'ingresso'),
        _event('b', _utc(12, 0), 'pausa'),
        _event('c', _utc(13, 0), 'ripresa'),
      ],
      now: _utc(16, 40),
      textScale: 1.3,
    );
  });

  testWidgets('phone — a punch made elsewhere, marked', (tester) async {
    await _render(
      tester,
      'phone-totem-provenance',
      sessions: const [],
      now: _utc(17, 0),
      serverRows: [
        _row('srv-1', start: _utc(7, 45), end: _utc(12, 0), sorgente: 'totem'),
        _row('srv-2', start: _utc(13, 0), end: _utc(16, 30), sorgente: 'totem'),
      ],
    );
  });

  testWidgets('phone — dark', (tester) async {
    // Both themes are first-class explicit choices in this app, so the surface owes evidence in
    // both: the deck's fixed `AppColors.Y` / `stopDark` fills and the rail's named surfaces are
    // the two places a dark-mode-only contrast bug would hide.
    await _render(
      tester,
      'phone-dark',
      sessions: [
        _event('a', _utc(8, 0), 'ingresso'),
        _event('b', _utc(12, 0), 'pausa'),
        _event('c', _utc(13, 0), 'ripresa'),
      ],
      now: _utc(16, 40),
      brightness: Brightness.dark,
    );
  });

  testWidgets('phone — a closed two-punch day', (tester) async {
    await _render(
      tester,
      'phone-two-punch',
      sessions: [
        _event('a', _utc(8, 0), 'ingresso'),
        _event('b', _utc(8, 40), 'fine'),
      ],
      now: _utc(17, 0),
    );
  });

  testWidgets('phone — an unpunched day', (tester) async {
    await _render(tester, 'phone-empty-day', sessions: const [], now: _utc(9, 0));
  });

  testWidgets('phone — an unsent punch beside a server row', (tester) async {
    await _render(
      tester,
      'phone-unsynced',
      // A closed, still-unsent morning beside a totem afternoon: one row must read "questo
      // telefono · in attesa", the other "totem". The morning is closed on purpose — a stretch
      // still open at this instant would draw past a server row it cannot already know about.
      sessions: [
        _event('a', _utc(8, 0), 'ingresso', pending: true),
        _event('b', _utc(12, 0), 'fine', pending: true),
      ],
      now: _utc(17, 0),
      serverRows: [_row('srv-1', start: _utc(13, 0), end: _utc(16, 0), sorgente: 'totem')],
    );
  });

  testWidgets('phone — the server day does not answer', (tester) async {
    await _render(
      tester,
      'phone-server-unknown',
      // A morning this phone recorded with no signal: the rail can still draw it, and the banner
      // above says the rest of the day may exist somewhere this screen cannot see.
      sessions: [_event('a', _utc(8, 0), 'ingresso', pending: true)],
      now: _utc(12, 30),
      serverFailed: true,
    );
  });

  testWidgets('phone — nothing known and nothing recorded', (tester) async {
    await _render(
      tester,
      'phone-server-unknown-empty',
      // Both sources silent: no local events and no server answer. This is the frame that used to
      // say "Nessuna timbratura oggi" — the one claim the rebuild exists to stop making.
      sessions: const [],
      now: _utc(9, 0),
      serverFailed: true,
    );
  });

  testWidgets('phone — the phone cannot read its own day', (tester) async {
    await _render(
      tester,
      'phone-local-unknown',
      sessions: const [],
      now: _utc(9, 0),
      // The phone's own table failed. The rail may not say "nothing happened today" beside the
      // banner that says the day could not be read, and it may not invite a punch into it.
      localReadFails: true,
    );
  });

  testWidgets('phone — a paid pause recorded by the server', (tester) async {
    await _render(
      tester,
      'phone-short-break',
      // A ShortBreak from the totem: the one break drawn as a SOLID amber bar, because it is
      // counted in the day. Its fill must stay the fill amber, not the darker text token.
      sessions: const [],
      now: _utc(17, 0),
      serverRows: [
        _row('srv-1', start: _utc(8, 0), end: _utc(12, 0), sorgente: 'totem'),
        _row(
          'srv-2',
          start: _utc(12, 0),
          end: _utc(12, 20),
          kind: DayWorkLogKind.shortBreak,
          sorgente: 'totem',
        ),
        _row('srv-3', start: _utc(12, 20), end: _utc(16, 30), sorgente: 'totem'),
      ],
    );
  });

  testWidgets('phone — a day the projection refuses', (tester) async {    await _render(
      tester,
      'phone-blocked',
      sessions: [_event('a', _utc(8, 0), 'ingresso')],
      now: _utc(9, 0),
      overrides: [
        punchGuardProvider.overrideWithValue(
          const TimbraGuard(
            blocked: true,
            reason: 'Il periodo è chiuso per le buste paga: chiedi all\'amministrazione.',
          ),
        ),
        pauseGuardProvider.overrideWithValue(TimbraGuard.allowed),
      ],
    );
  });
}
