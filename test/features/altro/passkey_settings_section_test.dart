// dart format width=100
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/core/security/passkey_support.dart';
import 'package:tasktap_mobile/core/widgets/app_button.dart';
import 'package:tasktap_mobile/data/auth/passkey_enroller.dart';
import 'package:tasktap_mobile/domain/auth/auth_failure.dart';
import 'package:tasktap_mobile/features/altro/passkey_settings_section.dart';

class _FakePasskeyEnroller extends PasskeyEnroller {
  _FakePasskeyEnroller() : super(Dio());

  List<PasskeySummary> passkeys = <PasskeySummary>[];
  AuthFailure? listFailure;
  ({bool ok, AuthFailure? failure}) enrolResult = (ok: true, failure: null);
  ({bool ok, AuthFailure? failure}) removeResult = (ok: true, failure: null);

  /// Thrown by [list] while set, modelling a provider that errors rather than
  /// returning the `(items: [], failure: …)` record.
  Object? listError;

  /// Set by [enrol] on success, so the refresh triggered by the enrolment fails.
  Object? listErrorAfterEnrol;

  int listCalls = 0;
  final List<String> enrolNames = <String>[];
  final List<String> removedIds = <String>[];

  @override
  Future<({List<PasskeySummary> items, AuthFailure? failure})> list() async {
    listCalls++;
    if (listError case final error?) throw error;
    return (items: List<PasskeySummary>.of(passkeys), failure: listFailure);
  }

  @override
  Future<({bool ok, AuthFailure? failure})> enrol({required String name}) async {
    enrolNames.add(name);
    if (enrolResult.ok) {
      passkeys = [...passkeys, (id: 'pk-new', name: name)];
      listError = listErrorAfterEnrol;
    }
    return enrolResult;
  }

  @override
  Future<({bool ok, AuthFailure? failure})> remove(String id) async {
    removedIds.add(id);
    if (removeResult.ok) {
      passkeys = passkeys.where((p) => p.id != id).toList();
    }
    return removeResult;
  }
}

Widget _wrap(_FakePasskeyEnroller enroller, {bool supported = true}) {
  return ProviderScope(
    overrides: [
      passkeyEnrollerProvider.overrideWithValue(enroller),
      passkeySupportedProvider.overrideWith((ref) async => supported),
    ],
    child: const MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: PasskeySettingsSection())),
    ),
  );
}

Future<void> _pump(
  WidgetTester tester,
  _FakePasskeyEnroller enroller, {
  bool supported = true,
}) async {
  await tester.pumpWidget(_wrap(enroller, supported: supported));
  await tester.pumpAndSettle();
}

Future<void> _drain(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows the personal-device warning', (tester) async {
    final enroller = _FakePasskeyEnroller();
    await _pump(tester, enroller);

    expect(find.text('Accesso con passkey'), findsOneWidget);
    expect(
      find.text(
        'La passkey è protetta dal blocco schermo di questo dispositivo. '
        'Attivala solo su un dispositivo personale.',
      ),
      findsOneWidget,
    );

    await _drain(tester);
  });

  testWidgets('shows the genuine empty state when there are no passkeys', (tester) async {
    final enroller = _FakePasskeyEnroller();
    await _pump(tester, enroller);

    expect(find.text('Nessuna passkey attiva su questo dispositivo.'), findsOneWidget);
    expect(find.text(authFailureMessage(const NetworkError())), findsNothing);
    expect(find.text('Riprova'), findsNothing);

    await _drain(tester);
  });

  testWidgets('enrolling success refreshes the list and toasts', (tester) async {
    final enroller = _FakePasskeyEnroller();
    await _pump(tester, enroller);

    await tester.tap(find.text('Attiva accesso con passkey'));
    await tester.pumpAndSettle();

    expect(enroller.enrolNames, ['TaskTap su questo dispositivo']);
    expect(find.text('TaskTap su questo dispositivo'), findsOneWidget);
    expect(find.text('Passkey attivata.'), findsOneWidget);

    await _drain(tester);
  });

  testWidgets('a failed refresh after enrolment clears busy and shows the failure branch', (
    tester,
  ) async {
    final enroller = _FakePasskeyEnroller()..listErrorAfterEnrol = Exception('list broke');
    await _pump(tester, enroller);

    await tester.tap(find.text('Attiva accesso con passkey'));
    await tester.pumpAndSettle();

    expect(find.text('Impossibile caricare le passkey. Riprova.'), findsOneWidget);
    expect(find.text('Riprova'), findsOneWidget);
    expect(find.text('Passkey attivata.'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    final button = tester.widget<AppButton>(
      find.widgetWithText(AppButton, 'Attiva accesso con passkey'),
    );
    expect(button.isLoading, isFalse);
    expect(button.onPressed, isNotNull);

    await _drain(tester);
  });

  testWidgets('a failed enrolment shows an error and leaves the list unchanged', (tester) async {
    final enroller = _FakePasskeyEnroller()
      ..passkeys = [(id: 'pk-1', name: 'iPhone di Mario')]
      ..enrolResult = (ok: false, failure: const NetworkError());
    await _pump(tester, enroller);

    await tester.tap(find.text('Attiva accesso con passkey'));
    await tester.pumpAndSettle();

    expect(find.text(authFailureMessage(const NetworkError())), findsOneWidget);
    expect(find.text('iPhone di Mario'), findsOneWidget);
    expect(find.text('Passkey attivata.'), findsNothing);

    await _drain(tester);
  });

  testWidgets('remove asks for confirmation and calls remove', (tester) async {
    final enroller = _FakePasskeyEnroller()..passkeys = [(id: 'pk-1', name: 'iPhone di Mario')];
    await _pump(tester, enroller);

    await tester.tap(find.text('Rimuovi passkey'));
    await tester.pumpAndSettle();

    expect(enroller.removedIds, isEmpty);
    expect(find.text('Rimuovi la passkey?'), findsOneWidget);

    await tester.tap(find.text('Rimuovi'));
    await tester.pumpAndSettle();

    expect(enroller.removedIds, ['pk-1']);
    expect(find.text('iPhone di Mario'), findsNothing);

    await _drain(tester);
  });

  testWidgets('section is disabled with a reason when unsupported', (tester) async {
    final enroller = _FakePasskeyEnroller();
    await _pump(tester, enroller, supported: false);

    expect(find.text(authFailureMessage(const PasskeyUnavailable())), findsOneWidget);

    final button = tester.widget<AppButton>(
      find.widgetWithText(AppButton, 'Attiva accesso con passkey'),
    );
    expect(button.onPressed, isNull);
    expect(enroller.listCalls, 0);

    await _drain(tester);
  });

  testWidgets('a failed list shows the mapped failure and retries', (tester) async {
    final enroller = _FakePasskeyEnroller()..listFailure = const NetworkError();
    await _pump(tester, enroller);

    expect(find.text(authFailureMessage(const NetworkError())), findsOneWidget);
    expect(find.text('Nessuna passkey attiva su questo dispositivo.'), findsNothing);

    enroller
      ..listFailure = null
      ..passkeys = [(id: 'pk-1', name: 'iPhone di Mario')];

    await tester.tap(find.text('Riprova'));
    await tester.pumpAndSettle();

    expect(enroller.listCalls, greaterThanOrEqualTo(2));
    expect(find.text('iPhone di Mario'), findsOneWidget);

    await _drain(tester);
  });
}
