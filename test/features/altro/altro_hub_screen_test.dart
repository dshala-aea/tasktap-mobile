// dart format width=100
// test/features/altro/altro_hub_screen_test.dart
//
// The Altro hub's entry into self-service smart working.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:tasktap_mobile/core/router/app_router.dart';
import 'package:tasktap_mobile/data/entitlements/entitlement_providers.dart';
import 'package:tasktap_mobile/domain/auth/auth_user.dart';
import 'package:tasktap_mobile/features/altro/altro_hub_screen.dart';
import 'package:tasktap_mobile/features/smart_working/smart_working_list_screen.dart';
import 'package:tasktap_mobile/presentation/providers/auth_providers.dart';

Widget _app() {
  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (_, _) => const AltroHubScreen()),
      GoRoute(
        path: AppRoutes.altroSmartWorking,
        builder: (_, _) => const SmartWorkingListScreen(),
      ),
    ],
  );
  return ProviderScope(
    overrides: [
      authStateProvider.overrideWith((ref) => Stream<AuthUser?>.value(null)),
      // Nothing cached = the field-seat baseline, which is exactly what a technician on a fresh
      // install sees. `presenze` is part of it, so the tile must be drawn.
      cachedEntitlementProvider.overrideWith((ref) => null),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

void main() {
  testWidgets('tile_opensTheSmartWorkingScreen', (tester) async {
    // No persisted caller id: the list resolves to its empty state without touching the network.
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(400, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    await tester.dragUntilVisible(
      find.text('Smart working'),
      find.byType(CustomScrollView),
      const Offset(0, -200),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Smart working'));
    await tester.pumpAndSettle();

    expect(find.byType(SmartWorkingListScreen), findsOneWidget);
    // The list screen's own header — the hub tile is offstage by now.
    expect(find.text('Smart working'), findsOneWidget);
    expect(find.text('Nessuna richiesta'), findsOneWidget);
  });
}
