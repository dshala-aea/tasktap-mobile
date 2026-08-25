// test/features/admin/magazzini/admin_magazzino_screens_test.dart
//
// Gap 2 of the feature audit: warehouse (Magazzino: Sede/Furgone) admin CRUD had no mobile screen
// at all. These pin the list screen's read path and the form's validation/payload shape.
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tasktap_mobile/core/widgets/widgets.dart';
import 'package:tasktap_mobile/data/api/dio_client.dart';
import 'package:tasktap_mobile/data/sync/connectivity_provider.dart';
import 'package:tasktap_mobile/features/admin/magazzini/admin_magazzino_form_screen.dart';
import 'package:tasktap_mobile/features/admin/magazzini/admin_magazzino_list_screen.dart';

class MockDio extends Mock implements Dio {}

Response<T> _okResponse<T>(T data, String path) =>
    Response<T>(data: data, statusCode: 200, requestOptions: RequestOptions(path: path));

void main() {
  setUpAll(() {
    registerFallbackValue(RequestOptions(path: '/'));
  });

  late MockDio mockDio;

  setUp(() {
    mockDio = MockDio();
    // The technician picker (`techniciansProvider`) hits /api/users from every screen under test.
    when(
      () => mockDio.get<Map<String, dynamic>>('/api/users', queryParameters: any(named: 'queryParameters')),
    ).thenAnswer((_) async => _okResponse({'items': <Map<String, dynamic>>[]}, '/api/users'));
  });

  Widget wrap(Widget child) => ProviderScope(
    overrides: [dioProvider.overrideWithValue(mockDio), isOnlineProvider.overrideWithValue(true)],
    child: MaterialApp(home: child),
  );

  group('AdminMagazzinoListScreen', () {
    testWidgets('renders a row per warehouse from GET /api/magazzino', (tester) async {
      when(
        () => mockDio.get<Map<String, dynamic>>('/api/magazzino', queryParameters: any(named: 'queryParameters')),
      ).thenAnswer(
        (_) async => _okResponse({
          'items': [
            {'id': 'm1', 'nome': 'Sede centrale', 'tipo': 'Sede', 'isActive': true},
            {'id': 'm2', 'nome': 'Furgone Mario', 'tipo': 'Furgone', 'isActive': true},
          ],
        }, '/api/magazzino'),
      );

      await tester.pumpWidget(wrap(const AdminMagazzinoListScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Sede centrale'), findsOneWidget);
      expect(find.text('Furgone Mario'), findsOneWidget);
      expect(find.byType(ListRow), findsNWidgets(2));
    });

    testWidgets('shows an empty state with no warehouses', (tester) async {
      when(
        () => mockDio.get<Map<String, dynamic>>('/api/magazzino', queryParameters: any(named: 'queryParameters')),
      ).thenAnswer((_) async => _okResponse({'items': <Map<String, dynamic>>[]}, '/api/magazzino'));

      await tester.pumpWidget(wrap(const AdminMagazzinoListScreen()));
      await tester.pumpAndSettle();

      expect(find.byType(UnavailableState), findsOneWidget);
    });
  });

  group('AdminMagazzinoFormScreen', () {
    testWidgets('create requires a name before POSTing', (tester) async {
      await tester.pumpWidget(wrap(const AdminMagazzinoFormScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Crea magazzino'));
      await tester.pumpAndSettle();

      expect(find.text('Campo obbligatorio'), findsOneWidget);
      verifyNever(() => mockDio.post<Map<String, dynamic>>('/api/magazzino', data: any(named: 'data')));
    });

    testWidgets('create posts nome and tipo', (tester) async {
      when(
        () => mockDio.post<Map<String, dynamic>>('/api/magazzino', data: any(named: 'data')),
      ).thenAnswer((_) async => _okResponse({'id': 'm9'}, '/api/magazzino'));

      await tester.pumpWidget(wrap(const AdminMagazzinoFormScreen()));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).first, 'Sede Nord');
      await tester.tap(find.text('Crea magazzino'));
      await tester.pumpAndSettle();

      final captured = verify(
        () => mockDio.post<Map<String, dynamic>>('/api/magazzino', data: captureAny(named: 'data')),
      ).captured.single as Map;
      expect(captured['nome'], 'Sede Nord');
      // Defaults to Sede — the first chip — when the technician doesn't touch the Tipo picker.
      expect(captured['tipo'], 'Sede');
    });
  });
}
