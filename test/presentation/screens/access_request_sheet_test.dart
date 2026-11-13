import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tasktap_mobile/core/theme/app_theme.dart';
import 'package:tasktap_mobile/core/widgets/app_button.dart';
import 'package:tasktap_mobile/data/access_requests/access_request_api_client.dart';
import 'package:tasktap_mobile/presentation/screens/login/access_request_sheet.dart';

class MockAccessRequestApiClient extends Mock implements AccessRequestApiClient {}

Widget _host(MockAccessRequestApiClient client, {String initialEmail = 'tech@tasktap.io'}) {
  return ProviderScope(
    overrides: [accessRequestApiClientProvider.overrideWithValue(client)],
    child: MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showAccessRequestSheet(context, initialEmail: initialEmail),
            child: const Text('apri'),
          ),
        ),
      ),
    ),
  );
}

Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.text('apri'));
  await tester.pumpAndSettle();
}

TextFormField _field(WidgetTester tester, String key) => tester.widget<TextFormField>(
  find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(TextFormField)),
);

Finder get _submit => find.widgetWithText(AppButton, 'Invia richiesta');

Future<void> _enter(WidgetTester tester, String key, String text) async {
  final finder = find.byKey(ValueKey(key));
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.enterText(finder, text);
  await tester.pumpAndSettle();
}

Future<void> _tapSubmit(WidgetTester tester) async {
  await tester.ensureVisible(_submit);
  await tester.pumpAndSettle();
  await tester.tap(_submit);
  await tester.pumpAndSettle();
}

void _stubSubmit(MockAccessRequestApiClient client) {
  when(
    () => client.submit(
      email: any(named: 'email'),
      name: any(named: 'name'),
      company: any(named: 'company'),
      phone: any(named: 'phone'),
      message: any(named: 'message'),
    ),
  ).thenAnswer((_) async {});
}

DioException _dioFailure({int? status, DioExceptionType type = DioExceptionType.badResponse}) {
  final options = RequestOptions(path: '/api/access-requests');
  return DioException(
    type: type,
    requestOptions: options,
    response: status == null ? null : Response<void>(statusCode: status, requestOptions: options),
  );
}

void main() {
  late MockAccessRequestApiClient client;

  setUp(() {
    client = MockAccessRequestApiClient();
  });

  testWidgets('prefills the email from the login field', (tester) async {
    await tester.pumpWidget(_host(client, initialEmail: '  tech@tasktap.io  '));
    await _open(tester);

    expect(_field(tester, 'access-request-email').controller?.text, 'tech@tasktap.io');
  });

  testWidgets('blocks submission when the email is invalid', (tester) async {
    await tester.pumpWidget(_host(client, initialEmail: ''));
    await _open(tester);

    await _enter(tester, 'access-request-email', 'not-an-email');
    await _tapSubmit(tester);

    expect(find.text('Inserisci un indirizzo email valido.'), findsOneWidget);
    verifyNever(
      () => client.submit(
        email: any(named: 'email'),
        name: any(named: 'name'),
        company: any(named: 'company'),
        phone: any(named: 'phone'),
        message: any(named: 'message'),
      ),
    );
  });

  testWidgets('requires an email', (tester) async {
    await tester.pumpWidget(_host(client, initialEmail: ''));
    await _open(tester);

    await _tapSubmit(tester);

    expect(find.text('Inserisci la tua email.'), findsOneWidget);
  });

  testWidgets('submits the email and the optional values', (tester) async {
    _stubSubmit(client);
    await tester.pumpWidget(_host(client));
    await _open(tester);

    await _enter(tester, 'access-request-name', 'Mario Rossi');
    await _enter(tester, 'access-request-company', 'ACME');
    await _enter(tester, 'access-request-phone', '333 1234567');
    await _enter(tester, 'access-request-message', 'Vorrei provare.');
    await _tapSubmit(tester);

    verify(
      () => client.submit(
        email: 'tech@tasktap.io',
        name: 'Mario Rossi',
        company: 'ACME',
        phone: '333 1234567',
        message: 'Vorrei provare.',
      ),
    ).called(1);
  });

  testWidgets('shows the success message', (tester) async {
    _stubSubmit(client);
    await tester.pumpWidget(_host(client));
    await _open(tester);

    await _tapSubmit(tester);

    expect(find.text('Richiesta inviata. Ti contatteremo.'), findsOneWidget);
    expect(_submit, findsNothing);
  });

  testWidgets('shows a safe message on 503', (tester) async {
    when(
      () => client.submit(
        email: any(named: 'email'),
        name: any(named: 'name'),
        company: any(named: 'company'),
        phone: any(named: 'phone'),
        message: any(named: 'message'),
      ),
    ).thenThrow(_dioFailure(status: 503));

    await tester.pumpWidget(_host(client));
    await _open(tester);
    await _tapSubmit(tester);

    expect(find.text('Il server non risponde. Riprova tra qualche minuto.'), findsOneWidget);
    expect(_field(tester, 'access-request-email').controller?.text, 'tech@tasktap.io');
  });

  testWidgets('shows a safe message when rate limited', (tester) async {
    when(
      () => client.submit(
        email: any(named: 'email'),
        name: any(named: 'name'),
        company: any(named: 'company'),
        phone: any(named: 'phone'),
        message: any(named: 'message'),
      ),
    ).thenThrow(_dioFailure(status: 429));

    await tester.pumpWidget(_host(client));
    await _open(tester);
    await _tapSubmit(tester);

    expect(find.text('Il server è occupato. Attendi qualche istante e riprova.'), findsOneWidget);
  });

  testWidgets('shows a safe message with no connection', (tester) async {
    when(
      () => client.submit(
        email: any(named: 'email'),
        name: any(named: 'name'),
        company: any(named: 'company'),
        phone: any(named: 'phone'),
        message: any(named: 'message'),
      ),
    ).thenThrow(_dioFailure(type: DioExceptionType.connectionError));

    await tester.pumpWidget(_host(client));
    await _open(tester);
    await _tapSubmit(tester);

    expect(
      find.text(
        'Nessuna connessione: impossibile inviare la richiesta ora. '
        'Riprova quando torni online.',
      ),
      findsOneWidget,
    );
  });
}
