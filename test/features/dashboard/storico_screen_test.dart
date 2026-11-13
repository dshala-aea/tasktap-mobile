// test/features/dashboard/storico_screen_test.dart
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/sync/sync_freshness_provider.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart';
import 'package:tasktap_mobile/features/dashboard/storico_screen.dart';

GoRouter _router() => GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(path: '/', builder: (_, _) => const StoricoScreen()),
    GoRoute(
      path: '/ticket/:id',
      builder: (_, _) => const Scaffold(body: Center(child: Text('TICKET-DETAIL-MARKER'))),
    ),
  ],
);

Widget _buildStorico(AppDatabase db) {
  return ProviderScope(retry: (_, _) => null, 
    overrides: [
      appDatabaseProvider.overrideWithValue(db),
      hasSyncedAtLeastOnceProvider.overrideWith((ref) => Stream.value(true)),
    ],
    child: MaterialApp.router(routerConfig: _router()),
  );
}

void main() {
  setUpAll(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    await initializeDateFormatting('it', null);
  });

  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> insert(
    String id,
    String title,
    DateTime date, {
    String? ticketId,
  }) => db.into(db.schedules).insert(
    SchedulesCompanion.insert(
      id: id,
      tenantId: 't1',
      createdAt: DateTime.utc(2026, 1, 1),
      ticketId: Value(ticketId),
      activityDate: date,
      timeStartMinutes: 480,
      timeEndMinutes: 540,
      userId: 'u1',
      statusId: 5,
      locationId: 'l1',
      title: title,
      description: '',
    ),
  );

  testWidgets('renders past schedules newest first and opens a linked ticket', (tester) async {
    final now = DateTime.now().toUtc();
    final today = DateTime.utc(now.year, now.month, now.day);

    await insert('old', 'Vecchio', today.subtract(const Duration(days: 2)));
    await insert(
      'recent',
      'Recente',
      today.subtract(const Duration(days: 1)),
      ticketId: 't-recent',
    );
    await insert('today', 'Oggi', today);

    await tester.pumpWidget(_buildStorico(db));
    await tester.pumpAndSettle();

    expect(find.text('Recente'), findsOneWidget);
    expect(find.text('Vecchio'), findsOneWidget);
    expect(find.text('Oggi'), findsNothing);
    expect(
      tester.getTopLeft(find.text('Recente')).dy,
      lessThan(tester.getTopLeft(find.text('Vecchio')).dy),
    );

    await tester.tap(find.text('Recente'));
    await tester.pumpAndSettle();
    expect(find.text('TICKET-DETAIL-MARKER'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('a row without a ticket is not tappable', (tester) async {
    final now = DateTime.now().toUtc();
    final today = DateTime.utc(now.year, now.month, now.day);
    await insert('old', 'Vecchio', today.subtract(const Duration(days: 1)));

    await tester.pumpWidget(_buildStorico(db));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Vecchio'));
    await tester.pumpAndSettle();

    expect(find.byType(StoricoScreen), findsOneWidget);
    expect(find.text('TICKET-DETAIL-MARKER'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('shows the history-specific empty state', (tester) async {
    await tester.pumpWidget(_buildStorico(db));
    await tester.pumpAndSettle();

    expect(find.text('Nessuno storico'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}
