import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/core/time/business_time.dart';
import 'package:tasktap_mobile/core/time/business_time_providers.dart' show businessTimeProvider;
import 'package:tasktap_mobile/core/widgets/detail/detail_hero.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/sync/connectivity_provider.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart' show appDatabaseProvider;
import 'package:tasktap_mobile/features/dashboard/active_trackers_provider.dart' show nowProvider;
import 'package:tasktap_mobile/features/ticket/ticket_providers.dart';
import 'package:tasktap_mobile/features/ticket/ticket_timer_hero.dart';
import 'package:tasktap_mobile/features/ticket/ticket_workflow_api_client.dart';
import 'package:tasktap_mobile/presentation/providers/auth_providers.dart'
    show internalUserIdProvider;

class _ActionProbe extends ConsumerWidget {
  const _ActionProbe({required this.onAction});

  final void Function(DetailAction action) onAction;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    onAction(ticketTimerAction(context, ref, 't1'));
    return const SizedBox.shrink();
  }
}

class _TimerHarness extends ConsumerWidget {
  const _TimerHarness();

  @override
  Widget build(BuildContext context, WidgetRef ref) => DetailHero(
    data: DetailHeroData(
      variant: DetailHeroVariant.operational,
      title: 'Ticket',
      status: const DetailStatus(label: 'Aperto'),
      liveValue: const TicketTimerLiveValue(ticketId: 't1'),
      primaryAction: ticketTimerAction(context, ref, 't1'),
    ),
  );
}

class _ScriptedWorkflowClient extends TicketWorkflowApiClient {
  _ScriptedWorkflowClient() : super(Dio());

  int starts = 0;
  int stops = 0;
  TicketWorkflowFailure? failure;

  @override
  Future<TicketTimerStart> startTimer(
    String ticketId, {
    String? clientId,
    DateTime? deviceUtc,
  }) async {
    starts++;
    final f = failure;
    if (f != null) throw f;
    return const TicketTimerStart(id: 'w1', isActive: true);
  }

  @override
  Future<int?> stopTimer(String ticketId, {String? clientId, DateTime? deviceUtc}) async {
    stops++;
    final f = failure;
    if (f != null) throw f;
    return null;
  }
}

TicketWorkLogDto _running() => TicketWorkLogDto(
  id: 'w1',
  ticketId: 't1',
  userId: 'u1',
  workDate: DateTime.utc(2026, 7, 10),
  startTime: const Duration(hours: 10),
  isManualEntry: false,
);

void main() {
  /// Pumps the timer hero with a worklogs answer already scripted, so no test reaches the DB or
  /// the network through that provider. The offline case goes through the real provider instead,
  /// because how it reports "no mirror" is exactly what is under test.
  Future<void> pumpHero(
    WidgetTester tester, {
    required List<Override> overrides,
    bool settle = true,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides,
        child: const MaterialApp(home: Scaffold(body: _TimerHarness())),
      ),
    );
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      // A running timer draws [LiveDot], whose pulse never settles.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('offline timer shows the reason without hiding the action', (tester) async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    await pumpHero(
      tester,
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        businessTimeProvider.overrideWithValue(BusinessTime('Europe/Rome')),
        isOnlineProvider.overrideWithValue(false),
      ],
    );

    expect(find.text('Timer non disponibile offline'), findsOneWidget);
    expect(find.text('Avvia intervento'), findsOneWidget);
  });

  testWidgets('offline action stays enabled so the offline queue can run', (tester) async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    late DetailAction action;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          businessTimeProvider.overrideWithValue(BusinessTime('Europe/Rome')),
          isOnlineProvider.overrideWithValue(false),
        ],
        child: MaterialApp(
          home: Scaffold(body: _ActionProbe(onAction: (value) => action = value)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(action.enabled, isTrue);
    expect(action.onPressed, isNotNull);
  });

  testWidgets('idle timer says no timer is active and offers a start', (tester) async {
    await pumpHero(
      tester,
      overrides: [
        isOnlineProvider.overrideWithValue(true),
        businessTimeProvider.overrideWithValue(BusinessTime('Europe/Rome')),
        ticketWorklogsProvider('t1').overrideWith((ref) async => const <TicketWorkLogDto>[]),
      ],
    );

    expect(find.text('Nessun timer attivo'), findsOneWidget);
    expect(find.text('Avvia intervento'), findsOneWidget);
    expect(find.text('Chiudi intervento'), findsNothing);
  });

  testWidgets('a running timer ticks and offers a close', (tester) async {
    await pumpHero(
      tester,
      overrides: [
        isOnlineProvider.overrideWithValue(true),
        businessTimeProvider.overrideWithValue(BusinessTime('Europe/Rome')),
        nowProvider.overrideWith((ref) => Stream.value(DateTime.utc(2026, 7, 10, 8, 5))),
        ticketWorklogsProvider('t1').overrideWith((ref) async => [_running()]),
      ],
      settle: false,
    );

    expect(find.text('05:00'), findsOneWidget);
    expect(find.text('Chiudi intervento'), findsOneWidget);
    expect(find.text('Avvia intervento'), findsNothing);
  });

  testWidgets('the action starts the clock and refreshes the worklogs', (tester) async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final client = _ScriptedWorkflowClient();

    await pumpHero(
      tester,
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        internalUserIdProvider.overrideWith((ref) async => 'user-1'),
        isOnlineProvider.overrideWithValue(true),
        businessTimeProvider.overrideWithValue(BusinessTime('Europe/Rome')),
        ticketWorkflowApiClientProvider.overrideWithValue(client),
        ticketWorklogsProvider('t1').overrideWith((ref) async => const <TicketWorkLogDto>[]),
      ],
    );

    await tester.tap(find.text('Avvia intervento'));
    await tester.pumpAndSettle();

    expect(client.starts, 1);
    expect(client.stops, 0);
  });

  testWidgets('the action stops the clock when it is running', (tester) async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final client = _ScriptedWorkflowClient();

    await pumpHero(
      tester,
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        isOnlineProvider.overrideWithValue(true),
        businessTimeProvider.overrideWithValue(BusinessTime('Europe/Rome')),
        nowProvider.overrideWith((ref) => Stream.value(DateTime.utc(2026, 7, 10, 8, 5))),
        ticketWorkflowApiClientProvider.overrideWithValue(client),
        ticketWorklogsProvider('t1').overrideWith((ref) async => [_running()]),
      ],
      settle: false,
    );

    await tester.tap(find.text('Chiudi intervento'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(client.stops, 1);
    expect(client.starts, 0);
  });

  testWidgets('a workflow failure is shown instead of swallowed', (tester) async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final options = RequestOptions(path: '/x');
    final client = _ScriptedWorkflowClient()
      ..failure = TicketWorkflowFailure(
        'Errore del timer',
        cause: DioException(
          requestOptions: options,
          type: DioExceptionType.badResponse,
          response: Response<dynamic>(requestOptions: options, statusCode: 400),
        ),
      );

    await pumpHero(
      tester,
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        isOnlineProvider.overrideWithValue(true),
        businessTimeProvider.overrideWithValue(BusinessTime('Europe/Rome')),
        ticketWorkflowApiClientProvider.overrideWithValue(client),
        ticketWorklogsProvider('t1').overrideWith((ref) async => const <TicketWorkLogDto>[]),
      ],
    );

    await tester.tap(find.text('Avvia intervento'));
    await tester.pumpAndSettle();

    expect(find.text('Errore del timer'), findsOneWidget);
  });
}
