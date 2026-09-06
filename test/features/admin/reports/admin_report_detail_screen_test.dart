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

import 'package:tasktap_mobile/features/admin/admin_api_client.dart';
import 'package:tasktap_mobile/features/admin/reports/admin_report_detail_screen.dart';
import 'package:tasktap_mobile/features/admin/reports/admin_report_list_screen.dart';

class _FakeAdminApiClient extends AdminApiClient {
  _FakeAdminApiClient() : super(Dio());

  int controllaCalls = 0;

  @override
  Future<void> controllaReport(String reportId) async => controllaCalls++;
}

void main() {
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
            return const <Map<String, dynamic>>[];
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

    await tester.tap(find.text('Segna come controllato'));
    await tester.pumpAndSettle();

    expect(api.controllaCalls, 1);
    expect(fetchCalls, greaterThan(fetchesBeforeTransition));
  });
}
