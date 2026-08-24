// dart format width=100
// test/features/rapportino/steps/step_dettagli_test.dart
//
// Widget tests for StepDettagli's "Bozza automatica" (AI draft) button.
//
// The gap: AiApiClient.generateDraft accepts a `voiceTranscript` parameter, and the backend's
// ReportContextBuilder folds it into the AI prompt ("Nota Vocale Tecnico"), but the button never
// passed it. On-device dictation (DictateButton) writes into the same `details` field the AI
// draft is meant to replace/augment — it is the only place dictated text is ever held in editor
// state (DictateButton has no separate transcript output — see dictate_button.dart) — so the
// fix is to forward whatever is currently in `details` as `voiceTranscript` before it is
// overwritten by the generated draft.
//
// Verifies:
//   - a populated `details` field (simulating dictated notes) is passed through as
//     voiceTranscript when "Genera" is pressed.
//   - an empty `details` field results in no voiceTranscript being sent (null, not '').

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tasktap_mobile/data/ai/ai_api_client.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/reports/draft_report_repository.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart';
import 'package:tasktap_mobile/features/rapportino/steps/step_dettagli.dart';
import 'package:tasktap_mobile/presentation/providers/report_editor_providers.dart';

const _reportId = 'draft-1';

/// Records the arguments `generateDraft` was called with, instead of hitting the network.
class _RecordingAiApiClient extends AiApiClient {
  _RecordingAiApiClient() : super(Dio());

  String? capturedVoiceTranscript;
  int calls = 0;
  bool voiceTranscriptWasPassed = false;

  @override
  Future<AiReportDraftDto> generateDraft({
    required String scheduleId,
    String? ticketId,
    String? voiceTranscript,
  }) async {
    calls++;
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
            scheduleId: 'sched-1',
            details: details,
          ),
          repo: DraftReportRepository(db),
        ),
      ),
    ],
  );
}

Widget _buildStep(ProviderContainer container) {
  return UncontrolledProviderScope(
    container: container,
    child: const MaterialApp(
      home: Scaffold(body: StepDettagli(reportId: _reportId)),
    ),
  );
}

void main() {
  late AppDatabase db;

  setUp(() => db = _makeDb());
  tearDown(() async => db.close());

  group('StepDettagli — AI draft voiceTranscript wiring', () {
    testWidgets('a populated details field (dictated notes) is passed as voiceTranscript', (
      tester,
    ) async {
      final aiClient = _RecordingAiApiClient();
      final container = _buildContainer(db: db, aiClient: aiClient, details: 'Nota dettata a voce');
      addTearDown(container.dispose);

      await tester.pumpWidget(_buildStep(container));
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

      await tester.pumpWidget(_buildStep(container));
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
