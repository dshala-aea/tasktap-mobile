// dart format width=100
// test/features/admin/cantieri/admin_cantiere_form_screen_test.dart
//
// Cantieri module #8, Gap 5: Cantiere.CommessaId existed on the backend entity but neither
// CreateCantiereRequest nor UpdateCantiereRequest accepted it — a mobile field would have
// silently no-opped, so it was deliberately left unbuilt until the backend fix landed (af9039c,
// "Accept CommessaId on cantiere create/update"). This covers:
//   - the Commessa picker is genuinely in the widget tree, fed by a live GET /api/commesse
//     (there is no local Drift mirror for commesse, same as Squadre/ProdottoAssistenza);
//   - selecting a commessa and creating sends commessaId in the POST body;
//   - editing prefills the picker from the cached Drift row's commessaId and re-sends it on save.

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/drift.dart' as drift show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import 'package:tasktap_mobile/data/api/dio_client.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/sync/connectivity_provider.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart';
import 'package:tasktap_mobile/features/admin/cantieri/admin_cantiere_form_screen.dart';

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

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    mockDio = MockDio();

    // GET /api/commesse → the picker's live source (no local Drift mirror).
    when(() => mockDio.get<Map<String, dynamic>>('/api/commesse')).thenAnswer(
      (_) async => _ok({
        'items': [
          {'id': 'commessa-1', 'codice': 'COM-001', 'descrizione': 'Manutenzione annuale'},
          {'id': 'commessa-2', 'codice': 'COM-002', 'descrizione': null},
        ],
      }, '/api/commesse'),
    );

    when(
      () => mockDio.post<Map<String, dynamic>>('/api/cantieri', data: any(named: 'data')),
    ).thenAnswer((_) async => _ok({'id': 'new-cant'}, '/api/cantieri'));

    when(
      () => mockDio.put<dynamic>(any(that: contains('/api/cantieri/')), data: any(named: 'data')),
    ).thenAnswer((_) async => _ok(null, '/api/cantieri/cant-1'));
  });

  tearDown(() async => db.close());

  /// A GoRouter harness with a real page stack, so `context.pop(true)` in
  /// `AdminCantiereFormScreen._save` has something to pop back to.
  Widget buildHarness({String? cantiereId}) {
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => context.push('/form'),
                child: const Text('Apri form'),
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/form',
          builder: (context, state) => AdminCantiereFormScreen(cantiereId: cantiereId),
        ),
      ],
    );

    return ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        dioProvider.overrideWithValue(mockDio),
        isOnlineProvider.overrideWithValue(true),
      ],
      child: MaterialApp.router(routerConfig: router),
    );
  }

  /// Tall surface: the form's ListView now has enough fields (the new Commessa picker pushed
  /// "Crea cantiere"/"Salva modifiche" further down) that the button sits below the default
  /// 800×600 test surface and `tester.tap` can't find it — mirrors the same `setSurfaceSize`
  /// convention admin_cantiere_detail_screen_test.dart and
  /// test/features/ticket/ticket_detail_screen_test.dart already use for their own long screens.
  Future<void> openForm(WidgetTester tester, {String? cantiereId}) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    await tester.pumpWidget(buildHarness(cantiereId: cantiereId));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apri form'));
    await tester.pumpAndSettle();
  }

  /// The form watches Drift StreamProviders (allCustomersProvider) — leaving one mounted at test
  /// end leaves a pending fake timer behind (StreamQueryStore.markAsClosed) that fails the test
  /// binding's invariant check. Unmount explicitly, mirroring the same convention
  /// cantiere_timbra_screen_test.dart and admin_cantiere_detail_screen_test.dart use.
  Future<void> teardown(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await tester.binding.setSurfaceSize(null);
  }

  group('Commessa picker (Gap 5)', () {
    testWidgets('lists commesse from the live GET /api/commesse fetch', (tester) async {
      await openForm(tester);

      await tester.tap(find.byType(DropdownButtonFormField<String?>).last);
      await tester.pumpAndSettle();

      expect(find.textContaining('COM-001'), findsWidgets);
      expect(find.textContaining('COM-002'), findsWidgets);
      await teardown(tester);
    });

    testWidgets('creating with a selected commessa sends commessaId', (tester) async {
      await openForm(tester);

      // 'Nome *' is the first TextFormField on the form — AppTextField renders its label as a
      // sibling of the field, not as InputDecoration.labelText, so find.widgetWithText can't
      // match it; mirrors admin_magazzino_screens_test.dart's own `.first` convention.
      await tester.enterText(find.byType(TextFormField).first, 'Cantiere Centro');

      await tester.tap(find.byType(DropdownButtonFormField<String?>).last);
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('COM-001').last);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Crea cantiere'));
      await tester.pumpAndSettle();

      final captured = verify(
        () => mockDio.post<Map<String, dynamic>>('/api/cantieri', data: captureAny(named: 'data')),
      ).captured.single as Map;
      expect(captured['commessaId'], 'commessa-1');
      await teardown(tester);
    });

    testWidgets('creating with no commessa selected omits commessaId', (tester) async {
      await openForm(tester);

      await tester.enterText(find.byType(TextFormField).first, 'Cantiere Centro');
      await tester.tap(find.text('Crea cantiere'));
      await tester.pumpAndSettle();

      final captured = verify(
        () => mockDio.post<Map<String, dynamic>>('/api/cantieri', data: captureAny(named: 'data')),
      ).captured.single as Map;
      expect(captured.containsKey('commessaId'), isFalse);
      await teardown(tester);
    });

    testWidgets('editing prefills from the cached commessaId and re-sends it on save', (
      tester,
    ) async {
      await db
          .into(db.cantieri)
          .insert(
            CantieriCompanion.insert(
              id: 'cant-1',
              tenantId: 'tenant-1',
              createdAt: DateTime.utc(2026, 1, 1),
              name: 'Cantiere Centro',
              commessaId: const drift.Value('commessa-2'),
            ),
          );

      await openForm(tester, cantiereId: 'cant-1');

      expect(find.textContaining('COM-002'), findsWidgets);

      await tester.tap(find.text('Salva modifiche'));
      await tester.pumpAndSettle();

      final captured = verify(
        () => mockDio.put<dynamic>('/api/cantieri/cant-1', data: captureAny(named: 'data')),
      ).captured.single as Map;
      expect(captured['commessaId'], 'commessa-2');
      await teardown(tester);
    });
  });
}
