// dart format width=100
// test/features/rapportino/rapportino_view_screen_test.dart
//
// Widget tests for RapportinoViewScreen (D3b-2).
//
// Covers:
//   1. Renders KeyVal rows (Sede, Tecnico, Cliente, Ore).
//   2. Renders StatusPill with correct label.
//   3. Renders Materiali list rows when materiali seeded.
//   4. Firma cliente and Firma tecnico blocks shown when their signature allegato ids are set.
//   5. Shows "not found" empty state for unknown report id.
//   6. Scarica PDF button present.

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mocktail/mocktail.dart';

import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';
import 'package:tasktap_mobile/core/location/geocoding_service.dart';
import 'package:tasktap_mobile/core/widgets/app_map_card.dart';
import 'package:tasktap_mobile/core/widgets/geo_map_card.dart';
import 'package:tasktap_mobile/core/widgets/widgets.dart';
import 'package:tasktap_mobile/data/api/dio_client.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/sync/connectivity_provider.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart';
import 'package:tasktap_mobile/features/rapportino/rapportino_view_screen.dart';

class _MockDio extends Mock implements Dio {}

/// Never geocodes for real — every test in this file overrides `geocodingServiceProvider` with
/// this, so a report location with an address exercises `GeoMapCard`'s fallback path
/// (`AppMapCard`, unchanged) deterministically instead of racing a real Nominatim request. Mirrors
/// `test/features/cantiere/cantiere_detail_screen_test.dart`'s own `_NullGeocodingService`.
class _NullGeocodingService extends GeocodingService {
  _NullGeocodingService() : super(dio: null);

  @override
  Future<GeocodedPoint?> geocode(String address) async => null;
}

Response<T> _okResponse<T>(T data, String path) => Response<T>(
  data: data,
  statusCode: 200,
  requestOptions: RequestOptions(path: path),
);

// ── Helpers ───────────────────────────────────────────────────────────────────

AppDatabase _makeDb() => AppDatabase(NativeDatabase.memory());

Future<void> _seedSubmittedDraft(
  AppDatabase db, {
  String id = 'report-1',
  String stato = 'Bozza',
  String? ticketId,
  String? technicianNotes,
  String? customerSignoffText,
  bool isAiAssisted = false,
  bool richiedeSecondoIntervento = false,
  bool materialiNotRequired = false,
  DateTime? inviatoAt,
  DateTime? controllatoAt,
  DateTime? fatturatoAt,
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
          ticketId: Value(ticketId),
          isLocalOnly: const Value(true),
          stato: Value(stato),
          submissionState: const Value('submitted'),
          customerSignatureAllegatoId: const Value('sig-c-1'),
          technicianSignatureAllegatoId: const Value('sig-t-1'),
          technicianNotes: Value(technicianNotes),
          customerSignoffText: Value(customerSignoffText),
          isAiAssisted: Value(isAiAssisted),
          richiedeSecondoIntervento: Value(richiedeSecondoIntervento),
          materialiNotRequired: Value(materialiNotRequired),
          inviatoAt: Value(inviatoAt),
          controllatoAt: Value(controllatoAt),
          fatturatoAt: Value(fatturatoAt),
        ),
      );
}

Future<void> _seedStaff(
  AppDatabase db,
  String reportId, {
  String id = 'staff-1',
  String userId = 'tecnico-1',
  double? hoursWorked = 3.5,
  double kmTraveled = 0.0,
  String? vehicle,
  String? notes,
}) async {
  await db
      .into(db.reportStaffTable)
      .insert(
        ReportStaffTableCompanion.insert(
          id: id,
          tenantId: 'tenant-1',
          createdAt: DateTime.utc(2026, 6, 1),
          reportId: reportId,
          userId: userId,
          hoursWorked: Value(hoursWorked),
          kmTraveled: Value(kmTraveled),
          vehicle: Value(vehicle),
          notes: Value(notes),
        ),
      );
}

Future<void> _seedControllo(
  AppDatabase db,
  String reportId, {
  String id = 'ctrl-row-1',
  required String controlId,
  String? stringValue,
  bool? boolValue,
}) async {
  await db
      .into(db.reportControlli)
      .insert(
        ReportControlliCompanion.insert(
          id: id,
          tenantId: 'tenant-1',
          createdAt: DateTime.utc(2026, 6, 1),
          reportId: reportId,
          controlId: controlId,
          stringValue: Value(stringValue),
          boolValue: Value(boolValue),
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

/// A real file on disk, so `File(path).existsSync()` — the local-first check both
/// `_SignatureBlock` and `_AllegatiPhotoGrid` make — is true without needing any network stub.
/// Content doesn't need to decode as a real image: these tests check that the resolved allegato
/// took the image branch (tappable, InteractiveViewer on tap), not that a real photo renders.
File _makeTempFile(String name, List<int> bytes) {
  final file = File('${Directory.systemTemp.path}/rapportino_view_test_$name');
  file.writeAsBytesSync(bytes);
  return file;
}

Future<void> _insertAllegato(
  AppDatabase db, {
  required String id,
  required String reportId,
  required String fileName,
  required String storagePath,
}) async {
  await db
      .into(db.reportAllegati)
      .insert(
        ReportAllegatiCompanion.insert(
          id: id,
          tenantId: 'tenant-1',
          createdAt: DateTime.utc(2026, 6, 1),
          fileName: fileName,
          contentType: 'image/jpeg',
          sizeBytes: 1024,
          storagePath: storagePath,
          url: storagePath,
          entityType: 1, // Report
          entityId: reportId,
          uploadedByUserId: 'tecnico-1',
        ),
      );
}

Widget _buildView({
  required AppDatabase db,
  String reportId = 'report-1',
  Dio? dio,
  bool isOnline = true,
}) {
  return ProviderScope(
    overrides: [
      appDatabaseProvider.overrideWithValue(db),
      if (dio != null) dioProvider.overrideWithValue(dio),
      isOnlineProvider.overrideWithValue(isOnline),
      geocodingServiceProvider.overrideWithValue(_NullGeocodingService()),
    ],
    child: MaterialApp(home: RapportinoViewScreen(reportId: reportId)),
  );
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  setUpAll(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    await initializeDateFormatting('it', null);
    registerFallbackValue(RequestOptions(path: '/'));
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
      // Uppercased by StatusStamp now (Il Documento's stamp device) — see
      // status_pill_test.dart's own note on this rendering change.
      expect(find.text('INVIATA'), findsWidgets);

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
      // _seedSubmittedDraft sets both signature ids — no allegato row seeded for either here, so
      // both sections render the "Firmato il" placeholder.
      expect(find.textContaining('Firmato il'), findsNWidgets(2));

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    // ── Real image, not the placeholder (2026-08-30 attachment viewer) ──────
    //
    // The placeholder-icon fallback above covers "no allegato resolved yet" — this covers what
    // used to be an unreachable branch: rapportino_view_screen.dart's own comment said "when the
    // allegati watcher is added to view, this can show the image." It's added now.

    testWidgets('shows the real signature image and opens the fullscreen viewer on tap', (
      tester,
    ) async {
      await _seedSubmittedDraft(db);
      final file = _makeTempFile('sig.jpg', [1, 2, 3]);
      addTearDown(() => file.deleteSync());
      await _insertAllegato(
        db,
        id: 'sig-c-1',
        reportId: 'report-1',
        fileName: 'firma.jpg',
        storagePath: file.path,
      );

      await tester.pumpWidget(_buildView(db: db));
      await tester.pumpAndSettle();

      // Customer's resolved to a real image (no pen icon); technician's has no allegato row
      // seeded, so it still shows the placeholder — one pen icon, one "Firmato il" each.
      expect(find.byIcon(LucideIcons.penTool), findsOneWidget);
      expect(find.textContaining('Firmato il'), findsNWidgets(2));

      // The customer block (first in the list) is the one actually wrapped in a tappable —
      // the placeholder branch isn't tappable at all.
      await tester.tap(find.textContaining('Firmato il').first);
      await tester.pumpAndSettle();

      expect(find.byType(InteractiveViewer), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  });

  group('RapportinoViewScreen — firma tecnico', () {
    testWidgets('firma block shown when technicianSignatureAllegatoId is set', (tester) async {
      await _seedSubmittedDraft(db);
      await tester.pumpWidget(_buildView(db: db));
      await tester.pumpAndSettle();

      expect(find.text('Firma tecnico'), findsOneWidget);
      // Both signature blocks render "Firmato il" — one for each section.
      expect(find.textContaining('Firmato il'), findsNWidgets(2));

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('shows the real technician signature image, distinct from the customer one', (
      tester,
    ) async {
      await _seedSubmittedDraft(db);
      final custFile = _makeTempFile('sig-c.jpg', [1, 2, 3]);
      final techFile = _makeTempFile('sig-t.jpg', [4, 5, 6]);
      addTearDown(() => custFile.deleteSync());
      addTearDown(() => techFile.deleteSync());
      await _insertAllegato(
        db,
        id: 'sig-c-1',
        reportId: 'report-1',
        fileName: 'firma-cliente.jpg',
        storagePath: custFile.path,
      );
      await _insertAllegato(
        db,
        id: 'sig-t-1',
        reportId: 'report-1',
        fileName: 'firma-tecnico.jpg',
        storagePath: techFile.path,
      );

      await tester.pumpWidget(_buildView(db: db));
      await tester.pumpAndSettle();

      // Both signatures resolved to real images — the placeholder pen icon is gone entirely.
      expect(find.byIcon(LucideIcons.penTool), findsNothing);
      expect(find.text('Firma cliente'), findsOneWidget);
      expect(find.text('Firma tecnico'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  });

  group('RapportinoViewScreen — foto (2026-08-30 attachment viewer)', () {
    testWidgets('shows a Foto section for Step 6 allegati, tap opens the viewer', (tester) async {
      await _seedSubmittedDraft(db);
      final file = _makeTempFile('job-photo.jpg', [4, 5, 6]);
      addTearDown(() => file.deleteSync());
      // A regular report photo — not one of the two signature ids, so it lands in the photo
      // grid rather than being resolved as a signature.
      await _insertAllegato(
        db,
        id: 'photo-1',
        reportId: 'report-1',
        fileName: 'lavoro.jpg',
        storagePath: file.path,
      );

      await tester.pumpWidget(_buildView(db: db));
      await tester.pumpAndSettle();

      expect(find.text('Foto (1)'), findsOneWidget);

      // The thumbnail itself is the tap target — no seeded signature in this test, so it's the
      // only Image on screen.
      await tester.tap(find.byType(Image).first);
      await tester.pumpAndSettle();

      expect(find.byType(InteractiveViewer), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('a signature allegato never shows up in the photo grid', (tester) async {
      await _seedSubmittedDraft(db);
      final file = _makeTempFile('sig-only.jpg', [7, 8, 9]);
      addTearDown(() => file.deleteSync());
      await _insertAllegato(
        db,
        id: 'sig-c-1', // matches customerSignatureAllegatoId from _seedSubmittedDraft
        reportId: 'report-1',
        fileName: 'firma.jpg',
        storagePath: file.path,
      );

      await tester.pumpWidget(_buildView(db: db));
      await tester.pumpAndSettle();

      // Only the signature block claims it — the photo section never appears for zero photos.
      expect(find.textContaining('Foto ('), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  });

  group('RapportinoViewScreen — download', () {
    testWidgets('Scarica PDF button is present', (tester) async {
      // The Firma tecnico section (shown by default — _seedSubmittedDraft sets both signature
      // ids) pushes this section below the default test surface height.
      await tester.binding.setSurfaceSize(const Size(800, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

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

  group('RapportinoViewScreen — Sede map', () {
    testWidgets(
      'shows GeoMapCard (never a raw KeyVal-only Sede) when the location has an address',
      (tester) async {
        await db
            .into(db.customers)
            .insert(
              CustomersCompanion.insert(
                id: 'customer-map-1',
                tenantId: 'tenant-1',
                createdAt: DateTime.utc(2026, 6, 1),
                companyName: 'Bianchi Impianti Srl',
              ),
            );
        await db
            .into(db.locations)
            .insert(
              LocationsCompanion.insert(
                id: 'location-map-1',
                tenantId: 'tenant-1',
                createdAt: DateTime.utc(2026, 6, 1),
                customerId: 'customer-map-1',
                name: 'Sede Via Torino 5',
                address: const Value('Via Torino 5'),
                city: const Value('Torino'),
              ),
            );
        await db
            .into(db.draftReports)
            .insert(
              DraftReportsCompanion.insert(
                id: 'report-map-1',
                tenantId: 'tenant-1',
                createdAt: DateTime.utc(2026, 6, 1),
                title: 'Manutenzione con sede geolocalizzata',
                insertedUserId: 'tecnico-1',
                locationId: 'location-map-1',
                customerId: const Value('customer-map-1'),
                isLocalOnly: const Value(true),
                stato: const Value('Bozza'),
                submissionState: const Value('submitted'),
              ),
            );

        await tester.pumpWidget(_buildView(db: db, reportId: 'report-map-1'));
        await tester.pumpAndSettle();

        // The fake geocoder never resolves a point, so this exercises GeoMapCard's own fallback
        // to AppMapCard, deterministically — see `_NullGeocodingService`'s own doc comment.
        expect(find.byType(GeoMapCard), findsOneWidget);
        expect(find.byType(AppMapCard), findsOneWidget);
        expect(find.text('Via Torino 5, Torino'), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
    );

    testWidgets('shows no map when the report has no real Location row (free-text-only sede)', (
      tester,
    ) async {
      await _seedSubmittedDraft(db); // locationId 'sede-abc' — no matching Locations row
      await tester.pumpWidget(_buildView(db: db));
      await tester.pumpAndSettle();

      expect(find.byType(GeoMapCard), findsNothing);

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
      // Uppercased by StatusStamp now (Il Documento's stamp device) — see
      // status_pill_test.dart's own note on this rendering change.
      expect(find.text('RESPINTA'), findsWidgets);

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

  group('RapportinoViewScreen — note tecnico', () {
    testWidgets('renders technicianNotes in its own section, separate from Descrizione', (
      tester,
    ) async {
      await _seedSubmittedDraft(db, technicianNotes: 'Verificare guarnizione al prossimo giro');
      await tester.pumpWidget(_buildView(db: db));
      await tester.pumpAndSettle();

      expect(find.text('Note tecnico'), findsOneWidget);
      expect(find.text('Verificare guarnizione al prossimo giro'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('no Note tecnico section when technicianNotes is empty', (tester) async {
      await _seedSubmittedDraft(db);
      await tester.pumpWidget(_buildView(db: db));
      await tester.pumpAndSettle();

      expect(find.text('Note tecnico'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  });

  group('RapportinoViewScreen — redazione AI / da tornare', () {
    testWidgets('shows the AI-drafted row when isAiAssisted is true', (tester) async {
      await _seedSubmittedDraft(db, isAiAssisted: true);
      await tester.pumpWidget(_buildView(db: db));
      await tester.pumpAndSettle();

      expect(find.text('Bozza generata con AI, poi rivista'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('no AI row when isAiAssisted is false', (tester) async {
      await _seedSubmittedDraft(db);
      await tester.pumpWidget(_buildView(db: db));
      await tester.pumpAndSettle();

      expect(find.text('Bozza generata con AI, poi rivista'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('shows a "Da tornare" badge when richiedeSecondoIntervento is true', (
      tester,
    ) async {
      await _seedSubmittedDraft(db, richiedeSecondoIntervento: true);
      await tester.pumpWidget(_buildView(db: db));
      await tester.pumpAndSettle();

      expect(find.text('Da tornare'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('no "Da tornare" badge when richiedeSecondoIntervento is false', (tester) async {
      await _seedSubmittedDraft(db);
      await tester.pumpWidget(_buildView(db: db));
      await tester.pumpAndSettle();

      expect(find.text('Da tornare'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  });

  group('RapportinoViewScreen — cronologia', () {
    testWidgets('shows Inviato/Controllato/Fatturato dates when present', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await _seedSubmittedDraft(
        db,
        inviatoAt: DateTime.utc(2026, 6, 2, 9),
        controllatoAt: DateTime.utc(2026, 6, 3, 10),
        fatturatoAt: DateTime.utc(2026, 6, 4, 11),
      );
      await tester.pumpWidget(_buildView(db: db));
      await tester.pumpAndSettle();

      expect(find.text('Cronologia'), findsOneWidget);
      expect(find.text('INVIATO IL'), findsOneWidget);
      expect(find.text('CONTROLLATO IL'), findsOneWidget);
      expect(find.text('FATTURATO IL'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('no Cronologia card when the report never left Bozza', (tester) async {
      await _seedSubmittedDraft(db);
      await tester.pumpWidget(_buildView(db: db));
      await tester.pumpAndSettle();

      expect(find.text('Cronologia'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  });

  group('RapportinoViewScreen — materiali non richiesti', () {
    testWidgets('shows the "not required" message when materialiNotRequired and no rows', (
      tester,
    ) async {
      await _seedSubmittedDraft(db, materialiNotRequired: true);
      await tester.pumpWidget(_buildView(db: db));
      await tester.pumpAndSettle();

      expect(find.text('Materiali'), findsOneWidget);
      expect(find.text('Nessun materiale utilizzato — confermato dal tecnico.'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('no Materiali section at all when not required and unseeded', (tester) async {
      await _seedSubmittedDraft(db);
      await tester.pumpWidget(_buildView(db: db));
      await tester.pumpAndSettle();

      expect(find.text('Materiali'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  });

  group('RapportinoViewScreen — squadra e ore', () {
    testWidgets('renders one row per technician with hours, km and vehicle', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await _seedSubmittedDraft(db);
      await _seedStaff(
        db,
        'report-1',
        id: 'staff-1',
        userId: 'tecnico-1',
        hoursWorked: 2.5,
        kmTraveled: 12.0,
        vehicle: 'Furgone',
      );
      await _seedStaff(
        db,
        'report-1',
        id: 'staff-2',
        userId: 'tecnico-2',
        hoursWorked: 1.0,
      );

      await tester.pumpWidget(_buildView(db: db));
      await tester.pumpAndSettle();

      expect(find.text('Squadra e ore'), findsOneWidget);
      expect(find.textContaining('2h 30min'), findsOneWidget);
      expect(find.textContaining('12.0 km'), findsOneWidget);
      expect(find.textContaining('Furgone'), findsOneWidget);
      expect(find.textContaining('1h'), findsWidgets);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('no Squadra e ore section when there are no staff rows', (tester) async {
      await db
          .into(db.draftReports)
          .insert(
            DraftReportsCompanion.insert(
              id: 'report-nostaff',
              tenantId: 'tenant-1',
              createdAt: DateTime.utc(2026, 6, 1),
              title: 'Senza squadra',
              insertedUserId: 'tecnico-1',
              locationId: 'sede-abc',
              isLocalOnly: const Value(true),
              stato: const Value('Bozza'),
              submissionState: const Value('submitted'),
            ),
          );
      await tester.pumpWidget(_buildView(db: db, reportId: 'report-nostaff'));
      await tester.pumpAndSettle();

      expect(find.text('Squadra e ore'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  });

  group('RapportinoViewScreen — accettazione cliente', () {
    testWidgets('shows customerSignoffText above the Firma cliente signature block', (
      tester,
    ) async {
      await _seedSubmittedDraft(
        db,
        customerSignoffText: 'Confermo accettazione lavoro eseguito e materiali utilizzati',
      );
      await tester.pumpWidget(_buildView(db: db));
      await tester.pumpAndSettle();

      expect(
        find.text('Confermo accettazione lavoro eseguito e materiali utilizzati'),
        findsOneWidget,
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  });

  group('RapportinoViewScreen — controlli', () {
    testWidgets('renders a recorded answer with its resolved checklist label', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      const ticketId = 'ticket-1';
      await _seedSubmittedDraft(db, ticketId: ticketId);
      await _seedControllo(db, 'report-1', controlId: 'tc-1', boolValue: true);

      final dio = _MockDio();
      when(() => dio.get<Map<String, dynamic>>('/api/tickets/$ticketId/controls')).thenAnswer(
        (_) async => _okResponse({
          'groups': [
            {
              'id': 'grp-1',
              'name': 'Sezione A',
              'description': null,
              'sortOrder': 0,
              'subgroups': <dynamic>[],
              'controls': [
                {
                  'id': 'tc-1',
                  'templateControlId': 'tpl-1',
                  'label': 'Pressione OK',
                  'description': null,
                  'type': 'Checkbox',
                  'isRequired': true,
                  'options': null,
                  'valoreLimite': null,
                  'sortOrder': 0,
                  'status': 'Completed',
                  'stringValue': null,
                  'boolValue': true,
                  'dateValue': null,
                },
              ],
            },
          ],
          'assetProgress': <dynamic>[],
        }, '/api/tickets/$ticketId/controls'),
      );

      await tester.pumpWidget(_buildView(db: db, dio: dio));
      await tester.pumpAndSettle();

      expect(find.text('Controlli'), findsOneWidget);
      expect(find.text('Pressione OK'), findsOneWidget);
      expect(find.text('Sì'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('falls back to the raw control id when the checklist is not cached', (
      tester,
    ) async {
      const ticketId = 'ticket-2';
      await _seedSubmittedDraft(db, ticketId: ticketId);
      await _seedControllo(db, 'report-1', controlId: 'tc-9', stringValue: 'Tutto ok');

      final dio = _MockDio();
      when(
        () => dio.get<Map<String, dynamic>>('/api/tickets/$ticketId/controls'),
      ).thenThrow(DioException(requestOptions: RequestOptions(path: '/')));

      await tester.pumpWidget(_buildView(db: db, dio: dio));
      await tester.pumpAndSettle();

      expect(find.text('Controlli'), findsOneWidget);
      expect(find.text('Controllo tc-9'), findsOneWidget);
      expect(find.text('Tutto ok'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('no Controlli section when no answers were recorded', (tester) async {
      await _seedSubmittedDraft(db);
      await tester.pumpWidget(_buildView(db: db));
      await tester.pumpAndSettle();

      expect(find.text('Controlli'), findsNothing);

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
