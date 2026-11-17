// test/features/altro/logout_progress_sheet_test.dart
//
// Pins the one navigation step of logout: the non-dismissible progress sheet
// (`runLogoutWithProgress`, logout_dialog.dart) closes itself when the sign-out work finishes.
//
// The sheet used to pop itself unconditionally. On a *successful* sign-out the router has already
// replaced the page underneath with /login, and the Navigator — not the sheet — is the one taking
// the sheet down: the transition delegate pops the pageless sheet above the exiting page, and that
// exit animation outlives the wipe the sheet was waiting for. The sheet was therefore still
// `mounted` but no longer `isCurrent` when it called `Navigator.pop()`, and `Navigator.pop()` pops
// the topmost *present* route — the /login page. That emptied the navigator while the router still
// believed it was at /login, so nothing rebuilt it: the blank screen a technician could only clear
// by force-quitting the app.
//
// The router is real (go_router, as in the app) rather than a stand-in Navigator: the whole defect
// lives in how a router-driven page swap interacts with a dialog route pushed on top of it, so a
// hand-built route stack would not reproduce it.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:tasktap_mobile/features/altro/logout_dialog.dart';
import 'package:tasktap_mobile/features/altro/logout_flow.dart';

/// A two-route router: the screen the logout button lives on, and the login screen the sign-out
/// redirect lands on. No `redirect` callback — the test drives `go('/login')` itself, which is
/// exactly what the auth gate answers once `authStateProvider` emits null.
GoRouter _buildRouter(Future<LogoutResult> Function() run) {
  return GoRouter(
    initialLocation: '/impostazioni',
    routes: [
      GoRoute(
        path: '/impostazioni',
        builder: (context, state) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => runLogoutWithProgress(context, run),
              child: const Text("Esci dall'account"),
            ),
          ),
        ),
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) =>
            const Scaffold(body: Center(child: Text('LOGIN'))),
      ),
    ],
  );
}

Future<void> _teardown(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
}

/// Opens the sheet and lets its enter transition finish.
///
/// `pumpAndSettle` can never be used while the sheet is on screen: its `CircularProgressIndicator`
/// is indeterminate, i.e. it schedules a frame forever, so settling times out rather than
/// finishing. Bounded pumps are the only way to advance past the dialog's own transition.
Future<void> _openSheet(WidgetTester tester) async {
  await tester.tap(find.text("Esci dall'account"));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

/// Advances a bounded slice of time — enough to run the route transitions a sign-out sets off,
/// without asking the spinner to stop animating.
Future<void> _pumpFrames(WidgetTester tester) async {
  await tester.pump();
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets('the progress sheet never pops the page the router has already navigated to', (
    tester,
  ) async {
    final pending = Completer<LogoutResult>();
    final router = _buildRouter(() => pending.future);
    addTearDown(router.dispose);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await _openSheet(tester);
    expect(find.text('Invio in corso…'), findsOneWidget);

    // What sign-out does to the app: the auth stream emits null, the redirect answers /login, the
    // router swaps the page under the sheet. Frames have to run for the navigator to start taking
    // the pageless sheet down — that exit animation is the window the defect lived in.
    router.go('/login');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // The work finishes while the sheet is still animating out: still mounted, no longer current.
    pending.complete(const LogoutResult(signedOut: true));
    await _pumpFrames(tester);

    expect(
      find.text('LOGIN'),
      findsOneWidget,
      reason: 'the sheet popped the page the router had already navigated to, leaving the '
          'navigator empty — the blank screen that needed an app restart',
    );
    expect(tester.takeException(), isNull);

    await _teardown(tester);
  });

  // The guard must not turn into a sheet nobody can leave: when the sign-out did NOT navigate
  // (a failed flush leaves the technician signed in), the sheet is still the current route and
  // has to close itself, or the caller sits behind a non-dismissible dialog forever.
  testWidgets('a logout that did not sign out still closes its own sheet', (tester) async {
    final pending = Completer<LogoutResult>();
    final router = _buildRouter(() => pending.future);
    addTearDown(router.dispose);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await _openSheet(tester);
    expect(find.text('Invio in corso…'), findsOneWidget);

    pending.complete(const LogoutResult(signedOut: false, remaining: 2));
    await _pumpFrames(tester);

    expect(find.text('Invio in corso…'), findsNothing);
    expect(find.text("Esci dall'account"), findsOneWidget);

    await _teardown(tester);
  });
}
