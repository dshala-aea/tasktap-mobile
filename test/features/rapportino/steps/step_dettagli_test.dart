// dart format width=100
// test/features/rapportino/steps/step_dettagli_test.dart
//
// Widget tests for StepDettagli's remaining Dettagli-form behavior.
//
// The AI-draft "Genera con AI" button and its `_generateAiDraft` logic moved out of this file and
// into `lib/features/rapportino/ai_draft_action.dart` (see ai_draft_action_test.dart) — StepDettagli
// no longer renders a "Genera" button or the cantiere-no-ticket explanatory note, both of which used
// to live here. What's left below are the tests for what StepDettagli still owns: the ticket/cantiere
// Collegamento lookup fields.

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';
import 'package:tasktap_mobile/core/location/location_service.dart';
import 'package:tasktap_mobile/core/widgets/geo_map_card.dart';
import 'package:tasktap_mobile/data/ai/ai_api_client.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/reports/draft_report_repository.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart';
import 'package:tasktap_mobile/features/rapportino/steps/step_dettagli.dart';
import 'package:tasktap_mobile/presentation/providers/report_editor_providers.dart';

const _reportId = 'draft-1';

/// A no-op AiApiClient — StepDettagli no longer calls it directly, but reportEditorProvider's
/// container still needs an override so nothing in the widget tree that reads `aiApiClientProvider`
/// (there is none left in StepDettagli itself, but overriding keeps this container shape aligned
/// with ai_draft_action_test.dart's).
class _FakeAiApiClient extends AiApiClient {
  _FakeAiApiClient() : super(Dio());
}

AppDatabase _makeDb() => AppDatabase(NativeDatabase.memory());

ProviderContainer _buildContainer({
  required AppDatabase db,
  String details = '',
  String? ticketId,
  String? ticketFreeText,
  String? cantiereId,
  String? cantiereFreeText,
  String? customerId,
  String? customerFreeText,
  String? locationId,
  String? locationFreeText,
  double? gpsLatitude,
  double? gpsLongitude,
}) {
  return ProviderContainer(
    overrides: [
      appDatabaseProvider.overrideWithValue(db),
      aiApiClientProvider.overrideWithValue(_FakeAiApiClient()),
      // StepDettagli itself no longer captures GPS (that moved to RapportinoFormScreen — see its
      // own header comment), so this override only keeps the manual "Acquisisci"/"Aggiorna" button
      // in _GpsCapture from hitting real location services in these tests. The auto-capture-on-
      // screen-entry behavior is covered end-to-end by rapportino_form_screen_test.dart instead.
      gpsPreferenceProvider.overrideWithValue(false),
      reportEditorProvider(_reportId).overrideWith(
        (ref) => ReportEditorNotifier(
          initialState: ReportEditorState(
            reportId: _reportId,
            tenantId: 'tenant-1',
            insertedUserId: 'user-1',
            scheduleId: 'sched-1',
            details: details,
            ticketId: ticketId,
            ticketFreeText: ticketFreeText,
            cantiereId: cantiereId,
            cantiereFreeText: cantiereFreeText,
            customerId: customerId,
            customerFreeText: customerFreeText,
            locationId: locationId,
            locationFreeText: locationFreeText,
            gpsLatitude: gpsLatitude,
            gpsLongitude: gpsLongitude,
          ),
          repo: DraftReportRepository(db),
        ),
      ),
    ],
  );
}

Widget _buildStep(ProviderContainer container) {
  return UncontrolledProviderScope(
    container: container,
    child: const MaterialApp(
      home: Scaffold(body: StepDettagli(reportId: _reportId)),
    ),
  );
}

void main() {
  late AppDatabase db;

  setUp(() => db = _makeDb());
  tearDown(() async => db.close());

  group('StepDettagli — no longer renders the AI draft action', () {
    testWidgets('no "Genera" button appears on this step', (tester) async {
      final container = _buildContainer(db: db);
      addTearDown(container.dispose);

      await tester.pumpWidget(_buildStep(container));
      await tester.pumpAndSettle();

      expect(find.text('Genera'), findsNothing);
      expect(find.text('Bozza automatica'), findsNothing);
    });
  });

  group('StepDettagli — Collegamento lookup fields show resolved state', () {
    // A resolved ticketId/cantiereId not yet in the local mirror still leaves the "Collegamento"
    // section expanded (linkedTicket/linkedCantiere can't be named), but the field itself must
    // still mark itself resolved (the check icon) rather than looking like unconfirmed free text.
    testWidgets('Ticket field shows the resolved check icon when ticketId is set', (
      tester,
    ) async {
      final container = _buildContainer(
        db: db,
        ticketId: 'ticket-not-yet-cached',
        ticketFreeText: 'TICK-042',
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(_buildStep(container));
      await tester.pumpAndSettle();

      expect(find.text('TICK-042'), findsOneWidget);
      expect(find.byIcon(LucideIcons.check), findsOneWidget);
      expect(find.byIcon(LucideIcons.x), findsNothing);
    });

    testWidgets('Cantiere field shows the resolved check icon when cantiereId is set', (
      tester,
    ) async {
      final container = _buildContainer(
        db: db,
        cantiereId: 'cantiere-not-yet-cached',
        cantiereFreeText: 'Cantiere Via Roma',
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(_buildStep(container));
      await tester.pumpAndSettle();

      expect(find.text('Cantiere Via Roma'), findsOneWidget);
      expect(find.byIcon(LucideIcons.check), findsOneWidget);
      expect(find.byIcon(LucideIcons.x), findsNothing);
    });
  });

  group('StepDettagli — cliente/sede are derived once a ticket is linked', () {
    testWidgets('shows the resolved name as a locked chip, not an editable lookup field', (
      tester,
    ) async {
      // linkedTicket must resolve to non-null (it gates lockedCliente/lockedSede in
      // step_dettagli.dart) — driven off allTicketsProvider, which reads this real, otherwise-
      // empty in-memory db. customerId/locationId themselves don't need matching rows: lacking a
      // Customer/Location row, lockedCliente/lockedSede fall back to state.customerFreeText/
      // locationFreeText, which is exactly what's asserted below.
      await db
          .into(db.tickets)
          .insert(
            TicketsCompanion.insert(
              id: 'ticket-1',
              tenantId: 'tenant-1',
              createdAt: DateTime.utc(2026, 1, 1),
              title: 'TICK-042',
              customerId: 'customer-1',
              locationId: 'location-1',
              statusId: 1,
              typeId: 1,
            ),
          );

      final container = _buildContainer(
        db: db,
        ticketId: 'ticket-1',
        ticketFreeText: 'TICK-042',
        customerId: 'customer-1',
        customerFreeText: 'Acme SRL',
        locationId: 'location-1',
        locationFreeText: 'Sede Legale',
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(_buildStep(container));
      await tester.pumpAndSettle();

      expect(find.text('Cliente · '), findsOneWidget);
      expect(find.text('Acme SRL'), findsOneWidget);
      expect(find.text('Sede · '), findsOneWidget);
      expect(find.text('Sede Legale'), findsOneWidget);

      // Not an editable lookup field: its label (AppFieldLabel upper-cases "Cliente *"/"Sede"
      // into "CLIENTE *"/"SEDE") must not render at all.
      expect(find.text('CLIENTE *'), findsNothing);
      expect(find.text('SEDE'), findsNothing);
    });

    testWidgets('stays an editable lookup field when no ticket is linked', (tester) async {
      final container = _buildContainer(
        db: db,
        customerId: 'customer-1',
        customerFreeText: 'Acme SRL',
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(_buildStep(container));
      await tester.pumpAndSettle();

      expect(find.text('CLIENTE *'), findsOneWidget);
      expect(find.text('SEDE'), findsOneWidget);
      expect(find.text('Cliente · '), findsNothing);
    });
  });

  group('StepDettagli — GPS capture never shows raw coordinates', () {
    testWidgets('shows a neutral label, never the raw lat/lng, when no fix is captured', (
      tester,
    ) async {
      final container = _buildContainer(db: db);
      addTearDown(container.dispose);

      await tester.pumpWidget(_buildStep(container));
      await tester.pumpAndSettle();

      expect(find.text('Posizione GPS non acquisita'), findsOneWidget);
      expect(find.byType(GeoMapCard), findsNothing);
    });

    testWidgets('shows GeoMapCard, never the raw lat/lng pair, once a fix is captured', (
      tester,
    ) async {
      final container = _buildContainer(db: db, gpsLatitude: 45.464200, gpsLongitude: 9.190000);
      addTearDown(container.dispose);

      await tester.pumpWidget(_buildStep(container));
      // Bounded pumps, not pumpAndSettle: a captured point renders the real embedded map
      // immediately (AsyncValue.data, no async wait), and its TileLayer's network image requests
      // never "settle" the way pumpAndSettle waits for — see the analogous note in
      // admin_location_detail_screen_test.dart. The assertions below only need the widget tree
      // built, not tiles painted.
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(find.text('Posizione GPS acquisita'), findsOneWidget);
      expect(find.byType(GeoMapCard), findsOneWidget);
      // The old rendering would have shown this exact string — assert it's gone entirely.
      expect(find.text('GPS: 45.46420, 9.19000'), findsNothing);
      expect(find.textContaining('45.4642'), findsNothing);
    });
  });
}
