// dart format width=100
// test/features/admin/reports/admin_report_detail_screen_test.dart
//
// Regression: a "controlla"/"fattura" state transition popped back to the list screen with the
// comment "// Pop to refresh list" — but popping refreshes nothing on its own. adminReportsProvider
// (a .family keyed by the list's stato filter) was never invalidated, so the list kept showing the
// report's pre-transition stato until a manual pull-to-refresh.

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:tasktap_mobile/features/admin/admin_api_client.dart';
import 'package:tasktap_mobile/features/admin/reports/admin_report_detail_screen.dart';
import 'package:tasktap_mobile/features/admin/reports/admin_report_list_screen.dart';

class _FakeAdminApiClient extends AdminApiClient {
  _FakeAdminApiClient() : super(Dio());

  int controllaCalls = 0;
  int fatturaCalls = 0;

  @override
  Future<void> controllaReport(String reportId) async => controllaCalls++;

  @override
  Future<void> fatturaReport(String reportId) async => fatturaCalls++;
}

void main() {
  setUpAll(() async => initializeDateFormatting('it'));

  testWidgets('renders the shell: Documenti → Sintesi → Attività, Apri PDF, no FAB', (
    tester,
  ) async {
    final api = _FakeAdminApiClient();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          adminApiClientProvider.overrideWithValue(api),
          adminReportsProvider.overrideWith(
            (ref, filter) async => const ReportListRows([], fromMirror: false),
          ),
        ],
        child: MaterialApp(
          home: Navigator(
            onGenerateRoute: (settings) => MaterialPageRoute(
              builder: (_) => AdminReportDetailScreen(
                report: const {
                  'id': 'r1',
                  'title': 'Rapportino 2026-0412',
                  'stato': 'Inviato',
                  'createdAt': '2026-10-01T08:00:00Z',
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Apri PDF'), findsWidgets);
    expect(find.byType(FloatingActionButton), findsNothing);
    expect(find.text('Documenti'), findsOneWidget);
    expect(find.text('Sintesi'), findsOneWidget);
    expect(find.text('Attività'), findsOneWidget);
    expect(find.text('PDF rapporto'), findsOneWidget);
    expect(find.text('Firma cliente'), findsOneWidget);
    expect(find.text('Firma tecnico'), findsOneWidget);
    // The state transition is kept, now inside Attività.
    expect(find.text('Segna come controllato'), findsOneWidget);

    final documenti = tester.getTopLeft(find.text('Documenti')).dy;
    final sintesi = tester.getTopLeft(find.text('Sintesi')).dy;
    final attivita = tester.getTopLeft(find.text('Attività')).dy;
    expect(documenti, lessThan(sintesi));
    expect(sintesi, lessThan(attivita));
  });

  testWidgets('a state transition invalidates adminReportsProvider, not just the pop', (
    tester,
  ) async {
    final api = _FakeAdminApiClient();
    var fetchCalls = 0;

    // `adminReportsProvider` is `.autoDispose` — invalidating it with nothing watching just marks
    // it dirty for whenever it's next read, it does not force an eager re-fetch. The real list
    // screen watches it and stays mounted underneath the detail push (Flutter's Navigator keeps
    // previous routes alive), so a small stand-in watcher, mounted alongside the detail screen
    // the same way, is what actually proves invalidate() forces a re-run — not the pop by itself.
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          adminApiClientProvider.overrideWithValue(api),
          adminReportsProvider.overrideWith((ref, filter) async {
            fetchCalls++;
            return const ReportListRows([], fromMirror: false);
          }),
        ],
        child: MaterialApp(
          home: Column(
            children: [
              // Stands in for the real list screen, which stays mounted underneath the detail
              // push (Flutter's Navigator keeps previous routes alive) and is what actually
              // observes the invalidation.
              Consumer(
                builder: (context, ref, _) {
                  ref.watch(adminReportsProvider(const StatoFilter(null)));
                  return const SizedBox.shrink();
                },
              ),
              Expanded(
                child: Navigator(
                  onGenerateRoute: (settings) => MaterialPageRoute(
                    builder: (_) => AdminReportDetailScreen(
                      report: const {'id': 'r1', 'title': 'Rapportino 1', 'stato': 'Inviato'},
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final fetchesBeforeTransition = fetchCalls;
    expect(fetchesBeforeTransition, 1);

    final controlla = find.text('Segna come controllato');
    await tester.ensureVisible(controlla);
    await tester.tap(controlla);
    await tester.pumpAndSettle();

    expect(api.controllaCalls, 1);
    expect(fetchCalls, greaterThan(fetchesBeforeTransition));
  });

  testWidgets('the Fattura action stays on this screen showing Fatturato + an XML download action, '
      'instead of popping back to the list', (tester) async {
    await initializeDateFormatting('it', null);
    final api = _FakeAdminApiClient();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          adminApiClientProvider.overrideWithValue(api),
          adminReportsProvider.overrideWith(
            (ref, filter) async => const ReportListRows([], fromMirror: false),
          ),
        ],
        child: MaterialApp(
          home: Navigator(
            onGenerateRoute: (settings) => MaterialPageRoute(
              builder: (_) => AdminReportDetailScreen(
                report: const {'id': 'r1', 'title': 'Rapportino 1', 'stato': 'Controllato'},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Segna come fatturato'), findsOneWidget);

    final fattura = find.text('Segna come fatturato');
    await tester.ensureVisible(fattura);
    await tester.tap(fattura);
    await tester.pumpAndSettle();

    // Transition fired, but the screen is still here — this used to pop back to the list on
    // its own, which is the reported bug (the office user's next step is usually downloading
    // the XML, not going back to find the row again).
    expect(api.fatturaCalls, 1);
    expect(find.byType(AdminReportDetailScreen), findsOneWidget);
    expect(find.text('Scarica XML fattura'), findsOneWidget);
    expect(find.text('Segna come fatturato'), findsNothing);
  });
}
