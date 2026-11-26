// Browser-only login: one primary "Accedi" button, helper text, no credential field of any kind.
//
// The identity service owns the credential entry (password, passkey, SSO). This screen only starts
// the browser flow and answers a cancelled / offline / failed attempt with a calm message.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tasktap_mobile/core/widgets/app_button.dart';
import 'package:tasktap_mobile/core/widgets/inline_alert.dart';
import 'package:tasktap_mobile/domain/auth/auth_failure.dart';
import 'package:tasktap_mobile/domain/auth/auth_user.dart';
import 'package:tasktap_mobile/domain/auth/i_auth_repository.dart';
import 'package:tasktap_mobile/presentation/providers/auth_providers.dart';
import 'package:tasktap_mobile/presentation/screens/login/login_screen.dart';

class MockAuthRepository extends Mock implements IAuthRepository {}

Widget _buildLoginScreen(IAuthRepository repo) {
  return ProviderScope(
    retry: (_, _) => null,
    overrides: [authRepositoryProvider.overrideWithValue(repo)],
    child: const MaterialApp(home: LoginScreen()),
  );
}

Finder get _loginCta => find.widgetWithText(AppButton, 'Accedi');

void main() {
  late MockAuthRepository repo;
  late StreamController<AuthUser?> authStream;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    repo = MockAuthRepository();
    authStream = StreamController<AuthUser?>.broadcast();
    when(() => repo.authStateChanges).thenAnswer((_) => authStream.stream);
    when(() => repo.currentUser).thenReturn(null);
  });

  tearDown(() {
    authStream.close();
  });

  group('layout', () {
    testWidgets('renders the logo, the helper text and one primary Accedi button', (tester) async {
      await tester.pumpWidget(_buildLoginScreen(repo));
      await tester.pumpAndSettle();

      expect(find.text('TT'), findsOneWidget);
      expect(find.text('TaskTap'), findsOneWidget);
      expect(find.textContaining('Si apre il browser'), findsOneWidget);
      expect(find.byType(AppButton), findsOneWidget);
      expect(_loginCta, findsOneWidget);
    });

    testWidgets('has no text field and no obscured field: credentials are never typed in the app',
        (tester) async {
      await tester.pumpWidget(_buildLoginScreen(repo));
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsNothing);
      expect(find.byType(TextFormField), findsNothing);
      expect(find.byType(EditableText), findsNothing);
      expect(find.text('Password'), findsNothing);
      expect(find.text('Continua'), findsNothing);
      expect(find.text('Accedi con passkey'), findsNothing);
      expect(find.text('Password dimenticata?'), findsNothing);
    });

    testWidgets('keeps the access-request entry point', (tester) async {
      await tester.pumpWidget(_buildLoginScreen(repo));
      await tester.pumpAndSettle();

      expect(find.text('Richiedi accesso'), findsOneWidget);
    });
  });

  group('signing in', () {
    testWidgets('Accedi starts the browser flow once, without a loginHint on a fresh device',
        (tester) async {
      when(() => repo.signIn()).thenAnswer((_) async => (user: null, failure: null));

      await tester.pumpWidget(_buildLoginScreen(repo));
      await tester.pumpAndSettle();
      await tester.tap(_loginCta);
      await tester.pumpAndSettle();

      verify(() => repo.signIn()).called(1);
    });

    testWidgets('Accedi passes the last used email as the loginHint', (tester) async {
      SharedPreferences.setMockInitialValues({lastLoginEmailPrefsKey: 'saved@tasktap.io'});
      when(() => repo.signIn(loginHint: any(named: 'loginHint')))
          .thenAnswer((_) async => (user: null, failure: null));

      await tester.pumpWidget(_buildLoginScreen(repo));
      await tester.pumpAndSettle();
      await tester.tap(_loginCta);
      await tester.pumpAndSettle();

      verify(() => repo.signIn(loginHint: 'saved@tasktap.io')).called(1);
    });

    testWidgets('the button shows its loading state while the browser flow runs and ignores a second tap',
        (tester) async {
      final completer = Completer<({AuthUser? user, AuthFailure? failure})>();
      when(() => repo.signIn()).thenAnswer((_) => completer.future);

      await tester.pumpWidget(_buildLoginScreen(repo));
      await tester.pumpAndSettle();
      await tester.tap(_loginCta);
      await tester.pump();

      expect(tester.widget<AppButton>(find.byType(AppButton)).isLoading, isTrue);
      await tester.tap(find.byType(AppButton), warnIfMissed: false);

      completer.complete((user: null, failure: null));
      await tester.pumpAndSettle();

      verify(() => repo.signIn()).called(1);
      expect(tester.widget<AppButton>(find.byType(AppButton)).isLoading, isFalse);
    });
  });

  group('calm failures', () {
    testWidgets('a cancelled sign-in shows the calm retry message and keeps the button',
        (tester) async {
      when(() => repo.signIn())
          .thenAnswer((_) async => (user: null, failure: const SignInCancelled()));

      await tester.pumpWidget(_buildLoginScreen(repo));
      await tester.pumpAndSettle();
      await tester.tap(_loginCta);
      await tester.pumpAndSettle();

      expect(find.text(authFailureMessage(const SignInCancelled())), findsOneWidget);
      expect(_loginCta, findsOneWidget);
      verifyNever(() => repo.signOut());
    });

    testWidgets('an offline attempt shows the connection message', (tester) async {
      when(() => repo.signIn())
          .thenAnswer((_) async => (user: null, failure: const NetworkError()));

      await tester.pumpWidget(_buildLoginScreen(repo));
      await tester.pumpAndSettle();
      await tester.tap(_loginCta);
      await tester.pumpAndSettle();

      expect(find.text(authFailureMessage(const NetworkError())), findsOneWidget);
      expect(find.byType(InlineAlert), findsOneWidget);
      verifyNever(() => repo.signOut());
    });

    testWidgets('the message clears when the user tries again', (tester) async {
      var attempts = 0;
      when(() => repo.signIn()).thenAnswer((_) async {
        attempts++;
        if (attempts == 1) return (user: null, failure: const SignInCancelled());
        return (user: null, failure: null);
      });

      await tester.pumpWidget(_buildLoginScreen(repo));
      await tester.pumpAndSettle();
      await tester.tap(_loginCta);
      await tester.pumpAndSettle();
      expect(find.byType(InlineAlert), findsOneWidget);

      await tester.tap(_loginCta);
      await tester.pumpAndSettle();
      expect(find.byType(InlineAlert), findsNothing);
    });
  });

  group('access request', () {
    testWidgets('Richiedi accesso opens the request form', (tester) async {
      await tester.pumpWidget(_buildLoginScreen(repo));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Richiedi accesso'));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('access-request-email')), findsOneWidget);
    });
  });
}
