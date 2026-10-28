import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:tasktap_mobile/core/router/app_router.dart';
import 'package:tasktap_mobile/data/auth/session_ender.dart';
import 'package:tasktap_mobile/data/auth/session_recovery_providers.dart';
import 'package:tasktap_mobile/data/auth/unsent_work_counter.dart';
import 'package:tasktap_mobile/data/badge/badge_api_client.dart';
import 'package:tasktap_mobile/data/badge/badge_models.dart';
import 'package:tasktap_mobile/data/entitlements/entitlement_providers.dart';
import 'package:tasktap_mobile/domain/auth/i_auth_repository.dart';
import 'package:tasktap_mobile/features/altro/altro_hub_screen.dart';
import 'package:tasktap_mobile/features/badge/badge_providers.dart';
import 'package:tasktap_mobile/features/badge/my_badge_screen.dart';
import 'package:tasktap_mobile/presentation/providers/auth_providers.dart';

BadgeCard _card(String token, {String? photoUrl}) => BadgeCard(
  badgeId: 'b1',
  token: token,
  expiresInSeconds: 60,
  displayName: 'Mario Rossi',
  photoUrl: photoUrl,
  employerName: 'Edilizia Bianchi Srl',
  status: 'Attivo',
);

/// Hands out queued results one per call; the last one repeats.
class _FakeBadgeApi implements BadgeApiClient {
  _FakeBadgeApi(this.results);
  final List<Object> results; // BadgeCard | Object to throw
  int calls = 0;
  Completer<BadgeCard>? gate;

  @override
  Future<BadgeCard> getMyBadge() async {
    final i = calls < results.length ? calls : results.length - 1;
    calls++;
    if (gate != null) return gate!.future;
    final r = results[i];
    if (r is BadgeCard) return r;
    throw r;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeWakelock implements BadgeWakelock {
  int enables = 0;
  int disables = 0;
  @override
  Future<void> enable() async => enables++;
  @override
  Future<void> disable() async => disables++;
}

class _MockUnsentWorkCounter extends Mock implements UnsentWorkCounter {}

class _MockUnsentWorkFlusher extends Mock implements UnsentWorkFlusher {}

class _MockSessionEnder extends Mock implements SessionEnder {}

class _MockAuthRepository extends Mock implements IAuthRepository {}

const _interval = Duration(seconds: 25);

void main() {
  late _FakeWakelock wake;

  setUp(() => wake = _FakeWakelock());

  Future<void> pumpScreen(WidgetTester tester, _FakeBadgeApi api) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          badgeApiClientProvider.overrideWithValue(api),
          badgeWakelockProvider.overrideWithValue(wake),
          badgeRefreshIntervalProvider.overrideWithValue(_interval),
        ],
        child: const MaterialApp(home: MyBadgeScreen()),
      ),
    );
    // Fetch microtask + completion.
    await tester.pump();
    await tester.pump();
  }

  String? qrData(WidgetTester tester) {
    final f = find.byType(BadgeQrCode);
    if (f.evaluate().isEmpty) return null;
    return tester.widget<BadgeQrCode>(f).data;
  }

  Future<void> background(WidgetTester tester) async {
    for (final s in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(s);
    }
    await tester.pump();
  }

  Future<void> foreground(WidgetTester tester) async {
    for (final s in [
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(s);
    }
  }

  testWidgets('shows_photo_name_employer_and_qr_when_ready', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          badgeApiClientProvider.overrideWithValue(
            _FakeBadgeApi([_card('tok-1', photoUrl: 'https://example.test/p.jpg')]),
          ),
          badgeWakelockProvider.overrideWithValue(wake),
        ],
        child: const MaterialApp(home: MyBadgeScreen()),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Mario Rossi'), findsOneWidget);
    expect(find.text('Edilizia Bianchi Srl'), findsOneWidget);
    expect(find.text('Attivo'), findsOneWidget);
    expect(find.byKey(const ValueKey('badge-photo')), findsOneWidget);
    expect(qrData(tester), 'tok-1');
    // The code sits on a white card whatever the theme.
    final qr = tester.widget<QrImageView>(find.byType(QrImageView));
    expect(qr.backgroundColor, Colors.white);
    expect(wake.enables, 1);

    await tester.pumpWidget(const SizedBox());
    expect(wake.disables, 1);
  });

  testWidgets('no_photo_shows_initials_placeholder', (tester) async {
    await pumpScreen(tester, _FakeBadgeApi([_card('t')]));
    expect(find.byKey(const ValueKey('badge-initials')), findsOneWidget);
    expect(find.text('MR'), findsOneWidget);
    expect(find.byKey(const ValueKey('badge-photo')), findsNothing);
  });

  testWidgets('revoked_409_shows_disattivato_message_no_qr_no_retry_loop', (tester) async {
    final api = _FakeBadgeApi([
      const BadgeApiException(statusCode: 409, code: 'badge_revoked', message: 'x'),
    ]);
    await pumpScreen(tester, api);

    expect(find.text('Badge disattivato — contatta l\'ufficio'), findsOneWidget);
    expect(find.byType(QrImageView), findsNothing);
    expect(find.text('Riprova'), findsNothing);
    await tester.pump(_interval * 3);
    expect(api.calls, 1);
  });

  testWidgets('inactive_shows_account_disattivato', (tester) async {
    final api = _FakeBadgeApi([
      const BadgeApiException(statusCode: 409, code: 'user_inactive', message: 'x'),
    ]);
    await pumpScreen(tester, api);

    expect(find.text('Account disattivato — contatta l\'ufficio'), findsOneWidget);
    expect(find.byType(QrImageView), findsNothing);
    await tester.pump(_interval * 3);
    expect(api.calls, 1);
  });

  group('offline_hides_qr_and_shows_offline_notice', () {
    const offlineText = 'Nessuna connessione — il badge richiede il segnale. Riprova';

    for (final entry in <String, Object>{
      'connection error': const BadgeApiException(message: 'net', offline: true),
      '503': const BadgeApiException(statusCode: 503, message: 'down'),
      'malformed body (TypeError)': TypeError(),
      'empty body (StateError)': StateError('empty'),
    }.entries) {
      testWidgets(entry.key, (tester) async {
        await pumpScreen(tester, _FakeBadgeApi([entry.value]));
        expect(find.text(offlineText), findsOneWidget);
        expect(find.widgetWithText(ElevatedButton, 'Riprova').evaluate().isNotEmpty ||
            find.text('Riprova').evaluate().isNotEmpty, isTrue);
        expect(find.byType(QrImageView), findsNothing);
      });
    }

    testWidgets('Riprova refetches and shows the QR on success', (tester) async {
      final api = _FakeBadgeApi([
        const BadgeApiException(message: 'net', offline: true),
        _card('tok-ok'),
      ]);
      await pumpScreen(tester, api);
      expect(qrData(tester), isNull);

      await tester.tap(find.text('Riprova'));
      await tester.pump();
      await tester.pump();
      expect(qrData(tester), 'tok-ok');
    });
  });

  testWidgets('a failed refresh hides the previous QR', (tester) async {
    final api = _FakeBadgeApi([
      _card('tok-1'),
      const BadgeApiException(message: 'net', offline: true),
    ]);
    await pumpScreen(tester, api);
    expect(qrData(tester), 'tok-1');

    await tester.pump(_interval);
    await tester.pump();
    expect(qrData(tester), isNull);
    expect(find.textContaining('Nessuna connessione'), findsOneWidget);
  });

  testWidgets('refreshes_token_on_interval', (tester) async {
    final api = _FakeBadgeApi([_card('tok-1'), _card('tok-2')]);
    await pumpScreen(tester, api);
    expect(qrData(tester), 'tok-1');
    expect(api.calls, 1);

    await tester.pump(_interval - const Duration(seconds: 1));
    expect(api.calls, 1);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(api.calls, 2);
    expect(qrData(tester), 'tok-2');
  });

  testWidgets('timers_stop_on_dispose', (tester) async {
    final api = _FakeBadgeApi([_card('tok-1')]);
    await pumpScreen(tester, api);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(_interval * 4);
    expect(api.calls, 1);
  });

  testWidgets('resume_refetches_before_showing_qr', (tester) async {
    final api = _FakeBadgeApi([_card('tok-1'), _card('tok-2')]);
    await pumpScreen(tester, api);
    expect(qrData(tester), 'tok-1');

    await background(tester);
    // Backgrounded (frames are off, so read the controller, not the tree): the old code is gone
    // and no timer fires.
    final container = ProviderScope.containerOf(tester.element(find.byType(MyBadgeScreen)));
    expect(container.read(badgeControllerProvider), isA<BadgeLoading>());
    await tester.pump(_interval * 3);
    expect(api.calls, 1);

    // Resume with the fetch held open: loading, still no QR.
    api.gate = Completer<BadgeCard>();
    await foreground(tester);
    await tester.pump();
    expect(api.calls, 2);
    expect(qrData(tester), isNull);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    api.gate!.complete(_card('tok-2'));
    await tester.pump();
    await tester.pump();
    expect(qrData(tester), 'tok-2');
  });

  testWidgets('uses_semantics_for_status', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpScreen(tester, _FakeBadgeApi([_card('t')]));

    final node = tester.getSemantics(find.text('Attivo'));
    expect(node.flagsCollection.isLiveRegion, isTrue);
    handle.dispose();
  });

  testWidgets('uses_semantics_for_error_message', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpScreen(
      tester,
      _FakeBadgeApi([const BadgeApiException(statusCode: 409, code: 'badge_revoked', message: 'x')]),
    );
    final node = tester.getSemantics(find.textContaining('Badge disattivato'));
    expect(node.flagsCollection.isLiveRegion, isTrue);
    handle.dispose();
  });

  testWidgets('the Altro hub has an "Il mio badge" tile that opens the badge route', (
    tester,
  ) async {
    final counter = _MockUnsentWorkCounter();
    final flusher = _MockUnsentWorkFlusher();
    final ender = _MockSessionEnder();
    final repo = _MockAuthRepository();
    when(() => repo.authStateChanges).thenAnswer((_) => const Stream.empty());

    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (_, _) => const AltroHubScreen()),
        GoRoute(path: AppRoutes.altroBadge, builder: (_, _) => const Text('BADGE-ROUTE')),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          unsentWorkCounterProvider.overrideWithValue(counter),
          unsentWorkFlusherProvider.overrideWithValue(flusher),
          sessionEnderProvider.overrideWithValue(ender),
          authRepositoryProvider.overrideWithValue(repo),
          cachedEntitlementProvider.overrideWith((ref) async => null),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    await tester.dragUntilVisible(
      find.text('Il mio badge'),
      find.byType(CustomScrollView),
      const Offset(0, -200),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Il mio badge'));
    await tester.pumpAndSettle();
    expect(find.text('BADGE-ROUTE'), findsOneWidget);
  });
}
