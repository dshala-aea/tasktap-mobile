// `smartWorkingToday` from /api/Auth/me: a day-level marker saying this technician has an
// approved smart-working day today. It relaxes the punch requirement, so the one rule these tests
// defend is that it must never be stale:
//
//   * it lives in memory only — no Drift column, no migration, nothing written by the cache path.
//     A cold start has to read unknown (`null`), never yesterday's answer.
//   * unknown is `null`, not `false`: a stale `true` would claim an approved day that ended
//     overnight, and a stale `false` would hide the punch button from someone who has one. The
//     server omitted the field (or answered with something that is not a bool) → unknown.
//   * a failed refresh is a no-op, like every other entitlement failure path.
//   * a signed-out session reads unknown, whatever the last signed-in user's answer was.
import 'package:dio/dio.dart';
// `isNull`/`isNotNull` also exist in drift's query builder (SQL predicates); the matchers are the
// ones these assertions mean.
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tasktap_mobile/data/entitlements/entitlement_providers.dart';
import 'package:tasktap_mobile/data/entitlements/entitlement_repository.dart';
import 'package:tasktap_mobile/data/entitlements/entitlement_service.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart';
import 'package:tasktap_mobile/domain/auth/auth_user.dart';
import 'package:tasktap_mobile/presentation/providers/auth_providers.dart';

import '../../support/auth_me_fixtures.dart';

class MockDio extends Mock implements Dio {}

/// "leave the key out of the body", distinct from an explicit null.
const _absent = Object();

AuthUser _user(String id) => AuthUser(
  id: id,
  email: '$id@example.com',
  accessToken: 'access-$id',
  refreshToken: 'refresh-$id',
  expiresAt: DateTime.utc(2030),
);

void main() {
  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  late AppDatabase db;
  late EntitlementRepository repo;
  late MockDio dio;
  late EntitlementService service;

  Response<Map<String, dynamic>> ok(Map<String, dynamic> body) => Response(
    requestOptions: RequestOptions(path: '/api/Auth/me'),
    statusCode: 200,
    data: body,
  );

  /// The minimal valid /me body, with `smartWorkingToday` added only when a test passes it.
  Map<String, dynamic> meBody({Object? smartWorkingToday = _absent}) => {
    ...authMeBody(),
    if (!identical(smartWorkingToday, _absent)) 'smartWorkingToday': smartWorkingToday,
  };

  void stub(Response<Map<String, dynamic>> response) {
    when(() => dio.get<Map<String, dynamic>>(any())).thenAnswer((_) async => response);
  }

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = EntitlementRepository(db);
    dio = MockDio();
    service = EntitlementService(dio: dio, repository: repo);
  });

  tearDown(() => db.close());

  group('what /auth/me said about today', () {
    test('refresh_True_SetsTheFlagTrue', () async {
      stub(ok(meBody(smartWorkingToday: true)));

      expect(await service.refresh(), isTrue);
      expect(repo.smartWorkingToday, isTrue);
    });

    test('refresh_False_SetsTheFlagFalse', () async {
      stub(ok(meBody(smartWorkingToday: false)));

      expect(await service.refresh(), isTrue);
      expect(repo.smartWorkingToday, isFalse);
    });

    test('refresh_WhenTheFieldIsAbsent_LeavesTheFlagUnknown', () async {
      // A previous answer must not survive: an old server (or a trimmed body) answers the whole
      // question, and its silence means "not known today", not "whatever it was yesterday".
      repo.setSmartWorkingToday(true);
      stub(ok(meBody()));

      expect(await service.refresh(), isTrue);
      expect(repo.smartWorkingToday, isNull);
    });

    test('a value that is not a bool is unknown, not a guess', () async {
      repo.setSmartWorkingToday(true);
      stub(ok(meBody(smartWorkingToday: 'true')));

      expect(await service.refresh(), isTrue);
      expect(repo.smartWorkingToday, isNull);
    });

    test('a failed refresh never touches the flag', () async {
      stub(ok(meBody(smartWorkingToday: true)));
      await service.refresh();

      when(
        () => dio.get<Map<String, dynamic>>(any()),
      ).thenThrow(DioException(requestOptions: RequestOptions(path: '/api/Auth/me')));

      expect(await service.refresh(), isFalse);
      expect(repo.smartWorkingToday, isTrue);
    });

    test('coldStart_FromTheDriftCache_ReportsUnknown', () async {
      stub(ok(meBody(smartWorkingToday: true)));
      await service.refresh();
      expect(repo.smartWorkingToday, isTrue);

      // Same on-disk row, a repository that has never seen an /me answer in this process.
      final cold = EntitlementRepository(db);
      expect(await cold.read(), isNotNull);
      expect(cold.smartWorkingToday, isNull);
    });
  });

  group('smartWorkingTodayProvider', () {
    ProviderContainer containerWith({required Stream<AuthUser?> auth}) {
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          authStateProvider.overrideWith((ref) => auth),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('signedOut_reportsUnknown', () async {
      final container = containerWith(auth: Stream<AuthUser?>.value(null));
      // The flag the previous signed-in user left behind in this process's memory.
      container.read(entitlementRepositoryProvider).setSmartWorkingToday(true);

      await container.read(authStateProvider.future);

      expect(container.read(smartWorkingTodayProvider), isNull);
    });

    test('signedIn_reportsWhatTheServerLastSaid', () async {
      final container = containerWith(auth: Stream<AuthUser?>.value(_user('user-a')));
      await container.read(authStateProvider.future);

      expect(container.read(smartWorkingTodayProvider), isNull);

      container.read(entitlementRepositoryProvider).setSmartWorkingToday(false);
      container.invalidate(smartWorkingTodayProvider);

      expect(container.read(smartWorkingTodayProvider), isFalse);
    });
  });
}
