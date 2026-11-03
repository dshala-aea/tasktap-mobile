import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mocktail/mocktail.dart';

import 'package:tasktap_mobile/core/theme/app_theme.dart';
import 'package:tasktap_mobile/core/widgets/app_button.dart';
import 'package:tasktap_mobile/data/ferie/absence_request_api_client.dart';
import 'package:tasktap_mobile/data/smart_working/smart_working_request_api_client.dart';
import 'package:tasktap_mobile/data/sync/connectivity_provider.dart';
import 'package:tasktap_mobile/data/users/user_directory.dart';
import 'package:tasktap_mobile/features/approvazioni/approvazioni_providers.dart';
import 'package:tasktap_mobile/features/approvazioni/approvazioni_screen.dart';

class _MockAbsenceApi extends Mock implements AbsenceRequestApiClient {}

class _MockSmartWorkingApi extends Mock implements SmartWorkingRequestApiClient {}

AbsenceRequestDto _absence({String id = 'a1', String reason = 'Vacanza'}) => AbsenceRequestDto(
  id: id,
  requestedByUserId: 'u1',
  createdByUserId: 'u1',
  type: 0,
  startDate: DateTime(2026, 3, 12),
  endDate: DateTime(2026, 3, 14),
  reason: reason,
  status: 0,
);

SmartWorkingRequestDto _smartWorking({String id = 's1', String? reason = 'Lavoro da casa'}) =>
    SmartWorkingRequestDto(
      id: id,
      requestedByUserId: 'u1',
      createdByUserId: 'u1',
      startDate: DateTime(2026, 3, 16),
      endDate: DateTime(2026, 3, 17),
      reason: reason,
      status: 0,
    );

Widget _app({
  List<AbsenceRequestDto> absences = const [],
  List<SmartWorkingRequestDto> smartWorking = const [],
  Map<String, String> names = const {'u1': 'Mario Rossi'},
  bool online = true,
  Object? absenceError,
  Object? smartWorkingError,
  AbsenceRequestApiClient? absenceApi,
  SmartWorkingRequestApiClient? smartWorkingApi,
}) => ProviderScope(
  overrides: [
    absenceApprovalQueueProvider.overrideWith((ref) async {
      if (absenceError != null) throw absenceError;
      return absences;
    }),
    smartWorkingApprovalQueueProvider.overrideWith((ref) async {
      if (smartWorkingError != null) throw smartWorkingError;
      return smartWorking;
    }),
    userNameByIdProvider.overrideWith((ref) async => names),
    isOnlineProvider.overrideWithValue(online),
    if (absenceApi != null) absenceRequestApiClientProvider.overrideWithValue(absenceApi),
    if (smartWorkingApi != null)
      smartWorkingRequestApiClientProvider.overrideWithValue(smartWorkingApi),
  ],
  child: MaterialApp(theme: buildAppTheme(), home: const ApprovazioniScreen()),
);

void main() {
  setUpAll(() async {
    await initializeDateFormatting('it', null);
  });

  testWidgets('renders both tabs and defaults to Ferie e permessi', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    expect(find.text('Approvazioni'), findsOneWidget);
    expect(find.text('Ferie e permessi'), findsOneWidget);
    expect(find.text('Smart working'), findsOneWidget);
  });

  testWidgets('an absence row shows the requester, type, period and reason', (tester) async {
    await tester.pumpWidget(_app(absences: [_absence()]));
    await tester.pumpAndSettle();

    expect(find.text('Mario Rossi'), findsOneWidget);
    expect(find.text('Ferie · 12 mar – 14 mar'), findsOneWidget);
    expect(find.text('Vacanza'), findsOneWidget);
  });

  testWidgets('switching to Smart working shows its rows', (tester) async {
    await tester.pumpWidget(
      _app(absences: [_absence()], smartWorking: [_smartWorking()]),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Smart working'));
    await tester.pumpAndSettle();

    expect(find.text('Smart working · 16 mar – 17 mar'), findsOneWidget);
    expect(find.text('Lavoro da casa'), findsOneWidget);
  });

  testWidgets('an empty queue says there is nothing to approve', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    expect(find.text('Nessuna richiesta da approvare'), findsOneWidget);
  });

  testWidgets('a failed read shows the retryable error', (tester) async {
    await tester.pumpWidget(_app(absenceError: Exception('boom')));
    await tester.pumpAndSettle();

    expect(find.text('Impossibile caricare i dati'), findsOneWidget);
    expect(find.text('Riprova'), findsOneWidget);
  });

  testWidgets('offline shows the offline state instead of a queue', (tester) async {
    await tester.pumpWidget(_app(online: false, absences: [_absence()]));
    await tester.pumpAndSettle();

    expect(find.text('Sei offline'), findsOneWidget);
    expect(find.text('Mario Rossi'), findsNothing);
  });

  testWidgets('an unknown requester id renders an em dash, never the id', (tester) async {
    await tester.pumpWidget(_app(absences: [_absence()], names: const {}));
    await tester.pumpAndSettle();

    expect(find.text('—'), findsOneWidget);
    expect(find.text('u1'), findsNothing);
  });

  group('decisions', () {
    testWidgets('approve confirms first, then sends exactly once', (tester) async {
      final api = _MockAbsenceApi();
      final done = Completer<void>();
      when(() => api.approve('a1')).thenAnswer((_) => done.future);

      await tester.pumpWidget(_app(absences: [_absence()], absenceApi: api));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Approva'));
      await tester.pumpAndSettle();
      expect(find.text('Approvare la richiesta di Mario Rossi?'), findsOneWidget);

      await tester.tap(find.text('Approva richiesta'));
      await tester.pump();
      verify(() => api.approve('a1')).called(1);

      done.complete();
      await tester.pumpAndSettle();
      expect(find.text('Richiesta approvata.'), findsOneWidget);
    });

    testWidgets('cancelling the confirmation sends nothing', (tester) async {
      final api = _MockAbsenceApi();

      await tester.pumpWidget(_app(absences: [_absence()], absenceApi: api));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Approva'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Annulla'));
      await tester.pumpAndSettle();

      verifyNever(() => api.approve(any()));
    });

    testWidgets('reject sends the trimmed reason', (tester) async {
      final api = _MockAbsenceApi();
      when(() => api.reject('a1', reason: any(named: 'reason'))).thenAnswer((_) async {});

      await tester.pumpWidget(_app(absences: [_absence()], absenceApi: api));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Rifiuta'));
      await tester.pumpAndSettle();
      expect(find.text('Rifiuta la richiesta di Mario Rossi'), findsOneWidget);

      await tester.enterText(find.byType(TextField), '  Copertura  ');
      await tester.pump();
      final submit = tester.widget<AppButton>(
        find.widgetWithText(AppButton, 'Conferma rifiuto'),
      );
      expect(submit.onPressed, isNotNull, reason: 'a non-empty reason enables the submit');
      await tester.tap(find.text('Conferma rifiuto'));
      await tester.pumpAndSettle();

      verify(() => api.reject('a1', reason: 'Copertura')).called(1);
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('a non-400 failure keeps the sheet and the typed reason', (tester) async {
      final api = _MockAbsenceApi();
      when(() => api.reject('a1', reason: any(named: 'reason'))).thenThrow(Exception('offline'));

      await tester.pumpWidget(_app(absences: [_absence()], absenceApi: api));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Rifiuta'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Copertura');
      await tester.pump();
      await tester.tap(find.text('Conferma rifiuto'));
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Copertura'), findsOneWidget);
      expect(find.text('Impossibile rifiutare la richiesta. Riprova.'), findsOneWidget);
    });

    testWidgets('going offline before confirming sends nothing', (tester) async {
      final api = _MockAbsenceApi();
      final online = ValueNotifier(true);
      addTearDown(online.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            absenceApprovalQueueProvider.overrideWith((ref) async => [_absence()]),
            userNameByIdProvider.overrideWith((ref) async => const {'u1': 'Mario Rossi'}),
            isOnlineProvider.overrideWith((ref) => online.value),
            absenceRequestApiClientProvider.overrideWithValue(api),
          ],
          child: MaterialApp(theme: buildAppTheme(), home: const ApprovazioniScreen()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Approva'));
      await tester.pumpAndSettle();

      online.value = false;
      final container = ProviderScope.containerOf(
        tester.element(find.byType(ApprovazioniScreen)),
      );
      container.invalidate(isOnlineProvider);
      await tester.pump();

      await tester.tap(find.text('Approva richiesta'));
      await tester.pumpAndSettle();

      verifyNever(() => api.approve(any()));
      expect(find.textContaining('Sei offline'), findsWidgets);
    });

    testWidgets('a 400 closes the sheet and shows the server detail', (tester) async {
      final api = _MockAbsenceApi();
      when(() => api.reject('a1', reason: any(named: 'reason'))).thenThrow(
        const AbsenceRequestValidationError('Solo una richiesta in attesa può essere rifiutata.'),
      );

      await tester.pumpWidget(_app(absences: [_absence()], absenceApi: api));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Rifiuta'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Copertura');
      await tester.pump();
      await tester.tap(find.text('Conferma rifiuto'));
      await tester.pumpAndSettle();

      expect(find.text('Solo una richiesta in attesa può essere rifiutata.'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
    });
  });
}
