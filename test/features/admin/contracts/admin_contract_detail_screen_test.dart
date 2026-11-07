// dart format width=100
// test/features/admin/contracts/admin_contract_detail_screen_test.dart
//
// Contratto detail, redesigned to `prototypes/other-details.html` on the wave-0 summary shell:
// SummaryHero (`Summary · contratto`) + `Modifica`, then Sintesi → Relazioni → Attività. The delete
// action stays in the header and `Genera pianificazione` stays a hero secondary action, so no FAB.
//
// Data is unchanged: the contract map arrives as `extra` (server fields when online, the smaller
// mirror shape offline) and the sections only add what the local mirror can answer — the customer,
// its sede, the contract's tickets and the schedules attached to those tickets.

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import 'package:tasktap_mobile/core/time/business_time.dart';
import 'package:tasktap_mobile/core/time/business_time_providers.dart';
import 'package:tasktap_mobile/core/widgets/widgets.dart';
import 'package:tasktap_mobile/data/api/dio_client.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/sync/connectivity_provider.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart';
import 'package:tasktap_mobile/features/admin/contracts/admin_contract_detail_screen.dart';

class MockDio extends Mock implements Dio {}

Response<T> _ok<T>(T data, String path) => Response<T>(
  data: data,
  statusCode: 200,
  requestOptions: RequestOptions(path: path),
);

/// Monday 15 January 2026, 12:00 Rome. A contract starting 2026-01-01 is Attivo; one ending
/// before today is Scaduto, and the 30-day window is deterministic.
final _now = DateTime.utc(2026, 1, 15, 11);

void main() {
  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    registerFallbackValue(RequestOptions(path: '/'));
    ensureTimeZonesInitialized();
  });

  late AppDatabase db;
  late MockDio mockDio;

  const contract = {
    'id': 'contr-1',
    'name': 'Manutenzione annuale',
    'numero': 'CTR-2026-001',
    'codice': 'C-001',
    'tipo': 'Manutenzione',
    'externalId': 'EXT-1',
    'customerId': 'cust-1',
    'locationId': 'loc-1',
    'autoRenewal': true,
    'scadenzaGiorni': 30,
    'condizioni': 'Pagamento a 30gg',
    'startDate': '2026-01-01T00:00:00Z',
    'endDate': '2026-12-31T00:00:00Z',
    'frequencyValue': 1,
    'frequencyUnit': 'Months',
    'isActive': true,
  };

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    mockDio = MockDio();

    when(
      () => mockDio.get<Map<String, dynamic>>(
        '/api/users',
        queryParameters: any(named: 'queryParameters'),
      ),
    ).thenAnswer(
      (_) async => _ok({
        'items': [
          {'id': 'tech-1', 'displayName': 'Mario Rossi'},
        ],
      }, '/api/users'),
    );
  });

  tearDown(() async => db.close());

  Future<void> seedContractContext() async {
    await db
        .into(db.customers)
        .insert(
          CustomersCompanion.insert(
            id: 'cust-1',
            tenantId: 'tenant-1',
            createdAt: DateTime.utc(2021, 4, 12),
            companyName: 'Rossi Srl',
          ),
        );
    await db
        .into(db.locations)
        .insert(
          LocationsCompanion.insert(
            id: 'loc-1',
            tenantId: 'tenant-1',
            createdAt: DateTime.utc(2022, 1, 1),
            customerId: 'cust-1',
            name: 'Sede Milano',
          ),
        );
    await db
        .into(db.ticketStatuses)
        .insert(
          TicketStatusesCompanion.insert(id: const Value(2), tenantId: 'tenant-1', name: 'Aperto'),
        );
    await db
        .into(db.tickets)
        .insert(
          TicketsCompanion.insert(
            id: 'ticket-1',
            tenantId: 'tenant-1',
            createdAt: DateTime.utc(2026, 1, 10),
            title: 'Perdita acqua caldaia',
            customerId: 'cust-1',
            locationId: 'loc-1',
            statusId: 2,
            typeId: 1,
            contractId: const Value('contr-1'),
          ),
        );
    await db
        .into(db.tickets)
        .insert(
          TicketsCompanion.insert(
            id: 'ticket-other',
            tenantId: 'tenant-1',
            createdAt: DateTime.utc(2026, 1, 12),
            title: 'Ticket di un altro contratto',
            customerId: 'cust-1',
            locationId: 'loc-1',
            statusId: 2,
            typeId: 1,
            contractId: const Value('contr-other'),
          ),
        );
    await db
        .into(db.schedules)
        .insert(
          SchedulesCompanion.insert(
            id: 'schedule-1',
            tenantId: 'tenant-1',
            createdAt: DateTime.utc(2026, 1, 1),
            activityDate: DateTime.utc(2026, 1, 20),
            timeStartMinutes: 540,
            timeEndMinutes: 600,
            userId: 'tech-1',
            statusId: 1,
            locationId: 'loc-1',
            title: 'Manutenzione programmata',
            description: '',
            ticketId: const Value('ticket-1'),
          ),
        );
  }

  Widget buildHarness({Map<String, dynamic>? contractOverride}) {
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => context.push('/detail'),
                child: const Text('Apri dettaglio'),
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/detail',
          builder: (context, state) =>
              AdminContractDetailScreen(contract: contractOverride ?? contract),
        ),
        GoRoute(
          path: '/altro/clienti/:id',
          builder: (context, state) => const Scaffold(body: Text('Cliente aperto')),
        ),
      ],
    );

    return ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        dioProvider.overrideWithValue(mockDio),
        isOnlineProvider.overrideWithValue(true),
        businessTimeProvider.overrideWithValue(BusinessTime('Europe/Rome', clock: () => _now)),
      ],
      child: MaterialApp.router(routerConfig: router),
    );
  }

  Future<void> openDetail(
    WidgetTester tester, {
    Map<String, dynamic>? contractOverride,
    Size size = const Size(800, 1800),
  }) async {
    await tester.binding.setSurfaceSize(size);
    await tester.pumpWidget(buildHarness(contractOverride: contractOverride));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apri dettaglio'));
    await tester.pumpAndSettle();
    // Drift-backed relationship providers complete on real I/O, which the fake-async test clock
    // does not advance. Give the event loop a slot, then draw what arrived.
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();
  }

  Future<void> teardown(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await tester.binding.setSurfaceSize(null);
  }

  group('summary shell', () {
    testWidgets('renders the SummaryHero with Modifica and no FAB', (tester) async {
      await openDetail(tester);

      expect(find.byKey(const Key('detail-hero-card')), findsOneWidget);
      expect(find.text('SUMMARY · CONTRATTO'), findsOneWidget);
      expect(find.byKey(const Key('detail-hero-title')), findsOneWidget);
      // The collapsed bar is built off-screen and carries the same action label.
      expect(find.text('Modifica'), findsWidgets);
      expect(find.text('Genera pianificazione'), findsOneWidget);
      expect(find.byType(AppFab), findsNothing);
      await teardown(tester);
    });

    testWidgets('hero facts carry the customer, expiry and renewal once', (tester) async {
      await seedContractContext();
      await openDetail(tester);

      final subtitle = tester.widget<Text>(find.byKey(const Key('detail-hero-subtitle')));
      expect(subtitle.data, 'Rossi Srl · scade 31/12/2026 · rinnovo auto');
      await teardown(tester);
    });
  });

  group('Sintesi', () {
    testWidgets('shows the scadenze and contract facts', (tester) async {
      await openDetail(tester);

      expect(find.text('CTR-2026-001'), findsOneWidget);
      expect(find.text('C-001'), findsOneWidget);
      expect(find.text('Manutenzione'), findsOneWidget);
      expect(find.text('30 giorni'), findsOneWidget);
      expect(find.text('1 mesi'), findsOneWidget);
      expect(find.text('01/01/2026'), findsOneWidget);
      await teardown(tester);
    });

    testWidgets('a mirrored contract (unsynced fields absent) never invents frequency or renewal', (
      tester,
    ) async {
      // Exactly the map the list builds offline from `db.contracts`: the sync payload has no
      // price/condizioni/frequency*/autoRenewal/scadenzaGiorni. Defaulting them would print
      // "Frequenza 1 mesi" and "Rinnovo automatico" as facts about the contract.
      await openDetail(
        tester,
        contractOverride: const {
          'id': 'contr-1',
          'name': 'Manutenzione annuale',
          'startDate': '2026-01-01T00:00:00Z',
          'isActive': true,
          'numero': 'CTR-2026-001',
          'codice': 'C-001',
          'externalId': 'EXT-1',
        },
      );

      expect(find.textContaining('mesi'), findsNothing);
      expect(find.textContaining('Rinnovo'), findsNothing);
      expect(find.text('INIZIO'), findsOneWidget);
      expect(find.text('NUMERO'), findsOneWidget);
      await teardown(tester);
    });
  });

  group('section order', () {
    testWidgets('Sintesi → Relazioni → Attività, with Documenti absent', (tester) async {
      await seedContractContext();
      await openDetail(tester);

      final sintesi = tester.getTopLeft(find.text('Sintesi')).dy;
      final relazioni = tester.getTopLeft(find.text('Relazioni')).dy;
      final attivita = tester.getTopLeft(find.text('Attività')).dy;
      expect(sintesi, lessThan(relazioni));
      expect(relazioni, lessThan(attivita));
      expect(find.text('Documenti'), findsNothing);
      await teardown(tester);
    });

    testWidgets('lays out without overflow at 320px', (tester) async {
      await seedContractContext();
      await openDetail(tester, size: const Size(320, 1800));

      expect(tester.takeException(), isNull);
      expect(find.text('Sintesi'), findsOneWidget);
      expect(find.text('Relazioni'), findsOneWidget);
      expect(find.text('Attività'), findsOneWidget);
      await teardown(tester);
    });
  });

  group('status', () {
    testWidgets('shows the expiry-derived stamp', (tester) async {
      await openDetail(
        tester,
        contractOverride: const {
          'id': 'contr-1',
          'name': 'Manutenzione annuale',
          'startDate': '2025-01-01T00:00:00Z',
          'endDate': '2026-01-20T00:00:00Z',
          'isActive': true,
        },
      );

      // The collapsed bar is built off-screen and carries the same stamp.
      expect(find.text('IN SCADENZA'), findsWidgets);
      await teardown(tester);
    });
  });

  group('Relazioni', () {
    testWidgets('shows the customer, its sede and the pianificazioni count', (tester) async {
      await seedContractContext();
      await openDetail(tester);

      expect(find.text('Cliente'), findsOneWidget);
      expect(find.text('Sede'), findsOneWidget);
      expect(find.text('Pianificazioni'), findsOneWidget);
      expect(find.text('1 PIANIFICAZIONE'), findsOneWidget);

      await tester.tap(find.text('Cliente'));
      await tester.pumpAndSettle();
      expect(find.text('Cliente aperto'), findsOneWidget);
      await teardown(tester);
    });

    testWidgets('is hidden when the mirror has no customer, sede or pianificazioni', (
      tester,
    ) async {
      await openDetail(tester);

      expect(find.text('Sintesi'), findsOneWidget);
      expect(find.text('Relazioni'), findsNothing);
      expect(find.text('Attività'), findsNothing);
      await teardown(tester);
    });
  });

  group('Attività', () {
    testWidgets('lists only the interventi linked to this contract', (tester) async {
      await seedContractContext();
      await openDetail(tester);

      expect(find.text('Perdita acqua caldaia'), findsOneWidget);
      expect(find.text('Ticket di un altro contratto'), findsNothing);
      await teardown(tester);
    });
  });

  group('missing data', () {
    testWidgets('a deep link without the contract map shows the unavailable state', (tester) async {
      await openDetail(tester, contractOverride: const {});

      expect(find.text('Contratto non disponibile'), findsOneWidget);
      expect(find.text('Modifica'), findsNothing);
      await teardown(tester);
    });
  });

  group('delete contract', () {
    testWidgets('confirms then DELETEs and pops', (tester) async {
      when(
        () => mockDio.delete<dynamic>('/api/contracts/contr-1'),
      ).thenAnswer((_) async => _ok(null, '/api/contracts/contr-1'));

      await openDetail(tester);

      await tester.tap(
        find.byWidgetPredicate((w) => w is HeaderIconBtn && w.label == 'Elimina contratto'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Elimina').last);
      await tester.pumpAndSettle();

      verify(() => mockDio.delete<dynamic>('/api/contracts/contr-1')).called(1);
      expect(find.text('Apri dettaglio'), findsOneWidget);
      await teardown(tester);
    });

    testWidgets('surfaces the backend\'s 409 message verbatim when linked records block it', (
      tester,
    ) async {
      when(() => mockDio.delete<dynamic>('/api/contracts/contr-1')).thenThrow(
        DioException(
          requestOptions: RequestOptions(path: '/api/contracts/contr-1'),
          response: Response(
            requestOptions: RequestOptions(path: '/api/contracts/contr-1'),
            statusCode: 409,
            data: {
              'message':
                  'Impossibile eliminare: il contratto ha prodotti, pianificazioni o interventi collegati',
            },
          ),
          type: DioExceptionType.badResponse,
        ),
      );

      await openDetail(tester);

      await tester.tap(
        find.byWidgetPredicate((w) => w is HeaderIconBtn && w.label == 'Elimina contratto'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Elimina').last);
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Impossibile eliminare: il contratto ha prodotti, pianificazioni o interventi '
          'collegati. Niente è andato perso.',
        ),
        findsOneWidget,
      );
      expect(find.text('Manutenzione annuale'), findsWidgets);
      await teardown(tester);
    });
  });

  group('genera pianificazione', () {
    testWidgets('requires a tecnico before Genera is enabled', (tester) async {
      await openDetail(tester);

      await tester.tap(find.text('Genera pianificazione'));
      await tester.pumpAndSettle();

      final generaButton = tester.widget<AppButton>(find.widgetWithText(AppButton, 'Genera'));
      expect(generaButton.onPressed, isNull);
      await teardown(tester);
    });

    testWidgets('posts the selected tecnico\'s userId and shows the server\'s summary', (
      tester,
    ) async {
      when(
        () => mockDio.post<Map<String, dynamic>>(
          '/api/contracts/contr-1/genera-schedule',
          data: any(named: 'data'),
        ),
      ).thenAnswer(
        (_) async => _ok({
          'created': 12,
          'message': '12 pianificazioni generate.',
        }, '/api/contracts/contr-1/genera-schedule'),
      );

      await openDetail(tester);

      await tester.tap(find.text('Genera pianificazione'));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mario Rossi').last);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Genera'));
      await tester.pumpAndSettle();

      final captured =
          verify(
                () => mockDio.post<Map<String, dynamic>>(
                  '/api/contracts/contr-1/genera-schedule',
                  data: captureAny(named: 'data'),
                ),
              ).captured.single
              as Map;
      expect(captured['userId'], 'tech-1');
      expect(find.text('12 pianificazioni generate.'), findsOneWidget);
      await teardown(tester);
    });
  });
}
