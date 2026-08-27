// dart format width=100
// test/features/rapportino/rapportino_view_screen_test.dart
//
// Widget tests for RapportinoViewScreen (D3b-2).
//
// Covers:
//   1. Renders KeyVal rows (Sede, Tecnico, Cliente, Ore).
//   2. Renders StatusPill with correct label.
//   3. Renders Materiali list rows when materiali seeded.
//   4. Firma cliente block shown when signature allegato id is set.
//   5. Shows "not found" empty state for unknown report id.
//   6. Scarica PDF button present.

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:tasktap_mobile/core/widgets/widgets.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart';
import 'package:tasktap_mobile/features/rapportino/rapportino_view_screen.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

AppDatabase _makeDb() => AppDatabase(NativeDatabase.memory());

Future<void> _seedSubmittedDraft(
  AppDatabase db, {
  String id = 'report-1',
  String stato = 'Bozza',
}) async {
  await db
      .into(db.draftReports)
      .insert(
        DraftReportsCompanion.insert(
          id: id,
          tenantId: 'tenant-1',
          createdAt: DateTime.utc(2026, 6, 1),
          title: 'Manutenzione straordinaria',
          insertedUserId: 'tecnico-1',
          locationId: 'sede-abc',
          customerId: const Value('Cliente Srl'),
          isLocalOnly: const Value(true),
          stato: Value(stato),
          submissionState: const Value('submitted'),
          customerSignatureAllegatoId: const Value('sig-c-1'),
          technicianSignatureAllegatoId: const Value('sig-t-1'),
        ),
      );
}

Future<void> _seedMateriali(AppDatabase db, String reportId) async {
  await db
      .into(db.reportMateriali)
      .insert(
        ReportMaterialiCompanion.insert(
          id: 'mat-1',
          tenantId: 'tenant-1',
          createdAt: DateTime.utc(2026, 6, 1),
          reportId: reportId,
          quantity: 3.0,
          freeTextName: const Value('Guarnizione'),
          unitOfMeasure: const Value('pz'),
          unitPrice: const Value(1.50),
        ),
      );
  await db
      .into(db.reportMateriali)
      .insert(
        ReportMaterialiCompanion.insert(
          id: 'mat-2',
          tenantId: 'tenant-1',
          createdAt: DateTime.utc(2026, 6, 1),
          reportId: reportId,
          quantity: 1.0,
          freeTextName: const Value('Tubo rame'),
          unitOfMeasure: const Value('m'),
        ),
      );
}

Widget _buildView({required AppDatabase db, String reportId = 'report-1'}) {
  return ProviderScope(
    overrides: [appDatabaseProvider.overrideWithValue(db)],
    child: MaterialApp(home: RapportinoViewScreen(reportId: reportId)),
  );
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  setUpAll(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    await initializeDateFormatting('it', null);
  });

  late AppDatabase db;
  setUp(() => db = _makeDb());
  tearDown(() async => db.close());

  group('RapportinoViewScreen — header card', () {
    testWidgets('renders StatusPill Inviata for submitted draft', (tester) async {
      await _seedSubmittedDraft(db);
      await tester.pumpWidget(_buildView(db: db));
      await tester.pumpAndSettle();

      expect(find.byType(StatusPill), findsWidgets);
      expect(find.text('Inviata'), findsWidgets);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('renders KeyVal rows Sede, Tecnico, Cliente, Ore', (tester) async {
      await _seedSubmittedDraft(db);
      await tester.pumpWidget(_buildView(db: db));
      await tester.pumpAndSettle();

      expect(find.byType(KeyVal), findsWidgets);
      // Labels are uppercased in KeyVal widget
      expect(find.text('SEDE'), findsOneWidget);
      expect(find.text('TECNICO'), findsOneWidget);
      expect(find.text('CLIENTE'), findsOneWidget);
      expect(find.text('ORE'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('renders title in ScreenHeader', (tester) async {
      await _seedSubmittedDraft(db);
      await tester.pumpWidget(_buildView(db: db));
      await tester.pumpAndSettle();

      expect(find.text('Manutenzione straordinaria'), findsWidgets);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  });

  group('RapportinoViewScreen — materiali', () {
    testWidgets('renders materiali list rows', (tester) async {
      await _seedSubmittedDraft(db);
      await _seedMateriali(db, 'report-1');

      await tester.pumpWidget(_buildView(db: db));
      await tester.pumpAndSettle();

      expect(find.text('Guarnizione'), findsOneWidget);
      expect(find.text('Tubo rame'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('shows qty and unit of measure in subtitle', (tester) async {
      await _seedSubmittedDraft(db);
      await _seedMateriali(db, 'report-1');

      await tester.pumpWidget(_buildView(db: db));
      await tester.pumpAndSettle();

      // subtitle built as "3 pz · €1.50"
      expect(find.textContaining('3 pz'), findsOneWidget);
      expect(find.textContaining('€1.50'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  });

  group('RapportinoViewScreen — firma cliente', () {
    testWidgets('firma block shown when customerSignatureAllegatoId is set', (tester) async {
      await _seedSubmittedDraft(db);
      await tester.pumpWidget(_buildView(db: db));
      await tester.pumpAndSettle();

      expect(find.text('Firma cliente'), findsOneWidget);
      expect(find.textContaining('Firmato il'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  });

  group('RapportinoViewScreen — download', () {
    testWidgets('Scarica PDF button is present', (tester) async {
      await _seedSubmittedDraft(db);
      await tester.pumpWidget(_buildView(db: db));
      await tester.pumpAndSettle();

      final pdfBtn = find.text('Scarica PDF');
      expect(pdfBtn, findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  });

  group('RapportinoViewScreen — customer/location names, not raw ids (regression)', () {
    testWidgets('Sede and Cliente resolve to names when the ids are in the local mirror', (
      tester,
    ) async {
      await db
          .into(db.customers)
          .insert(
            CustomersCompanion.insert(
              id: 'customer-real-1',
              tenantId: 'tenant-1',
              createdAt: DateTime.utc(2026, 6, 1),
              companyName: 'Rossi Impianti Srl',
            ),
          );
      await db
          .into(db.locations)
          .insert(
            LocationsCompanion.insert(
              id: 'location-real-1',
              tenantId: 'tenant-1',
              createdAt: DateTime.utc(2026, 6, 1),
              customerId: 'customer-real-1',
              name: 'Sede Via Roma 12',
            ),
          );
      await db
          .into(db.draftReports)
          .insert(
            DraftReportsCompanion.insert(
              id: 'report-2',
              tenantId: 'tenant-1',
              createdAt: DateTime.utc(2026, 6, 1),
              title: 'Manutenzione con id reali',
              insertedUserId: 'tecnico-1',
              locationId: 'location-real-1',
              customerId: const Value('customer-real-1'),
              isLocalOnly: const Value(true),
              stato: const Value('Bozza'),
              submissionState: const Value('submitted'),
            ),
          );

      await tester.pumpWidget(_buildView(db: db, reportId: 'report-2'));
      await tester.pumpAndSettle();

      expect(find.text('Rossi Impianti Srl'), findsOneWidget);
      expect(find.text('Sede Via Roma 12'), findsOneWidget);
      expect(find.text('customer-real-1'), findsNothing);
      expect(find.text('location-real-1'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('falls back to the raw id when the mirror does not know it', (tester) async {
      await _seedSubmittedDraft(db); // customerId 'Cliente Srl', locationId 'sede-abc' — no rows
      await tester.pumpWidget(_buildView(db: db));
      await tester.pumpAndSettle();

      expect(find.text('Cliente Srl'), findsOneWidget);
      expect(find.text('sede-abc'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  });

  group('RapportinoViewScreen — rejection banner (mobile audit item #1)', () {
    testWidgets('shows the rejection banner and Rilavora affordance for a Respinto report', (
      tester,
    ) async {
      await _seedSubmittedDraft(db, stato: 'Respinto');
      await tester.pumpWidget(_buildView(db: db));
      await tester.pumpAndSettle();

      expect(find.textContaining("L'ufficio ha respinto"), findsOneWidget);
      expect(find.text('Rilavora'), findsOneWidget);
      expect(find.text('Respinta'), findsWidgets);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('shows no rejection banner for a report still awaiting review (Inviato)', (
      tester,
    ) async {
      await _seedSubmittedDraft(db, stato: 'Inviato');
      await tester.pumpWidget(_buildView(db: db));
      await tester.pumpAndSettle();

      expect(find.textContaining("L'ufficio ha respinto"), findsNothing);
      expect(find.text('Rilavora'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('shows no rejection banner for a submitted-not-yet-synced report (stato Bozza)', (
      tester,
    ) async {
      await _seedSubmittedDraft(db);
      await tester.pumpWidget(_buildView(db: db));
      await tester.pumpAndSettle();

      expect(find.textContaining("L'ufficio ha respinto"), findsNothing);
      expect(find.text('Rilavora'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  });

  group('RapportinoViewScreen — not found', () {
    testWidgets('shows empty state for unknown report id', (tester) async {
      await tester.pumpWidget(_buildView(db: db, reportId: 'nonexistent'));
      await tester.pumpAndSettle();

      expect(find.byType(EmptyState), findsOneWidget);
      expect(find.text('Rapportino non trovato'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  });
}
