// dart format width=100
// test/data/materiali/materiale_barcode_lookup_test.dart
//
// lookupMaterialeByBarcode: local mirror first (works offline, and is the common case for an
// already-synced device), live GET /api/materiali/lookup only when nothing local matched and the
// device is online.

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:tasktap_mobile/data/api/dio_client.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/materiali/materiale_barcode_lookup.dart';
import 'package:tasktap_mobile/data/sync/connectivity_provider.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart' show appDatabaseProvider;

class MockDio extends Mock implements Dio {}

AppDatabase _makeDb() => AppDatabase(NativeDatabase.memory());

/// Runs lookupMaterialeByBarcode(ref, barcode) through a real WidgetRef, matching how the app's
/// own scan button calls it — mocktail's `when` needs no BuildContext, but the function's own
/// signature does.
Future<MaterialeMatch?> _lookup(
  WidgetTester tester,
  ProviderContainer container,
  String barcode,
) async {
  MaterialeMatch? result;
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Consumer(
          builder: (context, ref, _) {
            return ElevatedButton(
              onPressed: () async {
                result = await lookupMaterialeByBarcode(ref, barcode);
              },
              child: const Text('go'),
            );
          },
        ),
      ),
    ),
  );
  await tester.tap(find.text('go'));
  await tester.pumpAndSettle();
  return result;
}

void main() {
  late AppDatabase db;
  late MockDio mockDio;

  setUp(() {
    db = _makeDb();
    mockDio = MockDio();
  });

  tearDown(() async => db.close());

  ProviderContainer buildContainer({bool isOnline = true}) => ProviderContainer(
    overrides: [
      appDatabaseProvider.overrideWithValue(db),
      dioProvider.overrideWithValue(mockDio),
      isOnlineProvider.overrideWithValue(isOnline),
    ],
  );

  Future<void> seedLocalMateriale({
    String materialeId = 'mat-1',
    String barcode = '8001234567890',
  }) async {
    await db
        .into(db.materiali)
        .insert(
          MaterialiCompanion.insert(
            id: materialeId,
            tenantId: 'tenant-1',
            createdAt: DateTime.utc(2026, 1, 1),
            code: 'ART-001',
            name: 'Tubo rame 15mm',
            unitOfMeasure: const Value('m'),
          ),
        );
    await db
        .into(db.materialeBarcodes)
        .insert(
          MaterialeBarcodesCompanion.insert(
            id: 'bc-1',
            tenantId: 'tenant-1',
            createdAt: DateTime.utc(2026, 1, 1),
            materialeId: materialeId,
            barcode: barcode,
          ),
        );
  }

  group('local mirror hit', () {
    testWidgets('resolves to the material without touching the network', (tester) async {
      await seedLocalMateriale();
      final container = buildContainer();
      addTearDown(container.dispose);

      final match = await _lookup(tester, container, '8001234567890');

      expect(match, isNotNull);
      expect(match!.id, 'mat-1');
      expect(match.code, 'ART-001');
      expect(match.name, 'Tubo rame 15mm');
      expect(match.unitOfMeasure, 'm');
      verifyNever(() => mockDio.get<Map<String, dynamic>>(any(), queryParameters: any(named: 'queryParameters')));
    });

    testWidgets('an orphan barcode (parent Materiale missing) falls through to a live lookup', (
      tester,
    ) async {
      // The barcode row exists locally but its parent never synced (e.g. went inactive after the
      // barcode was cached) — this must not report a false match for a material the device can't
      // actually show, and must still try the network instead of just giving up.
      await db
          .into(db.materialeBarcodes)
          .insert(
            MaterialeBarcodesCompanion.insert(
              id: 'bc-orphan',
              tenantId: 'tenant-1',
              createdAt: DateTime.utc(2026, 1, 1),
              materialeId: 'mat-missing',
              barcode: '8009999999999',
            ),
          );
      when(
        () => mockDio.get<Map<String, dynamic>>(any(), queryParameters: any(named: 'queryParameters')),
      ).thenAnswer(
        (_) async => Response<Map<String, dynamic>>(
          requestOptions: RequestOptions(path: '/api/materiali/lookup'),
          statusCode: 200,
          data: {'id': 'mat-missing', 'code': 'ART-009', 'name': 'Recovered live', 'unitOfMeasure': null},
        ),
      );

      final container = buildContainer();
      addTearDown(container.dispose);
      final match = await _lookup(tester, container, '8009999999999');

      expect(match, isNotNull);
      expect(match!.name, 'Recovered live');
    });
  });

  group('live fallback', () {
    testWidgets('no local match, online, backend has it — returns the live result', (
      tester,
    ) async {
      when(
        () => mockDio.get<Map<String, dynamic>>(any(), queryParameters: any(named: 'queryParameters')),
      ).thenAnswer(
        (_) async => Response<Map<String, dynamic>>(
          requestOptions: RequestOptions(path: '/api/materiali/lookup'),
          statusCode: 200,
          data: {'id': 'mat-live', 'code': 'ART-LIVE', 'name': 'Solo online', 'unitOfMeasure': 'pz'},
        ),
      );

      final container = buildContainer();
      addTearDown(container.dispose);
      final match = await _lookup(tester, container, '8007777777777');

      expect(match, isNotNull);
      expect(match!.id, 'mat-live');
      expect(match.unitOfMeasure, 'pz');
    });

    testWidgets('no local match, online, backend 404s — returns null, not an exception', (
      tester,
    ) async {
      when(
        () => mockDio.get<Map<String, dynamic>>(any(), queryParameters: any(named: 'queryParameters')),
      ).thenThrow(
        DioException(
          requestOptions: RequestOptions(path: '/api/materiali/lookup'),
          response: Response(
            requestOptions: RequestOptions(path: '/api/materiali/lookup'),
            statusCode: 404,
          ),
        ),
      );

      final container = buildContainer();
      addTearDown(container.dispose);
      final match = await _lookup(tester, container, '0000000000000');

      expect(match, isNull);
    });

    testWidgets('no local match, offline — returns null without attempting the network', (
      tester,
    ) async {
      final container = buildContainer(isOnline: false);
      addTearDown(container.dispose);

      final match = await _lookup(tester, container, '0000000000000');

      expect(match, isNull);
      verifyNever(() => mockDio.get<Map<String, dynamic>>(any(), queryParameters: any(named: 'queryParameters')));
    });
  });
}
