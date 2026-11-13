// test/features/materiali/magazzino_movimento_dialog_test.dart
import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tasktap_mobile/data/api/dio_client.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/magazzino/magazzino_api_client.dart';
import 'package:tasktap_mobile/data/sync/connectivity_provider.dart';
import 'package:tasktap_mobile/data/sync/sync_freshness_provider.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart';
import 'package:tasktap_mobile/features/magazzino/magazzino_providers.dart';
import 'package:tasktap_mobile/features/materiali/magazzino_movimento_dialog.dart';
import 'package:tasktap_mobile/features/materiali/materiale_qty_field.dart';

class MockDio extends Mock implements Dio {}

final _magazzini = [
  const MagazzinoDto(id: 'm1', nome: 'Furgone Mario', tipo: 'Furgone', isActive: true),
  const MagazzinoDto(id: 'm2', nome: 'Sede Torino', tipo: 'Sede', isActive: true),
];

Widget _build({
  required AppDatabase db,
  required Dio dio,
  required bool online,
  BarcodeScanner? scanner,
}) {
  return ProviderScope(retry: (_, _) => null, 
    overrides: [
      appDatabaseProvider.overrideWithValue(db),
      dioProvider.overrideWithValue(dio),
      isOnlineProvider.overrideWithValue(online),
      hasSyncedAtLeastOnceProvider.overrideWith((ref) => Stream.value(true)),
      magazziniProvider.overrideWith((ref) async => _magazzini),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () => showMagazzinoMovimentoDialog(context, scanner: scanner),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    registerFallbackValue(RequestOptions(path: '/'));
  });

  late AppDatabase db;
  late MockDio dio;
  late List<({String path, Object? data})> captured;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    dio = MockDio();
    captured = [];
    await db
        .into(db.materiali)
        .insert(
          MaterialiCompanion.insert(
            id: 'mat-1',
            tenantId: 't1',
            createdAt: DateTime.utc(2026, 1, 1),
            code: 'ART-1',
            name: 'Vite',
            unitOfMeasure: const Value('pz'),
          ),
        );
    when(() => dio.post<dynamic>(any(), data: any(named: 'data'))).thenAnswer((invocation) async {
      final path = invocation.positionalArguments[0] as String;
      final data = invocation.namedArguments[#data];
      captured.add((path: path, data: data));
      return Response<dynamic>(
        data: null,
        statusCode: 200,
        requestOptions: RequestOptions(path: path),
      );
    });
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> open(WidgetTester tester, {bool online = true, BarcodeScanner? scanner}) async {
    await tester.pumpWidget(_build(db: db, dio: dio, online: online, scanner: scanner));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Future<void> pickArticle(WidgetTester tester) async {
    await tester.tap(find.byType(TextFormField).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Vite').last);
    await tester.pumpAndSettle();
  }

  Future<void> pickWarehouse(WidgetTester tester, {required String nome, int index = 0}) async {
    final dropdowns = find.byWidgetPredicate((w) => w is DropdownButtonFormField);
    await tester.tap(dropdowns.at(index));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining(nome).last);
    await tester.pumpAndSettle();
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  }

  testWidgets('carico POSTs the chosen destination, material and decimal qty', (tester) async {
    await open(tester);
    await pickArticle(tester);
    await pickWarehouse(tester, nome: 'Furgone Mario');
    await tester.enterText(find.byKey(const Key('movimento-qty-field')), '2,5');
    await tester.pump();

    await tester.tap(find.text('Registra'));
    await tester.pumpAndSettle();

    expect(captured.single.path, '/api/magazzino/m1/carico');
    expect(captured.single.data, {'materialeId': 'mat-1', 'quantita': 2.5});

    await unmount(tester);
  });

  testWidgets('scarico POSTs to the source magazzino', (tester) async {
    await open(tester);
    await tester.tap(find.text('Scarico'));
    await tester.pumpAndSettle();
    await pickArticle(tester);
    await pickWarehouse(tester, nome: 'Furgone Mario');

    await tester.tap(find.text('Registra'));
    await tester.pumpAndSettle();

    expect(captured.single.path, '/api/magazzino/m1/scarico');
    expect(captured.single.data, {'materialeId': 'mat-1', 'quantita': 1});

    await unmount(tester);
  });

  testWidgets('trasferimento POSTs source, destination, material and qty', (tester) async {
    await open(tester);
    await tester.tap(find.text('Trasferisci'));
    await tester.pumpAndSettle();
    await pickArticle(tester);
    await pickWarehouse(tester, nome: 'Furgone Mario', index: 0);
    await pickWarehouse(tester, nome: 'Sede Torino', index: 1);

    await tester.enterText(find.byKey(const Key('movimento-qty-field')), '4');
    await tester.pump();
    await tester.tap(find.text('Registra'));
    await tester.pumpAndSettle();

    expect(captured.single.path, '/api/magazzino/m1/trasferimento');
    expect(captured.single.data, {
      'materialeId': 'mat-1',
      'quantita': 4.0,
      'magazzinoDestinazioneId': 'm2',
    });

    await unmount(tester);
  });

  testWidgets('offline says the movement needs a connection and posts nothing', (tester) async {
    await open(tester, online: false);

    expect(
      find.text('Serve una connessione per registrare un movimento.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Registra'));
    await tester.pumpAndSettle();

    expect(captured, isEmpty);

    await unmount(tester);
  });

  testWidgets('switching back to Carico does not display a stale warehouse', (tester) async {
    await open(tester);
    await pickArticle(tester);
    await tester.tap(find.text('Trasferisci'));
    await tester.pumpAndSettle();
    await pickWarehouse(tester, nome: 'Furgone Mario', index: 0);
    await pickWarehouse(tester, nome: 'Sede Torino', index: 1);

    await tester.tap(find.text('Carico'));
    await tester.pumpAndSettle();

    // The visible destination must match the parent value, not the old source.
    expect(find.textContaining('Sede Torino'), findsOneWidget);

    await tester.tap(find.text('Registra'));
    await tester.pumpAndSettle();

    expect(captured.single.path, '/api/magazzino/m2/carico');

    await unmount(tester);
  });

  testWidgets('using the current destination as the transfer source clears it safely', (
    tester,
  ) async {
    await open(tester);
    await pickArticle(tester);
    await tester.tap(find.text('Trasferisci'));
    await tester.pumpAndSettle();
    await pickWarehouse(tester, nome: 'Furgone Mario', index: 0);
    await pickWarehouse(tester, nome: 'Sede Torino', index: 1);

    // Pick the destination as the new source; the destination must clear, not assert.
    await pickWarehouse(tester, nome: 'Sede Torino', index: 0);
    await pickWarehouse(tester, nome: 'Furgone Mario', index: 1);

    await tester.tap(find.text('Registra'));
    await tester.pumpAndSettle();

    expect(captured.single.path, '/api/magazzino/m2/trasferimento');
    expect(captured.single.data, {
      'materialeId': 'mat-1',
      'quantita': 1.0,
      'magazzinoDestinazioneId': 'm1',
    });

    await unmount(tester);
  });

  testWidgets('a scan shows the resolved article in the field', (tester) async {
    await db
        .into(db.materialeBarcodes)
        .insert(
          MaterialeBarcodesCompanion.insert(
            id: 'bc-1',
            tenantId: 't1',
            createdAt: DateTime.utc(2026, 1, 1),
            materialeId: 'mat-1',
            barcode: '8001234567890',
          ),
        );

    await open(tester, scanner: (_) async => '8001234567890');
    await tester.tap(find.byTooltip('Scansiona codice'));
    await tester.pumpAndSettle();

    expect(find.text('Vite'), findsOneWidget);

    await pickWarehouse(tester, nome: 'Furgone Mario');
    await tester.tap(find.text('Registra'));
    await tester.pumpAndSettle();

    expect(captured.single.path, '/api/magazzino/m1/carico');
    expect(captured.single.data, {'materialeId': 'mat-1', 'quantita': 1});

    await unmount(tester);
  });

  testWidgets('insufficient stock shows the server message', (tester) async {
    when(() => dio.post<dynamic>(any(), data: any(named: 'data'))).thenThrow(
      DioException(
        requestOptions: RequestOptions(path: '/api/magazzino/m1/carico'),
        response: Response<dynamic>(
          statusCode: 400,
          data: 'Scorte insufficienti',
          requestOptions: RequestOptions(path: '/api/magazzino/m1/carico'),
        ),
      ),
    );

    await open(tester);
    await pickArticle(tester);
    await pickWarehouse(tester, nome: 'Furgone Mario');
    await tester.tap(find.text('Registra'));
    await tester.pumpAndSettle();

    expect(find.text('Scorte insufficienti'), findsOneWidget);

    await unmount(tester);
  });
}
