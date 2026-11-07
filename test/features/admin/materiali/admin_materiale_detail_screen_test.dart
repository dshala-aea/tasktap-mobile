// dart format width=100
// test/features/admin/materiali/admin_materiale_detail_screen_test.dart
//
// The redesigned Materiale detail on the wave-0 summary shell: SummaryHero + Modifica, then
// Movimenti → Sintesi → Documenti. The local mirror has no stock columns, so Movimenti links to
// the existing Giacenze e movimenti screen on demand instead of inventing a quantity; Documenti
// shows the mirrored photo as an on-demand attachment row.

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';
import 'package:tasktap_mobile/core/widgets/widgets.dart';
import 'package:tasktap_mobile/data/api/dio_client.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/sync/connectivity_provider.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart';
import 'package:tasktap_mobile/features/admin/materiali/admin_materiale_detail_screen.dart';

class MockDio extends Mock implements Dio {}

Response<T> _ok<T>(T data, String path) => Response<T>(
  data: data,
  statusCode: 200,
  requestOptions: RequestOptions(path: path),
);

class _NoopSync extends SyncNotifier {
  _NoopSync(AppDatabase db) : super(SyncService(db: db, dio: Dio()), db);
  @override
  Future<void> performSync() async {}
}

AppDatabase _makeDb() => AppDatabase(NativeDatabase.memory());

Future<void> _seedMateriale(
  AppDatabase db, {
  String id = 'm1',
  String code = 'ART-001',
  String name = 'Sifone 40 mm',
  String? category = 'Idraulica',
  String? unitOfMeasure = 'pz',
  String? marca = 'Acme',
  double? purchasePrice = 2.10,
  double? salePrice = 4.20,
  String? description = 'Sifone in ottone.',
  String? imageUrl = 'https://example.test/foto.jpg',
  bool active = true,
}) {
  return db
      .into(db.materiali)
      .insert(
        MaterialiCompanion.insert(
          id: id,
          tenantId: 'tenant-1',
          createdAt: DateTime.utc(2026, 1, 1),
          code: code,
          name: name,
          category: Value(category),
          unitOfMeasure: Value(unitOfMeasure),
          marca: Value(marca),
          purchasePrice: Value(purchasePrice),
          salePrice: Value(salePrice),
          description: Value(description),
          imageUrl: Value(imageUrl),
          isActive: Value(active),
        ),
      );
}

Widget _buildScreen(
  AppDatabase db,
  MockDio dio, {
  String materialeId = 'm1',
  List<Override> overrides = const [],
}) {
  final router = GoRouter(
    initialLocation: '/detail',
    routes: [
      GoRoute(
        path: '/detail',
        builder: (_, _) => AdminMaterialeDetailScreen(materialeId: materialeId),
      ),
      // Static before dynamic so `/giacenze` is not captured as a materiale id.
      GoRoute(
        path: '/altro/magazzino/giacenze',
        builder: (_, _) => const Scaffold(body: Text('giacenze-screen')),
      ),
      GoRoute(
        path: '/altro/magazzino/:id/modifica',
        builder: (_, state) => Scaffold(body: Text('modifica:${state.pathParameters['id']}')),
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      appDatabaseProvider.overrideWithValue(db),
      dioProvider.overrideWithValue(dio),
      isOnlineProvider.overrideWithValue(true),
      syncProvider.overrideWith((ref) => _NoopSync(db)),
      ...overrides,
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

Future<void> _pump(
  WidgetTester tester,
  AppDatabase db,
  MockDio dio, {
  String materialeId = 'm1',
  List<Override> overrides = const [],
}) async {
  await tester.pumpWidget(_buildScreen(db, dio, materialeId: materialeId, overrides: overrides));
  await tester.pumpAndSettle();
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    registerFallbackValue(RequestOptions(path: '/'));
  });

  late AppDatabase db;
  late MockDio dio;

  setUp(() {
    db = _makeDb();
    dio = MockDio();
  });

  tearDown(() async => db.close());

  testWidgets('renders the summary hero, the three sections in order, and no FAB', (tester) async {
    await _seedMateriale(db);
    await _pump(tester, db, dio);

    // Hero: kind, entity, status stamp, facts and the primary action.
    expect(find.text('SUMMARY · ARTICOLO'), findsNWidgets(2)); // kicker above + kind in the card
    expect(find.text('Sifone 40 mm'), findsOneWidget);
    expect(find.text('Idraulica · pz · € 4,20'), findsOneWidget);
    final hero = find.byKey(const Key('detail-hero-card'));
    expect(find.descendant(of: hero, matching: find.text('ATTIVO')), findsOneWidget);
    expect(find.descendant(of: hero, matching: find.text('Modifica')), findsOneWidget);
    expect(find.byType(AppFab), findsNothing);

    // Sections: Movimenti first, then Sintesi, then Documenti.
    expect(find.text('Movimenti'), findsOneWidget);
    expect(find.text('Apri giacenze e movimenti'), findsOneWidget);
    expect(find.text('CARICHI, SCARICHI, RETTIFICHE'), findsOneWidget);
    expect(find.text('Sintesi'), findsOneWidget);
    expect(find.text('Documenti'), findsOneWidget);
    expect(find.text('1 FOTO'), findsOneWidget);

    final movimentiY = tester.getTopLeft(find.text('Movimenti')).dy;
    final sintesiY = tester.getTopLeft(find.text('Sintesi')).dy;
    final documentiY = tester.getTopLeft(find.text('Documenti')).dy;
    expect(movimentiY, lessThan(sintesiY));
    expect(sintesiY, lessThan(documentiY));

    // Sintesi: code, brand, purchase price, description.
    expect(find.text('CODICE'), findsOneWidget);
    expect(find.text('ART-001'), findsOneWidget);
    expect(find.text('MARCA'), findsOneWidget);
    expect(find.text('Acme'), findsOneWidget);
    expect(find.text('PREZZO ACQUISTO'), findsOneWidget);
    expect(find.text('€ 2,10'), findsOneWidget);
    expect(find.text('DESCRIZIONE'), findsOneWidget);
    expect(find.text('Sifone in ottone.'), findsOneWidget);

    // Documenti: the mirrored photo as an on-demand row, not an eager image.
    expect(find.text('Foto materiale'), findsOneWidget);
    expect(find.text('FOTO'), findsOneWidget);

    await _unmount(tester);
  });

  testWidgets('hero facts stay in the hero and Sintesi carries the rest', (tester) async {
    await _seedMateriale(db);
    await _pump(tester, db, dio);

    // The hero renders one joined fact line; the category, unit and sale price appear once.
    expect(find.text('Idraulica · pz · € 4,20'), findsOneWidget);
    expect(find.textContaining('Idraulica'), findsOneWidget);
    expect(find.textContaining('€ 4,20'), findsOneWidget);
    // Sintesi owns the code, brand and purchase price, with no overlap.
    expect(find.text('ART-001'), findsOneWidget);
    expect(find.text('Acme'), findsOneWidget);
    expect(find.text('€ 2,10'), findsOneWidget);

    await _unmount(tester);
  });

  testWidgets('hides Documenti when the mirror carries no photo', (tester) async {
    await _seedMateriale(db, imageUrl: null);
    await _pump(tester, db, dio);

    expect(find.text('Documenti'), findsNothing);
    expect(find.text('FOTO'), findsNothing);

    await _unmount(tester);
  });

  testWidgets('an inactive material shows INATTIVO and offers Riattiva', (tester) async {
    await _seedMateriale(db, active: false);
    await _pump(tester, db, dio);

    final hero = find.byKey(const Key('detail-hero-card'));
    expect(find.descendant(of: hero, matching: find.text('INATTIVO')), findsOneWidget);
    expect(find.byIcon(LucideIcons.checkCircle), findsOneWidget);

    await _unmount(tester);
  });

  testWidgets('deactivating asks for confirmation, then calls DELETE', (tester) async {
    await _seedMateriale(db);
    when(
      () => dio.delete<dynamic>('/api/materiali/m1'),
    ).thenAnswer((_) async => _ok<dynamic>(null, '/api/materiali/m1'));

    await _pump(tester, db, dio);

    await tester.tap(find.byIcon(LucideIcons.xCircle));
    await tester.pumpAndSettle();

    expect(find.text('Disattiva materiale'), findsOneWidget);

    await tester.tap(find.text('Disattiva'));
    await tester.pumpAndSettle();

    verify(() => dio.delete<dynamic>('/api/materiali/m1')).called(1);
    expect(find.text('Materiale disattivato'), findsOneWidget);

    await _unmount(tester);
  });

  testWidgets('reactivating calls PUT with isActive true', (tester) async {
    await _seedMateriale(db, active: false);
    when(
      () => dio.put<dynamic>('/api/materiali/m1', data: any(named: 'data')),
    ).thenAnswer((_) async => _ok<dynamic>(null, '/api/materiali/m1'));

    await _pump(tester, db, dio);

    await tester.tap(find.byIcon(LucideIcons.checkCircle));
    await tester.pumpAndSettle();

    expect(find.text('Riattiva materiale'), findsOneWidget);

    await tester.tap(find.text('Riattiva'));
    await tester.pumpAndSettle();

    final captured =
        verify(
              () => dio.put<dynamic>('/api/materiali/m1', data: captureAny(named: 'data')),
            ).captured.single
            as Map;
    expect(captured['isActive'], isTrue);

    await _unmount(tester);
  });

  testWidgets('Modifica opens the existing edit route', (tester) async {
    await _seedMateriale(db);
    await _pump(tester, db, dio);

    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('detail-hero-card')),
        matching: find.text('Modifica'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('modifica:m1'), findsOneWidget);

    await _unmount(tester);
  });

  testWidgets('the Movimenti row opens the existing giacenze route on demand', (tester) async {
    await _seedMateriale(db);
    await _pump(tester, db, dio);

    await tester.tap(find.text('Apri giacenze e movimenti'));
    await tester.pumpAndSettle();

    expect(find.text('giacenze-screen'), findsOneWidget);

    await _unmount(tester);
  });

  testWidgets('a missing materiale on a synced device says it was not found', (tester) async {
    await db.setLastSync(DateTime.utc(2026, 1, 1));
    await _pump(tester, db, dio, materialeId: 'ghost');

    expect(find.text('Materiale non trovato'), findsOneWidget);

    await _unmount(tester);
  });

  testWidgets('a missing materiale before any sync says the catalogue is not downloaded', (
    tester,
  ) async {
    await _pump(tester, db, dio, materialeId: 'ghost');

    expect(find.text('Materiale non disponibile'), findsOneWidget);
    expect(find.textContaining('non è ancora sincronizzato'), findsOneWidget);

    await _unmount(tester);
  });

  testWidgets('a stream error shows the unavailable state with retry', (tester) async {
    await _pump(
      tester,
      db,
      dio,
      overrides: [
        adminMaterialeDetailProvider.overrideWith(
          (ref, id) => Stream<MaterialiData?>.error(StateError('boom')),
        ),
      ],
    );

    expect(find.text('Materiale non disponibile'), findsOneWidget);
    expect(find.text('Riprova'), findsOneWidget);

    await _unmount(tester);
  });

  testWidgets('the loading state uses the shell skeleton', (tester) async {
    final controller = StreamController<MaterialiData?>();
    addTearDown(controller.close);

    await tester.pumpWidget(
      _buildScreen(
        db,
        dio,
        overrides: [adminMaterialeDetailProvider.overrideWith((ref, id) => controller.stream)],
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('detail-loading-skeleton')), findsOneWidget);

    await _unmount(tester);
  });

  testWidgets('lays out at 320px without overflow', (tester) async {
    tester.view.physicalSize = const Size(320, 900) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await _seedMateriale(
      db,
      name: 'Sifone in ottone cromato con guarnizione rinforzata 40 mm',
      code: 'ART-001-OTTONE-CROMATO-LUNGO',
      category: 'Idraulica professionale e raccordi',
      marca: 'Marca con un nome molto lungo',
      description:
          'Sifone in ottone cromato con guarnizione rinforzata, compatibile con lavabi '
          'da 40 mm. Include il kit di montaggio e le istruzioni.',
    );
    await _pump(tester, db, dio);

    expect(tester.takeException(), isNull);

    await _unmount(tester);
  });
}
