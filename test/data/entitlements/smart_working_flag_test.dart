// `smartWorkingToday` from /api/Auth/me: a day-level marker saying this technician has an
// approved smart-working day today. It relaxes the punch requirement, so the rules these tests
// defend are all about not lying:
//
//   * it lives in memory only — no Drift column, no migration, nothing written by the cache path.
//     A cold start has to read unknown (`null`), never yesterday's answer.
//   * unknown is `null`, not `false`: a stale `true` would claim an approved day that ended
//     overnight, and a stale `false` would hide the punch button from someone who has one. The
//     server omitted the field (or answered with something that is not a bool) → unknown.
//   * the answer belongs to the user who asked for it. Memory outlives a sign-out, and this device
//     can be a shared van/tablet, so a signed-in user who is NOT the owner must read unknown.
//   * a failed refresh is a no-op, like every other entitlement failure path.
//
// The wire key is real (`AuthController.cs`, from `IsApprovedOnAsync`). `/api/Auth/me` has no
// response schema in the OpenAPI contract, so the mobile contract gate cannot see it — these
// fixture bodies are the contract for this field.
import 'dart:async';

import 'package:dio/dio.dart';
// `isNull`/`isNotNull` also exist in drift's query builder (SQL predicates); the matchers are the
// ones these assertions mean.
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
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

  /// The identity `service` reports as the signed-in session — the owner each answer is bound to.
  late String? session;

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
    session = 'user-a';
    db = AppDatabase(NativeDatabase.memory());
    repo = EntitlementRepository(db);
    dio = MockDio();
    service = EntitlementService(dio: dio, repository: repo, currentSessionId: () => session);
  });

  tearDown(() => db.close());

  group('what /auth/me said about today', () {
    test('refresh_True_SetsTheFlagTrue', () async {
      stub(ok(meBody(smartWorkingToday: true)));

      expect(await service.refresh(), isTrue);
      expect(repo.smartWorkingTodayFor('user-a'), isTrue);
    });

    test('refresh_False_SetsTheFlagFalse', () async {
      stub(ok(meBody(smartWorkingToday: false)));

      expect(await service.refresh(), isTrue);
      expect(repo.smartWorkingTodayFor('user-a'), isFalse);
    });

    test('refresh_WhenTheFieldIsAbsent_ReplacesAPreviousTrueWithUnknown', () async {
      // A previous answer must not survive: an old server (or a trimmed body) answers the whole
      // question, and its silence means "not known today", not "whatever it was yesterday".
      repo.setSmartWorkingToday(true, ownerId: 'user-a');
      stub(ok(meBody()));

      expect(await service.refresh(), isTrue);
      expect(repo.smartWorkingTodayFor('user-a'), isNull);
    });

    test('a value that is not a bool is unknown, not a guess', () async {
      repo.setSmartWorkingToday(true, ownerId: 'user-a');
      stub(ok(meBody(smartWorkingToday: 'true')));

      expect(await service.refresh(), isTrue);
      expect(repo.smartWorkingTodayFor('user-a'), isNull);
    });

    test('a failed refresh never touches the flag', () async {
      stub(ok(meBody(smartWorkingToday: true)));
      await service.refresh();

      when(
        () => dio.get<Map<String, dynamic>>(any()),
      ).thenThrow(DioException(requestOptions: RequestOptions(path: '/api/Auth/me')));

      expect(await service.refresh(), isFalse);
      expect(repo.smartWorkingTodayFor('user-a'), isTrue);
    });

    test('an answer for a session that ended in flight never sets the flag', () async {
      final gate = Completer<Response<Map<String, dynamic>>>();
      when(() => dio.get<Map<String, dynamic>>(any())).thenAnswer((_) => gate.future);

      final pending = service.refresh();
      session = null; // signed out while the request was in flight
      gate.complete(ok(meBody(smartWorkingToday: true)));

      expect(await pending, isFalse);
      expect(repo.smartWorkingTodayFor('user-a'), isNull);
      expect(repo.smartWorkingTodayFor(null), isNull);
    });

    test('coldStart_FromTheDriftCache_ReportsUnknown', () async {
      stub(ok(meBody(smartWorkingToday: true)));
      await service.refresh();
      expect(repo.smartWorkingTodayFor('user-a'), isTrue);

      // Same on-disk row, a repository that has never seen an /me answer in this process.
      final cold = EntitlementRepository(db);
      expect(await cold.read(), isNotNull);
      expect(cold.smartWorkingTodayFor('user-a'), isNull);
    });

    test('the answer is not handed to anyone but the session that produced it', () async {
      stub(ok(meBody(smartWorkingToday: true)));
      await service.refresh();

      expect(repo.smartWorkingTodayFor('user-a'), isTrue);
      expect(repo.smartWorkingTodayFor('user-b'), isNull);
      // No identifiable session (a service built without the guard) reads unknown too.
      expect(repo.smartWorkingTodayFor(null), isNull);
    });
  });

  group('smartWorkingTodayProvider', () {
    /// The container owns its own [EntitlementRepository], so every test below sets the flag on
    /// that instance — a flag set on the local `repo` would prove nothing.
    ProviderContainer containerWith({
      required Stream<AuthUser?> auth,
      Override? serviceOverride,
    }) {
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          authStateProvider.overrideWith((ref) => auth),
          ?serviceOverride,
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('signedOut_reportsUnknown', () async {
      final container = containerWith(auth: Stream<AuthUser?>.value(null));
      // The flag the previous signed-in user left behind in this process's memory.
      container
          .read(entitlementRepositoryProvider)
          .setSmartWorkingToday(true, ownerId: 'user-a');

      await container.read(authStateProvider.future);

      expect(container.read(smartWorkingTodayProvider), isNull);
    });

    test('signedIn_reportsWhatTheServerLastSaid', () async {
      final container = containerWith(auth: Stream<AuthUser?>.value(_user('user-a')));
      await container.read(authStateProvider.future);

      expect(container.read(smartWorkingTodayProvider), isNull);

      container
          .read(entitlementRepositoryProvider)
          .setSmartWorkingToday(false, ownerId: 'user-a');
      container.invalidate(smartWorkingTodayProvider);

      expect(container.read(smartWorkingTodayProvider), isFalse);
    });

    test('differentUser_signsIn_reportsUnknown', () async {
      final auth = StreamController<AuthUser?>.broadcast();
      addTearDown(auth.close);
      final container = containerWith(auth: auth.stream);
      // Subscribe before the first event, the way the UI does: a broadcast stream drops events
      // that nobody is listening for.
      container.listen(authStateProvider, (_, _) {});
      container
          .read(entitlementRepositoryProvider)
          .setSmartWorkingToday(true, ownerId: 'user-a');

      auth.add(_user('user-a'));
      await pumpEventQueue();
      expect(container.read(smartWorkingTodayProvider), isTrue);

      // B signs in on the shared tablet while offline: no `/me` answers for B in between, and A's
      // approved day must not follow B. Without the owner check that window is unbounded.
      auth.add(_user('user-b'));
      await pumpEventQueue();
      expect(container.read(smartWorkingTodayProvider), isNull);
    });

    testWidgets('refreshEntitlements_makesTheNewAnswerVisible', (tester) async {
      stub(ok(meBody(smartWorkingToday: true)));
      final container = containerWith(
        auth: Stream<AuthUser?>.value(_user('user-a')),
        serviceOverride: entitlementServiceProvider.overrideWith(
          (ref) => EntitlementService(
            dio: dio,
            repository: ref.watch(entitlementRepositoryProvider),
            currentSessionId: () => 'user-a',
          ),
        ),
      );
      await container.read(authStateProvider.future);

      late WidgetRef widgetRef;
      await tester.pumpWidget(
        // The same container, so the provider state read below is the one the widget layer sees.
        UncontrolledProviderScope(
          container: container,
          child: Consumer(
            builder: (context, ref, _) {
              widgetRef = ref;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      // Cached at unknown, exactly as Task 3's first frame would see it.
      expect(container.read(smartWorkingTodayProvider), isNull);

      await refreshEntitlements(widgetRef);

      // Without the invalidation inside refreshEntitlements this stays null forever: nothing else
      // the refresh touches is a dependency of this provider.
      expect(container.read(smartWorkingTodayProvider), isTrue);
    });
  });
}
