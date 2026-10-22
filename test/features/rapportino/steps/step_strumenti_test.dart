// dart format width=100
// test/features/rapportino/steps/step_strumenti_test.dart
//
// The Strumenti step: pre-fill from the technician's kit exactly once, add/remove from the local
// catalogue, an expired instrument requiring an explicit acknowledgement, and the pure rules.

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart';
import 'package:tasktap_mobile/domain/reports/strumenti_selection.dart';
import 'package:tasktap_mobile/features/rapportino/steps/step_strumenti.dart';
import 'package:tasktap_mobile/presentation/providers/strumenti_selection_providers.dart';

const _rid = 'rep-1';

Future<void> _seedDraft(AppDatabase db, {bool prefilled = false}) => db
    .into(db.draftReports)
    .insert(
      DraftReportsCompanion.insert(
        id: _rid,
        tenantId: 't1',
        createdAt: DateTime.utc(2026, 6, 22, 12),
        title: 'T',
        insertedUserId: 'u1',
        locationId: '',
        startedAt: Value(DateTime.utc(2026, 6, 22, 12)),
        strumentiPrefilled: Value(prefilled),
      ),
    );

Future<void> _seedCatalogue(AppDatabase db) async {
  await db.batch(
    (b) => b.insertAll(db.strumenti, [
      StrumentiCompanion.insert(
        id: 'mine-valid',
        name: 'Multimetro',
        matricola: 'M-1',
        calibrationExpiry: const Value('2027-01-01'),
        isMine: const Value(true),
      ),
      StrumentiCompanion.insert(
        id: 'mine-expired',
        name: 'Termocamera',
        matricola: 'T-9',
        calibrationExpiry: const Value('2026-01-01'),
        isMine: const Value(true),
      ),
      StrumentiCompanion.insert(
        id: 'other',
        name: 'Anemometro',
        matricola: 'A-3',
        calibrationExpiry: const Value('2027-03-03'),
      ),
    ]),
  );
}

ProviderContainer _container(AppDatabase db) {
  final c = ProviderContainer(overrides: [appDatabaseProvider.overrideWithValue(db)]);
  addTearDown(c.dispose);
  return c;
}

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  group('pure rules', () {
    test('valid THROUGH the expiry day, expired the day after, no expiry never expired', () {
      expect(isStrumentoExpiredOn('2026-06-22', '2026-06-22'), isFalse);
      expect(isStrumentoExpiredOn('2026-06-21', '2026-06-22'), isTrue);
      expect(isStrumentoExpiredOn(null, '2026-06-22'), isFalse);
    });

    test('body acknowledges only expired instruments and dedupes', () {
      final body = buildStrumentiBody(const [
        StrumentoSelectionInput(
          strumentoId: 'a',
          calibrationExpiry: '2027-01-01',
          expiredAcknowledged: true, // valid + ack = 422, must be forced false
        ),
        StrumentoSelectionInput(
          strumentoId: 'b',
          calibrationExpiry: '2026-01-01',
          expiredAcknowledged: true,
        ),
        StrumentoSelectionInput(
          strumentoId: 'b',
          calibrationExpiry: '2026-01-01',
          expiredAcknowledged: false,
        ),
      ], '2026-06-22');
      expect(body.map((s) => (s.strumentoId, s.expiredAcknowledged)), [('a', false), ('b', true)]);
      for (final s in body) {
        expect(s.toJson().keys.toSet(), {'strumentoId', 'expiredAcknowledged'});
      }
    });

    test('body carries the notes through, and the DTO omits blank ones', () {
      final body = buildStrumentiBody(const [
        StrumentoSelectionInput(
          strumentoId: 'a',
          calibrationExpiry: null,
          expiredAcknowledged: false,
          usageDescription: 'Misura',
          outcome: '  ',
        ),
      ], '2026-06-22');
      expect(body.single.toJson(), {
        'strumentoId': 'a',
        'expiredAcknowledged': false,
        'usageDescription': 'Misura',
      });
    });
  });

  group('StrumentiSelectionNotifier', () {
    test('pre-fills the technician kit once and never again after a deselect', () async {
      await _seedDraft(db);
      await _seedCatalogue(db);

      final c1 = _container(db);
      final n1 = c1.read(strumentiSelectionProvider(_rid).notifier);
      await n1.ready;
      expect(
        c1.read(strumentiSelectionProvider(_rid)).items.map((i) => i.strumentoId).toSet(),
        {'mine-valid', 'mine-expired'},
      );
      expect((await db.select(db.draftReports).getSingle()).strumentiPrefilled, isTrue);

      await n1.remove('mine-valid');
      await n1.remove('mine-expired');
      expect(c1.read(strumentiSelectionProvider(_rid)).items, isEmpty);

      // A fresh open (new container) must not re-fill the deselected kit.
      final c2 = _container(db);
      await c2.read(strumentiSelectionProvider(_rid).notifier).ready;
      expect(c2.read(strumentiSelectionProvider(_rid)).items, isEmpty);
    });

    test('does not burn the pre-fill while the catalogue is still empty', () async {
      await _seedDraft(db);
      final c1 = _container(db);
      await c1.read(strumentiSelectionProvider(_rid).notifier).ready;
      expect((await db.select(db.draftReports).getSingle()).strumentiPrefilled, isFalse);

      await _seedCatalogue(db); // sync delivers it later
      final c2 = _container(db);
      await c2.read(strumentiSelectionProvider(_rid).notifier).ready;
      expect(c2.read(strumentiSelectionProvider(_rid)).items, hasLength(2));
    });

    test('adopts the server selection (not the kit) for a draft the server already holds', () async {
      await _seedDraft(db);
      await _seedCatalogue(db);
      await db
          .into(db.reportStrumenti)
          .insert(
            ReportStrumentiCompanion.insert(
              id: 'srv-1',
              reportId: _rid,
              strumentoId: const Value('other'),
              name: 'Anemometro',
              matricola: 'A-3',
            ),
          );
      final c = _container(db);
      await c.read(strumentiSelectionProvider(_rid).notifier).ready;
      expect(c.read(strumentiSelectionProvider(_rid)).items.map((i) => i.strumentoId), ['other']);
    });

    test('adopting the server selection keeps its notes', () async {
      await _seedDraft(db);
      await _seedCatalogue(db);
      await db
          .into(db.reportStrumenti)
          .insert(
            ReportStrumentiCompanion.insert(
              id: 'srv-1',
              reportId: _rid,
              strumentoId: const Value('other'),
              name: 'Anemometro',
              matricola: 'A-3',
              usageDescription: const Value('Portata canale'),
              outcome: const Value('12 m/s'),
            ),
          );
      final c = _container(db);
      await c.read(strumentiSelectionProvider(_rid).notifier).ready;
      final item = c.read(strumentiSelectionProvider(_rid)).items.single;
      expect(item.usageDescription, 'Portata canale');
      expect(item.outcome, '12 m/s');
    });

    test('setUsageDescription/setOutcome persist at once, survive an acknowledgement, blank -> null',
        () async {
      await _seedDraft(db);
      await _seedCatalogue(db);
      final c = _container(db);
      final n = c.read(strumentiSelectionProvider(_rid).notifier);
      await n.ready;

      await n.setUsageDescription('mine-expired', 'Ispezione quadro');
      await n.setOutcome('mine-expired', 'Punto caldo');
      await n.setAcknowledged('mine-expired', true); // rewrites the row: must not wipe the notes

      Future<ReportStrumentoRow> row() => (db.select(
        db.reportStrumenti,
      )..where((s) => s.strumentoId.equals('mine-expired'))).getSingle();
      var r = await row();
      expect(r.usageDescription, 'Ispezione quadro');
      expect(r.outcome, 'Punto caldo');
      expect(r.expiredAcknowledged, isTrue);

      await n.setOutcome('mine-expired', '   ');
      r = await row();
      expect(r.outcome, isNull);
      expect(r.usageDescription, 'Ispezione quadro');

      // A fresh open reads them back.
      final c2 = _container(db);
      await c2.read(strumentiSelectionProvider(_rid).notifier).ready;
      final item = c2
          .read(strumentiSelectionProvider(_rid))
          .items
          .firstWhere((i) => i.strumentoId == 'mine-expired');
      expect(item.usageDescription, 'Ispezione quadro');
      expect(item.outcome, '');
    });

    test('the note reaches the state too, so a reopened sheet shows it', () async {
      // The form screen watches this provider (its "Strumenti" row counts items), so the notifier
      // outlives the compartment sheet. Reopening the sheet reuses this same state — it does not
      // hydrate again. If the note only reached the database, the reopened text fields would seed
      // from an empty item and the text would vanish even though the value was saved.
      await _seedDraft(db);
      await _seedCatalogue(db);
      final c = _container(db);
      final n = c.read(strumentiSelectionProvider(_rid).notifier);
      await n.ready;

      await n.setUsageDescription('mine-expired', 'Ispezione quadro');
      await n.setOutcome('mine-expired', 'Punto caldo');

      final item = c
          .read(strumentiSelectionProvider(_rid))
          .items
          .firstWhere((i) => i.strumentoId == 'mine-expired');
      expect(item.usageDescription, 'Ispezione quadro');
      expect(item.outcome, 'Punto caldo');

      // Cleared text is mirrored as '' — never back as the old note.
      await n.setOutcome('mine-expired', '   ');
      final afterClear = c
          .read(strumentiSelectionProvider(_rid))
          .items
          .firstWhere((i) => i.strumentoId == 'mine-expired');
      expect(afterClear.outcome, '');
      expect(afterClear.usageDescription, 'Ispezione quadro');
    });

    test('add pulls from the catalogue and remove drops it; the picker excludes selected', () async {
      await _seedDraft(db, prefilled: true);
      await _seedCatalogue(db);
      final c = _container(db);
      final n = c.read(strumentiSelectionProvider(_rid).notifier);
      await n.ready;
      expect(c.read(strumentiSelectionProvider(_rid)).items, isEmpty);
      expect(c.read(strumentiSelectionProvider(_rid)).available.first.isMine, isTrue);

      await n.add('other');
      var s = c.read(strumentiSelectionProvider(_rid));
      expect(s.items.single.name, 'Anemometro');
      expect(s.available.any((a) => a.id == 'other'), isFalse);

      await n.remove('other');
      s = c.read(strumentiSelectionProvider(_rid));
      expect(s.items, isEmpty);
      expect(s.available.any((a) => a.id == 'other'), isTrue);
    });

    test('acknowledgement is stored for an expired instrument and ignored for a valid one', () async {
      await _seedDraft(db);
      await _seedCatalogue(db);
      final c = _container(db);
      final n = c.read(strumentiSelectionProvider(_rid).notifier);
      await n.ready;
      expect(c.read(strumentiSelectionProvider(_rid)).unacknowledgedExpired, 1);

      await n.setAcknowledged('mine-valid', true); // valid: ignored
      await n.setAcknowledged('mine-expired', true);
      final s = c.read(strumentiSelectionProvider(_rid));
      expect(s.unacknowledgedExpired, 0);
      final byId = {for (final i in s.items) i.strumentoId: i};
      expect(byId['mine-expired']!.expiredAcknowledged, isTrue);
      expect(byId['mine-valid']!.expiredAcknowledged, isFalse);
    });
  });

  group('StepStrumenti widget', () {
    testWidgets('expired instrument shows Scaduto and its acknowledgement toggle persists', (
      tester,
    ) async {
      await _seedDraft(db);
      await _seedCatalogue(db);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [appDatabaseProvider.overrideWithValue(db)],
          child: const MaterialApp(
            home: Scaffold(body: SingleChildScrollView(child: StepStrumenti(reportId: _rid))),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Multimetro'), findsOneWidget);
      expect(find.text('Termocamera'), findsOneWidget);
      expect(find.text('Scaduto'), findsOneWidget);
      expect(find.textContaining('Confermo di aver usato'), findsOneWidget);

      await tester.ensureVisible(find.textContaining('Confermo di aver usato'));
      await tester.tap(find.textContaining('Confermo di aver usato'));
      await tester.pumpAndSettle();

      final row = await (db.select(
        db.reportStrumenti,
      )..where((s) => s.strumentoId.equals('mine-expired'))).getSingle();
      expect(row.expiredAcknowledged, isTrue);
      expect(row.isLocal, isTrue);
    });

    testWidgets('typing in the two note fields persists to the Drift row, counter hidden until 1800',
        (tester) async {
      await _seedDraft(db);
      await _seedCatalogue(db);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [appDatabaseProvider.overrideWithValue(db)],
          child: const MaterialApp(
            home: Scaffold(body: SingleChildScrollView(child: StepStrumenti(reportId: _rid))),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final usage = find.byKey(const ValueKey('strumento-usage-mine-valid'));
      final esito = find.byKey(const ValueKey('strumento-outcome-mine-valid'));
      expect(find.text('DESCRIZIONE DELL\'UTILIZZO'), findsNWidgets(2));
      expect(find.text('ESITO'), findsNWidgets(2));
      await tester.ensureVisible(usage);
      await tester.enterText(
        find.descendant(of: usage, matching: find.byType(TextFormField)),
        'Misura isolamento',
      );
      await tester.ensureVisible(esito);
      await tester.enterText(
        find.descendant(of: esito, matching: find.byType(TextFormField)),
        'Conforme',
      );
      await tester.pumpAndSettle();

      final row = await (db.select(
        db.reportStrumenti,
      )..where((s) => s.strumentoId.equals('mine-valid'))).getSingle();
      expect(row.usageDescription, 'Misura isolamento');
      expect(row.outcome, 'Conforme');
      expect(find.text('17/2000'), findsNothing, reason: 'counter hidden below 1800');

      await tester.enterText(
        find.descendant(of: usage, matching: find.byType(TextFormField)),
        'x' * 1850,
      );
      await tester.pumpAndSettle();
      expect(find.text('1850/2000'), findsOneWidget, reason: 'counter shows from 1800');
    });
  });
}
