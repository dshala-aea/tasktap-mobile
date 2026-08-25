// dart format width=100
// test/features/admin/contracts/admin_contract_detail_screen_test.dart
//
// Feature audit module #11 (Fatturazione/Contratti):
//   - Gap A: numero/codice/tipo/externalId/autoRenewal/scadenzaGiorni/condizioni are now shown.
//   - Gap B: delete had no UI at all — now a confirm dialog + DELETE call behind the header's
//     trash icon (mirrors admin_prodotto_detail_screen.dart's own `_deleteProdotto`), and the
//     backend's clean 409 ("...ha prodotti, pianificazioni o interventi collegati") surfaces
//     verbatim via humanErrorMessage.
//   - Gap C: "Genera pianificazione" had zero mobile UI trigger — now a confirm dialog with a
//     required Tecnico picker (the one input GeneraScheduleRequest.UserId genuinely requires),
//     then a success summary from the server's own message.

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import 'package:tasktap_mobile/core/widgets/widgets.dart';
import 'package:tasktap_mobile/data/api/dio_client.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/sync/connectivity_provider.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart';
import 'package:tasktap_mobile/features/admin/contracts/admin_contract_detail_screen.dart';

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

  const contract = {
    'id': 'contr-1',
    'name': 'Manutenzione annuale',
    'numero': 'CTR-2026-001',
    'codice': 'C-001',
    'tipo': 'Manutenzione',
    'externalId': 'EXT-1',
    'autoRenewal': true,
    'scadenzaGiorni': 30,
    'condizioni': 'Pagamento a 30gg',
    'startDate': '2026-01-01T00:00:00Z',
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

  Widget buildHarness() {
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
          builder: (context, state) => const AdminContractDetailScreen(contract: contract),
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

  Future<void> openDetail(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1800));
    await tester.pumpWidget(buildHarness());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apri dettaglio'));
    await tester.pumpAndSettle();
  }

  Future<void> teardown(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await tester.binding.setSurfaceSize(null);
  }

  group('Gap A fields', () {
    testWidgets('shows numero/codice/tipo/externalId/autoRenewal/scadenzaGiorni/condizioni', (
      tester,
    ) async {
      await openDetail(tester);

      expect(find.text('CTR-2026-001'), findsOneWidget);
      expect(find.text('C-001'), findsOneWidget);
      expect(find.text('Manutenzione'), findsOneWidget);
      expect(find.text('EXT-1'), findsOneWidget);
      expect(find.text('Sì'), findsOneWidget);
      expect(find.text('30 giorni'), findsOneWidget);
      expect(find.text('Pagamento a 30gg'), findsOneWidget);
      await teardown(tester);
    });
  });

  group('delete contract (Gap B)', () {
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

      // humanErrorMessage appends its own "nothing was lost" reassurance whenever `azione` is
      // given (see error_message.dart) — same shape `_deleteProdotto` already uses for its own
      // 409-equivalent errors — so the full SnackBar text carries that suffix, not just the
      // server's own sentence.
      expect(
        find.text(
          'Impossibile eliminare: il contratto ha prodotti, pianificazioni o interventi '
          'collegati. Niente è andato perso.',
        ),
        findsOneWidget,
      );
      // Still on the detail screen — a blocked delete must not pop.
      expect(find.text('Manutenzione annuale'), findsWidgets);
      await teardown(tester);
    });
  });

  group('genera pianificazione (Gap C)', () {
    testWidgets('requires a tecnico before Genera is enabled', (tester) async {
      await openDetail(tester);

      await tester.tap(find.text('Genera pianificazione'));
      await tester.pumpAndSettle();

      final generaButton = tester.widget<TextButton>(
        find.widgetWithText(TextButton, 'Genera'),
      );
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

      final captured = verify(
        () => mockDio.post<Map<String, dynamic>>(
          '/api/contracts/contr-1/genera-schedule',
          data: captureAny(named: 'data'),
        ),
      ).captured.single as Map;
      expect(captured['userId'], 'tech-1');
      expect(find.text('12 pianificazioni generate.'), findsOneWidget);
      await teardown(tester);
    });
  });
}
