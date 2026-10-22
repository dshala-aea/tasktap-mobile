// dart format width=100
// test/features/rapportino/draft_for_ticket_test.dart
//
// "Crea rapportino" used to mint a second Bozza for a ticket that already had one. These cover the
// query that notices the existing draft and the dialog that asks what to do about it.

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/features/rapportino/draft_for_ticket.dart';

Future<void> _seedDraft(
  AppDatabase db, {
  required String id,
  String? ticketId = 'tk1',
  String stato = 'Bozza',
  String submissionState = 'draft',
  DateTime? updatedAt,
  bool isLocalOnly = true,
}) => db
    .into(db.draftReports)
    .insert(
      DraftReportsCompanion.insert(
        id: id,
        tenantId: 't1',
        createdAt: DateTime.utc(2026, 6, 1),
        title: 'Bozza $id',
        insertedUserId: 'u1',
        locationId: '',
        ticketId: Value(ticketId),
        stato: Value(stato),
        submissionState: Value(submissionState),
        updatedAt: Value(updatedAt),
        isLocalOnly: Value(isLocalOnly),
      ),
    );

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  group('editableDraftsForTicket', () {
    test('returns only editable Bozze of that ticket, newest first', () async {
      await _seedDraft(db, id: 'old', updatedAt: DateTime.utc(2026, 6, 1));
      await _seedDraft(db, id: 'new', updatedAt: DateTime.utc(2026, 6, 5));
      await _seedDraft(db, id: 'sent', stato: 'Inviato');
      // Submitted on this device, `stato` not yet flipped by the next sync: reopening it would
      // re-open a report the server already holds.
      await _seedDraft(db, id: 'submitted', submissionState: 'submitted');
      await _seedDraft(db, id: 'other-ticket', ticketId: 'tk2');
      await _seedDraft(db, id: 'no-ticket', ticketId: null);

      final drafts = await editableDraftsForTicket(db, 'tk1');
      expect(drafts.map((d) => d.id), ['new', 'old']);
    });

    test(
      'a server-authored Bozza counts too — the check must see sync rows, not just local ones',
      () async {
        await _seedDraft(db, id: 'server', isLocalOnly: false);
        final drafts = await editableDraftsForTicket(db, 'tk1');
        expect(drafts.single.id, 'server');
      },
    );

    test('no drafts for the ticket returns empty', () async {
      await _seedDraft(db, id: 'x', ticketId: 'tk9');
      expect(await editableDraftsForTicket(db, 'tk1'), isEmpty);
    });
  });

  group('askAboutExistingDraft', () {
    /// Pumps a host that runs the dialog and records what it answered.
    Future<void> host(
      WidgetTester tester,
      List<DraftReport> drafts,
      void Function(ExistingDraftChoice?) record,
    ) async {
      await tester.pumpWidget(
        _DialogHost(
          onRun: (ctx) async {
            record(await askAboutExistingDraft(ctx, drafts: drafts));
          },
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<DraftReport> one() async {
      await _seedDraft(db, id: 'a', updatedAt: DateTime.utc(2026, 6, 1));
      return (await editableDraftsForTicket(db, 'tk1')).single;
    }

    testWidgets('names the existing draft rather than a bare count', (tester) async {
      final d = await one();
      await host(tester, [d], (_) => null);
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      expect(find.text('Bozza già presente'), findsOneWidget);
      expect(find.textContaining('«Bozza a»'), findsOneWidget);
    });

    testWidgets('Apri bozza and Crea nuova answer distinctly', (tester) async {
      final d = await one();
      for (final (label, expected) in [
        ('Apri bozza', ExistingDraftChoice.openExisting),
        ('Crea nuova', ExistingDraftChoice.createNew),
      ]) {
        ExistingDraftChoice? result;
        await host(tester, [d], (v) => result = v);
        await tester.tap(find.text('go'));
        await tester.pumpAndSettle();
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
        expect(result, expected);
      }
    });

    testWidgets('a dismissed dialog answers cancelled, so nothing is created', (tester) async {
      final d = await one();
      ExistingDraftChoice? result;
      await host(tester, [d], (v) => result = v);
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(5, 5)); // the barrier
      await tester.pumpAndSettle();
      expect(result, ExistingDraftChoice.cancelled);
    });
  });
}

class _DialogHost extends StatelessWidget {
  const _DialogHost({required this.onRun});

  final Future<void> Function(BuildContext ctx) onRun;

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Builder(
      builder: (ctx) => Scaffold(
        body: Center(
          child: ElevatedButton(onPressed: () => onRun(ctx), child: const Text('go')),
        ),
      ),
    ),
  );
}
