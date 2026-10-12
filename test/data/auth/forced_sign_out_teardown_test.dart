// dart format width=100
//
// The forced sign-out path, driven the way the app really wires it: the Dio instance that
// `dioProvider` builds, its `AuthInterceptor`, and the shared teardown behind `onForcedSignOut`.
//
// Regression for a security finding: the interceptor's forced path used to call
// `IAuthRepository.signOut()` only, which drops the secure-storage refresh token and the cached
// identity and nothing else. So a session the identity provider had positively killed left the
// previous user's Drift rows and SharedPreferences on the device — on a shared/rotating-device
// field-service app, in front of whoever signs in next. The normal logout had its own, complete
// teardown; there were two sequences and one of them was wrong. This test is the guard that they
// stay one sequence: it asserts the *forced* path produces the same clean device.

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tasktap_mobile/core/time/business_time_providers.dart';
import 'package:tasktap_mobile/data/api/dio_client.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart';
import 'package:tasktap_mobile/domain/auth/auth_failure.dart';
import 'package:tasktap_mobile/domain/auth/auth_user.dart';
import 'package:tasktap_mobile/domain/auth/i_auth_repository.dart';
import 'package:tasktap_mobile/presentation/providers/auth_providers.dart';

/// The failure that means the session is actually gone: the identity provider positively answered
/// `invalid_grant`. This IS the forced path — every other refresh failure deliberately leaves the
/// session alone.
class _DeadSessionRepo implements IAuthRepository {
  int signOuts = 0;

  @override
  AuthUser? get currentUser => null;

  @override
  Stream<AuthUser?> get authStateChanges => const Stream<AuthUser?>.empty();

  @override
  Future<({AuthUser? user, AuthFailure? failure})> signIn() async =>
      (user: null, failure: const UnknownAuthError('unused'));

  @override
  Future<({AuthUser? user, AuthFailure? failure})> signInWithPassword(
    String loginName,
    String password,
  ) async => (user: null, failure: const UnknownAuthError('unused'));

  @override
  Future<({AuthUser? user, AuthFailure? failure})> refreshSession() async =>
      (user: null, failure: const SessionExpired());

  @override
  Future<void> signOut() async => signOuts++;
}

class _MockErrorHandler extends Mock implements ErrorInterceptorHandler {}

DioException _make401() {
  final options = RequestOptions(path: '/api/data');
  return DioException(
    requestOptions: options,
    response: Response<dynamic>(requestOptions: options, statusCode: 401),
    type: DioExceptionType.badResponse,
  );
}

void main() {
  setUp(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    SharedPreferences.setMockInitialValues({});
  });

  test('a confirmed SessionExpired leaves the device as clean as the logout button does', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db
        .into(db.customers)
        .insert(
          CustomersCompanion.insert(
            id: 'cust-1',
            tenantId: 'tenant-1',
            createdAt: DateTime.utc(2026, 1, 1),
            companyName: 'Acme Srl',
          ),
        );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('autenticazioneBiometrica', true);
    await prefs.setString(tenantTimeZonePrefsKey, 'Asia/Tokyo');

    final repo = _DeadSessionRepo();
    final container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(repo),
        appDatabaseProvider.overrideWithValue(db),
      ],
    );
    addTearDown(container.dispose);

    // The real wiring: `dioProvider` is what points the interceptor at the shared teardown.
    final interceptor = container
        .read(dioProvider)
        .interceptors
        .whereType<AuthInterceptor>()
        .single;

    await interceptor.onError(_make401(), _MockErrorHandler());

    expect(await db.select(db.customers).get(), isEmpty);
    expect(
      prefs.getBool('autenticazioneBiometrica'),
      isNull,
      reason: 'the previous user\'s settings must not be readable by the next one',
    );
    expect(prefs.getString(tenantTimeZonePrefsKey), isNull);
    expect(
      container.read(businessZoneIdProvider),
      'Europe/Rome',
      reason: 'Riverpod state outlives the prefs wipe — the next tenant would inherit this one\'s',
    );
    expect(repo.signOuts, 1, reason: 'the teardown still drops the credentials themselves');
  });
}
