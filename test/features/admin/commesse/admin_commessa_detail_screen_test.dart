// dart format width=100
// test/features/admin/commesse/admin_commessa_detail_screen_test.dart
//
// Commessa detail — a genuinely missing screen closed by re-diffing the shipped app against the
// Vetro mockup's own screens. Read-only: Dettagli card + Cantieri/Ticket collegati, both resolved
// from the local Drift mirror (module #13 of the feature audit already synced commessaId on both
// tables, just never showed the reverse link).

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:tasktap_mobile/data/api/dio_client.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/sync/connectivity_provider.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart';
import 'package:tasktap_mobile/features/admin/commesse/admin_commessa_detail_screen.dart';

class MockDio extends Mock implements Dio {}

Response<T> _ok<T>(T data, String path) =>
    Response<T>(data: data, statusCode: 200, requestOptions: RequestOptions(path: path));

void main() {
  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    registerFallbackValue(RequestOptions(path: '/'));
  });

  late AppDatabase db;
  late MockDio mockDio;

  const commessa = {
    'id': 'comm-1',
    'codice': '#4471',
    'descrizione': 'Ristrutturazione impianto',
    'stato': 'Aperta',
    'dataApertura': '2026-06-03T00:00:00Z',
    'importo': 8400.0,
  };

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    mockDio = MockDio();
    when(
      () => mockDio.get<Map<String, dynamic>>('/api/commesse/comm-1'),
    ).thenAnswer((_) async => _ok(commessa, '/api/commesse/comm-1'));
  });

  tearDown(() async => db.close());

  Widget buildHarness({bool isOnline = true}) {
    return ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        dioProvider.overrideWithValue(mockDio),
        isOnlineProvider.overrideWithValue(isOnline),
      ],
      child: const MaterialApp(home: AdminCommessaDetailScreen(commessaId: 'comm-1')),
    );
  }

  testWidgets('shows codice, descrizione, stato and importo', (tester) async {
    await tester.pumpWidget(buildHarness());
    await tester.pumpAndSettle();

    expect(find.text('Ristrutturazione impianto'), findsOneWidget);
    expect(find.textContaining('#4471'), findsOneWidget);
    expect(find.text('Aperta'), findsOneWidget);
    expect(find.textContaining('8400'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('lists linked cantieri and tickets from the local mirror', (tester) async {
    await db
        .into(db.cantieri)
        .insert(
          CantieriCompanion.insert(
            id: 'cant-1',
            tenantId: 'tenant-1',
            name: 'Cantiere Rossi SRL',
            createdAt: DateTime.now().toUtc(),
            commessaId: const Value('comm-1'),
          ),
        );
    await db
        .into(db.tickets)
        .insert(
          TicketsCompanion.insert(
            id: 'tkt-1',
            tenantId: 'tenant-1',
            title: 'Perdita idraulica',
            numero: const Value('TKT-0142'),
            customerId: 'cust-1',
            locationId: 'loc-1',
            statusId: 1,
            typeId: 1,
            createdAt: DateTime.now().toUtc(),
            commessaId: const Value('comm-1'),
          ),
        );

    await tester.pumpWidget(buildHarness());
    await tester.pumpAndSettle();

    expect(find.text('Cantieri collegati'), findsOneWidget);
    expect(find.text('Cantiere Rossi SRL'), findsOneWidget);
    expect(find.text('Ticket collegati'), findsOneWidget);
    expect(find.textContaining('TKT-0142'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('hides collegati sections when nothing is linked', (tester) async {
    await tester.pumpWidget(buildHarness());
    await tester.pumpAndSettle();

    expect(find.text('Cantieri collegati'), findsNothing);
    expect(find.text('Ticket collegati'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('says plainly it is offline instead of showing a broken screen', (tester) async {
    await tester.pumpWidget(buildHarness(isOnline: false));
    await tester.pumpAndSettle();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Ristrutturazione impianto'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}
