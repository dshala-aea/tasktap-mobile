// Widget tests for TimbraScreen.
//
// Uses in-memory Drift + Riverpod overrides; no network.
// The screen has a 1-second Timer.periodic for the live clock. We dispose
// it by advancing fake time by 1 s, then replacing the widget. This avoids
// the "timer still pending" assertion from the test framework.

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart';
import 'package:tasktap_mobile/features/timbra/timbra_screen.dart';

AppDatabase _makeDb() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  return AppDatabase(NativeDatabase.memory());
}

Widget _buildApp(AppDatabase db) {
  return ProviderScope(
    overrides: [appDatabaseProvider.overrideWithValue(db)],
    child: const MaterialApp(home: TimbraScreen()),
  );
}

/// Disposes the screen by unmounting it, which cancels the Timer.periodic.
/// Must be called at the end of every test.
Future<void> _teardownTimer(WidgetTester tester) async {
  await tester.pumpWidget(const MaterialApp(home: SizedBox()));
  // Pump enough times to flush any pending zero-duration timers (e.g., Drift).
  for (var i = 0; i < 5; i++) {
    await tester.pump(Duration.zero);
  }
}

void main() {
  late AppDatabase db;

  setUp(() => db = _makeDb());
  tearDown(() async => db.close());

  testWidgets('TimbraScreen renders Scaffold', (tester) async {
    await tester.pumpWidget(_buildApp(db));
    await tester.pump();
    expect(find.byType(Scaffold), findsOneWidget);
    await _teardownTimer(tester);
  });

  testWidgets('shows INIZIA TURNO initially', (tester) async {
    await tester.pumpWidget(_buildApp(db));
    await tester.pump();
    expect(find.text('INIZIA TURNO'), findsOneWidget);
    await _teardownTimer(tester);
  });

  testWidgets('shows Sessioni di oggi section heading', (tester) async {
    await tester.pumpWidget(_buildApp(db));
    await tester.pump();
    expect(find.text('SESSIONI DI OGGI'), findsOneWidget);
    await _teardownTimer(tester);
  });

  testWidgets('shows Nessuna timbratura oggi when no sessions', (tester) async {
    await tester.pumpWidget(_buildApp(db));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Nessuna timbratura oggi'), findsOneWidget);
    await _teardownTimer(tester);
  });

  testWidgets('punch button tap adds Ingresso session row', (tester) async {
    await tester.pumpWidget(_buildApp(db));
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.text('INIZIA TURNO'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Ingresso'), findsOneWidget);
    await _teardownTimer(tester);
  });
}
