import 'dart:async';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tasktap_mobile/core/time/business_time_providers.dart';
import 'package:tasktap_mobile/data/api/dio_client.dart';
import 'package:tasktap_mobile/data/entitlements/entitlement_providers.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart';
import 'package:tasktap_mobile/domain/auth/auth_user.dart';
import 'package:tasktap_mobile/domain/auth/i_auth_repository.dart';
import 'package:tasktap_mobile/presentation/providers/auth_providers.dart';

import '../../support/auth_me_fixtures.dart';

class _MockDio extends Mock implements Dio {}

class _MockAuthRepository extends Mock implements IAuthRepository {}

/// The real wiring: `/auth/me` -> EntitlementService -> businessZoneIdProvider, with the
/// signed-in-session guard and the "every response sets the zone" rule.
void main() {
  late _MockDio dio;
  late _MockAuthRepository auth;
  late AppDatabase db;
  late ProviderContainer container;
  AuthUser? signedIn;

  final user = AuthUser(
    id: 'user-1',
    email: 'tech@tasktap.io',
    accessToken: 'tok',
    refreshToken: 'refresh',
    expiresAt: DateTime.utc(2099),
  );

  Response<Map<String, dynamic>> ok(Map<String, dynamic> body) => Response(
    requestOptions: RequestOptions(path: '/api/Auth/me'),
    statusCode: 200,
    data: body,
  );

  void stubMe(Map<String, dynamic> body) {
    when(() => dio.get<Map<String, dynamic>>(any())).thenAnswer((_) async => ok(body));
  }

  Future<String?> prefsZone() async =>
      (await SharedPreferences.getInstance()).getString(tenantTimeZonePrefsKey);

  Future<void> refresh() => container.read(entitlementServiceProvider).refresh();

  setUp(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    SharedPreferences.setMockInitialValues({});
    dio = _MockDio();
    auth = _MockAuthRepository();
    signedIn = user;
    when(() => auth.currentUser).thenAnswer((_) => signedIn);
    when(() => auth.authStateChanges).thenAnswer((_) => const Stream<AuthUser?>.empty());
    when(() => auth.signOut()).thenAnswer((_) async => signedIn = null);
    db = AppDatabase(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [
        dioProvider.overrideWithValue(dio),
        authRepositoryProvider.overrideWithValue(auth),
        appDatabaseProvider.overrideWithValue(db),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  test('a valid zone is adopted and persisted', () async {
    stubMe(authMeBody(tenantTimeZone: 'Europe/Berlin'));
    await refresh();
    await pumpEventQueue();

    expect(container.read(businessZoneIdProvider), 'Europe/Berlin');
    expect(await prefsZone(), 'Europe/Berlin');
  });

  test('a later body without the key resets to Rome and forgets the cache', () async {
    stubMe(authMeBody(tenantTimeZone: 'Europe/Berlin'));
    await refresh();
    await pumpEventQueue();

    stubMe(authMeBody());
    await refresh();
    await pumpEventQueue();

    expect(container.read(businessZoneIdProvider), 'Europe/Rome');
    expect(await prefsZone(), isNull);
  });

  for (final bad in <Object?>['', '   ', null, 'W. Europe Standard Time', 'europe/berlin', 7]) {
    test(
      'a later invalid tenantTimeZone ($bad) resets to Rome, never keeps the old zone',
      () async {
        stubMe(authMeBody(tenantTimeZone: 'Asia/Tokyo'));
        await refresh();
        await pumpEventQueue();
        expect(container.read(businessZoneIdProvider), 'Asia/Tokyo');

        stubMe(authMeBody(tenantTimeZone: bad));
        await refresh();
        await pumpEventQueue();

        expect(container.read(businessZoneIdProvider), 'Europe/Rome');
        expect(await prefsZone(), isNull);
      },
    );
  }

  test('a failed refresh leaves the zone alone', () async {
    stubMe(authMeBody(tenantTimeZone: 'Asia/Tokyo'));
    await refresh();
    await pumpEventQueue();

    when(
      () => dio.get<Map<String, dynamic>>(any()),
    ).thenThrow(DioException(requestOptions: RequestOptions(path: '/api/Auth/me')));
    await refresh();
    await pumpEventQueue();

    expect(container.read(businessZoneIdProvider), 'Asia/Tokyo');
  });

  test('a /me answered after sign-out (old tenant) does not set the zone', () async {
    final gate = Completer<Response<Map<String, dynamic>>>();
    when(() => dio.get<Map<String, dynamic>>(any())).thenAnswer((_) => gate.future);

    final pending = refresh();
    await container.read(loginProvider.notifier).signOut();
    expect(container.read(businessZoneIdProvider), 'Europe/Rome');
    expect(await prefsZone(), isNull);

    gate.complete(ok(authMeBody(tenantTimeZone: 'Pacific/Auckland')));
    await pending;
    await pumpEventQueue();

    expect(container.read(businessZoneIdProvider), 'Europe/Rome');
    expect(await prefsZone(), isNull);
  });
}
