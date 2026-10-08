// dart format width=100
import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tasktap_mobile/data/api/dio_client.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart';
import 'package:tasktap_mobile/features/ticket/new_ticket_form_state.dart';
import 'package:tasktap_mobile/features/ticket/steps/step_dettagli_ticket.dart';

class MockDio extends Mock implements Dio {}

/// The step is stateless about its own selection — it hands every change up through `onChanged` —
/// so a test needs a small owner that feeds the new [NewTicketFormState] back in, exactly the way
/// `NewTicketFormScreen._onFormChanged` does.
class _DettagliHarness extends StatefulWidget {
  const _DettagliHarness();

  @override
  State<_DettagliHarness> createState() => _DettagliHarnessState();
}

class _DettagliHarnessState extends State<_DettagliHarness> {
  NewTicketFormState _state = const NewTicketFormState(customerId: 'cust-1');

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: StepDettagliTicket(
          state: _state,
          onChanged: (s) => setState(() => _state = s),
        ),
      ),
    );
  }
}

void main() {
  late AppDatabase db;
  late MockDio mockDio;

  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    registerFallbackValue(RequestOptions(path: '/'));
    registerFallbackValue(<String, dynamic>{});
  });

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    mockDio = MockDio();
  });

  tearDown(() => db.close());

  testWidgets(
    'a Riferimento found by search shows its name in the field, not "Nessuno"',
    (tester) async {
      when(
        () => mockDio.get<Map<String, dynamic>>(
          '/api/agents',
          queryParameters: any(named: 'queryParameters'),
        ),
      ).thenAnswer(
        (_) async => Response<Map<String, dynamic>>(
          requestOptions: RequestOptions(path: '/api/agents'),
          statusCode: 200,
          data: {
            'items': [
              {
                'id': 'agent-1',
                'tenantId': 'tenant-1',
                'createdAt': '2026-01-01T00:00:00.000Z',
                'nome': 'Rossi',
                'cellulare': '3331112222',
                'isActive': true,
              },
            ],
          },
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            dioProvider.overrideWithValue(mockDio),
          ],
          child: const _DettagliHarness(),
        ),
      );
      await tester.pumpAndSettle();

      // Bring the Riferimento field into the viewport (the step is a ListView, so it builds lazily).
      // The mirror is empty, so the field has no label to resolve and says so. The scrollable is
      // named: the step's own TextFields each carry an internal Scrollable, so the default
      // `find.byType(Scrollable)` is ambiguous.
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('agent-field')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(find.text('Nessuno'), findsOneWidget);

      // Open the sheet and search for the agent the server holds — one the mirror does not have yet.
      await tester.tap(find.byKey(const ValueKey('agent-field')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(
          of: find.byKey(const ValueKey('agent-search-field')),
          matching: find.byType(TextFormField),
        ),
        'Ross',
      );
      // Past the sheet's 300 ms debounce, then let the search's upsert land in the mirror.
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('agent-picker-agent-1')));
      await tester.pumpAndSettle();

      // The pick was stored AND the field re-read the mirror to render its name. Without the
      // invalidation of `localAgentsProvider('')` on the pick, the list the label resolves against
      // had already resolved and this stayed "Nessuno" — a stored pick the field denied.
      expect(find.text('Rossi'), findsOneWidget);
      expect(find.text('Nessuno'), findsNothing);

      // Unmount inside the body and let the frame after it settle: the ProviderScope disposes its
      // container here, which cancels the drift stream queries and arms drift's zero-duration
      // stream-removal timer. Both the dispose and that timer have to happen under this test's own
      // pumps — left to the framework's teardown, the timer is still pending with the tree already
      // gone and trips the "A Timer is still pending" invariant. Same two lines the ticket-detail
      // tests end on, for the same reason.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
}
