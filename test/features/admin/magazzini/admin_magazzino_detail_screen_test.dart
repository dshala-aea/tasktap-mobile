// dart format width=100
// test/features/admin/magazzini/admin_magazzino_detail_screen_test.dart
//
// The redesigned Magazzino detail on the wave-0 summary shell: SummaryHero + Modifica, then
// Sintesi (sotto scorta) → Movimenti → Documenti, with no FAB. Stock and movements are online-only
// and must stay on demand: opening the detail performs no network read.
import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:tasktap_mobile/core/widgets/widgets.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/magazzino/magazzino_api_client.dart';
import 'package:tasktap_mobile/data/sync/connectivity_provider.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart' show appDatabaseProvider;
import 'package:tasktap_mobile/features/admin/magazzini/admin_magazzino_detail_screen.dart';
import 'package:tasktap_mobile/features/ticket/steps/step_assegnazione.dart'
    show techniciansProvider;

class _FakeMagazzinoApiClient extends MagazzinoApiClient {
  _FakeMagazzinoApiClient({this.giacenze = const [], this.movimenti = const []}) : super(Dio());

  final List<GiacenzaDto> giacenze;
  final List<MovimentoDto> movimenti;

  int giacenzeCalls = 0;
  int movimentiCalls = 0;
  String? lastGiacenzeMagazzinoId;
  String? lastMovimentiMagazzinoId;
  bool? lastSoloSottoScorta;
  int? lastPageSize;

  @override
  Future<PagedResult<GiacenzaDto>> getGiacenze({
    String? magazzinoId,
    bool? sottoScorta,
    String? q,
    int page = 1,
    int pageSize = 50,
  }) async {
    giacenzeCalls++;
    lastGiacenzeMagazzinoId = magazzinoId;
    lastSoloSottoScorta = sottoScorta;
    lastPageSize = pageSize;
    return PagedResult(
      elementi: giacenze,
      pagina: 1,
      dimensionePagina: pageSize,
      totaleElementi: giacenze.length,
      totalePagine: 1,
    );
  }

  @override
  Future<PagedResult<MovimentoDto>> getMovimenti({
    String? tipo,
    String? magazzinoId,
    String? materialeId,
    DateTime? dataFrom,
    DateTime? dataTo,
    String? q,
    int page = 1,
    int pageSize = 50,
  }) async {
    movimentiCalls++;
    lastMovimentiMagazzinoId = magazzinoId;
    lastPageSize = pageSize;
    return PagedResult(
      elementi: movimenti,
      pagina: 1,
      dimensionePagina: pageSize,
      totaleElementi: movimenti.length,
      totalePagine: 1,
    );
  }
}

MagazzinoDto _sede({
  String id = 'm1',
  String nome = 'Magazzino Milano',
  String? indirizzo = 'Via Roma 1',
  String? note,
  bool isActive = true,
}) => MagazzinoDto(
  id: id,
  nome: nome,
  tipo: 'Sede',
  indirizzo: indirizzo,
  note: note,
  isActive: isActive,
);

MagazzinoDto _furgone({
  String id = 'm2',
  String nome = 'Furgone 3',
  String? assegnatoUserId = 'u-daniel',
  String? indirizzo,
  bool isActive = true,
}) => MagazzinoDto(
  id: id,
  nome: nome,
  tipo: 'Furgone',
  assegnatoUserId: assegnatoUserId,
  indirizzo: indirizzo,
  isActive: isActive,
);

GiacenzaDto _giacenza({
  required String id,
  required String materialeNome,
  double quantita = 2,
  double? stockMinimo = 5,
  String? unitOfMeasure = 'pz',
}) => GiacenzaDto(
  id: id,
  magazzinoId: 'm1',
  materialeId: 'mat-$id',
  quantita: quantita,
  sottoScorta: true,
  magazzinoNome: 'Magazzino Milano',
  materialeNome: materialeNome,
  unitOfMeasure: unitOfMeasure,
  stockMinimo: stockMinimo,
);

MovimentoDto _movimento({
  required String id,
  required String materialeNome,
  String tipo = 'Carico',
  double quantita = 4,
}) => MovimentoDto(
  id: id,
  data: DateTime.utc(2026, 11, 5, 14, 30),
  tipo: tipo,
  materialeId: 'mat-$id',
  quantita: quantita,
  userId: 'u-1',
  magazzinoDestinazioneNome: 'Magazzino Milano',
  materialeNome: materialeNome,
  userNome: 'Daniel Shala',
);

AppDatabase _makeDb() => AppDatabase(NativeDatabase.memory());

Widget _screen({
  required AppDatabase db,
  required MagazzinoApiClient api,
  MagazzinoDto? magazzino,
  bool online = true,
}) {
  final router = GoRouter(
    initialLocation: '/detail',
    routes: [
      GoRoute(
        path: '/detail',
        builder: (_, _) => AdminMagazzinoDetailScreen(magazzino: magazzino),
      ),
      GoRoute(
        path: '/altro/magazzino/magazzini/:id/modifica',
        builder: (_, state) => Scaffold(body: Text('modifica:${state.pathParameters['id']}')),
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      appDatabaseProvider.overrideWithValue(db),
      magazzinoApiClientProvider.overrideWithValue(api),
      isOnlineProvider.overrideWithValue(online),
      techniciansProvider.overrideWith(
        (ref) async => [
          {'id': 'u-daniel', 'displayName': 'Daniel Shala'},
        ],
      ),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

Future<void> _pump(
  WidgetTester tester, {
  required AppDatabase db,
  required MagazzinoApiClient api,
  MagazzinoDto? magazzino,
  bool online = true,
}) async {
  await tester.binding.setSurfaceSize(const Size(800, 2200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(_screen(db: db, api: api, magazzino: magazzino, online: online));
  await tester.pumpAndSettle();
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  late AppDatabase db;
  setUp(() => db = _makeDb());
  tearDown(() async => db.close());

  testWidgets('renders the summary hero, the three sections in order, and no FAB', (tester) async {
    final api = _FakeMagazzinoApiClient();
    await _pump(
      tester,
      db: db,
      api: api,
      magazzino: _sede(note: 'Accesso dal cortile interno.'),
    );

    expect(find.text('SUMMARY · MAGAZZINO'), findsNWidgets(2));
    expect(find.text('Magazzino Milano'), findsOneWidget);
    expect(find.text('Sede · Via Roma 1'), findsOneWidget);
    final hero = find.byKey(const Key('detail-hero-card'));
    expect(find.descendant(of: hero, matching: find.text('ATTIVO')), findsOneWidget);
    expect(find.descendant(of: hero, matching: find.text('Modifica')), findsOneWidget);
    expect(find.byType(AppFab), findsNothing);

    expect(find.text('Sintesi'), findsOneWidget);
    expect(find.text('SOTTO SCORTA'), findsOneWidget);
    expect(find.text('Movimenti'), findsOneWidget);
    expect(find.text('ULTIMI CARICHI E SCARICHI'), findsOneWidget);
    expect(find.text('Documenti'), findsOneWidget);
    expect(find.text('MAPPA'), findsOneWidget);
    expect(find.byKey(const Key('magazzino-map')), findsOneWidget);

    final sintesiY = tester.getTopLeft(find.text('Sintesi')).dy;
    final movimentiY = tester.getTopLeft(find.text('Movimenti')).dy;
    final documentiY = tester.getTopLeft(find.text('Documenti')).dy;
    expect(sintesiY, lessThan(movimentiY));
    expect(movimentiY, lessThan(documentiY));

    // The note lives in Sintesi and is not repeated in the hero.
    expect(find.text('NOTE'), findsOneWidget);
    expect(find.text('Accesso dal cortile interno.'), findsOneWidget);

    await _unmount(tester);
  });

  testWidgets('opening the detail reads neither giacenze nor movimenti', (tester) async {
    final api = _FakeMagazzinoApiClient(
      giacenze: [_giacenza(id: 'g1', materialeNome: 'Sifone 40 mm')],
      movimenti: [_movimento(id: 'v1', materialeNome: 'Tubo rame')],
    );
    await _pump(tester, db: db, api: api, magazzino: _sede());

    expect(api.giacenzeCalls, 0);
    expect(api.movimentiCalls, 0);
    expect(find.byKey(const Key('magazzino-scorte-load')), findsOneWidget);
    expect(find.byKey(const Key('magazzino-movimenti-load')), findsOneWidget);

    await _unmount(tester);
  });

  testWidgets('the scorte row loads only this warehouse, under minimum', (tester) async {
    final api = _FakeMagazzinoApiClient(
      giacenze: [
        _giacenza(id: 'g1', materialeNome: 'Sifone 40 mm', quantita: 2),
        _giacenza(id: 'g2', materialeNome: 'Guarnizione 1/2', quantita: 1),
      ],
    );
    await _pump(tester, db: db, api: api, magazzino: _sede());

    await tester.tap(find.byKey(const Key('magazzino-scorte-load')));
    await tester.pumpAndSettle();

    expect(api.giacenzeCalls, 1);
    expect(api.lastGiacenzeMagazzinoId, 'm1');
    expect(api.lastSoloSottoScorta, true);
    expect(api.lastPageSize, 20);
    expect(find.text('2 SOTTO SCORTA'), findsOneWidget);
    expect(find.byKey(const ValueKey('magazzino-scorta-g1')), findsOneWidget);
    expect(find.text('Sifone 40 mm'), findsOneWidget);
    expect(find.text('2 PZ · MIN 5'), findsOneWidget);

    await _unmount(tester);
  });

  testWidgets('the movimenti row loads this warehouse and draws latest rows', (tester) async {
    final api = _FakeMagazzinoApiClient(
      movimenti: [
        _movimento(id: 'v1', materialeNome: 'Tubo rame'),
        _movimento(id: 'v2', materialeNome: 'Sifone 40 mm', tipo: 'Scarico'),
      ],
    );
    await _pump(tester, db: db, api: api, magazzino: _sede());

    await tester.tap(find.byKey(const Key('magazzino-movimenti-load')));
    await tester.pumpAndSettle();

    expect(api.movimentiCalls, 1);
    expect(api.lastMovimentiMagazzinoId, 'm1');
    expect(find.text('2 MOVIMENTI'), findsOneWidget);
    expect(find.byKey(const ValueKey('magazzino-movimento-v1')), findsOneWidget);
    expect(find.text('Tubo rame'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (w) => w is Text && (w.data?.startsWith('CARICO · MAGAZZINO MILANO · 4 · ') ?? false),
      ),
      findsOneWidget,
    );

    await _unmount(tester);
  });

  testWidgets('offline keeps the rows on demand and explains why', (tester) async {
    final api = _FakeMagazzinoApiClient(
      giacenze: [_giacenza(id: 'g1', materialeNome: 'Sifone 40 mm')],
    );
    await _pump(tester, db: db, api: api, magazzino: _sede(), online: false);

    await tester.tap(find.byKey(const Key('magazzino-scorte-load')));
    await tester.pumpAndSettle();

    expect(api.giacenzeCalls, 0);
    expect(find.textContaining('solo online'), findsOneWidget);
    expect(find.text('Riprova'), findsOneWidget);

    await _unmount(tester);
  });

  testWidgets('a Furgone shows its assignee and hides Documenti without an address', (
    tester,
  ) async {
    final api = _FakeMagazzinoApiClient();
    await _pump(tester, db: db, api: api, magazzino: _furgone());

    expect(find.text('Furgone · Assegnato a Daniel Shala'), findsOneWidget);
    expect(find.text('Documenti'), findsNothing);
    expect(find.byKey(const Key('magazzino-map')), findsNothing);

    await _unmount(tester);
  });

  testWidgets('an inactive warehouse shows INATTIVO', (tester) async {
    final api = _FakeMagazzinoApiClient();
    await _pump(tester, db: db, api: api, magazzino: _sede(isActive: false));

    final hero = find.byKey(const Key('detail-hero-card'));
    expect(find.descendant(of: hero, matching: find.text('INATTIVO')), findsOneWidget);

    await _unmount(tester);
  });

  testWidgets('Modifica pushes the existing edit route with the warehouse', (tester) async {
    final api = _FakeMagazzinoApiClient();
    await _pump(tester, db: db, api: api, magazzino: _sede());

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

  testWidgets('a missing warehouse keeps the unavailable state', (tester) async {
    final api = _FakeMagazzinoApiClient();
    await _pump(tester, db: db, api: api);

    expect(find.text('Magazzino non disponibile'), findsOneWidget);
    expect(find.text("Torna all'elenco e riapri questo magazzino."), findsOneWidget);

    await _unmount(tester);
  });
}
