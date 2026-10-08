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
import 'package:tasktap_mobile/features/ticket/steps/blamed_field_notice.dart';
import 'package:tasktap_mobile/features/ticket/steps/step_dettagli_ticket.dart';

class MockDio extends Mock implements Dio {}

/// The step is stateless about its own selection — it hands every change up through `onChanged` —
/// so a test needs a small owner that feeds the new [NewTicketFormState] back in, exactly the way
/// `NewTicketFormScreen._onFormChanged` does.
class _DettagliHarness extends StatefulWidget {
  const _DettagliHarness({required this.initialState, this.blamedField});

  final NewTicketFormState initialState;

  /// The field a repair is waiting on, or null for an ordinary wizard.
  final String? blamedField;

  @override
  State<_DettagliHarness> createState() => _DettagliHarnessState();
}

class _DettagliHarnessState extends State<_DettagliHarness> {
  late NewTicketFormState _state = widget.initialState;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: StepDettagliTicket(
          state: _state,
          blamedField: widget.blamedField,
          onChanged: (s) => setState(() => _state = s),
        ),
      ),
    );
  }
}

/// One agent as `/api/agents` returns it — the shape the search client expects back.
Map<String, dynamic> agentJson({String id = 'agent-1', String nome = 'Rossi'}) => {
  'id': id,
  'tenantId': 'tenant-1',
  'createdAt': '2026-01-01T00:00:00.000Z',
  'nome': nome,
  'cellulare': '3331112222',
  'isActive': true,
};

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

  /// Answers every `/api/agents` search with [items]. The mirror starts empty in every test here,
  /// so whatever the sheet shows came from this stub.
  void stubAgentSearch(List<Map<String, dynamic>> items) {
    when(
      () => mockDio.get<Map<String, dynamic>>(
        '/api/agents',
        queryParameters: any(named: 'queryParameters'),
      ),
    ).thenAnswer(
      (_) async => Response<Map<String, dynamic>>(
        requestOptions: RequestOptions(path: '/api/agents'),
        statusCode: 200,
        data: {'items': items},
      ),
    );
  }

  Future<void> pumpStep(
    WidgetTester tester, {
    NewTicketFormState state = const NewTicketFormState(customerId: 'cust-1'),
    String? blamedField,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          dioProvider.overrideWithValue(mockDio),
        ],
        child: _DettagliHarness(initialState: state, blamedField: blamedField),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// The step is a lazily-built ListView, so anything below the fold has to be scrolled to before
  /// it exists at all. The scrollable is named: the step's own TextFields each carry an internal
  /// Scrollable, so the default `find.byType(Scrollable)` is ambiguous.
  Future<void> scrollTo(WidgetTester tester, Finder target) async {
    await tester.scrollUntilVisible(
      target,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
  }

  Future<void> openAgentSheet(WidgetTester tester) async {
    await scrollTo(tester, find.byKey(const ValueKey('agent-field')));
    await tester.tap(find.byKey(const ValueKey('agent-field')));
    await tester.pumpAndSettle();
  }

  /// Types into the sheet's own search field, then waits past its 300 ms debounce and lets the
  /// search's answer — or its failure — land.
  Future<void> searchInSheet(WidgetTester tester, String query) async {
    await tester.enterText(
      find.descendant(
        of: find.byKey(const ValueKey('agent-search-field')),
        matching: find.byType(TextFormField),
      ),
      query,
    );
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
  }

  /// Unmount inside the body and let the frame after it settle: the ProviderScope disposes its
  /// container here, which cancels the drift stream queries and arms drift's zero-duration
  /// stream-removal timer. Both the dispose and that timer have to happen under this test's own
  /// pumps — left to the framework's teardown, the timer is still pending with the tree already
  /// gone and trips the "A Timer is still pending" invariant. Same two lines the ticket-detail
  /// tests end on, for the same reason.
  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  }

  testWidgets(
    'a Riferimento found by search shows its name in the field, not "Nessuno"',
    (tester) async {
      stubAgentSearch([agentJson()]);
      await pumpStep(tester);

      // The mirror is empty, so the field has no label to resolve and says so.
      await scrollTo(tester, find.byKey(const ValueKey('agent-field')));
      expect(find.text('Nessuno'), findsOneWidget);

      // Search for the agent the server holds — one the mirror does not have yet — and pick it.
      await openAgentSheet(tester);
      await searchInSheet(tester, 'Ross');
      await tester.tap(find.byKey(const ValueKey('agent-picker-agent-1')));
      await tester.pumpAndSettle();

      // The pick was stored AND the field re-read the mirror to render its name. Without the
      // invalidation of `localAgentsProvider('')` on the pick, the list the label resolves against
      // had already resolved and this stayed "Nessuno" — a stored pick the field denied.
      expect(find.text('Rossi'), findsOneWidget);
      expect(find.text('Nessuno'), findsNothing);

      await unmount(tester);
    },
  );

  // ── The Riferimento sheet's own line when it has nothing to show ────────────

  testWidgets('the Riferimento sheet says the cache is empty, and how to fill it', (
    tester,
  ) async {
    await pumpStep(tester);
    await openAgentSheet(tester);

    // Nothing mirrored, nothing typed: without this line the sheet is a lone "Nessuno" row, which
    // reads as the picker being broken rather than as the device holding no agents yet.
    expect(find.text('Nessun agente in cache. Cerca per nome.'), findsOneWidget);

    await unmount(tester);
  });

  testWidgets('a search that matches nothing says so, not that the cache is empty', (
    tester,
  ) async {
    stubAgentSearch(const []);
    await pumpStep(tester);
    await openAgentSheet(tester);
    await searchInSheet(tester, 'zzz');

    // The two empty states are different news: one is "type a name", the other is "this name is not
    // there". Telling a technician who just searched to go and search again is the bug.
    expect(find.text('Nessun agente trovato.'), findsOneWidget);
    expect(find.text('Nessun agente in cache. Cerca per nome.'), findsNothing);

    await unmount(tester);
  });

  // ── A blamed field whose loss is more than the value ────────────────────────

  testWidgets('a blamed prodotti field also says the coverage went with it', (tester) async {
    await pumpStep(tester, blamedField: 'prodottoAssistenzaIds');
    await scrollTo(tester, find.byKey(const ValueKey('prodotto-adder-0')));

    // The shared sentence alone would send the technician looking for one missing product: the
    // server refused a prodotto and the whole list went with it, so the detail has to say so.
    expect(
      find.text(
        'Il riferimento non è più valido: scegline un altro. '
        'La copertura è stata azzerata: i prodotti vanno scelti di nuovo.',
      ),
      findsOneWidget,
    );

    await unmount(tester);
  });

  testWidgets('a blamed field with nothing extra to say carries the shared sentence alone', (
    tester,
  ) async {
    await pumpStep(tester, blamedField: 'agentId');
    await scrollTo(tester, find.byKey(const ValueKey('agent-field')));

    // "Only when that field is blamed": the Riferimento notice is the plain one, and the prodotti
    // detail belongs to a different field — rendering it here would invent a loss that did not
    // happen.
    expect(find.text(kBlamedFieldNotice), findsOneWidget);
    expect(find.textContaining('copertura'), findsNothing);

    await unmount(tester);
  });

  // ── A prodotto the mirror cannot resolve ────────────────────────────────────

  testWidgets('an unresolvable prodotto is chipped with a neutral label, never the raw id', (
    tester,
  ) async {
    await pumpStep(
      tester,
      state: const NewTicketFormState(
        customerId: 'cust-1',
        prodottoAssistenzaIds: ['ghost-1'],
      ),
    );
    await scrollTo(tester, find.byKey(const ValueKey('prodotto-chip-ghost-1')));

    // The riepilogo drops an id it cannot label rather than print it; this chip cannot be dropped —
    // it is the only way to remove the selection — so it gets a state, not a GUID a technician would
    // read as a product's name.
    expect(find.text('Prodotto non disponibile'), findsOneWidget);
    expect(find.text('ghost-1'), findsNothing);

    await unmount(tester);
  });
}
