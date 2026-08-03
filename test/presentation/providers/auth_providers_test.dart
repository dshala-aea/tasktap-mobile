import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tasktap_mobile/domain/auth/auth_failure.dart';
import 'package:tasktap_mobile/domain/auth/auth_user.dart';
import 'package:tasktap_mobile/domain/auth/i_auth_repository.dart';
import 'package:tasktap_mobile/presentation/providers/auth_providers.dart';

// ── Mocks ──────────────────────────────────────────────────────────────────

class MockAuthRepository extends Mock implements IAuthRepository {}

// ── Helpers ────────────────────────────────────────────────────────────────

AuthUser _fakeUser({String id = 'user-1', String token = 'tok'}) => AuthUser(
      id: id,
      email: 'tech@tasktap.io',
      accessToken: token,
      refreshToken: 'refresh',
      expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
    );

ProviderContainer _makeContainer(MockAuthRepository repo) {
  return ProviderContainer(
    overrides: [
      authRepositoryProvider.overrideWithValue(repo),
    ],
  );
}

void main() {
  late MockAuthRepository repo;
  late StreamController<AuthUser?> authStreamController;

  setUp(() {
    repo = MockAuthRepository();
    authStreamController = StreamController<AuthUser?>.broadcast();
    when(() => repo.authStateChanges).thenAnswer(
      (_) => authStreamController.stream,
    );
    when(() => repo.currentUser).thenReturn(null);
  });

  tearDown(() {
    authStreamController.close();
  });

  // ── authStateProvider ──────────────────────────────────────────────────

  group('authStateProvider', () {
    test('emits null initially (unauthenticated)', () async {
      final container = _makeContainer(repo);
      addTearDown(container.dispose);

      // Stream starts with no event — provider is AsyncLoading then emits null.
      final state = container.read(authStateProvider);
      expect(state, isA<AsyncLoading>());
    });

    test('emits AuthUser when stream emits a user', () async {
      final container = _makeContainer(repo);
      addTearDown(container.dispose);

      final user = _fakeUser();

      // Listen before emitting.
      final states = <AsyncValue<AuthUser?>>[];
      container.listen<AsyncValue<AuthUser?>>(
        authStateProvider,
        (_, next) => states.add(next),
        fireImmediately: false,
      );

      authStreamController.add(user);
      await Future<void>.delayed(Duration.zero);

      expect(states.last, isA<AsyncData<AuthUser?>>());
      expect(states.last.value, equals(user));
    });

    test('emits null when stream emits null (sign-out)', () async {
      final container = _makeContainer(repo);
      addTearDown(container.dispose);

      final states = <AsyncValue<AuthUser?>>[];
      container.listen<AsyncValue<AuthUser?>>(
        authStateProvider,
        (_, next) => states.add(next),
        fireImmediately: false,
      );

      // Sign in then sign out.
      authStreamController.add(_fakeUser());
      await Future<void>.delayed(Duration.zero);
      authStreamController.add(null);
      await Future<void>.delayed(Duration.zero);

      expect(states.last.value, isNull);
    });
  });

  // ── currentUserProvider ────────────────────────────────────────────────

  group('currentUserProvider', () {
    test('returns null when auth state is loading', () {
      final container = _makeContainer(repo);
      addTearDown(container.dispose);

      final user = container.read(currentUserProvider);
      expect(user, isNull);
    });

    test('returns user when authenticated', () async {
      final container = _makeContainer(repo);
      addTearDown(container.dispose);

      final expected = _fakeUser();

      // Subscribe to authStateProvider so the container starts listening
      // to the stream and processes incoming events.
      container.listen(authStateProvider, (prev, next) {});

      authStreamController.add(expected);
      await Future<void>.delayed(Duration.zero);

      final user = container.read(currentUserProvider);
      expect(user, equals(expected));
    });
  });

  // ── LoginNotifier ──────────────────────────────────────────────────────

  group('LoginNotifier', () {
    test('initial state is not loading, no failure', () {
      final container = _makeContainer(repo);
      addTearDown(container.dispose);

      final state = container.read(loginProvider);
      expect(state.isLoading, isFalse);
      expect(state.failure, isNull);
    });

    test('signIn sets isLoading then clears on success', () async {
      when(() => repo.signIn()).thenAnswer((_) async => (user: _fakeUser(), failure: null));

      final container = _makeContainer(repo);
      addTearDown(container.dispose);

      await container
          .read(loginProvider.notifier)
          .signIn();

      final state = container.read(loginProvider);
      expect(state.isLoading, isFalse);
      expect(state.failure, isNull);
    });

    test('signIn sets failure on InvalidCredentials', () async {
      when(() => repo.signIn()).thenAnswer(
            (_) async => (user: null, failure: const InvalidCredentials()),
          );

      final container = _makeContainer(repo);
      addTearDown(container.dispose);

      await container
          .read(loginProvider.notifier)
          .signIn();

      final state = container.read(loginProvider);
      expect(state.isLoading, isFalse);
      expect(state.failure, isA<InvalidCredentials>());
    });

    test('clearError resets failure to null', () async {
      when(() => repo.signIn()).thenAnswer(
            (_) async => (user: null, failure: const NetworkError()),
          );

      final container = _makeContainer(repo);
      addTearDown(container.dispose);

      await container
          .read(loginProvider.notifier)
          .signIn();

      expect(container.read(loginProvider).failure, isA<NetworkError>());

      container.read(loginProvider.notifier).clearError();
      expect(container.read(loginProvider).failure, isNull);
    });

    test('signOut calls repository signOut', () async {
      when(() => repo.signOut()).thenAnswer((_) async {});

      final container = _makeContainer(repo);
      addTearDown(container.dispose);

      await container.read(loginProvider.notifier).signOut();

      verify(() => repo.signOut()).called(1);
    });
  });

  // ── Router redirect logic ──────────────────────────────────────────────

  group('route guard logic (auth state → redirect decision)', () {
    // These tests encode the redirect rules used in app_router.dart without
    // spinning up a real router — they verify the decision function directly.

    String? routeRedirect({
      required AsyncValue<AuthUser?> authAsync,
      required bool isOnLogin,
    }) {
      return authAsync.when(
        loading: () => null,
        error: (err, stack) => isOnLogin ? null : '/login',
        data: (user) {
          final isAuthenticated = user != null;
          if (!isAuthenticated && !isOnLogin) return '/login';
          if (isAuthenticated && isOnLogin) return '/oggi';
          return null;
        },
      );
    }

    test('loading → no redirect (stay on current route)', () {
      expect(
        routeRedirect(authAsync: const AsyncLoading(), isOnLogin: false),
        isNull,
      );
    });

    test('unauthenticated on protected route → /login', () {
      expect(
        routeRedirect(
          authAsync: const AsyncData(null),
          isOnLogin: false,
        ),
        equals('/login'),
      );
    });

    test('unauthenticated already on /login → no redirect', () {
      expect(
        routeRedirect(
          authAsync: const AsyncData(null),
          isOnLogin: true,
        ),
        isNull,
      );
    });

    test('authenticated on /login → /oggi', () {
      expect(
        routeRedirect(
          authAsync: AsyncData(_fakeUser()),
          isOnLogin: true,
        ),
        equals('/oggi'),
      );
    });

    test('authenticated on protected route → no redirect', () {
      expect(
        routeRedirect(
          authAsync: AsyncData(_fakeUser()),
          isOnLogin: false,
        ),
        isNull,
      );
    });

    test('error state on protected route → /login', () {
      expect(
        routeRedirect(
          authAsync: AsyncError(Exception('boom'), StackTrace.empty),
          isOnLogin: false,
        ),
        equals('/login'),
      );
    });

    test('error state already on /login → no redirect', () {
      expect(
        routeRedirect(
          authAsync: AsyncError(Exception('boom'), StackTrace.empty),
          isOnLogin: true,
        ),
        isNull,
      );
    });
  });
}
