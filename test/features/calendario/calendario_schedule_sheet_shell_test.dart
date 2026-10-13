// Regression: a Calendario event sheet must clear the shell's floating bottom nav.
//
// Owner repro (ClickUp 12493t4pm1u): "for events that are not tickets the sheet opens but it is
// behind the bottom nav and it is covered."
//
// Calendario is a StatefulShellBranch. HomeShell renders `Scaffold(extendBody: true,
// bottomNavigationBar: AppBottomNav)`, so anything a branch pushes onto its own inner navigator
// is painted inside the shell body — under the nav pill. `_showScheduleSheet` therefore passes
// `useRootNavigator: true`, which puts the modal on the root navigator (above the whole shell).
//
// What this proves: the schedule sheet is hosted by the ROOT navigator, i.e. an ancestor-layer
// above HomeShell and its AppBottomNav — the exact property that was missing and that let the nav
// cover the sheet. Without the fix, the sheet is hosted by the branch navigator and this fails.
//
// What it does NOT prove: a pixel-level assertion that the sheet's lower edge visually clears the
// pill. It asserts the routing property that produces that outcome rather than sampling pixels,
// because a full-shell pump has no stable layout to assert against (fonts substitute in tests and
// the branch content, not the nav, owns the sheet's own height).
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tasktap_mobile/core/router/app_router.dart';
import 'package:tasktap_mobile/core/widgets/bottom_nav.dart';
import 'package:tasktap_mobile/data/api/dio_client.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart';
import 'package:tasktap_mobile/domain/auth/auth_user.dart';
import 'package:tasktap_mobile/domain/auth/i_auth_repository.dart';
import 'package:tasktap_mobile/main.dart';
import 'package:tasktap_mobile/presentation/providers/auth_providers.dart';

class MockAuthRepository extends Mock implements IAuthRepository {}

class MockDio extends Mock implements Dio {}

Map<String, dynamic> _emptySyncPayload() => {
  'syncedAt': DateTime.utc(2026, 6, 21).toIso8601String(),
  'since': null,
  'schedules': <dynamic>[],
  'draftReports': <dynamic>[],
  'customers': <dynamic>[],
  'locations': <dynamic>[],
  'tickets': <dynamic>[],
};

/// Seeds one all-day schedule for today with no ticketId, so tapping its Giorno block opens
/// `_ScheduleInfoSheet` (the non-ticket path the owner reported) rather than pushing a ticket.
Future<void> _seedAllDaySchedule(AppDatabase db) async {
  final today = DateTime.now();
  final todayUtc = DateTime(today.year, today.month, today.day).toUtc();

  await db
      .into(db.schedules)
      .insert(
        SchedulesCompanion.insert(
          id: 'sched-allday',
          tenantId: 'tenant-1',
          createdAt: todayUtc,
          activityDate: todayUtc,
          timeStartMinutes: 0,
          timeEndMinutes: 1439,
          userId: 'u1',
          statusId: 2, // In corso
          locationId: 'loc-1',
          allDay: const Value(true),
          title: 'Evento tutto il giorno',
          description: 'Descrizione evento',
        ),
      );
}

void main() {
  setUpAll(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    registerFallbackValue(RequestOptions(path: '/'));
    await initializeDateFormatting('it', null);
  });

  late MockAuthRepository repo;
  late StreamController<AuthUser?> authStream;
  late AppDatabase db;
  late MockDio mockDio;

  setUp(() {
    repo = MockAuthRepository();
    authStream = StreamController<AuthUser?>.broadcast();
    db = AppDatabase(NativeDatabase.memory());
    mockDio = MockDio();

    when(
      () => mockDio.get<Map<String, dynamic>>(
        any(),
        queryParameters: any(named: 'queryParameters'),
      ),
    ).thenAnswer(
      (_) async => Response<Map<String, dynamic>>(
        requestOptions: RequestOptions(path: '/api/sync/mobile'),
        statusCode: 200,
        data: _emptySyncPayload(),
      ),
    );

    final fakeUser = AuthUser(
      id: 'test-user',
      email: 'tech@tasktap.io',
      accessToken: 'fake-token',
      refreshToken: 'fake-refresh',
      expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
    );
    when(() => repo.authStateChanges).thenAnswer((_) => authStream.stream);
    when(() => repo.currentUser).thenReturn(fakeUser);
    Future.microtask(() => authStream.add(fakeUser));
  });

  tearDown(() async {
    authStream.close();
    await db.close();
  });

  testWidgets('a Calendario event sheet is hosted by the root navigator (clears AppBottomNav)', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(repo),
          appDatabaseProvider.overrideWithValue(db),
          dioProvider.overrideWithValue(mockDio),
        ],
        child: const TaskTapApp(),
      ),
    );
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // Confirm we really are inside the shell (the construct whose nav covers branch sheets).
    expect(find.byType(AppBottomNav), findsOneWidget);

    // Seed after the startup sync has settled, so an empty sync payload cannot wipe it.
    await _seedAllDaySchedule(db);

    // Switch to the Calendario tab (inactive tabs are icon-only; the nav exposes a Semantics
    // label per tab).
    final calendarioTab = find.byWidgetPredicate(
      (w) => w is Semantics && w.properties.label == 'Calendario',
    );
    expect(calendarioTab, findsWidgets);
    await tester.tap(calendarioTab.first);
    await tester.pumpAndSettle();

    // Tap the all-day event block → opens the info sheet (non-ticket path).
    await tester.tap(find.text('Evento tutto il giorno'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget, reason: 'the event sheet opened');

    // The sheet's nearest Navigator ancestor must be the ROOT navigator. In the buggy version it
    // is the branch navigator, which HomeShell paints beneath the bottomNavigationBar — that is
    // exactly how the nav comes to cover the sheet.
    final hostingNavigator = tester.state<NavigatorState>(
      find.ancestor(of: find.byType(BottomSheet), matching: find.byType(Navigator)).first,
    );
    expect(
      identical(hostingNavigator, rootNavigatorKey.currentState),
      isTrue,
      reason: 'the sheet must be pushed on the root navigator, above HomeShell and its nav',
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}
