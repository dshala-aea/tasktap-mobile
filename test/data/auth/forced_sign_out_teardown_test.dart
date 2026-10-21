// dart format width=100
//
// The forced sign-out path, driven the way the app really wires it: the Dio instance that
// `dioProvider` builds, its `AuthInterceptor`, and the shared teardown behind `onForcedSignOut`.
//
// History, because this test used to assert the opposite: a `SessionExpired` confirmed by the
// identity provider used to be treated as a logout, wiping Drift and prefs. The security rationale
// was sound (a dead session must leave no rows in front of the next person) and the consequence was
// not: the forced path fires on the first refresh/flush after a long offline period, i.e. with
// every outbox full, so it deleted the very work the flush was trying to send (offline audit F1).
//
// The contract now: the forced path drops credentials ONLY. The local data stays, with a marker
// naming its owner, and the "whose data is this?" decision is made at the next sign-in by
// `SessionRecoveryController` (same account → send it; other account → explicit, confirmed
// discard — `test/data/auth/session_recovery_test.dart`). Manual logout still wipes
// (`session_ender_test.dart`).

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tasktap_mobile/core/time/business_time_providers.dart' show tenantTimeZonePrefsKey;
import 'package:tasktap_mobile/data/api/dio_client.dart';
import 'package:tasktap_mobile/data/auth/session_recovery.dart';
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
  _DeadSessionRepo({this.user});

  AuthUser? user;
  int signOuts = 0;

  @override
  AuthUser? get currentUser => user;

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

  test('a confirmed SessionExpired drops credentials and KEEPS the unsent local data', () async {
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

    expect(
      await db.select(db.customers).get(),
      hasLength(1),
      reason: 'F1: the forced path fires with every queue full — it must delete nothing',
    );
    expect(
      prefs.getBool('autenticazioneBiometrica'),
      isTrue,
      reason: 'the device is unchanged; the next sign-in decides what happens to this data',
    );
    expect(prefs.getString(tenantTimeZonePrefsKey), 'Asia/Tokyo');
    expect(repo.signOuts, 1, reason: 'the credentials themselves do go');
  });

  test('the owner marker is left for the next sign-in when the subject is readable', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = _DeadSessionRepo(
      user: AuthUser(
        id: 'zitadel-sub-owner',
        email: 'tecnico@example.it',
        accessToken: '', // skips the FCM unregister platform channel
        refreshToken: 'refresh',
        expiresAt: DateTime.utc(2030),
      ),
    );
    final container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(repo),
        appDatabaseProvider.overrideWithValue(db),
      ],
    );
    addTearDown(container.dispose);

    final interceptor = container
        .read(dioProvider)
        .interceptors
        .whereType<AuthInterceptor>()
        .single;

    await interceptor.onError(_make401(), _MockErrorHandler());

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(sessionRetainedOwnerSubKey), 'zitadel-sub-owner');
  });
}
