// dart format width=100
// test/features/ticket/ticket_materiali_editor_test.dart
//
// Widget tests for TicketMaterialiEditor — the Fabbisogno tab's edit mode, closing the gap where
// mobile could only VIEW a ticket's planned materials, never add/edit/remove a row (web's
// TicketMaterialiEditor.tsx already allowed this via the ticket detail page's Materials tab).

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tasktap_mobile/data/api/dio_client.dart';
import 'package:tasktap_mobile/data/local/app_database.dart' hide Entitlement;
import 'package:tasktap_mobile/data/sync/connectivity_provider.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart';
import 'package:tasktap_mobile/features/ticket/ticket_detail_api_client.dart';
import 'package:tasktap_mobile/features/ticket/ticket_materiali_editor.dart';

class MockDio extends Mock implements Dio {}

Response<T> _okResponse<T>(T data, String path) =>
    Response<T>(data: data, statusCode: 200, requestOptions: RequestOptions(path: path));

Widget _wrap(Widget child, {required Dio dio, AppDatabase? db, bool? online}) {
  return ProviderScope(
    overrides: [
      dioProvider.overrideWithValue(dio),
      if (db != null) appDatabaseProvider.overrideWithValue(db),
      if (online != null) isOnlineProvider.overrideWithValue(online),
    ],
    child: MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child))),
  );
}

Map<String, dynamic> _giacenzeResponse(List<Map<String, dynamic>> rows) => {
  'elementi': rows,
  'pagina': 1,
  'dimensionePagina': 100,
  'totaleElementi': rows.length,
  'totalePagine': 1,
};

Map<String, dynamic> _giacenza(String magazzinoId, String nome, double qty) => {
  'id': 'g-$magazzinoId',
  'magazzinoId': magazzinoId,
  'magazzinoNome': nome,
  'materialeId': 'mat-1',
  'materialeNome': 'Valvola idraulica',
  'quantita': qty,
  'sottoScorta': false,
  'unitOfMeasure': 'pz',
};

void _stubGiacenze(MockDio dio, List<Map<String, dynamic>> rows) {
  when(
    () => dio.get<Map<String, dynamic>>(
      '/api/app/magazzino/giacenze',
      queryParameters: any(named: 'queryParameters'),
    ),
  ).thenAnswer(
    (_) async => Response<Map<String, dynamic>>(
      requestOptions: RequestOptions(path: '/api/app/magazzino/giacenze'),
      statusCode: 200,
      data: _giacenzeResponse(rows),
    ),
  );
}

void main() {
  late MockDio mockDio;
  late AppDatabase basicDb;

  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    registerFallbackValue(RequestOptions(path: '/'));
  });

  setUp(() {
    mockDio = MockDio();
    basicDb = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await basicDb.close();
  });

  testWidgets('starts with one row per initial dto, pre-filled', (tester) async {
    await tester.pumpWidget(
      _wrap(
        TicketMaterialiEditor(
          initialRows: const [
            TicketMaterialeDto(
              id: 'row-1',
              materialeId: 'mat-1',
              codice: 'V-001',
              nome: 'Valvola',
              quantita: 2,
              unitaMisura: 'pz',
              disponibile: true,
            ),
          ],
          onSave: (_) async {},
          onCancel: () {},
        ),
        dio: mockDio,
        db: basicDb,
      ),
    );

    expect(find.text('Valvola'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('pz'), findsOneWidget);
  });

  testWidgets('"Aggiungi materiale" opens the shared picker and adds a free-text row', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        TicketMaterialiEditor(initialRows: const [], onSave: (_) async {}, onCancel: () {}),
        dio: mockDio,
        db: basicDb,
      ),
    );

    expect(find.byType(TextFormField), findsNothing);

    await tester.tap(find.text('Aggiungi materiale'));
    await tester.pumpAndSettle();

    // The shared modal: lookup + numeric quantity, not an inline empty row.
    expect(find.text('Qtà'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).first, 'Guarnizione custom');
    await tester.pump();
    await tester.enterText(find.byKey(const Key('materiale-qty-field')), '2,5');
    await tester.pump();

    await tester.tap(find.text('Aggiungi').last);
    await tester.pumpAndSettle();

    // Back in the editor with one editable row.
    expect(find.text('Guarnizione custom'), findsOneWidget);
    expect(find.text('2.5'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('"Aggiungi materiale" adds a catalogue article from the shared picker', (
    tester,
  ) async {
    await basicDb
        .into(basicDb.materiali)
        .insert(
          MaterialiCompanion.insert(
            id: 'mat-1',
            tenantId: 'tenant-1',
            createdAt: DateTime.utc(2026, 1, 1),
            code: 'ART001',
            name: 'Valvola idraulica',
            unitOfMeasure: const Value('pz'),
          ),
        );
    _stubGiacenze(mockDio, const []);

    await tester.pumpWidget(
      _wrap(
        TicketMaterialiEditor(initialRows: const [], onSave: (_) async {}, onCancel: () {}),
        dio: mockDio,
        db: basicDb,
        online: true,
      ),
    );

    await tester.tap(find.text('Aggiungi materiale'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(TextFormField).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Valvola idraulica').last);
    await tester.pumpAndSettle();

    expect(find.text('Nessuna giacenza: lo scarico non sarà registrato.'), findsOneWidget);

    await tester.tap(find.text('Aggiungi').last);
    await tester.pumpAndSettle();

    expect(find.text('Valvola idraulica'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('a new catalogue row auto-selects a single giacenza and saves its source', (
    tester,
  ) async {
    List<TicketMaterialeWriteRow>? savedRows;
    await basicDb
        .into(basicDb.materiali)
        .insert(
          MaterialiCompanion.insert(
            id: 'mat-1',
            tenantId: 'tenant-1',
            createdAt: DateTime.utc(2026, 1, 1),
            code: 'ART001',
            name: 'Valvola idraulica',
            unitOfMeasure: const Value('pz'),
          ),
        );
    _stubGiacenze(mockDio, [_giacenza('mag-1', 'Furgone Mario', 3)]);

    await tester.pumpWidget(
      _wrap(
        TicketMaterialiEditor(
          initialRows: const [],
          onSave: (rows) async => savedRows = rows,
          onCancel: () {},
        ),
        dio: mockDio,
        db: basicDb,
        online: true,
      ),
    );

    await tester.tap(find.text('Aggiungi materiale'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(TextFormField).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Valvola idraulica').last);
    await tester.pumpAndSettle();

    expect(find.textContaining('Da: Furgone Mario'), findsOneWidget);

    await tester.tap(find.text('Aggiungi').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Salva'));
    await tester.pumpAndSettle();

    expect(savedRows!.single.magazzinoId, 'mag-1');
  });

  testWidgets('multiple giacenze offer a source picker and save the chosen warehouse', (
    tester,
  ) async {
    List<TicketMaterialeWriteRow>? savedRows;
    await basicDb
        .into(basicDb.materiali)
        .insert(
          MaterialiCompanion.insert(
            id: 'mat-1',
            tenantId: 'tenant-1',
            createdAt: DateTime.utc(2026, 1, 1),
            code: 'ART001',
            name: 'Valvola idraulica',
            unitOfMeasure: const Value('pz'),
          ),
        );
    _stubGiacenze(mockDio, [
      _giacenza('mag-1', 'Magazzino A', 3),
      _giacenza('mag-2', 'Magazzino B', 10),
    ]);

    await tester.pumpWidget(
      _wrap(
        TicketMaterialiEditor(
          initialRows: const [],
          onSave: (rows) async => savedRows = rows,
          onCancel: () {},
        ),
        dio: mockDio,
        db: basicDb,
        online: true,
      ),
    );

    await tester.tap(find.text('Aggiungi materiale'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(TextFormField).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Valvola idraulica').last);
    await tester.pumpAndSettle();

    // Multiple sources default to the largest, exactly like the report picker.
    expect(find.textContaining('Magazzino B · 10 pz'), findsOneWidget);
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Magazzino A').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Aggiungi').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Salva'));
    await tester.pumpAndSettle();

    expect(savedRows!.single.magazzinoId, 'mag-1');
  });

  testWidgets('no giacenza saves the row with no source', (tester) async {
    List<TicketMaterialeWriteRow>? savedRows;
    await basicDb
        .into(basicDb.materiali)
        .insert(
          MaterialiCompanion.insert(
            id: 'mat-1',
            tenantId: 'tenant-1',
            createdAt: DateTime.utc(2026, 1, 1),
            code: 'ART001',
            name: 'Valvola idraulica',
            unitOfMeasure: const Value('pz'),
          ),
        );
    _stubGiacenze(mockDio, const []);

    await tester.pumpWidget(
      _wrap(
        TicketMaterialiEditor(
          initialRows: const [],
          onSave: (rows) async => savedRows = rows,
          onCancel: () {},
        ),
        dio: mockDio,
        db: basicDb,
        online: true,
      ),
    );

    await tester.tap(find.text('Aggiungi materiale'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(TextFormField).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Valvola idraulica').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Aggiungi').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Salva'));
    await tester.pumpAndSettle();

    expect(savedRows!.single.magazzinoId, isNull);
  });

  testWidgets('an existing catalogue row with no source auto-selects a single giacenza', (
    tester,
  ) async {
    List<TicketMaterialeWriteRow>? savedRows;
    _stubGiacenze(mockDio, [_giacenza('mag-1', 'Furgone Mario', 3)]);

    await tester.pumpWidget(
      _wrap(
        TicketMaterialiEditor(
          initialRows: const [
            TicketMaterialeDto(
              id: 'row-1',
              materialeId: 'mat-1',
              nome: 'Valvola',
              quantita: 2,
              disponibile: true,
            ),
          ],
          onSave: (rows) async => savedRows = rows,
          onCancel: () {},
        ),
        dio: mockDio,
        db: basicDb,
        online: true,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Da: Furgone Mario'), findsOneWidget);

    await tester.tap(find.text('Salva'));
    await tester.pumpAndSettle();

    expect(savedRows!.single.magazzinoId, 'mag-1');
  });

  testWidgets('editing preserves an existing source warehouse and shows its name', (
    tester,
  ) async {
    List<TicketMaterialeWriteRow>? savedRows;

    await tester.pumpWidget(
      _wrap(
        TicketMaterialiEditor(
          initialRows: const [
            TicketMaterialeDto(
              id: 'row-1',
              materialeId: 'mat-1',
              nome: 'Valvola',
              quantita: 2,
              magazzinoId: 'mag-1',
              magazzinoNome: 'Furgone Mario',
              disponibile: true,
            ),
          ],
          onSave: (rows) async => savedRows = rows,
          onCancel: () {},
        ),
        dio: mockDio,
        db: basicDb,
      ),
    );

    expect(find.textContaining('Furgone Mario'), findsOneWidget);

    await tester.tap(find.text('Salva'));
    await tester.pumpAndSettle();

    expect(savedRows!.single.magazzinoId, 'mag-1');
  });

  testWidgets('remove button deletes the row', (tester) async {
    await tester.pumpWidget(
      _wrap(
        TicketMaterialiEditor(
          initialRows: const [
            TicketMaterialeDto(
              id: 'row-1',
              nome: 'Guarnizione generica',
              quantita: 1,
              disponibile: true,
            ),
          ],
          onSave: (_) async {},
          onCancel: () {},
        ),
        dio: mockDio,
        db: basicDb,
      ),
    );

    expect(find.text('Guarnizione generica'), findsOneWidget);

    await tester.tap(find.byTooltip('Rimuovi materiale'));
    await tester.pumpAndSettle();

    expect(find.text('Guarnizione generica'), findsNothing);
  });

  testWidgets('Salva calls onSave with the edited rows, mapped to the write shape', (
    tester,
  ) async {
    List<TicketMaterialeWriteRow>? savedRows;

    await tester.pumpWidget(
      _wrap(
        TicketMaterialiEditor(
          initialRows: const [
            TicketMaterialeDto(
              id: 'row-1',
              materialeId: 'mat-1',
              nome: 'Valvola',
              quantita: 2,
              unitaMisura: 'pz',
              disponibile: true,
            ),
          ],
          onSave: (rows) async => savedRows = rows,
          onCancel: () {},
        ),
        dio: mockDio,
        db: basicDb,
      ),
    );

    await tester.tap(find.text('Salva'));
    await tester.pumpAndSettle();

    expect(savedRows, isNotNull);
    expect(savedRows!.single.materialeId, 'mat-1');
    expect(savedRows!.single.freeTextName, isNull);
    expect(savedRows!.single.quantity, 2);
    expect(savedRows!.single.unitOfMeasure, 'pz');
  });

  testWidgets('Salva is disabled when a row has neither an article nor free text', (
    tester,
  ) async {
    var saveCalled = false;

    await tester.pumpWidget(
      _wrap(
        TicketMaterialiEditor(
          initialRows: const [
            TicketMaterialeDto(id: 'row-1', nome: '', quantita: 1, disponibile: true),
          ],
          onSave: (_) async {},
          onCancel: () {},
        ),
        dio: mockDio,
        db: basicDb,
      ),
    );

    // Empty row: neither an article nor free text — save must not run.
    final salvaFinder = find.text('Salva');
    await tester.tap(salvaFinder);
    await tester.pumpAndSettle();

    expect(saveCalled, isFalse);
  });

  testWidgets('Annulla calls onCancel', (tester) async {
    var cancelled = false;

    await tester.pumpWidget(
      _wrap(
        TicketMaterialiEditor(
          initialRows: const [],
          onSave: (_) async {},
          onCancel: () => cancelled = true,
        ),
        dio: mockDio,
        db: basicDb,
      ),
    );

    await tester.tap(find.text('Annulla'));
    await tester.pumpAndSettle();

    expect(cancelled, isTrue);
  });

  testWidgets('typing free text into a new row and saving sends freeTextName, not materialeId', (
    tester,
  ) async {
    List<TicketMaterialeWriteRow>? savedRows;
    when(
      () => mockDio.get<dynamic>('/Materiali', queryParameters: any(named: 'queryParameters')),
    ).thenAnswer((_) async => _okResponse<dynamic>({'items': []}, '/Materiali'));

    await tester.pumpWidget(
      _wrap(
        TicketMaterialiEditor(
          initialRows: const [],
          onSave: (rows) async => savedRows = rows,
          onCancel: () {},
        ),
        dio: mockDio,
        db: basicDb,
      ),
    );

    await tester.tap(find.text('Aggiungi materiale'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, 'Guarnizione custom');
    await tester.pump();
    await tester.enterText(find.byKey(const Key('materiale-qty-field')), '3');
    await tester.pump();
    await tester.tap(find.text('Aggiungi').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Salva'));
    await tester.pumpAndSettle();

    expect(savedRows, isNotNull);
    expect(savedRows!.single.materialeId, isNull);
    expect(savedRows!.single.freeTextName, 'Guarnizione custom');
    expect(savedRows!.single.quantity, 3);
    expect(savedRows!.single.magazzinoId, isNull);
  });

  testWidgets('picking an article in an existing row resolves its single giacenza', (
    tester,
  ) async {
    List<TicketMaterialeWriteRow>? savedRows;
    await basicDb
        .into(basicDb.materiali)
        .insert(
          MaterialiCompanion.insert(
            id: 'mat-1',
            tenantId: 'tenant-1',
            createdAt: DateTime.utc(2026, 1, 1),
            code: 'ART001',
            name: 'Valvola idraulica',
            unitOfMeasure: const Value('pz'),
          ),
        );
    _stubGiacenze(mockDio, [_giacenza('mag-1', 'Furgone Mario', 3)]);
    when(
      () => mockDio.get<dynamic>('/Materiali', queryParameters: any(named: 'queryParameters')),
    ).thenAnswer(
      (_) async => _okResponse<dynamic>({
        'items': [
          {
            'id': 'mat-1',
            'name': 'Valvola idraulica',
            'code': 'ART001',
            'unitOfMeasure': 'pz',
          },
        ],
      }, '/Materiali'),
    );

    await tester.pumpWidget(
      _wrap(
        TicketMaterialiEditor(
          initialRows: const [
            TicketMaterialeDto(
              id: 'row-1',
              nome: 'Testo libero',
              quantita: 1,
              disponibile: true,
            ),
          ],
          onSave: (rows) async => savedRows = rows,
          onCancel: () {},
        ),
        dio: mockDio,
        db: basicDb,
        online: true,
      ),
    );

    await tester.enterText(find.byType(TextFormField).at(0), 'idraulica');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Valvola idraulica').last);
    await tester.pumpAndSettle();

    expect(find.textContaining('Da: Furgone Mario'), findsOneWidget);

    await tester.tap(find.text('Salva'));
    await tester.pumpAndSettle();

    expect(savedRows!.single.materialeId, 'mat-1');
    expect(savedRows!.single.magazzinoId, 'mag-1');
  });

  group('barcode scan', () {
    late AppDatabase db;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      await db
          .into(db.materiali)
          .insert(
            MaterialiCompanion.insert(
              id: 'mat-1',
              tenantId: 'tenant-1',
              createdAt: DateTime.utc(2026, 1, 1),
              code: 'ART001',
              name: 'Valvola idraulica',
              unitOfMeasure: const Value('pz'),
            ),
          );
      await db
          .into(db.materialeBarcodes)
          .insert(
            MaterialeBarcodesCompanion.insert(
              id: 'bc-1',
              tenantId: 'tenant-1',
              createdAt: DateTime.utc(2026, 1, 1),
              materialeId: 'mat-1',
              barcode: '8001234567890',
            ),
          );
    });

    tearDown(() => db.close());

    // Offline on purpose: an unknown code must resolve from the local mirror alone, with no
    // live-lookup call (the MockDio has no stub for it).
    Widget wrapScan(
      TicketMaterialiEditor editor,
    ) {
      return ProviderScope(
        overrides: [
          dioProvider.overrideWithValue(mockDio),
          appDatabaseProvider.overrideWithValue(db),
          isOnlineProvider.overrideWithValue(false),
        ],
        child: MaterialApp(home: Scaffold(body: SingleChildScrollView(child: editor))),
      );
    }

    TicketMaterialiEditor editorScanning(
      String? code,
      void Function(List<TicketMaterialeWriteRow>) onSaved,
    ) {
      return TicketMaterialiEditor(
        initialRows: const [],
        scanner: (_) async => code,
        onSave: (rows) async => onSaved(rows),
        onCancel: () {},
      );
    }

    testWidgets('shows the scan button', (tester) async {
      await tester.pumpWidget(wrapScan(editorScanning(null, (_) {})));

      expect(find.text('Scansiona codice'), findsOneWidget);

      // Disposes the toast overlay so its auto-dismiss Timer doesn't outlive the test.
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('a known code adds the article as a row', (tester) async {
      List<TicketMaterialeWriteRow>? saved;
      await tester.pumpWidget(wrapScan(editorScanning('8001234567890', (r) => saved = r)));

      await tester.tap(find.text('Scansiona codice'));
      await tester.pumpAndSettle();

      expect(find.text('Valvola idraulica'), findsOneWidget);

      await tester.tap(find.text('Salva'));
      await tester.pumpAndSettle();

      expect(saved!.single.materialeId, 'mat-1');
      expect(saved!.single.freeTextName, isNull);
      expect(saved!.single.quantity, 1);
      expect(saved!.single.unitOfMeasure, 'pz');

      // Disposes the toast overlay so its auto-dismiss Timer doesn't outlive the test.
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('scanning the same code again increments the quantity, no second row', (
      tester,
    ) async {
      List<TicketMaterialeWriteRow>? saved;
      await tester.pumpWidget(wrapScan(editorScanning('8001234567890', (r) => saved = r)));

      await tester.tap(find.text('Scansiona codice'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Scansiona codice'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Salva'));
      await tester.pumpAndSettle();

      expect(saved!.length, 1);
      expect(saved!.single.quantity, 2);

      // Disposes the toast overlay so its auto-dismiss Timer doesn't outlive the test.
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('an unknown code becomes a free-text row and says so', (tester) async {
      List<TicketMaterialeWriteRow>? saved;
      await tester.pumpWidget(wrapScan(editorScanning('999000', (r) => saved = r)));

      await tester.tap(find.text('Scansiona codice'));
      await tester.pumpAndSettle();

      expect(find.textContaining('non in catalogo'), findsOneWidget);

      await tester.tap(find.text('Salva'));
      await tester.pumpAndSettle();

      expect(saved!.single.materialeId, isNull);
      expect(saved!.single.freeTextName, '999000');

      // Disposes the toast overlay so its auto-dismiss Timer doesn't outlive the test.
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('backing out of the scanner adds nothing', (tester) async {
      await tester.pumpWidget(wrapScan(editorScanning(null, (_) {})));

      await tester.tap(find.text('Scansiona codice'));
      await tester.pumpAndSettle();

      expect(find.byType(TextFormField), findsNothing);

      // Disposes the toast overlay so its auto-dismiss Timer doesn't outlive the test.
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  group('catalogue search', () {
    late AppDatabase db;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      await db
          .into(db.materiali)
          .insert(
            MaterialiCompanion.insert(
              id: 'mat-1',
              tenantId: 'tenant-1',
              createdAt: DateTime.utc(2026, 1, 1),
              code: 'ART001',
              name: 'Valvola idraulica',
              unitOfMeasure: const Value('pz'),
            ),
          );
      await db
          .into(db.materiali)
          .insert(
            MaterialiCompanion.insert(
              id: 'mat-2',
              tenantId: 'tenant-1',
              createdAt: DateTime.utc(2026, 1, 1),
              code: 'GUA002',
              name: 'Guarnizione testata',
            ),
          );
      // Retired by the office: it must not come back as a suggestion just because the row is
      // still in the mirror.
      await db
          .into(db.materiali)
          .insert(
            MaterialiCompanion.insert(
              id: 'mat-3',
              tenantId: 'tenant-1',
              createdAt: DateTime.utc(2026, 1, 1),
              code: 'OLD003',
              name: 'Valvola dismessa',
              isActive: const Value(false),
            ),
          );
    });

    tearDown(() => db.close());

    /// Offline on purpose: the article field used to be a bare `GET /Materiali`, so on site it
    /// threw out of the debounce timer and silently offered nothing. MockDio has no stub here, so
    /// a live call would fail the test as well as the verifyNever below.
    Widget wrapSearch({Future<void> Function(List<TicketMaterialeWriteRow>)? onSave}) =>
        ProviderScope(
          overrides: [
            dioProvider.overrideWithValue(mockDio),
            appDatabaseProvider.overrideWithValue(db),
            isOnlineProvider.overrideWithValue(false),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: TicketMaterialiEditor(
                  initialRows: const [
                    TicketMaterialeDto(id: 'row-1', nome: '', quantita: 1, disponibile: true),
                  ],
                  onSave: onSave ?? (_) async {},
                  onCancel: () {},
                ),
              ),
            ),
          ),
        );

    Future<void> typeArticle(WidgetTester tester, String text) async {
      // Articolo is the first field of the (already present) row — see
      // _MaterialeRowEditorState.build. Adding is now the shared modal; the row editor remains
      // the way an existing line is edited.
      await tester.enterText(find.byType(TextFormField).at(0), text);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
    }

    testWidgets('offline it searches the mirrored catalogue and never calls the API', (
      tester,
    ) async {
      await tester.pumpWidget(wrapSearch());
      await typeArticle(tester, 'valvola');

      expect(find.text('Valvola idraulica'), findsWidgets);
      expect(find.text('Valvola dismessa'), findsNothing);
      verifyNever(
        () => mockDio.get<dynamic>(
          '/Materiali',
          queryParameters: any(named: 'queryParameters'),
        ),
      );
    });

    testWidgets('offline the code matches too — a technician may know the code, not the name', (
      tester,
    ) async {
      await tester.pumpWidget(wrapSearch());
      await typeArticle(tester, 'GUA002');

      expect(find.text('Guarnizione testata'), findsWidgets);
    });

    testWidgets('picking a mirrored article keeps its id and its unit', (tester) async {
      List<TicketMaterialeWriteRow>? saved;
      await tester.pumpWidget(wrapSearch(onSave: (rows) async => saved = rows));
      await typeArticle(tester, 'idraulica');

      await tester.tap(find.text('Valvola idraulica').last);
      await tester.pumpAndSettle();

      // Quantity is required before Salva does anything.
      await tester.enterText(find.byType(TextFormField).at(1), '2');
      await tester.pump();
      await tester.tap(find.text('Salva'));
      await tester.pumpAndSettle();

      expect(saved, isNotNull);
      expect(saved!.single.materialeId, 'mat-1');
      expect(saved!.single.unitOfMeasure, 'pz');
    });
  });
}
