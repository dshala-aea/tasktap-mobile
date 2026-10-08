// dart format width=100
// test/features/ticket/step_cliente_sede_test.dart
//
// Step 1's two reference pickers are shared by two wizards with different powers: the create
// wizard can move both, and `EditTicketScreen`'s two-step mini-wizard can move neither — its PUT
// (`UpdateTicketRequest`) carries no `ContractId` and applies a commessa set-only. These tests pin
// the two flags that let the step say so instead of offering picks the save would drop.

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';
import 'package:tasktap_mobile/data/api/dio_client.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/features/ticket/new_ticket_form_state.dart';
import 'package:tasktap_mobile/features/ticket/steps/read_only_caption.dart';
import 'package:tasktap_mobile/features/ticket/steps/step_cliente_sede.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart';

class MockDio extends Mock implements Dio {}

/// The step is stateless about its own selection — it hands every change up through `onChanged` —
/// so the tests need a small owner that feeds the new [NewTicketFormState] back in, exactly the way
/// `NewTicketFormScreen._onFormChanged` does.
class _ClienteSedeHarness extends StatefulWidget {
  const _ClienteSedeHarness({
    super.key,
    required this.initialState,
    this.contractEditable = true,
    this.commessaClearable = true,
  });

  final NewTicketFormState initialState;
  final bool contractEditable;
  final bool commessaClearable;

  @override
  State<_ClienteSedeHarness> createState() => _ClienteSedeHarnessState();
}

class _ClienteSedeHarnessState extends State<_ClienteSedeHarness> {
  late NewTicketFormState _state = widget.initialState;

  /// What the step is currently holding — the state a refusal must leave untouched.
  NewTicketFormState get state => _state;

  /// Every state the step handed up. A refusal must leave this empty — that is what makes it a
  /// refusal rather than a state change nobody noticed.
  final List<NewTicketFormState> changes = [];

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: StepClienteSede(
          state: _state,
          contractEditable: widget.contractEditable,
          commessaClearable: widget.commessaClearable,
          onChanged: (s) {
            changes.add(s);
            setState(() => _state = s);
          },
        ),
      ),
    );
  }
}

/// The key the picker's underlying lookup field carries, derived from its label — see
/// [ReferencePickerField.fieldKey].
const _contrattoField = ValueKey('reference-picker-contratto');
const _commessaField = ValueKey('reference-picker-commessa');

/// The Commessa field's own key: the value it is showing plus the epoch a *refused* clear bumps
/// (`StepClienteSede._commessaPickerEpoch`). Both halves are part of the key because both are what
/// make the field rebuild — the value for a change the state really made, the epoch for a refusal
/// that made none.
ValueKey<String> commessaFieldKey(String? commessaId, [int epoch = 0]) =>
    ValueKey('commessa-$commessaId-$epoch');

void main() {
  late AppDatabase db;
  late MockDio mockDio;

  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    registerFallbackValue(RequestOptions(path: '/'));
  });

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    mockDio = MockDio();

    await db
        .into(db.customers)
        .insert(
          CustomersCompanion.insert(
            id: 'cust-1',
            tenantId: 'tenant-1',
            createdAt: DateTime.utc(2026, 1, 1),
            companyName: 'Acme Srl',
          ),
        );
    await db
        .into(db.locations)
        .insert(
          LocationsCompanion.insert(
            id: 'loc-1',
            tenantId: 'tenant-1',
            createdAt: DateTime.utc(2026, 1, 1),
            customerId: 'cust-1',
            name: 'Sede Milano',
          ),
        );
    // The customer's references, as a sync would have written them.
    await db
        .into(db.contracts)
        .insert(
          ContractsCompanion.insert(
            id: 'ctr-1',
            tenantId: 'tenant-1',
            createdAt: DateTime.utc(2026, 1, 1),
            name: 'Contratto Annuale',
            customerId: 'cust-1',
            startDate: DateTime.utc(2026, 1, 1),
          ),
        );
    for (final c in [
      ('com-1', 'COM-001', 'Rifacimento bagno'),
      ('com-2', 'COM-002', 'Manutenzione caldaie'),
    ]) {
      await db
          .into(db.commesse)
          .insert(
            CommesseCompanion.insert(
              id: c.$1,
              tenantId: 'tenant-1',
              createdAt: DateTime.utc(2026, 1, 1),
              codice: c.$2,
              customerId: const Value('cust-1'),
              descrizione: Value(c.$3),
            ),
          );
    }
  });

  tearDown(() => db.close());

  /// A ticket that really carries a contract and a commessa — the state edit mode seeds.
  const seeded = NewTicketFormState(
    customerId: 'cust-1',
    locationId: 'loc-1',
    title: 'Perdita idrica',
    typeId: 1,
    statusId: 1,
    contractId: 'ctr-1',
    commessaId: 'com-1',
  );

  Future<GlobalKey<_ClienteSedeHarnessState>> pumpStep(
    WidgetTester tester, {
    NewTicketFormState state = seeded,
    bool contractEditable = true,
    bool commessaClearable = true,
  }) async {
    final key = GlobalKey<_ClienteSedeHarnessState>();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          dioProvider.overrideWithValue(mockDio),
        ],
        child: _ClienteSedeHarness(
          key: key,
          initialState: state,
          contractEditable: contractEditable,
          commessaClearable: commessaClearable,
        ),
      ),
    );
    await tester.pumpAndSettle();
    return key;
  }

  /// The customer the customer-change branch switches to. Inserted per test — `setUp` builds a fresh
  /// database for each one.
  Future<void> insertSecondCustomer() async {
    await db
        .into(db.customers)
        .insert(
          CustomersCompanion.insert(
            id: 'cust-2',
            tenantId: 'tenant-1',
            createdAt: DateTime.utc(2026, 1, 1),
            companyName: 'Beta Spa',
          ),
        );
  }

  /// Switch the Cliente field to Beta Spa: open it, type enough to suggest it, take the suggestion.
  Future<void> selectBetaSpa(WidgetTester tester) async {
    final clienteField = find.byKey(const ValueKey('cliente-cust-1'));
    await tester.tap(clienteField);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(of: clienteField, matching: find.byType(TextFormField)),
      'Beta',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Beta Spa').last);
    await tester.pumpAndSettle();
  }

  /// The X on a resolved field — the only gesture that releases a pick.
  Finder clearButtonOf(Key fieldKey) =>
      find.descendant(of: find.byKey(fieldKey), matching: find.byType(IconButton));

  /// Unmount inside the body and let the frame after it settle — same two lines the sibling step
  /// tests end on: the ProviderScope disposes its container here, which cancels the drift stream
  /// queries and arms drift's zero-duration stream-removal timer, both of which have to happen
  /// under this test's own pumps.
  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  }

  // ── Contratto: drawn, never offered ─────────────────────────────────────────

  testWidgets('contractEditable: false still shows the contract, with the reason under it', (
    tester,
  ) async {
    await pumpStep(tester, contractEditable: false);

    // The record's real contract is on screen — a read-only field that showed nothing would be a
    // second lie in place of the first.
    expect(find.text('Contratto Annuale'), findsOneWidget);
    expect(find.text(kReadOnlyFieldCaption), findsOneWidget);

    // Read-only the way the picker already means it: an absorbing pointer, so neither a tap nor a
    // keystroke reaches the field. Matched on `absorbing` rather than on the type alone — the
    // framework puts non-absorbing `AbsorbPointer`s of its own in the tree.
    expect(
      find.ancestor(
        of: find.byKey(_contrattoField),
        matching: find.byWidgetPredicate((w) => w is AbsorbPointer && w.absorbing),
      ),
      findsOneWidget,
    );

    await unmount(tester);
  });

  testWidgets('contractEditable: false cannot be picked or typed into', (tester) async {
    final key = await pumpStep(tester, contractEditable: false);

    await tester.tap(find.byKey(_contrattoField), warnIfMissed: false);
    await tester.pumpAndSettle();

    // Nothing was handed up: a tap that changed the contract would be a change this screen cannot
    // save, which is the defect the flag exists to close.
    expect(key.currentState!.changes, isEmpty);
    expect(key.currentState!.state.contractId, 'ctr-1');

    await unmount(tester);
  });

  testWidgets('contractEditable (the default) leaves the contract editable', (tester) async {
    final key = await pumpStep(tester);

    // Guards the default: the create wizard's own contract pick must stay live.
    expect(find.text('Contratto Annuale'), findsOneWidget);
    expect(find.text(kReadOnlyFieldCaption), findsNothing);
    expect(
      find.ancestor(
        of: find.byKey(_contrattoField),
        matching: find.byWidgetPredicate((w) => w is AbsorbPointer && w.absorbing),
      ),
      findsNothing,
    );

    // Releasing the pick releases it in state, as before.
    await tester.tap(clearButtonOf(_contrattoField));
    await tester.pumpAndSettle();
    expect(key.currentState!.state.contractId, isNull);

    await unmount(tester);
  });

  // ── Commessa: picking is real, clearing is not ──────────────────────────────

  testWidgets('commessaClearable: false refuses the clear, says why, and changes nothing', (
    tester,
  ) async {
    final key = await pumpStep(tester, commessaClearable: false);

    expect(find.text('COM-001'), findsOneWidget);
    await tester.tap(clearButtonOf(commessaFieldKey('com-1')));
    await tester.pump();

    // Nothing was handed up at all, so the stored commessa survives a gesture that would otherwise
    // have dropped it — and, because the server applies a commessa set-only, a null that reached
    // the PUT would have been a removal that never happened.
    expect(key.currentState!.changes, isEmpty);
    expect(key.currentState!.state.commessaId, 'com-1');

    // And the refusal is said out loud: a field that just ignored the gesture is the bug.
    expect(find.text('La commessa non può essere rimossa da qui.'), findsOneWidget);

    await unmount(tester);
  });

  /// D1: the refusal is right, what followed it was not. A refusal deliberately changes no state, so
  /// nothing rebuilt the field and the box stayed empty — the technician saw no commessa over a
  /// record that still carried one, and what the save then sent contradicted the field. The stored
  /// code has to come back: the field is the thing that was wrong, so the field is what is asserted.
  testWidgets('a refused commessa clear puts the stored commessa back on the field', (tester) async {
    final key = await pumpStep(tester, commessaClearable: false);

    expect(find.text('COM-001'), findsOneWidget);
    await tester.tap(clearButtonOf(commessaFieldKey('com-1')));
    await tester.pump();

    // The refusal itself is unchanged: nothing was handed up, so the stored commessa survives...
    expect(key.currentState!.changes, isEmpty);
    expect(key.currentState!.state.commessaId, 'com-1');
    expect(find.text('La commessa non può essere rimossa da qui.'), findsOneWidget);

    // ...and the field no longer sits empty over it. The epoch bumped the key, the field was rebuilt
    // from the stored id, and the code is back on it, ticked as the resolved record it is.
    expect(find.byKey(commessaFieldKey('com-1', 1)), findsOneWidget);
    expect(find.text('COM-001'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(commessaFieldKey('com-1', 1)),
        matching: find.byIcon(LucideIcons.check),
      ),
      findsOneWidget,
    );

    await unmount(tester);
  });

  testWidgets('commessaClearable: false still allows picking a different commessa', (tester) async {
    final key = await pumpStep(tester, commessaClearable: false);

    // The field is not disabled — only the *release* is refused, so picking has to keep working end
    // to end. `AppLookupField` shows no suggestions for an already-resolved field until its text
    // changes (`_suggestions` returns nothing while `_selectedId != null`), so a pick starts by
    // typing: that releases the old pick, which is exactly the gesture that is now refused, and the
    // search still runs behind it. The toast is left to expire first so it cannot swallow the tap.
    await tester.enterText(
      find.descendant(of: find.byKey(_commessaField), matching: find.byType(TextFormField)),
      'COM-002',
    );
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();

    await tester.tap(find.text('COM-002').last);
    await tester.pumpAndSettle();

    expect(key.currentState!.state.commessaId, 'com-2');

    await unmount(tester);
  });

  testWidgets('commessaClearable (the default) clears as it always did', (tester) async {
    final key = await pumpStep(tester);

    // Guards the default: the create wizard's own clear must not have been made a refusal.
    expect(find.text('COM-001'), findsOneWidget);
    await tester.tap(clearButtonOf(commessaFieldKey('com-1')));
    await tester.pumpAndSettle();

    expect(key.currentState!.state.commessaId, isNull);
    expect(find.text('La commessa non può essere rimossa da qui.'), findsNothing);

    await unmount(tester);
  });

  /// The picker's own tick marks a resolved field; a clear must not leave the tick behind over an
  /// empty box. Cheap sanity on the affordance the tests above drive.
  testWidgets('the resolved commessa field is ticked, not marked as free text', (tester) async {
    await pumpStep(tester);

    expect(
      find.descendant(
        of: find.byKey(commessaFieldKey('com-1')),
        matching: find.byIcon(LucideIcons.check),
      ),
      findsOneWidget,
    );

    await unmount(tester);
  });

  // ── The value key: what it is actually for ──────────────────────────────────

  /// The reason the Commessa field is keyed by its own value. Switching customer clears the
  /// commessa in *state* (it belongs to the customer being dropped), and `AppLookupField` never
  /// clears its own text on an update — only ever fills it in — so without the key the field went on
  /// showing the previous customer's commessa code over a null selection.
  testWidgets('changing the customer takes the commessa off the field, not just out of state', (
    tester,
  ) async {
    await insertSecondCustomer();

    final key = await pumpStep(tester);
    expect(find.text('COM-001'), findsOneWidget);

    await selectBetaSpa(tester);

    expect(key.currentState!.state.customerId, 'cust-2');
    expect(key.currentState!.state.commessaId, isNull);
    // The field no longer claims a commessa the state does not hold, and the new customer's own
    // (empty) list is what it is now keyed to.
    expect(find.byKey(commessaFieldKey('com-1')), findsNothing);
    expect(find.text('COM-001'), findsNothing);

    await unmount(tester);
  });

  // ── The same key on the Contratto field ─────────────────────────────────────

  /// D2: the customer-change branch sets `clearContractId` too (and so does emptying the Cliente
  /// field), and the Contratto field carried no key at all — so the previous customer's contract
  /// name stayed on the field over a null selection. Edit mode draws that field read-only, which is
  /// what made it worse than an editable field with the same defect: there was no gesture left that
  /// could have corrected it.
  testWidgets(
    'changing the customer takes the previous contract off the field, not just out of state',
    (tester) async {
      await insertSecondCustomer();

      final key = await pumpStep(tester);
      expect(find.byKey(const ValueKey('contratto-ctr-1')), findsOneWidget);
      expect(find.text('Contratto Annuale'), findsOneWidget);

      await selectBetaSpa(tester);

      expect(key.currentState!.state.customerId, 'cust-2');
      expect(key.currentState!.state.contractId, isNull);
      // Keyed by its own value, the cleared contract rebuilt the field into an empty one rather than
      // leaving the old name standing over a selection the record no longer points at.
      expect(find.byKey(const ValueKey('contratto-null')), findsOneWidget);
      expect(find.text('Contratto Annuale'), findsNothing);

      await unmount(tester);
    },
  );

  /// The direction that key could plausibly have broken: an ordinary pick on an empty field. The key
  /// moves with the value it shows, so a pick *does* rebuild the field — and that rebuild has to
  /// resolve the picked id to its name, not reset the field to blank over a real selection.
  testWidgets('a contract picked on the default build lands on the field', (tester) async {
    final key = await pumpStep(tester, state: seeded.copyWith(clearContractId: true));

    final contractField = find.byKey(_contrattoField);
    await tester.tap(contractField);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(of: contractField, matching: find.byType(TextFormField)),
      'Contratto Annuale',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Contratto Annuale').last);
    await tester.pumpAndSettle();

    expect(key.currentState!.state.contractId, 'ctr-1');
    expect(find.byKey(const ValueKey('contratto-ctr-1')), findsOneWidget);
    expect(find.text('Contratto Annuale'), findsOneWidget);

    await unmount(tester);
  });
}
