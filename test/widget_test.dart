// Widget smoke test — verifies the app tree assembles without error.
// Full shell tests are in test/presentation/app_shell_test.dart.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tasktap_mobile/domain/auth/auth_user.dart';
import 'package:tasktap_mobile/domain/auth/i_auth_repository.dart';
import 'package:tasktap_mobile/main.dart';
import 'package:tasktap_mobile/presentation/providers/auth_providers.dart';

class _MockAuthRepository extends Mock implements IAuthRepository {}

void main() {
  testWidgets('TaskTapApp smoke test — renders without error',
      (WidgetTester tester) async {
    final repo = _MockAuthRepository();
    final authStream = StreamController<AuthUser?>.broadcast();

    // Unauthenticated state — app should show login screen.
    when(() => repo.authStateChanges).thenAnswer((_) => authStream.stream);
    when(() => repo.currentUser).thenReturn(null);
    Future.microtask(() => authStream.add(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [authRepositoryProvider.overrideWithValue(repo)],
        child: const TaskTapApp(),
      ),
    );
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // App should mount a MaterialApp at minimum.
    expect(find.byType(MaterialApp), findsWidgets);

    await authStream.close();
  });
}
