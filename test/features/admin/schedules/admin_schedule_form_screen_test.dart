// dart format width=100
// test/features/admin/schedules/admin_schedule_form_screen_test.dart
//
// AdminScheduleFormScreen used to offer only a single-technician dropdown, even though the
// backend's assignment model (ADR-0009) has always supported team-lead+staff and squadra
// assignment too, and AdminApiClient.updateSchedule couldn't touch assignment at all. This covers:
//   - each assignment tab (Tecnico / Capo squadra / Squadra) submits the right payload shape on
//     create;
//   - the picker is genuinely in the widget tree, not just accepted by the client method;
//   - an edit submits assignment fields, explicitly clearing the ones not in use;
//   - the pre-save conflict check: a clean save proceeds normally, a conflicting save shows the
//     conflict list and lets the admin force-save, and force-save sends `force=true`.

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tasktap_mobile/data/api/dio_client.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/sync/connectivity_provider.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart';
import 'package:tasktap_mobile/features/admin/schedules/admin_schedule_form_screen.dart';
import 'package:tasktap_mobile/core/widgets/vetro_button.dart';
import 'package:tasktap_mobile/core/widgets/widgets.dart';

class MockDio extends Mock implements Dio {}

Response<T> _ok<T>(T data, String path) =>
    Response<T>(data: data, statusCode: 200, requestOptions: RequestOptions(path: path));

void main() {
  setUpAll(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    registerFallbackValue(RequestOptions(path: '/'));
    await initializeDateFormatting('it', null);
  });

  late AppDatabase db;
  late MockDio mockDio;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    mockDio = MockDio();

    await db
        .into(db.locations)
        .insert(
          LocationsCompanion.insert(
            id: 'loc-1',
            tenantId: 'tenant-1',
            createdAt: DateTime.utc(2026, 1, 1),
            customerId: 'cust-1',
            name: 'Sede Nord',
          ),
        );

    // GET /api/users → technicians (paginated envelope — see json_parse.dart's pagedItems).
    when(
      () => mockDio.get<Map<String, dynamic>>('/api/users', queryParameters: any(named: 'queryParameters')),
    ).thenAnswer(
      (_) async => _ok({
        'items': [
          {'id': 'tech-1', 'displayName': 'Mario Rossi'},
          {'id': 'tech-2', 'displayName': 'Luigi Bianchi'},
        ],
      }, '/api/users'),
    );

    // GET /api/squadre → squadre.
    when(() => mockDio.get<Map<String, dynamic>>('/api/squadre')).thenAnswer(
      (_) async => _ok({
        'items': [
          {'id': 'sq-1', 'nome': 'Squadra Nord'},
        ],
      }, '/api/squadre'),
    );

    // No conflicts by default — individual tests override this.
    when(
      () => mockDio.post<Map<String, dynamic>>(
        '/api/schedules/check-conflicts',
        data: any(named: 'data'),
      ),
    ).thenAnswer((_) async => _ok({'hasConflicts': false, 'conflicts': <dynamic>[]}, '/'));

    when(
      () => mockDio.post<Map<String, dynamic>>(
        '/api/schedules',
        queryParameters: any(named: 'queryParameters'),
        data: any(named: 'data'),
      ),
    ).thenAnswer((_) async => _ok({'id': 'new-sched'}, '/api/schedules'));

    when(
      () => mockDio.put<dynamic>(
        any(that: contains('/api/schedules/')),
        queryParameters: any(named: 'queryParameters'),
        data: any(named: 'data'),
      ),
    ).thenAnswer((_) async => _ok(null, '/api/schedules/sched-1'));
  });

  tearDown(() async => db.close());

  /// A GoRouter harness with a real page stack (initial route → form), so `context.pop(true)` in
  /// `AdminScheduleFormScreen._save` has something to pop back to — the same reasoning
  /// `edit_ticket_screen_test.dart`'s launcher uses for `Navigator.push`, just for go_router.
  Widget buildHarness({String? scheduleId}) {
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => context.push('/form'),
                child: const Text('Apri form'),
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/form',
          builder: (context, state) => AdminScheduleFormScreen(scheduleId: scheduleId),
        ),
      ],
    );

    return ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        dioProvider.overrideWithValue(mockDio),
        isOnlineProvider.overrideWithValue(true),
      ],
      child: MaterialApp.router(routerConfig: router),
    );
  }

  Future<void> openForm(WidgetTester tester, {String? scheduleId}) async {
    await tester.pumpWidget(buildHarness(scheduleId: scheduleId));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apri form'));
    await tester.pumpAndSettle();
  }

  Future<void> selectDropdown(
    WidgetTester tester, {
    required int index,
    required String optionText,
  }) async {
    await tester.tap(find.byType(DropdownButtonFormField<String>).at(index));
    await tester.pumpAndSettle();
    await tester.tap(find.text(optionText).last);
    await tester.pumpAndSettle();
  }

  /// The `AppFieldLabel` for the squadra picker. `AppFieldLabel` renders its text through
  /// `Text.rich` (uppercased, asterisk split into its own span — see
  /// field_label_convention_test.dart), so it can never be reached with `find.text('Squadra *')`;
  /// match on the widget's own un-transformed `label` instead.
  final squadraFieldLabel = find.byWidgetPredicate(
    (w) => w is AppFieldLabel && w.label == 'Squadra *',
  );

  /// The form's own vertical `ListView`'s `Scrollable`. `scrollUntilVisible`'s default `scrollable`
  /// finder is `find.byType(Scrollable)`, which needs exactly one match — but this tree has several:
  /// `AppTabs` renders its tab strip through its own horizontal `ListView.builder`
  /// (app_tabs.dart), and every `TextField`'s `EditableText` carries its own internal `Scrollable`
  /// too (for cursor scrolling).
  ///
  /// `find.descendant(of: <the ListView>, matching: find.byType(Scrollable))` still isn't enough —
  /// "descendant" isn't "direct child": the outer `ListView` contains everything else in the form,
  /// so it also picks up `AppTabs`' and every field's own nested `Scrollable`. What actually
  /// isolates the outer one is an ancestor walk from a plain `Text` that's a direct child of the
  /// `ListView` itself — not nested inside `AppTabs` or any text field — so its only `Scrollable`
  /// ancestor is the page's own. "Assegnazione *" (the tab section's own label, immediately before
  /// `AppTabs` in the `children` list) always exists and is always on-screen near the top,
  /// regardless of which tab or how far the page has scrolled.
  final formScrollable = find.ancestor(
    of: find.text('Assegnazione *'),
    matching: find.byType(Scrollable),
  );

  /// Taps the form's submit button (`Crea pianificazione` / `Salva modifiche`).
  ///
  /// The form's `ListView` — like every other admin form screen's — lazily builds only the
  /// children within its viewport plus cache extent (standard Sliver behaviour, not test-specific:
  /// see new_ticket_form_test.dart for the same pattern). The button sits below the assignment
  /// picker, location field and notes, which pushes it outside that window on the default test
  /// surface, so it has to be scrolled into view before `find` can see it at all — `ensureVisible`
  /// isn't enough here because that scrolls a widget that's already found; this one hasn't been
  /// built yet.
  Future<void> tapSubmitButton(WidgetTester tester, String label) async {
    final button = find.widgetWithText(VetroButton, label);
    await tester.scrollUntilVisible(button, 300, scrollable: formScrollable);
    await tester.tap(button);
    await tester.pumpAndSettle();
  }

  /// Like [tapSubmitButton], for a save that is expected to hit a conflict and open the dialog.
  ///
  /// This can't finish with `pumpAndSettle`: `_isSaving` stays true for as long as the conflict
  /// dialog is up — that is the point, so a second tap can't race in behind it — and `VetroButton`
  /// renders that as an indeterminate `CircularProgressIndicator`, which never lets
  /// `pumpAndSettle`'s frame-quiescence check succeed (the same class of problem
  /// ticket_detail_screen_test.dart's own `tapAndSettle` documents for its upload buttons).
  /// Bounded pumps give the mocked check-conflicts call — and the dialog's entrance animation —
  /// room to resolve without waiting for that spinner to stop, which it never will on its own.
  Future<void> tapSubmitButtonExpectingDialog(WidgetTester tester, String label) async {
    final button = find.widgetWithText(VetroButton, label);
    await tester.scrollUntilVisible(button, 300, scrollable: formScrollable);
    await tester.tap(button);
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  /// `AdminScheduleFormScreen` watches `allLocationsProvider`, a Drift stream. Every test that
  /// pumps it MUST end with this, or Drift's `StreamQueryStore` leaves a zero-duration teardown
  /// `Timer` pending when the widget tree unmounts, and flutter_test's `!timersPending` invariant
  /// check fails right after the test has already passed its own assertions — see
  /// cantiere_timbra_screen_test.dart's identical `_teardown` for the same requirement.
  Future<void> teardown(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  }

  Map<String, dynamic> lastScheduleCreatePayload() {
    final captured = verify(
      () => mockDio.post<Map<String, dynamic>>(
        '/api/schedules',
        queryParameters: captureAny(named: 'queryParameters'),
        data: captureAny(named: 'data'),
      ),
    ).captured;
    return captured[captured.length - 1] as Map<String, dynamic>;
  }

  Map<String, dynamic>? lastQueryParams() {
    final captured = verify(
      () => mockDio.post<Map<String, dynamic>>(
        '/api/schedules',
        queryParameters: captureAny(named: 'queryParameters'),
        data: captureAny(named: 'data'),
      ),
    ).captured;
    return captured[captured.length - 2] as Map<String, dynamic>?;
  }

  group('assignment picker — visible in the widget tree', () {
    testWidgets('shows the three assignment tabs, and Squadra reveals the squadra dropdown', (
      tester,
    ) async {
      await openForm(tester);

      expect(find.text('Tecnico'), findsOneWidget);
      expect(find.text('Capo squadra'), findsOneWidget);
      expect(find.text('Squadra'), findsOneWidget);
      // Default tab is Tecnico — no "Squadra *" field label yet.
      //
      // The field label itself is `AppFieldLabel`, which renders through `Text.rich` (uppercased,
      // with the asterisk as its own coloured `TextSpan` — see field_label_convention_test.dart) —
      // not a plain `Text('Squadra *')`. `find.text` only matches a `Text` widget's own `.data`, so
      // it can never see this label; match on the widget's un-transformed `label` instead.
      expect(squadraFieldLabel, findsNothing);

      await tester.tap(find.text('Squadra'));
      await tester.pumpAndSettle();

      expect(squadraFieldLabel, findsOneWidget);
      await teardown(tester);
    });
  });

  group('create — payload shape per assignment type', () {
    testWidgets('Tecnico sends userId, no teamLeadId/staffIds/squadraId', (tester) async {
      await openForm(tester);

      await selectDropdown(tester, index: 0, optionText: 'Mario Rossi'); // technician
      await selectDropdown(tester, index: 1, optionText: 'Sede Nord'); // location

      await tapSubmitButton(tester, 'Crea pianificazione');

      final body = lastScheduleCreatePayload();
      expect(body['userId'], 'tech-1');
      expect(body.containsKey('teamLeadId'), isFalse);
      expect(body.containsKey('staffIds'), isFalse);
      expect(body.containsKey('squadraId'), isFalse);
      await teardown(tester);
    });

    testWidgets('Capo squadra sends teamLeadId + staffIds, no userId/squadraId', (tester) async {
      await openForm(tester);

      await tester.tap(find.text('Capo squadra'));
      await tester.pumpAndSettle();

      await selectDropdown(tester, index: 0, optionText: 'Mario Rossi'); // team lead
      await tester.pumpAndSettle();
      // Staff picker offers everyone except the selected lead — Luigi Bianchi.
      await tester.tap(find.text('Luigi Bianchi'));
      await tester.pumpAndSettle();

      await selectDropdown(tester, index: 1, optionText: 'Sede Nord'); // location

      await tapSubmitButton(tester, 'Crea pianificazione');

      final body = lastScheduleCreatePayload();
      expect(body['teamLeadId'], 'tech-1');
      expect(body['staffIds'], contains('tech-2'));
      expect(body.containsKey('userId'), isFalse);
      expect(body.containsKey('squadraId'), isFalse);
      await teardown(tester);
    });

    testWidgets('Squadra sends squadraId, no userId/teamLeadId', (tester) async {
      await openForm(tester);

      await tester.tap(find.text('Squadra'));
      await tester.pumpAndSettle();

      await selectDropdown(tester, index: 0, optionText: 'Squadra Nord'); // squadra
      await selectDropdown(tester, index: 1, optionText: 'Sede Nord'); // location

      await tapSubmitButton(tester, 'Crea pianificazione');

      final body = lastScheduleCreatePayload();
      expect(body['squadraId'], 'sq-1');
      expect(body.containsKey('userId'), isFalse);
      expect(body.containsKey('teamLeadId'), isFalse);
      await teardown(tester);
    });
  });

  group('update — includes assignment fields', () {
    testWidgets('edit submits userId and explicitly clears the unused assignment sources', (
      tester,
    ) async {
      await db
          .into(db.schedules)
          .insert(
            SchedulesCompanion.insert(
              id: 'sched-1',
              tenantId: 'tenant-1',
              createdAt: DateTime.utc(2026, 1, 1),
              activityDate: DateTime.utc(2026, 6, 21),
              timeStartMinutes: 480,
              timeEndMinutes: 600,
              userId: 'tech-1',
              statusId: 1,
              locationId: 'loc-1',
              title: 'Manutenzione',
              description: '',
            ),
          );
      // Offline-safe fallback path: no ScheduleAssignees row and the live detail fetch below both
      // resolve to "direct, tech-1" — consistent so the test isn't sensitive to which one wins.
      when(() => mockDio.get<Map<String, dynamic>>('/api/schedules/sched-1')).thenAnswer(
        (_) async => _ok({
          'userId': 'tech-1',
          'teamLeadId': null,
          'squadraId': null,
          'assignees': <dynamic>[],
        }, '/api/schedules/sched-1'),
      );

      await openForm(tester, scheduleId: 'sched-1');

      await tapSubmitButton(tester, 'Salva modifiche');

      final captured = verify(
        () => mockDio.put<dynamic>(
          '/api/schedules/sched-1',
          queryParameters: captureAny(named: 'queryParameters'),
          data: captureAny(named: 'data'),
        ),
      ).captured;
      final body = captured[captured.length - 1] as Map<String, dynamic>;

      expect(body['userId'], 'tech-1');
      expect(body['teamLeadId'], '00000000-0000-0000-0000-000000000000');
      expect(body['squadraId'], '00000000-0000-0000-0000-000000000000');
      expect(body['staffIds'], '[]');
      await teardown(tester);
    });
  });

  group('conflict check', () {
    testWidgets('a conflict-free save proceeds without showing a dialog', (tester) async {
      await openForm(tester);

      await selectDropdown(tester, index: 0, optionText: 'Mario Rossi');
      await selectDropdown(tester, index: 1, optionText: 'Sede Nord');

      await tapSubmitButton(tester, 'Crea pianificazione');

      expect(find.text('Conflitti rilevati'), findsNothing);
      verify(
        () => mockDio.post<Map<String, dynamic>>(
          '/api/schedules',
          queryParameters: any(named: 'queryParameters'),
          data: any(named: 'data'),
        ),
      ).called(1);
      await teardown(tester);
    });

    testWidgets('a conflicting save shows the conflict list and lets the admin force-save', (
      tester,
    ) async {
      when(
        () => mockDio.post<Map<String, dynamic>>(
          '/api/schedules/check-conflicts',
          data: any(named: 'data'),
        ),
      ).thenAnswer(
        (_) async => _ok({
          'hasConflicts': true,
          'conflicts': [
            {
              'id': 'other-sched',
              'activityDate': '2026-08-24T00:00:00Z',
              'timeStart': '08:00:00',
              'timeEnd': '10:00:00',
              'userId': 'tech-1',
              'squadraId': null,
              'title': 'Intervento esistente',
              'conflictOnUser': true,
              'conflictOnSquadra': false,
            },
          ],
        }, '/'),
      );

      await openForm(tester);
      await selectDropdown(tester, index: 0, optionText: 'Mario Rossi');
      await selectDropdown(tester, index: 1, optionText: 'Sede Nord');

      await tapSubmitButtonExpectingDialog(tester, 'Crea pianificazione');

      expect(find.text('Conflitti rilevati'), findsOneWidget);
      expect(find.text('Intervento esistente'), findsOneWidget);

      // No save attempted yet.
      verifyNever(
        () => mockDio.post<Map<String, dynamic>>(
          '/api/schedules',
          queryParameters: any(named: 'queryParameters'),
          data: any(named: 'data'),
        ),
      );

      await tester.tap(find.text('Salva comunque'));
      await tester.pumpAndSettle();

      final query = lastQueryParams();
      expect(query, isNotNull);
      expect(query!['force'], isTrue);
      await teardown(tester);
    });
  });
}
