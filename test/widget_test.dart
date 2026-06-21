// Widget smoke test — verifies the app tree assembles without error.
// Full shell tests are in test/presentation/app_shell_test.dart.

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tasktap_mobile/data/api/dio_client.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart';
import 'package:tasktap_mobile/domain/auth/auth_user.dart';
import 'package:tasktap_mobile/domain/auth/i_auth_repository.dart';
import 'package:tasktap_mobile/main.dart';
import 'package:tasktap_mobile/presentation/providers/auth_providers.dart';

class _MockAuthRepository extends Mock implements IAuthRepository {}

class _MockDio extends Mock implements Dio {}

void main() {
  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    registerFallbackValue(RequestOptions(path: '/'));
  });

  testWidgets('TaskTapApp smoke test — renders without error',
      (WidgetTester tester) async {
    final repo = _MockAuthRepository();
    final authStream = StreamController<AuthUser?>.broadcast();
    final db = AppDatabase(NativeDatabase.memory());
    final mockDio = _MockDio();

    // Stub the sync endpoint so HomeShell's performSync doesn't throw.
    when(
      () => mockDio.get<Map<String, dynamic>>(
        any(),
        queryParameters: any(named: 'queryParameters'),
      ),
    ).thenAnswer(
      (_) async => Response<Map<String, dynamic>>(
        requestOptions: RequestOptions(path: '/api/sync/mobile'),
        statusCode: 200,
        data: {
          'syncedAt': DateTime.utc(2026, 6, 21).toIso8601String(),
          'since': null,
          'schedules': <dynamic>[],
          'draftReports': <dynamic>[],
          'customers': <dynamic>[],
          'locations': <dynamic>[],
          'tickets': <dynamic>[],
        },
      ),
    );

    // Unauthenticated state — app should show login screen.
    when(() => repo.authStateChanges).thenAnswer((_) => authStream.stream);
    when(() => repo.currentUser).thenReturn(null);
    Future.microtask(() => authStream.add(null));

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

    // App should mount a MaterialApp at minimum.
    expect(find.byType(MaterialApp), findsWidgets);

    // Unmount cleanly so Drift stream-close timers fire before the test ends.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();

    await authStream.close();
    await db.close();
  });
}
