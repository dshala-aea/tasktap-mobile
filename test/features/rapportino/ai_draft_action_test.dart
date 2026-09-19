// dart format width=100
// test/features/rapportino/ai_draft_action_test.dart
//
// Widget tests for AiDraftAction — the top-level "Bozza automatica" AI-draft action, promoted out
// of step_dettagli.dart's buried `_AiDraftButton` onto RapportinoFormScreen itself (see
// ai_draft_action.dart's own header comment).
//
// Verifies:
//   - it always renders, even with nothing to draft from — disabled, with an explanation, not
//     hidden (the behavior change from the old _AiDraftButton, which returned SizedBox.shrink()).
//   - it renders enabled with quota text when a scheduleId, ticketId, cantiereId, or typed/dictated
//     details text is present — mirroring the backend's tiered context resolution, which now
//     accepts any of the four and only 400s when none are given.
//   - AiApiClient.generateDraft accepts a `voiceTranscript` parameter, and the backend folds it
//     into the AI prompt ("Nota Vocale Tecnico") — a populated `details` field (simulating
//     dictated notes) is passed through as voiceTranscript when "Genera" is pressed, and an empty
//     one results in no voiceTranscript being sent (null, not '').
//   - the right combination of scheduleId/ticketId/cantiereId/voiceTranscript reaches
//     generateDraft for each availability case.

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tasktap_mobile/core/widgets/widgets.dart';
import 'package:tasktap_mobile/data/ai/ai_api_client.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/reports/draft_report_repository.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart';
import 'package:tasktap_mobile/features/rapportino/ai_draft_action.dart';
import 'package:tasktap_mobile/presentation/providers/report_editor_providers.dart';

const _reportId = 'draft-1';

/// Records the arguments `generateDraft` was called with, instead of hitting the network.
class _RecordingAiApiClient extends AiApiClient {
  _RecordingAiApiClient() : super(Dio());

  String? capturedScheduleId;
  String? capturedTicketId;
  String? capturedCantiereId;
  String? capturedVoiceTranscript;
  int calls = 0;
  bool voiceTranscriptWasPassed = false;

  @override
  Future<AiReportDraftDto> generateDraft({
    String? scheduleId,
    String? ticketId,
    String? cantiereId,
    String? voiceTranscript,
  }) async {
    calls++;
    capturedScheduleId = scheduleId;
    capturedTicketId = ticketId;
    capturedCantiereId = cantiereId;
    capturedVoiceTranscript = voiceTranscript;
    voiceTranscriptWasPassed = true;
    return const AiReportDraftDto(title: 'Titolo AI', details: 'Descrizione AI', modelUsed: 'test-model');
  }

  @override
  Future<AiQuotaDto> getQuota() async {
    return const AiQuotaDto(monthlyLimit: 10, used: 1, remaining: 9);
  }
}

AppDatabase _makeDb() => AppDatabase(NativeDatabase.memory());

ProviderContainer _buildContainer({
  required AppDatabase db,
  required _RecordingAiApiClient aiClient,
  String details = '',
  String? scheduleId = 'sched-1',
  String? ticketId,
  String? cantiereId,
}) {
  return ProviderContainer(
    overrides: [
      appDatabaseProvider.overrideWithValue(db),
      aiApiClientProvider.overrideWithValue(aiClient),
      reportEditorProvider(_reportId).overrideWith(
        (ref) => ReportEditorNotifier(
          initialState: ReportEditorState(
            reportId: _reportId,
            tenantId: 'tenant-1',
            insertedUserId: 'user-1',
            scheduleId: scheduleId,
            details: details,
            ticketId: ticketId,
            cantiereId: cantiereId,
          ),
          repo: DraftReportRepository(db),
        ),
      ),
    ],
  );
}

Widget _buildAction(ProviderContainer container) {
  return UncontrolledProviderScope(
    container: container,
    child: const MaterialApp(
      home: Scaffold(body: AiDraftAction(reportId: _reportId)),
    ),
  );
}

void main() {
  late AppDatabase db;

  setUp(() => db = _makeDb());
  tearDown(() async => db.close());

  group('AiDraftAction — visibility with nothing to draft from', () {
    testWidgets(
      'renders visibly but disabled, with an explanation, when schedule/ticket/cantiere/details '
      'are all absent',
      (tester) async {
        final aiClient = _RecordingAiApiClient();
        final container = _buildContainer(db: db, aiClient: aiClient, scheduleId: null);
        addTearDown(container.dispose);

        await tester.pumpWidget(_buildAction(container));
        await tester.pumpAndSettle();

        // Unlike the old _AiDraftButton (SizedBox.shrink() with no scheduleId), the card itself
        // and its title must still be on screen.
        expect(find.text('Bozza automatica'), findsOneWidget);
        expect(find.text('Genera'), findsOneWidget);
        expect(tester.widget<AppButton>(find.byType(AppButton)).onPressed, isNull);

        expect(
          find.text(
            'Aggiungi un ticket o un cantiere, oppure scrivi o detta qualcosa in Descrizione '
            'prima di generare la bozza AI.',
          ),
          findsOneWidget,
        );
      },
    );
  });

  group('AiDraftAction — enabled with a schedule', () {
    testWidgets('renders enabled with quota text when scheduleId is present', (tester) async {
      final aiClient = _RecordingAiApiClient();
      final container = _buildContainer(db: db, aiClient: aiClient);
      addTearDown(container.dispose);

      await tester.pumpWidget(_buildAction(container));
      await tester.pumpAndSettle();

      expect(find.text('Bozza automatica'), findsOneWidget);
      expect(find.text('9 generazioni rimaste all\'azienda questo mese'), findsOneWidget);
      expect(tester.widget<AppButton>(find.byType(AppButton)).onPressed, isNotNull);
    });
  });

  group('AiDraftAction — enabled with only a ticket, only a cantiere, or only typed text', () {
    testWidgets('renders enabled when only ticketId is present (no schedule)', (tester) async {
      final aiClient = _RecordingAiApiClient();
      final container = _buildContainer(
        db: db,
        aiClient: aiClient,
        scheduleId: null,
        ticketId: 'ticket-1',
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(_buildAction(container));
      await tester.pumpAndSettle();

      expect(tester.widget<AppButton>(find.byType(AppButton)).onPressed, isNotNull);

      await tester.tap(find.text('Genera'));
      await tester.pumpAndSettle();

      expect(aiClient.calls, 1);
      expect(aiClient.capturedScheduleId, isNull);
      expect(aiClient.capturedTicketId, 'ticket-1');
      expect(aiClient.capturedCantiereId, isNull);
    });

    testWidgets('renders enabled when only cantiereId is present (no schedule, no ticket)', (
      tester,
    ) async {
      final aiClient = _RecordingAiApiClient();
      final container = _buildContainer(
        db: db,
        aiClient: aiClient,
        scheduleId: null,
        cantiereId: 'cantiere-1',
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(_buildAction(container));
      await tester.pumpAndSettle();

      expect(tester.widget<AppButton>(find.byType(AppButton)).onPressed, isNotNull);

      await tester.tap(find.text('Genera'));
      await tester.pumpAndSettle();

      expect(aiClient.calls, 1);
      expect(aiClient.capturedScheduleId, isNull);
      expect(aiClient.capturedTicketId, isNull);
      expect(aiClient.capturedCantiereId, 'cantiere-1');
    });

    testWidgets('renders enabled when there are no ids but details text is already present', (
      tester,
    ) async {
      final aiClient = _RecordingAiApiClient();
      final container = _buildContainer(
        db: db,
        aiClient: aiClient,
        scheduleId: null,
        details: 'Sostituita guarnizione pompa',
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(_buildAction(container));
      await tester.pumpAndSettle();

      expect(tester.widget<AppButton>(find.byType(AppButton)).onPressed, isNotNull);

      await tester.tap(find.text('Genera'));
      await tester.pumpAndSettle();

      // details already has text, so the overwrite-confirmation dialog appears first.
      expect(find.text('Sostituire il testo?'), findsOneWidget);
      await tester.tap(find.text('Sostituisci'));
      await tester.pumpAndSettle();

      expect(aiClient.calls, 1);
      expect(aiClient.capturedScheduleId, isNull);
      expect(aiClient.capturedTicketId, isNull);
      expect(aiClient.capturedCantiereId, isNull);
      expect(aiClient.capturedVoiceTranscript, 'Sostituita guarnizione pompa');
    });
  });

  group('AiDraftAction — voiceTranscript wiring', () {
    testWidgets('a populated details field (dictated notes) is passed as voiceTranscript', (
      tester,
    ) async {
      final aiClient = _RecordingAiApiClient();
      final container = _buildContainer(db: db, aiClient: aiClient, details: 'Nota dettata a voce');
      addTearDown(container.dispose);

      await tester.pumpWidget(_buildAction(container));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Genera'));
      await tester.pumpAndSettle();

      // details already has text, so the overwrite-confirmation dialog appears first.
      expect(find.text('Sostituire il testo?'), findsOneWidget);
      await tester.tap(find.text('Sostituisci'));
      await tester.pumpAndSettle();

      expect(aiClient.calls, 1);
      expect(aiClient.capturedVoiceTranscript, 'Nota dettata a voce');
    });

    testWidgets('an empty details field passes no voiceTranscript', (tester) async {
      final aiClient = _RecordingAiApiClient();
      final container = _buildContainer(db: db, aiClient: aiClient, details: '');
      addTearDown(container.dispose);

      await tester.pumpWidget(_buildAction(container));
      await tester.pumpAndSettle();

      // Nothing typed yet, so "Genera" applies immediately with no overwrite prompt.
      await tester.tap(find.text('Genera'));
      await tester.pumpAndSettle();

      expect(aiClient.calls, 1);
      expect(aiClient.voiceTranscriptWasPassed, isTrue);
      expect(aiClient.capturedVoiceTranscript, isNull);
    });
  });
}
