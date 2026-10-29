// dart format width=100
// test/features/smart_working/smart_working_form_screen_test.dart
//
// The new-request form: two civil dates and an optional note, nothing that looks like a timesheet.
//
// The range checks here are a client-side mirror of the server's own three rules
// (`SmartWorkingRequestService.ValidateRange`, api PR #183), and this file pins the two properties
// that matter about them: the refusal happens BEFORE the round trip (and before anything could be
// queued offline), and it speaks the server's own sentence. Where the two can disagree — "today"
// is the tenant's civil day on the server and the device's locally — the server's 400 `detail`
// must reach the technician unchanged.

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';
import 'package:tasktap_mobile/data/entitlements/entitlement_providers.dart';
import 'package:tasktap_mobile/data/entitlements/entitlement_service.dart' show internalUserIdPrefsKey;
import 'package:tasktap_mobile/data/smart_working/smart_working_request_api_client.dart';
import 'package:tasktap_mobile/data/sync/connectivity_provider.dart';
import 'package:tasktap_mobile/features/smart_working/smart_working_form_screen.dart';

const String _formPath = '/altro/smart-working/nuovo';

class _FakeSmartWorkingRequestApiClient extends SmartWorkingRequestApiClient {
  _FakeSmartWorkingRequestApiClient() : super(Dio());

  /// Every `create` that reached the API layer, in order. An empty list is the assertion that the
  /// form refused the request itself.
  final List<Map<String, dynamic>> creates = [];

  final List<SmartWorkingRequestDto> items = [];
  int fetchCalls = 0;
  Object? throwOnCreate;

  /// Holds `create` open so a test can back out of the screen while the POST is still on the wire.
  Completer<void>? createGate;

  @override
  Future<List<SmartWorkingRequestDto>> fetchMine({String? userId}) async {
    fetchCalls++;
    return List.of(items);
  }

  @override
  Future<String> create({
    required DateTime startDate,
    required DateTime endDate,
    String? reason,
  }) async {
    if (createGate != null) await createGate!.future;
    creates.add({'startDate': startDate, 'endDate': endDate, 'reason': reason});
    if (throwOnCreate != null) throw throwOnCreate!;
    // What the server does on success: a new pending row, newest first.
    items.insert(
      0,
      SmartWorkingRequestDto(
        id: 'sw-new-${creates.length}',
        requestedByUserId: 'user-1',
        createdByUserId: 'user-1',
        startDate: DateTime.utc(startDate.year, startDate.month, startDate.day),
        endDate: DateTime.utc(endDate.year, endDate.month, endDate.day),
        reason: reason,
        status: 0,
      ),
    );
    return 'sw-new-${creates.length}';
  }
}

/// Stands in for the list screen underneath the pushed form: it keeps
/// `mySmartWorkingRequestsProvider` listened to (so the form's `invalidate` re-runs it) and shows
/// what the provider currently answers.
class _ListStub extends ConsumerWidget {
  const _ListStub();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final requests = ref.watch(mySmartWorkingRequestsProvider);
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ElevatedButton(
              onPressed: () => context.push(_formPath),
              child: const Text('Apri form'),
            ),
            Text(
              requests.when(
                data: (items) => 'richieste: ${items.length}',
                error: (_, _) => 'errore',
                loading: () => 'caricamento',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Widget _buildHarness(
  _FakeSmartWorkingRequestApiClient fake, {
  bool online = true,
  DateTime? initialStartDate,
  DateTime? initialEndDate,
}) {
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(path: '/', builder: (context, state) => const _ListStub()),
      GoRoute(
        path: _formPath,
        builder: (context, state) => SmartWorkingFormScreen(
          initialStartDate: initialStartDate,
          initialEndDate: initialEndDate,
        ),
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      smartWorkingRequestApiClientProvider.overrideWithValue(fake),
      isOnlineProvider.overrideWithValue(online),
      cachedEntitlementProvider.overrideWith((ref) => null),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

/// Pushes the form from the stub list, exactly as the list's FAB does.
Future<void> _openForm(
  WidgetTester tester,
  _FakeSmartWorkingRequestApiClient fake, {
  bool online = true,
  DateTime? initialStartDate,
  DateTime? initialEndDate,
}) async {
  await tester.pumpWidget(
    _buildHarness(
      fake,
      online: online,
      initialStartDate: initialStartDate,
      initialEndDate: initialEndDate,
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Apri form'));
  await tester.pumpAndSettle();
}

/// Device-local civil today, the same "today" the form compares against.
DateTime _today() {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
}

DateTime _shifted(DateTime day, int days) =>
    DateTime(day.year, day.month, day.day + days);

void main() {
  setUpAll(() async {
    // The date fields render Italian weekday/month names.
    await initializeDateFormatting('it', null);
  });

  setUp(() {
    // The real `mySmartWorkingRequestsProvider` reads the signed-in id from prefs on every read.
    SharedPreferences.setMockInitialValues({internalUserIdPrefsKey: 'user-1'});
  });

  testWidgets('creates_withTheDefaultTodayDates', (tester) async {
    // Opened from the FAB, the form offers a single-day request starting today: the common case
    // the technician should be able to send with one tap and no picker at all.
    final fake = _FakeSmartWorkingRequestApiClient();
    // Captured BEFORE the form is built: the form takes its reference day when it opens, and a run
    // straddling local midnight must not compare a "today" read after the submit against a form
    // seeded a moment earlier (the repo's Rome-midnight flake class).
    final today = _today();
    await _openForm(tester, fake);

    await tester.tap(find.text('Invia richiesta'));
    await tester.pumpAndSettle();

    expect(fake.creates, hasLength(1));
    expect(fake.creates.single['startDate'], today);
    expect(fake.creates.single['endDate'], today);
    expect(fake.creates.single['reason'], isNull, reason: 'the note is optional');
  });

  testWidgets('endBeforeStart_showsTheItalianError_andNeverCallsTheApi', (tester) async {
    final fake = _FakeSmartWorkingRequestApiClient();
    final today = _today();
    await _openForm(
      tester,
      fake,
      // Reachable in real use too: pick an end date, then move the start past it. The form keeps
      // the end date as chosen rather than silently rewriting it.
      initialStartDate: _shifted(today, 5),
      initialEndDate: _shifted(today, 2),
    );

    await tester.tap(find.text('Invia richiesta'));
    await tester.pumpAndSettle();

    expect(find.text('La data di fine non può precedere la data di inizio.'), findsOneWidget);
    expect(fake.creates, isEmpty);
  });

  testWidgets('rangeOver366Days_isRefusedBeforeTheRoundTrip', (tester) async {
    // The server allows a span DIFFERENCE of 366 (`> 366` is refused); 367 is over the line.
    final fake = _FakeSmartWorkingRequestApiClient();
    final today = _today();
    await _openForm(
      tester,
      fake,
      initialStartDate: today,
      initialEndDate: _shifted(today, 367),
    );

    await tester.tap(find.text('Invia richiesta'));
    await tester.pumpAndSettle();

    expect(find.text('Il periodo richiesto è troppo lungo (massimo un anno).'), findsOneWidget);
    expect(fake.creates, isEmpty);
  });

  testWidgets('aSpanOfExactly366Days_isAccepted', (tester) async {
    // The boundary in the other direction: the off-by-one is the whole rule, so pin the day the
    // server still accepts (a 366-day difference means the end date is day 367).
    final fake = _FakeSmartWorkingRequestApiClient();
    final today = _today();
    await _openForm(
      tester,
      fake,
      initialStartDate: today,
      initialEndDate: _shifted(today, 366),
    );

    await tester.tap(find.text('Invia richiesta'));
    await tester.pumpAndSettle();

    expect(fake.creates, hasLength(1));
  });

  testWidgets('backdatedStart_isRefusedBeforeTheRoundTrip', (tester) async {
    final fake = _FakeSmartWorkingRequestApiClient();
    final today = _today();
    await _openForm(
      tester,
      fake,
      initialStartDate: _shifted(today, -1),
      initialEndDate: today,
    );

    await tester.tap(find.text('Invia richiesta'));
    await tester.pumpAndSettle();

    expect(
      find.text('Non è possibile richiedere smart working per una data passata.'),
      findsOneWidget,
    );
    expect(fake.creates, isEmpty);
  });

  testWidgets('offline_submit_isRefusedWithTheOfflineNotice_andNeverCallsTheApi', (
    tester,
  ) async {
    // Online-only: a request the server never saw must not be queued, and the technician keeps
    // what they typed. `ensureOnlineOrWarn` supplies the notice.
    final fake = _FakeSmartWorkingRequestApiClient();
    await _openForm(tester, fake, online: false);

    await tester.tap(find.text('Invia richiesta'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Sei offline'), findsOneWidget);
    expect(fake.creates, isEmpty);
    expect(
      find.text('Invia richiesta'),
      findsOneWidget,
      reason: 'the form stays put so nothing typed is lost',
    );
  });

  testWidgets('serverDetail_isShownVerbatim', (tester) async {
    // The one case the client cannot decide: the server resolves "today" in the TENANT's zone, so
    // a window this device believes starts today can already be past there. Its sentence must
    // reach the snackbar untouched — never replaced by a retry line.
    const detail = 'Non è possibile richiedere smart working per una data passata.';
    final fake = _FakeSmartWorkingRequestApiClient()
      ..throwOnCreate = const SmartWorkingValidationError(detail);
    await _openForm(tester, fake);

    await tester.tap(find.text('Invia richiesta'));
    await tester.pumpAndSettle();

    // The round trip really happened: the same sentence is also what the client's own rule 3
    // emits, so without this the test would pass even if the local check fired first and the
    // catch branch never ran.
    expect(fake.creates, hasLength(1));
    expect(find.text(detail), findsOneWidget);
    expect(find.text('Impossibile inviare la richiesta. Riprova.'), findsNothing);
  });

  testWidgets('success_popsTheScreen_andRefreshesTheList', (tester) async {
    final fake = _FakeSmartWorkingRequestApiClient();
    await _openForm(tester, fake);

    final fetchesBeforeSubmit = fake.fetchCalls;
    expect(fetchesBeforeSubmit, greaterThan(0), reason: 'the stub list loaded once');

    await tester.tap(find.text('Invia richiesta'));
    await tester.pumpAndSettle();

    expect(find.text('Invia richiesta'), findsNothing, reason: 'the form was popped');
    expect(find.text('Richiesta di smart working inviata'), findsOneWidget);
    expect(
      fake.fetchCalls,
      greaterThan(fetchesBeforeSubmit),
      reason: 'the invalidated list re-asked the server',
    );
    expect(find.text('richieste: 1'), findsOneWidget);
  });

  testWidgets('sendsTheNoteAsTheReason_whenOneIsTyped', (tester) async {
    final fake = _FakeSmartWorkingRequestApiClient();
    await _openForm(tester, fake);

    await tester.enterText(find.byType(TextField).last, '  Lavoro da casa  ');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Invia richiesta'));
    await tester.pumpAndSettle();

    expect(fake.creates.single['reason'], 'Lavoro da casa');
  });

  testWidgets('theNoteCannotExceedTheServersColumn', (tester) async {
    // `SmartWorkingRequest.Reason` is varchar(1000) and the create endpoint does not length-check
    // it, so a longer note would come back as an error the form can only report as "riprova" — a
    // retry that can never succeed. The field caps it instead.
    final fake = _FakeSmartWorkingRequestApiClient();
    await _openForm(tester, fake);

    await tester.enterText(find.byType(TextField).last, 'x' * 1001);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Invia richiesta'));
    await tester.pumpAndSettle();

    expect(fake.creates.single['reason'], hasLength(1000));
  });

  testWidgets('backingOutMidPost_stillRefreshesTheList', (tester) async {
    // The request is already created server-side; the list underneath must not keep claiming the
    // stale state just because the form (and its `ref`) is gone. The invalidate goes through the
    // provider CONTAINER, which outlives the route.
    final fake = _FakeSmartWorkingRequestApiClient();
    final gate = Completer<void>();
    fake.createGate = gate;
    await _openForm(tester, fake);

    final fetchesBeforeSubmit = fake.fetchCalls;

    await tester.tap(find.text('Invia richiesta'));
    await tester.pump();

    // Back out while the POST is still on the wire (the header chevron the form actually shows).
    await tester.tap(find.byIcon(LucideIcons.chevronLeft));
    await tester.pumpAndSettle();
    expect(find.text('Invia richiesta'), findsNothing, reason: 'the form was popped');

    gate.complete();
    await tester.pumpAndSettle();

    expect(fake.creates, hasLength(1));
    expect(
      fake.fetchCalls,
      greaterThan(fetchesBeforeSubmit),
      reason: 'the created request must reach the list even though the form is gone',
    );
    expect(find.text('richieste: 1'), findsOneWidget);
  });
}
