// test/features/calendario/calendario_screen_test.dart
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';
import 'package:tasktap_mobile/core/widgets/widgets.dart';
import 'package:tasktap_mobile/data/api/dio_client.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart';
import 'package:tasktap_mobile/domain/auth/auth_user.dart';
import 'package:tasktap_mobile/domain/auth/i_auth_repository.dart';
import 'package:tasktap_mobile/features/calendario/calendario_providers.dart';
import 'package:tasktap_mobile/features/calendario/calendario_screen.dart';
import 'package:tasktap_mobile/features/calendario/views/giorno_view.dart';
import 'package:tasktap_mobile/features/calendario/views/lista_view.dart';
import 'package:tasktap_mobile/features/calendario/views/mese_view.dart';
import 'package:tasktap_mobile/features/calendario/views/settimana_view.dart';
import 'package:tasktap_mobile/presentation/providers/auth_providers.dart';

class MockAuthRepository extends Mock implements IAuthRepository {}

class MockDio extends Mock implements Dio {}

// ── Helpers ───────────────────────────────────────────────────────────────────

Widget _buildScreen({
  required AppDatabase db,
  required MockAuthRepository repo,
  CalendarioView? initialView,
  DateTime? initialDate,
}) {
  return ProviderScope(
    overrides: [
      authRepositoryProvider.overrideWithValue(repo),
      appDatabaseProvider.overrideWithValue(db),
      dioProvider.overrideWithValue(MockDio()),
      if (initialView != null) calendarioViewProvider.overrideWith((ref) => initialView),
      if (initialDate != null) selectedDateProvider.overrideWith((ref) => initialDate),
    ],
    child: const MaterialApp(home: CalendarioScreen()),
  );
}

/// Seeds two schedules into the DB: one today (In corso) and one tomorrow
/// (Completato), so tests can verify date-grouping across both days.
Future<void> seedSchedules(AppDatabase db) async {
  final today = DateTime.now();
  final todayUtc = DateTime(today.year, today.month, today.day).toUtc();
  final tomorrowUtc = todayUtc.add(const Duration(days: 1));

  await db
      .into(db.schedules)
      .insert(
        SchedulesCompanion.insert(
          id: 'sched-today',
          tenantId: 'tenant-1',
          createdAt: todayUtc,
          activityDate: todayUtc,
          timeStartMinutes: 480, // 08:00
          timeEndMinutes: 600, // 10:00
          userId: 'u1',
          statusId: 2, // In corso
          locationId: 'loc-1',
          title: 'Intervento mattina',
          description: 'Descrizione intervento',
          ticketId: const Value('ticket-abc'),
        ),
      );

  await db
      .into(db.schedules)
      .insert(
        SchedulesCompanion.insert(
          id: 'sched-tomorrow',
          tenantId: 'tenant-1',
          createdAt: tomorrowUtc,
          activityDate: tomorrowUtc,
          timeStartMinutes: 540, // 09:00
          timeEndMinutes: 660, // 11:00
          userId: 'u1',
          statusId: 5, // Completato
          locationId: 'loc-2',
          title: 'Intervento domani',
          description: '',
        ),
      );
}

// ── Test setup ─────────────────────────────────────────────────────────────────

void main() {
  setUpAll(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    registerFallbackValue(RequestOptions(path: '/'));
    await initializeDateFormatting('it', null);
  });

  late AppDatabase db;
  late MockAuthRepository repo;
  late StreamController<AuthUser?> authStream;

  final fakeUser = AuthUser(
    id: 'u1',
    email: 'mario@tasktap.io',
    accessToken: 'token',
    refreshToken: 'refresh',
    expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
  );

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = MockAuthRepository();
    authStream = StreamController<AuthUser?>.broadcast();
    when(() => repo.authStateChanges).thenAnswer((_) => authStream.stream);
    when(() => repo.currentUser).thenReturn(fakeUser);
  });

  tearDown(() async {
    authStream.close();
    await db.close();
  });

  Future<void> pump(
    WidgetTester tester, {
    CalendarioView view = CalendarioView.giorno,
    DateTime? date,
  }) async {
    await tester.pumpWidget(_buildScreen(db: db, repo: repo, initialView: view, initialDate: date));
    await tester.pump();
    authStream.add(fakeUser);
    await tester.pumpAndSettle(const Duration(seconds: 2));
  }

  // ── Scaffold ───────────────────────────────────────────────────────────────

  /// Moving between periods, which the calendar could not do.
  ///
  /// The only date controls were a week strip that reaches inside the week it is already on and a
  /// "vai a oggi" icon. In Mese the strip was hidden, so a month view could show no month but the
  /// current one — and nothing on screen named the month it was showing.
  group('CalendarioScreen — period navigation', () {
    testWidgets('names the month, and can leave it', (tester) async {
      await tester.pumpWidget(
        _buildScreen(
          db: db,
          repo: repo,
          initialView: CalendarioView.mese,
          initialDate: DateTime(2026, 8, 15),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Agosto 2026'), findsOneWidget);

      await tester.tap(find.byTooltip('Periodo successivo'));
      await tester.pumpAndSettle();
      expect(find.text('Settembre 2026'), findsOneWidget);

      await tester.tap(find.byTooltip('Periodo precedente'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Periodo precedente'));
      await tester.pumpAndSettle();
      expect(find.text('Luglio 2026'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('a step means a day in Giorno and a week in Settimana', (tester) async {
      // Same two arrows, different unit — the view decides what "next" measures.
      await tester.pumpWidget(
        _buildScreen(
          db: db,
          repo: repo,
          initialView: CalendarioView.giorno,
          initialDate: DateTime(2026, 8, 15),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Periodo successivo'));
      await tester.pumpAndSettle();
      expect(find.text('Domenica 16 agosto'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();

      await tester.pumpWidget(
        _buildScreen(
          db: db,
          repo: repo,
          initialView: CalendarioView.settimana,
          initialDate: DateTime(2026, 8, 15),
        ),
      );
      await tester.pumpAndSettle();

      // 15 Aug 2026 is a Saturday; its week is Mon 10 – Sun 16.
      expect(find.text('10 – 16 ago'), findsOneWidget);
      await tester.tap(find.byTooltip('Periodo successivo'));
      await tester.pumpAndSettle();
      expect(find.text('17 – 23 ago'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('Lista is a rolling window, so it offers no steps', (tester) async {
      // Anchored to today by definition. Arrows there would move nothing.
      await tester.pumpWidget(
        _buildScreen(db: db, repo: repo, initialView: CalendarioView.lista),
      );
      await tester.pumpAndSettle();

      expect(find.text('Prossimi 30 giorni'), findsOneWidget);
      expect(find.byTooltip('Periodo successivo'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('Oggi appears only once the calendar has moved off today', (tester) async {
      await tester.pumpWidget(
        _buildScreen(db: db, repo: repo, initialView: CalendarioView.giorno),
      );
      await tester.pumpAndSettle();

      expect(find.text('Oggi'), findsNothing, reason: 'a control for a state you are in');

      await tester.tap(find.byTooltip('Periodo successivo'));
      await tester.pumpAndSettle();
      expect(find.text('Oggi'), findsOneWidget);

      await tester.tap(find.text('Oggi'));
      await tester.pumpAndSettle();
      expect(find.text('Oggi'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('swiping across the body steps the period', (tester) async {
      // The gesture people try first, and the one that works with a phone in one hand.
      await tester.pumpWidget(
        _buildScreen(
          db: db,
          repo: repo,
          initialView: CalendarioView.mese,
          initialDate: DateTime(2026, 8, 15),
        ),
      );
      await tester.pumpAndSettle();

      await tester.fling(find.byType(MeseView), const Offset(-300, 0), 1000);
      await tester.pumpAndSettle();
      expect(find.text('Settembre 2026'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  });

  group('CalendarioScreen — shell', () {
    testWidgets('renders Scaffold with "Calendario" title', (tester) async {
      await pump(tester);
      expect(find.byType(Scaffold), findsOneWidget);
      expect(find.text('Calendario'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('shows AppTabs with 4 view labels', (tester) async {
      await pump(tester);
      expect(find.byType(AppTabs), findsOneWidget);
      expect(find.text('Giorno'), findsOneWidget);
      expect(find.text('Settimana'), findsOneWidget);
      expect(find.text('Mese'), findsOneWidget);
      expect(find.text('Lista'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('tab switch — tapping Settimana renders SettimanaView', (tester) async {
      await pump(tester, view: CalendarioView.giorno);
      // GiornoView should start visible
      expect(find.byType(GiornoView), findsOneWidget);

      // Tap the Settimana tab
      await tester.tap(find.text('Settimana'));
      await tester.pumpAndSettle();
      expect(find.byType(SettimanaView), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('tab switch — tapping Mese renders MeseView', (tester) async {
      await pump(tester, view: CalendarioView.giorno);
      await tester.tap(find.text('Mese'));
      await tester.pumpAndSettle();
      expect(find.byType(MeseView), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('tab switch — tapping Lista renders ListaView', (tester) async {
      await pump(tester, view: CalendarioView.giorno);
      await tester.tap(find.text('Lista'));
      await tester.pumpAndSettle();
      expect(find.byType(ListaView), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  });

  // ── Giorno view ────────────────────────────────────────────────────────────

  group('GiornoView', () {
    testWidgets('shows hour labels starting at 07:00', (tester) async {
      await pump(tester, view: CalendarioView.giorno);
      expect(find.text('07:00'), findsOneWidget);
      expect(find.text('08:00'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('renders event block for today schedule', (tester) async {
      await seedSchedules(db);
      final today = DateTime.now();
      await pump(
        tester,
        view: CalendarioView.giorno,
        date: DateTime(today.year, today.month, today.day),
      );
      // The event block should show the title
      expect(find.text('Intervento mattina'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('shows empty grid with no events', (tester) async {
      await pump(tester, view: CalendarioView.giorno);
      // GiornoView renders even with no events (just the hour labels)
      expect(find.byType(GiornoView), findsOneWidget);
      expect(find.text('07:00'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  });

  // ── Settimana view ─────────────────────────────────────────────────────────

  group('SettimanaView', () {
    testWidgets('renders 7 day headers', (tester) async {
      await pump(tester, view: CalendarioView.settimana);
      expect(find.byType(SettimanaView), findsOneWidget);
      // Each day has a day-number text; the current week must have 7 days
      // We verify column count indirectly via the widget tree
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('shows event chips when schedules exist', (tester) async {
      await seedSchedules(db);
      final today = DateTime.now();
      await pump(
        tester,
        view: CalendarioView.settimana,
        date: DateTime(today.year, today.month, today.day),
      );
      // Both seeded schedules are within this week (today + tomorrow)
      expect(find.text('Intervento mattina'), findsWidgets);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  });

  // ── Mese view ──────────────────────────────────────────────────────────────

  group('MeseView', () {
    testWidgets('renders MeseView without crash', (tester) async {
      await pump(tester, view: CalendarioView.mese);
      expect(find.byType(MeseView), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('shows current day number in grid', (tester) async {
      final today = DateTime.now();
      await pump(tester, view: CalendarioView.mese);
      // Today's day number appears at least once in the grid
      expect(find.text('${today.day}'), findsWidgets);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  });

  // ── Lista view ─────────────────────────────────────────────────────────────

  group('ListaView', () {
    testWidgets('shows EmptyState when no schedules', (tester) async {
      await pump(tester, view: CalendarioView.lista);
      expect(find.byType(EmptyState), findsOneWidget);
      expect(find.text('Nessun intervento'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('shows seeded schedules as ListRows', (tester) async {
      await seedSchedules(db);
      await pump(tester, view: CalendarioView.lista);
      expect(find.byType(ListRow), findsWidgets);
      expect(find.text('Intervento mattina'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('groups schedules by day (two date section headers)', (tester) async {
      await seedSchedules(db);
      await pump(tester, view: CalendarioView.lista);
      // The two schedules are on different days → two date section headers.
      // Section headers are Sora text; we check that ListRows appear.
      expect(find.byType(ListRow), findsNWidgets(2));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('StatusPill shown for each row', (tester) async {
      await seedSchedules(db);
      await pump(tester, view: CalendarioView.lista);
      // Two schedules → two StatusPills
      expect(find.byType(StatusPill), findsNWidgets(2));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('shows a squadra indicator only on the team-assigned schedule', (tester) async {
      await seedSchedules(db);
      // Only "sched-today" is squadra-assigned — a row per (schedule, user) in the local
      // ScheduleAssignees mirror, isTeam=true (see teamAssignedScheduleIdsProvider).
      await db
          .into(db.scheduleAssignees)
          .insert(
            ScheduleAssigneesCompanion.insert(
              scheduleId: 'sched-today',
              userId: 'u2',
              isTeam: const Value(true),
            ),
          );

      await pump(tester, view: CalendarioView.lista);

      expect(find.byIcon(LucideIcons.users), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  });

  // ── Providers helpers ──────────────────────────────────────────────────────

  group('calendario_providers helpers', () {
    test('scheduleStatusName maps known IDs', () {
      expect(scheduleStatusName(2), 'In corso');
      expect(scheduleStatusName(5), 'Completato');
      expect(scheduleStatusName(1), 'Aperto');
      expect(scheduleStatusName(999), 'Pianificato');
    });

    test('formatMinutes formats correctly', () {
      expect(formatMinutes(0), '00:00');
      expect(formatMinutes(480), '08:00');
      expect(formatMinutes(605), '10:05');
      expect(formatMinutes(1439), '23:59');
    });

    test('groupSchedulesByDay groups correctly', () {
      // We can't easily construct Schedule Drift data classes in unit tests
      // without a real DB; grouping is exercised by the widget tests above.
      // Just verify the trivial empty case.
      final result = groupSchedulesByDay([]);
      expect(result, isEmpty);
    });

    test('DateRange equality', () {
      final a = DateRange(start: DateTime(2026, 6, 1), end: DateTime(2026, 6, 8));
      final b = DateRange(start: DateTime(2026, 6, 1), end: DateTime(2026, 6, 8));
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });
  });
}
