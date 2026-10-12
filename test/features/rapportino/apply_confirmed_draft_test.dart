// dart format width=100
// test/features/rapportino/apply_confirmed_draft_test.dart
//
// The mobile half of I2's client split (spec §5.5): the copilot's Conferma resolves the draft
// server-side and persists nothing, so the phone writes the resolved draft into its own Drift
// draft — the same tables the wizard fills by hand — and then uses the existing save/submit path.
//
// Harness mirrored from create_draft_test.dart: a ProviderContainer whose internalUserIdProvider
// resolves to a fixed id, pumped through UncontrolledProviderScope + Consumer so the function
// under test receives a real WidgetRef from a real widget callback.

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tasktap_mobile/data/ai/ai_api_client.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/reports/import_server_report.dart' show controlRowId;
import 'package:tasktap_mobile/data/sync/sync_service.dart' show appDatabaseProvider;
import 'package:tasktap_mobile/features/rapportino/apply_confirmed_draft.dart';
import 'package:tasktap_mobile/presentation/providers/auth_providers.dart';
import 'package:tasktap_mobile/presentation/providers/report_editor_providers.dart';

AppDatabase _makeDb() => AppDatabase(NativeDatabase.memory());

/// The signed-in user's INTERNAL database id, as `internalUserIdProvider` would resolve it.
const _testInternalUserId = 'internal-guid-2';

Future<String?> _callApply(
  WidgetTester tester,
  ProviderContainer container,
  AiConversationConfirmResponse response, {
  String? ticketId,
  String? cantiereId,
}) async {
  String? result;
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Consumer(
          builder: (context, ref, _) => ElevatedButton(
            onPressed: () async {
              result = await applyConfirmedDraft(
                ref,
                response: response,
                ticketId: ticketId,
                cantiereId: cantiereId,
              );
            },
            child: const Text('go'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('go'));
  await tester.pumpAndSettle();
  return result;
}

ProviderContainer _container(AppDatabase db, {String? internalUserId = _testInternalUserId}) =>
    ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        internalUserIdProvider.overrideWith((ref) async => internalUserId),
      ],
    );

void main() {
  testWidgets("writes the resolved draft as the phone's own local rapportino", (tester) async {
    final db = _makeDb();
    addTearDown(db.close);
    final container = _container(db);
    addTearDown(container.dispose);

    final id = await _callApply(
      tester,
      container,
      const AiConversationConfirmResponse(
        title: 'Sostituzione valvola',
        details: 'Valvola bloccata',
        customerSignoffText: 'accettato',
        ticketId: 'tkt-1',
        locationId: null,
        staff: [AiResolvedStaff(userId: 'u-1', hoursWorked: 6.5, kmTraveled: 12)],
        materials: [
          AiResolvedMaterial(
            freeTextName: 'Guarnizione',
            quantity: 2,
            notes: 'Da verificare: materiale non trovato a catalogo.',
          ),
        ],
        controlli: [AiResolvedControl(ticketControlId: 'tc-1', boolValue: true)],
      ),
      ticketId: 'tkt-1',
    );

    expect(id, isNotNull);
    final row = await (db.select(db.draftReports)..where((r) => r.id.equals(id!))).getSingle();
    expect(row.title, 'Sostituzione valvola');
    expect(row.details, 'Valvola bloccata');
    expect(row.ticketId, 'tkt-1');
    expect(row.locationId, '', reason: 'a null location stays empty — never a sentinel');
    expect(row.stato, 'Bozza');
    expect(row.customerSignoffText, 'accettato');
    expect(row.isLocalOnly, isTrue, reason: "it is the phone's draft until the queue sends it");
    expect(
      row.isAiAssisted,
      isTrue,
      reason: 'provenance lands in this same write; nothing else sets it on this path',
    );

    final staff = await db.select(db.reportStaffTable).get();
    expect(staff.single.userId, 'u-1');
    expect(staff.single.hoursWorked, 6.5);
    expect(staff.single.kmTraveled, 12);

    final mat = await db.select(db.reportMateriali).getSingle();
    expect(mat.freeTextName, 'Guarnizione');
    expect(mat.quantity, 2);
    expect(mat.notes, contains('Da verificare'));
    expect(mat.magazzinoId, isNull, reason: 'nothing resolved a magazzino — no stock leaves by itself');

    final ctrl = await db.select(db.reportControlli).getSingle();
    expect(ctrl.controlId, 'tc-1');
    expect(ctrl.boolValue, isTrue);
    expect(
      ctrl.id,
      controlRowId(id!, 'tc-1'),
      reason: 'the Controlli step looks rows up by this id; any other scheme inserts a second row',
    );
  });

  testWidgets('the header this writes survives a later editor mount unharmed', (tester) async {
    final db = _makeDb();
    addTearDown(db.close);
    final container = _container(db);
    addTearDown(container.dispose);

    final id = await _callApply(
      tester,
      container,
      const AiConversationConfirmResponse(
        title: 'Pompa bloccata',
        details: 'Sostituita pompa',
        ticketId: 'tkt-1',
        staff: [AiResolvedStaff(userId: 'u-1', hoursWorked: 6.5)],
      ),
      ticketId: 'tkt-1',
    );
    expect(id, isNotNull);

    // The regression this guards: mount reportEditorProvider(localId) AFTER applyConfirmedDraft
    // and await its `ready`, then assert the applied header is still there. A notifier write before
    // hydration (markAiAssisted's autosave of a blank placeholder state) would blank title/ticketId.
    final sub = container.listen(reportEditorProvider(id!), (_, __) {});
    addTearDown(sub.close);
    await container.read(reportEditorProvider(id).notifier).ready;

    final row = await (db.select(db.draftReports)..where((r) => r.id.equals(id))).getSingle();
    expect(row.title, 'Pompa bloccata', reason: 'a notifier write before hydration blanks this');
    expect(row.ticketId, 'tkt-1');
    expect(row.details, 'Sostituita pompa');
    expect(row.isAiAssisted, isTrue);
  });

  testWidgets('a response with no title leaves one for the technician rather than inventing one',
      (tester) async {
    final db = _makeDb();
    addTearDown(db.close);
    final container = _container(db);
    addTearDown(container.dispose);

    // `ReportHeaderDeriver` returns string.Empty when no ticket title, no numero, no cantiere name
    // and no operator activity resolved — reachable for a session whose technician only answered
    // the checklist. validateDraft requires a title, so the technician fills it in; nothing here
    // may substitute a plausible-looking string.
    final id = await _callApply(
      tester,
      container,
      const AiConversationConfirmResponse(
        title: '',
        locationId: null,
        controlli: [AiResolvedControl(ticketControlId: 'tc-1', boolValue: true)],
      ),
    );

    expect(id, isNotNull);
    final row = await (db.select(db.draftReports)..where((r) => r.id.equals(id!))).getSingle();
    expect(row.title, '');
    expect(row.locationId, '');
  });

  testWidgets('no signed-in internal user id refuses, exactly as createLocalDraft does',
      (tester) async {
    final db = _makeDb();
    addTearDown(db.close);
    final container = _container(db, internalUserId: null);
    addTearDown(container.dispose);

    final id = await _callApply(
      tester,
      container,
      const AiConversationConfirmResponse(title: 'X'),
    );

    expect(id, isNull);
    expect(await db.select(db.draftReports).get(), isEmpty);
  });
}
