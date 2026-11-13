// dart format width=100
// test/features/admin/commesse/admin_commessa_detail_screen_test.dart
//
// Commessa detail — the wave-0 summary shell: hero + Modifica, Relazioni (cantieri), Sintesi,
// Attività (ticket). The commessa is fetched live through `commessaByIdProvider`; cantieri and
// tickets come from the local Drift mirror.

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

Response<T> _ok<T>(T data, String path) => Response<T>(
  data: data,
  statusCode: 200,
  requestOptions: RequestOptions(path: path),
);

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
    'dataChiusura': '2026-07-15T00:00:00Z',
    'importo': 8400.0,
    'customerId': 'cust-1',
    'note': 'Consegna al piano.',
  };

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    mockDio = MockDio();
    when(
      () => mockDio.get<Map<String, dynamic>>('/api/commesse/comm-1'),
    ).thenAnswer((_) async => _ok(commessa, '/api/commesse/comm-1'));
    await db
        .into(db.customers)
        .insert(
          CustomersCompanion.insert(
            id: 'cust-1',
            tenantId: 'tenant-1',
            createdAt: DateTime.utc(2026, 1, 1),
            companyName: 'Rossi Srl',
          ),
        );
  });

  tearDown(() async => db.close());

  Widget buildHarness({bool isOnline = true}) {
    return ProviderScope(retry: (_, _) => null, 
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        dioProvider.overrideWithValue(mockDio),
        isOnlineProvider.overrideWithValue(isOnline),
      ],
      child: const MaterialApp(home: AdminCommessaDetailScreen(commessaId: 'comm-1')),
    );
  }

  testWidgets('hero leads with the codice, then description, facts and stamp', (tester) async {
    await tester.pumpWidget(buildHarness());
    await tester.pumpAndSettle();

    expect(find.text('#4471'), findsOneWidget);
    expect(find.text('Ristrutturazione impianto'), findsOneWidget);
    expect(find.textContaining('Rossi Srl'), findsOneWidget);
    expect(find.textContaining('03/06–15/07'), findsOneWidget);
    expect(find.textContaining('8.400'), findsOneWidget);
    // Uppercased by StatusStamp, Il Documento's stamp device. The collapsed bar holds an
    // off-screen copy too, so scope this to the hero card.
    expect(
      find.descendant(of: find.byKey(const Key('detail-hero-card')), matching: find.text('APERTA')),
      findsOneWidget,
    );

    // The prototype's Sintesi carries only what the hero does not: the notes. Period and amount
    // stay in the hero facts, so no fact is repeated.
    expect(find.text('Sintesi'), findsOneWidget);
    expect(find.text('Consegna al piano.'), findsOneWidget);
    expect(find.text('03/06/2026'), findsNothing);
    expect(find.text('15/07/2026'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('labels the period by business calendar date, not the device day', (tester) async {
    // Both instants are UTC midnight, i.e. the previous day in America/Los_Angeles. The hero must
    // read the business date label (01/01), never a device-local conversion (31/12).
    final boundary = <String, dynamic>{
      ...commessa,
      'dataApertura': '2026-01-01T00:00:00Z',
      'dataChiusura': '2026-01-02T00:00:00Z',
    };
    when(
      () => mockDio.get<Map<String, dynamic>>('/api/commesse/comm-1'),
    ).thenAnswer((_) async => _ok(boundary, '/api/commesse/comm-1'));

    await tester.pumpWidget(buildHarness());
    await tester.pumpAndSettle();

    expect(find.textContaining('01/01–02/01'), findsOneWidget);
    expect(find.textContaining('31/12'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('lists linked cantieri and tickets, in Relazioni then Attività', (tester) async {
    await db
        .into(db.cantieri)
        .insert(
          CantieriCompanion.insert(
            id: 'cant-1',
            tenantId: 'tenant-1',
            name: 'Cantiere Rossi SRL',
            createdAt: DateTime.now().toUtc(),
            commessaId: const Value('comm-1'),
            city: const Value('Milano'),
          ),
        );
    await db
        .into(db.ticketStatuses)
        .insert(
          TicketStatusesCompanion.insert(
            id: const Value(1),
            tenantId: 'tenant-1',
            name: 'In corso',
            isInProgress: const Value(true),
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

    expect(find.text('Relazioni'), findsOneWidget);
    expect(find.text('Cantiere Rossi SRL'), findsOneWidget);
    expect(find.text('Attività'), findsOneWidget);
    expect(find.textContaining('TKT-0142'), findsOneWidget);
    expect(find.text('Avanzamento'), findsOneWidget);

    final relazioniY = tester.getTopLeft(find.text('Relazioni')).dy;
    final sintesiY = tester.getTopLeft(find.text('Sintesi')).dy;
    final attivitaY = tester.getTopLeft(find.text('Attività')).dy;
    expect(relazioniY, lessThan(sintesiY));
    expect(sintesiY, lessThan(attivitaY));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('hides empty sections and never invents Documenti', (tester) async {
    await tester.pumpWidget(buildHarness());
    await tester.pumpAndSettle();

    expect(find.text('Relazioni'), findsNothing);
    expect(find.text('Attività'), findsNothing);
    expect(find.text('Documenti'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('keeps the hero action visible, disabled and explained — no FAB', (tester) async {
    await tester.pumpWidget(buildHarness());
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byKey(const Key('detail-hero-card')),
        matching: find.text('Modifica'),
      ),
      findsOneWidget,
    );
    expect(find.textContaining('non è disponibile su questo telefono'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('lays out cleanly at 320px', (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(buildHarness());
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('#4471'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('says plainly it is offline instead of showing a broken screen', (tester) async {
    await tester.pumpWidget(buildHarness(isOnline: false));
    await tester.pumpAndSettle();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Ristrutturazione impianto'), findsNothing);
    expect(find.text('Commessa non disponibile'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('shows the mirror copy offline when the commessa was synced', (tester) async {
    await db
        .into(db.commesse)
        .insert(
          CommesseCompanion.insert(
            id: 'comm-1',
            tenantId: 'tenant-1',
            createdAt: DateTime.utc(2026, 1, 1),
            codice: '#4471',
            descrizione: const Value('Ristrutturazione impianto'),
            customerId: const Value('cust-1'),
            stato: const Value('Aperta'),
          ),
        );

    await tester.pumpWidget(buildHarness(isOnline: false));
    await tester.pumpAndSettle();

    expect(find.text('#4471'), findsOneWidget);
    expect(find.text('Ristrutturazione impianto'), findsOneWidget);
    expect(find.text('Rossi Srl'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}
