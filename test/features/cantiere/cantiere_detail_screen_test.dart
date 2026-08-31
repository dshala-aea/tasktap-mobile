// dart format width=100
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:tasktap_mobile/core/router/app_router.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart';
import 'package:tasktap_mobile/features/cantiere/cantiere_detail_screen.dart';

/// Builds this screen's `/cantieri/:id` route behind a real [GoRouter], with a marker screen at
/// the cantiere-timbra route that echoes back its `ticketId` query param. Verifies the router-level
/// gap this fix wave closed: `CantiereDetailScreen`'s own forwarding of `widget.ticketId` into
/// `AppRoutes.cantiereTimbraPath` was already correct — the bug was that no real call site ever
/// passed a `ticketId` into `CantiereDetailScreen` in the first place. This test drives the whole
/// chain through the router (as `/cantieri/c1?ticketId=ticket-9` would arrive from the ticket-detail
/// chip) rather than passing `ticketId` directly to the widget, which wouldn't catch that gap.
GoRouter _makeTimbraForwardingRouter({required String cantiereId, required String ticketId}) =>
    GoRouter(
      initialLocation: '/cantieri/$cantiereId?ticketId=$ticketId',
      routes: [
        GoRoute(
          path: AppRoutes.cantieriDetail,
          builder: (_, state) => CantiereDetailScreen(
            cantiereId: state.pathParameters['id']!,
            ticketId: state.uri.queryParameters['ticketId'],
          ),
        ),
        GoRoute(
          path: AppRoutes.cantiereTimbra,
          builder: (_, state) => Scaffold(
            body: Center(
              child: Text(
                'CANTIERE-TIMBRA-MARKER:ticketId=${state.uri.queryParameters['ticketId']}',
              ),
            ),
          ),
        ),
      ],
    );

void main() {
  testWidgets('shows cantiere info and an empty tickets section', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    await db
        .into(db.cantieri)
        .insert(
          CantieriCompanion.insert(
            id: 'c1',
            tenantId: 'tenant1',
            createdAt: DateTime.utc(2026, 8, 31),
            name: 'Cantiere Alpha',
            address: const Value('Via Roma 1'),
          ),
        );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: const MaterialApp(home: CantiereDetailScreen(cantiereId: 'c1')),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Cantiere Alpha'), findsOneWidget);
    expect(find.text('Via Roma 1'), findsOneWidget);
    expect(find.text('Timbra cantiere'), findsOneWidget);
    expect(find.text('Nessun ticket collegato'), findsOneWidget);

    await db.close();
  });

  testWidgets('lists linked tickets when present', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    await db
        .into(db.cantieri)
        .insert(
          CantieriCompanion.insert(
            id: 'c1',
            tenantId: 'tenant1',
            createdAt: DateTime.utc(2026, 8, 31),
            name: 'Cantiere Alpha',
          ),
        );
    await db
        .into(db.tickets)
        .insert(
          TicketsCompanion.insert(
            id: 't1',
            tenantId: 'tenant1',
            createdAt: DateTime.utc(2026, 8, 31),
            title: 'Ticket collegato',
            customerId: 'cust1',
            locationId: 'l1',
            statusId: 1,
            typeId: 1,
            cantiereId: const Value('c1'),
          ),
        );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: const MaterialApp(home: CantiereDetailScreen(cantiereId: 'c1')),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Ticket collegato'), findsOneWidget);

    await db.close();
  });

  testWidgets(
    'a ticketId arriving via the router (as from the ticket-detail chip) reaches the Timbra push',
    (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      await db
          .into(db.cantieri)
          .insert(
            CantieriCompanion.insert(
              id: 'c1',
              tenantId: 'tenant1',
              createdAt: DateTime.utc(2026, 8, 31),
              name: 'Cantiere Alpha',
            ),
          );

      final router = _makeTimbraForwardingRouter(cantiereId: 'c1', ticketId: 'ticket-9');
      await tester.pumpWidget(
        ProviderScope(
          overrides: [appDatabaseProvider.overrideWithValue(db)],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Timbra cantiere'));
      await tester.pumpAndSettle();

      expect(find.text('CANTIERE-TIMBRA-MARKER:ticketId=ticket-9'), findsOneWidget);

      await db.close();
    },
  );
}
