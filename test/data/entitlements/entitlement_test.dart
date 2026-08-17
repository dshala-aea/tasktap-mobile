import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tasktap_mobile/data/entitlements/entitlement_repository.dart';
import 'package:tasktap_mobile/data/entitlements/entitlement_service.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';

class MockDio extends Mock implements Dio {}

/// Offline feature gating.
///
/// The rule under test, and the reason most of these are failure-path tests: **a failed refresh
/// must never downgrade what the technician can do.** A phone on a building site loses signal
/// constantly. If a timeout could empty the cache, a lapsed network would cost someone their day —
/// a far worse outcome than a tenant briefly retaining a module they stopped paying for. The server
/// remains the enforcement point; this only decides what the app offers.
void main() {
  late AppDatabase db;
  late EntitlementRepository repo;
  late MockDio dio;
  late EntitlementService service;

  Response<Map<String, dynamic>> ok(Map<String, dynamic> body) => Response(
    requestOptions: RequestOptions(path: '/api/Auth/me'),
    statusCode: 200,
    data: body,
  );

  Map<String, dynamic> meBody({
    List<String> features = const ['clienti', 'team', 'sistema', 'rapportini', 'magazzino'],
    List<String> capabilities = const ['rapportini.report.write'],
    String seatType = 'field',
  }) => {'features': features, 'capabilities': capabilities, 'seatType': seatType};

  void stub(Response<Map<String, dynamic>> response) {
    when(() => dio.get<Map<String, dynamic>>(any())).thenAnswer((_) async => response);
  }

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = EntitlementRepository(db);
    dio = MockDio();
    service = EntitlementService(dio: dio, repository: repo);
  });

  tearDown(() async => db.close());

  group('caching what the server said', () {
    test('stores features, capabilities and seat type', () async {
      stub(ok(meBody()));

      expect(await service.refresh(), isTrue);

      final cached = await repo.read();
      expect(cached!.features, contains('magazzino'));
      expect(cached.capabilities, contains('rapportini.report.write'));
      expect(cached.seatType, 'field');
      expect(cached.isFieldSeat, isTrue);
    });

    test('a later refresh replaces the previous answer rather than merging', () async {
      stub(ok(meBody(features: ['clienti', 'magazzino'])));
      await service.refresh();

      // The tenant drops the magazzino add-on.
      stub(ok(meBody(features: ['clienti', 'rapportini'])));
      await service.refresh();

      expect(await repo.hasFeature('magazzino'), isFalse);
      expect(await repo.hasFeature('rapportini'), isTrue);
    });
  });

  group('a failed refresh never downgrades the technician', () {
    setUp(() async {
      stub(ok(meBody(features: ['clienti', 'rapportini', 'magazzino'])));
      await service.refresh();
    });

    test('a network error leaves the cache untouched', () async {
      when(
        () => dio.get<Map<String, dynamic>>(any()),
      ).thenThrow(DioException(requestOptions: RequestOptions(path: '/api/Auth/me')));

      expect(await service.refresh(), isFalse);
      expect(await repo.hasFeature('magazzino'), isTrue);
    });

    test('a non-200 leaves the cache untouched', () async {
      stub(
        Response(requestOptions: RequestOptions(path: '/api/Auth/me'), statusCode: 503, data: null),
      );

      expect(await service.refresh(), isFalse);
      expect(await repo.hasFeature('magazzino'), isTrue);
    });

    /// A captive portal or a misrouted proxy answers 200 with something that is not our payload.
    /// Writing `features: []` from that would strip every module the tenant has.
    test('a 200 with a body that is not ours leaves the cache untouched', () async {
      stub(ok({'unexpected': 'payload'}));

      expect(await service.refresh(), isFalse);
      expect(await repo.hasFeature('magazzino'), isTrue);
    });

    test('an empty feature list is treated as a failed answer, not as "nothing granted"', () async {
      stub(ok(meBody(features: [])));

      expect(await service.refresh(), isFalse);
      expect(await repo.hasFeature('magazzino'), isTrue);
    });
  });

  group('before the first successful refresh', () {
    /// A fresh install that cannot reach the network must not be a brick. These three are what a
    /// field seat exists for, and the server rejects anything the tenant genuinely lacks.
    test('a field seat can still record work', () async {
      expect(await repo.hasFeature('rapportini'), isTrue);
      expect(await repo.hasFeature('presenze'), isTrue);
      expect(await repo.hasFeature('interventi'), isTrue);
    });

    test('a paid module is not offered on a guess', () async {
      expect(await repo.hasFeature('magazzino'), isFalse);
      expect(await repo.hasFeature('fatturazione'), isFalse);
    });

    /// Finer-grained than a module, with no safe baseline. Offering an action the user may not
    /// hold would queue work the server rejects — losing it later rather than refusing it now.
    test('no capability is assumed', () async {
      expect(await repo.hasCapability('rapportini.report.write'), isFalse);
    });
  });

  group('always-on modules', () {
    test('are granted with nothing cached at all', () async {
      expect(await repo.hasFeature('clienti'), isTrue);
      expect(await repo.hasFeature('team'), isTrue);
      expect(await repo.hasFeature('sistema'), isTrue);
    });

    /// The server enforces these true in code (`ModuleKeys.AlwaysOn`). A client that gated them
    /// off would hide screens the backend would serve.
    test('are granted even if the server somehow omits them', () async {
      stub(ok(meBody(features: ['rapportini'])));
      await service.refresh();

      expect(await repo.hasFeature('clienti'), isTrue);
    });
  });

  test('the cache records when it was confirmed, but nothing expires it', () async {
    stub(ok(meBody()));
    await service.refresh();

    // Compared as an instant, not on `.isUtc`: Drift persists a unix timestamp and hands it back
    // flagged local, so the flag says nothing about correctness while the instant does.
    final cached = await repo.read();
    expect(
      DateTime.now().toUtc().difference(cached!.fetchedAt.toUtc()).inMinutes.abs(),
      lessThan(5),
    );

    // No API exists to invalidate on age, and that is deliberate — see the file header.
    expect(await repo.hasFeature('magazzino'), isTrue);
  });
}
