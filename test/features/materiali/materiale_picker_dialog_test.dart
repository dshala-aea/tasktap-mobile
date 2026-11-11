// test/features/materiali/materiale_picker_dialog_test.dart
import 'dart:async';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tasktap_mobile/data/api/dio_client.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/sync/connectivity_provider.dart';
import 'package:tasktap_mobile/data/sync/sync_freshness_provider.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart';
import 'package:tasktap_mobile/features/materiali/materiale_picker_dialog.dart';

class MockDio extends Mock implements Dio {}

Widget _build({
  required AppDatabase db,
  required Dio dio,
  required bool online,
  required ValueChanged<MaterialePickerResult?> onResult,
}) {
  return ProviderScope(
    overrides: [
      appDatabaseProvider.overrideWithValue(db),
      dioProvider.overrideWithValue(dio),
      isOnlineProvider.overrideWithValue(online),
      hasSyncedAtLeastOnceProvider.overrideWith((ref) => Stream.value(true)),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () async {
                final result = await showMaterialePickerDialog(
                  context,
                  showSource: true,
                  showFabbisognoSuggestions: false,
                );
                onResult(result);
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
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
  'materialeNome': 'Vite',
  'quantita': qty,
  'sottoScorta': false,
  'unitOfMeasure': 'pz',
};


Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() {
    registerFallbackValue(RequestOptions(path: '/'));
  });

  late AppDatabase db;
  late MockDio dio;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    dio = MockDio();
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
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> openAndPick(WidgetTester tester) async {
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(TextFormField).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Vite'));
    await tester.pumpAndSettle();
  }

  testWidgets('a single giacenza is selected automatically', (tester) async {
    when(
      () => dio.get<Map<String, dynamic>>(
        '/api/app/magazzino/giacenze',
        queryParameters: any(named: 'queryParameters'),
      ),
    ).thenAnswer(
      (_) async => Response<Map<String, dynamic>>(
        requestOptions: RequestOptions(path: '/api/app/magazzino/giacenze'),
        statusCode: 200,
        data: _giacenzeResponse([_giacenza('m1', 'Furgone Mario', 3)]),
      ),
    );

    MaterialePickerResult? result;
    await tester.pumpWidget(_build(db: db, dio: dio, online: true, onResult: (r) => result = r));
    await openAndPick(tester);

    expect(find.textContaining('Da: Furgone Mario'), findsOneWidget);

    await tester.tap(find.text('Aggiungi'));
    await tester.pumpAndSettle();

    expect(result?.magazzinoId, 'm1');
    expect(result?.quantity, 1);

    await _unmount(tester);
  });

  testWidgets('multiple giacenze default to the largest and can be changed', (tester) async {
    when(
      () => dio.get<Map<String, dynamic>>(
        '/api/app/magazzino/giacenze',
        queryParameters: any(named: 'queryParameters'),
      ),
    ).thenAnswer(
      (_) async => Response<Map<String, dynamic>>(
        requestOptions: RequestOptions(path: '/api/app/magazzino/giacenze'),
        statusCode: 200,
        data: _giacenzeResponse([
          _giacenza('m1', 'Magazzino A', 3),
          _giacenza('m2', 'Magazzino B', 10),
        ]),
      ),
    );

    MaterialePickerResult? result;
    await tester.pumpWidget(_build(db: db, dio: dio, online: true, onResult: (r) => result = r));
    await openAndPick(tester);

    expect(find.textContaining('Magazzino B · 10 pz'), findsOneWidget);

    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Magazzino A').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Aggiungi'));
    await tester.pumpAndSettle();

    expect(result?.magazzinoId, 'm1');

    await _unmount(tester);
  });

  testWidgets('no giacenza adds with a null source and a notice', (tester) async {
    when(
      () => dio.get<Map<String, dynamic>>(
        '/api/app/magazzino/giacenze',
        queryParameters: any(named: 'queryParameters'),
      ),
    ).thenAnswer(
      (_) async => Response<Map<String, dynamic>>(
        requestOptions: RequestOptions(path: '/api/app/magazzino/giacenze'),
        statusCode: 200,
        data: _giacenzeResponse([]),
      ),
    );

    MaterialePickerResult? result;
    await tester.pumpWidget(_build(db: db, dio: dio, online: true, onResult: (r) => result = r));
    await openAndPick(tester);

    expect(find.text('Nessuna giacenza: lo scarico non sarà registrato.'), findsOneWidget);

    await tester.tap(find.text('Aggiungi'));
    await tester.pumpAndSettle();

    expect(result?.magazzinoId, isNull);

    await _unmount(tester);
  });

  testWidgets('offline offers the magazzini mirror with a stock warning', (tester) async {
    await db
        .into(db.magazzini)
        .insert(
          MagazziniCompanion.insert(
            id: 'm1',
            tenantId: 't1',
            createdAt: DateTime.utc(2026, 1, 1),
            nome: 'Furgone Mario',
            tipo: 'Furgone',
          ),
        );

    MaterialePickerResult? result;
    await tester.pumpWidget(_build(db: db, dio: dio, online: false, onResult: (r) => result = r));
    await openAndPick(tester);

    expect(find.text('Disponibilità non verificabile offline'), findsOneWidget);

    await tester.tap(find.text('Aggiungi'));
    await tester.pumpAndSettle();

    // No furgone is invented when the source is unknown.
    expect(result?.magazzinoId, isNull);

    await _unmount(tester);
  });

  testWidgets('quantity accepts a decimal typed on the numeric keyboard', (tester) async {
    when(
      () => dio.get<Map<String, dynamic>>(
        '/api/app/magazzino/giacenze',
        queryParameters: any(named: 'queryParameters'),
      ),
    ).thenAnswer(
      (_) async => Response<Map<String, dynamic>>(
        requestOptions: RequestOptions(path: '/api/app/magazzino/giacenze'),
        statusCode: 200,
        data: _giacenzeResponse([_giacenza('m1', 'Furgone Mario', 3)]),
      ),
    );

    MaterialePickerResult? result;
    await tester.pumpWidget(_build(db: db, dio: dio, online: true, onResult: (r) => result = r));
    await openAndPick(tester);

    await tester.enterText(find.byKey(const Key('materiale-qty-field')), '2,5');
    await tester.pump();

    await tester.tap(find.text('Aggiungi'));
    await tester.pumpAndSettle();

    expect(result?.quantity, 2.5);

    await _unmount(tester);
  });

  testWidgets('a late giacenza response cannot attach a source to free text', (tester) async {
    final completer = Completer<Response<Map<String, dynamic>>>();
    when(
      () => dio.get<Map<String, dynamic>>(
        '/api/app/magazzino/giacenze',
        queryParameters: any(named: 'queryParameters'),
      ),
    ).thenAnswer((_) => completer.future);

    MaterialePickerResult? result;
    await tester.pumpWidget(_build(db: db, dio: dio, online: true, onResult: (r) => result = r));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(TextFormField).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Vite'));
    await tester.pump();

    // Switch to free text while the giacenze request is still in flight.
    await tester.enterText(find.byType(TextFormField).first, 'Guarnizione custom');
    await tester.pump();

    completer.complete(
      Response<Map<String, dynamic>>(
        requestOptions: RequestOptions(path: '/api/app/magazzino/giacenze'),
        statusCode: 200,
        data: _giacenzeResponse([_giacenza('m1', 'Furgone Mario', 3)]),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Aggiungi'));
    await tester.pumpAndSettle();

    expect(result?.freeTextName, 'Guarnizione custom');
    expect(result?.magazzinoId, isNull);

    await _unmount(tester);
  });

  testWidgets('queries by name, asks for a full page, and filters another materialeId', (
    tester,
  ) async {
    Map<String, dynamic>? query;
    when(
      () => dio.get<Map<String, dynamic>>(
        '/api/app/magazzino/giacenze',
        queryParameters: any(named: 'queryParameters'),
      ),
    ).thenAnswer((invocation) async {
      query = invocation.namedArguments[#queryParameters] as Map<String, dynamic>;
      return Response<Map<String, dynamic>>(
        requestOptions: RequestOptions(path: '/api/app/magazzino/giacenze'),
        statusCode: 200,
        data: _giacenzeResponse([
          _giacenza('m1', 'Furgone Mario', 3),
          {..._giacenza('m2', 'Sede Torino', 9), 'materialeId': 'other'},
        ]),
      );
    });

    MaterialePickerResult? result;
    await tester.pumpWidget(_build(db: db, dio: dio, online: true, onResult: (r) => result = r));
    await openAndPick(tester);

    expect(query?['q'], 'Vite');
    expect(query?['pageSize'], 100);
    expect(find.textContaining('Furgone Mario'), findsOneWidget);
    expect(find.textContaining('Sede Torino'), findsNothing);

    await tester.tap(find.text('Aggiungi'));
    await tester.pumpAndSettle();

    expect(result?.magazzinoId, 'm1');

    await _unmount(tester);
  });

  testWidgets('a leading decimal point parses instead of blocking Add', (tester) async {
    when(
      () => dio.get<Map<String, dynamic>>(
        '/api/app/magazzino/giacenze',
        queryParameters: any(named: 'queryParameters'),
      ),
    ).thenAnswer(
      (_) async => Response<Map<String, dynamic>>(
        requestOptions: RequestOptions(path: '/api/app/magazzino/giacenze'),
        statusCode: 200,
        data: _giacenzeResponse([_giacenza('m1', 'Furgone Mario', 3)]),
      ),
    );

    MaterialePickerResult? result;
    await tester.pumpWidget(_build(db: db, dio: dio, online: true, onResult: (r) => result = r));
    await openAndPick(tester);

    await tester.enterText(find.byKey(const Key('materiale-qty-field')), '.5');
    await tester.pump();
    await tester.tap(find.text('Aggiungi'));
    await tester.pumpAndSettle();

    expect(result?.quantity, 0.5);

    await _unmount(tester);
  });

  testWidgets('an empty quantity explains what is wrong and blocks Add', (tester) async {
    when(
      () => dio.get<Map<String, dynamic>>(
        '/api/app/magazzino/giacenze',
        queryParameters: any(named: 'queryParameters'),
      ),
    ).thenAnswer(
      (_) async => Response<Map<String, dynamic>>(
        requestOptions: RequestOptions(path: '/api/app/magazzino/giacenze'),
        statusCode: 200,
        data: _giacenzeResponse([_giacenza('m1', 'Furgone Mario', 3)]),
      ),
    );

    MaterialePickerResult? result;
    await tester.pumpWidget(_build(db: db, dio: dio, online: true, onResult: (r) => result = r));
    await openAndPick(tester);

    await tester.enterText(find.byKey(const Key('materiale-qty-field')), '');
    await tester.pump();

    expect(find.text('Inserisci una quantità valida.'), findsOneWidget);

    await tester.tap(find.text('Aggiungi'));
    await tester.pumpAndSettle();

    expect(result, isNull);

    await _unmount(tester);
  });

  testWidgets('a third decimal is rejected instead of silently rounded', (tester) async {
    when(
      () => dio.get<Map<String, dynamic>>(
        '/api/app/magazzino/giacenze',
        queryParameters: any(named: 'queryParameters'),
      ),
    ).thenAnswer(
      (_) async => Response<Map<String, dynamic>>(
        requestOptions: RequestOptions(path: '/api/app/magazzino/giacenze'),
        statusCode: 200,
        data: _giacenzeResponse([_giacenza('m1', 'Furgone Mario', 3)]),
      ),
    );

    MaterialePickerResult? result;
    await tester.pumpWidget(_build(db: db, dio: dio, online: true, onResult: (r) => result = r));
    await openAndPick(tester);

    await tester.enterText(find.byKey(const Key('materiale-qty-field')), '1,234');
    await tester.pump();

    final field = tester.widget<TextField>(find.byKey(const Key('materiale-qty-field')));
    expect(field.controller!.text, '1');

    await tester.tap(find.text('Aggiungi'));
    await tester.pumpAndSettle();

    expect(result?.quantity, 1);

    await _unmount(tester);
  });

  testWidgets('free text says no scarico will be recorded', (tester) async {
    await tester.pumpWidget(_build(db: db, dio: dio, online: true, onResult: (_) {}));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(TextFormField).first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, 'Guarnizione custom');
    await tester.pump();

    expect(find.text('Testo libero: lo scarico non sarà registrato.'), findsOneWidget);

    await _unmount(tester);
  });

  testWidgets('a permission error is not reported as offline', (tester) async {
    when(
      () => dio.get<Map<String, dynamic>>(
        '/api/app/magazzino/giacenze',
        queryParameters: any(named: 'queryParameters'),
      ),
    ).thenThrow(
      DioException(
        requestOptions: RequestOptions(path: '/api/app/magazzino/giacenze'),
        response: Response<Map<String, dynamic>>(
          statusCode: 403,
          data: null,
          requestOptions: RequestOptions(path: '/api/app/magazzino/giacenze'),
        ),
      ),
    );

    await tester.pumpWidget(_build(db: db, dio: dio, online: true, onResult: (_) {}));
    await openAndPick(tester);

    expect(find.text('Disponibilità non verificabile offline'), findsNothing);

    await _unmount(tester);
  });
}
