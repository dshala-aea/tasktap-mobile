// dart format width=100
// test/features/rapportino/steps/step_riepilogo_failed_test.dart
//
// The Riepilogo step's `failed` branch, which used to be one shape for every failure: a red
// "Invio fallito" card and an enabled "Riprova invio" button. For a stale-submit conflict (the
// office edited the report since this phone last saw it) that button directly contradicted the
// card above it — the message says "Non riprovare a inviarlo" while the button resends the same
// stored request, same idempotency key and same stale `expectedVersion`, which is a guaranteed
// second 409. The button is now suppressed for that one message, and only that one: every other
// permanent failure (e.g. a 400 validation refusal, which the technician can fix by editing the
// draft and resending) must keep it, since editing does not reset `failed`.

import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/reports/draft_report_repository.dart';
import 'package:tasktap_mobile/data/sync/connectivity_provider.dart';
import 'package:tasktap_mobile/data/sync/submission_queue.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart';
import 'package:tasktap_mobile/data/users/user_signature_api_client.dart';
import 'package:tasktap_mobile/features/rapportino/steps/step_riepilogo.dart';
import 'package:tasktap_mobile/presentation/providers/report_editor_providers.dart';

const _reportId = 'draft-f';

class _NoSignature implements UserSignatureApiClient {
  const _NoSignature();
  @override
  Future<Uint8List?> fetchSavedSignatureContent() async => null;
  @override
  Future<UserSignatureUploadResult> uploadSignature(Uint8List bytes) =>
      throw UnimplementedError();
}

void main() {
  Future<void> pumpFailedDraft(WidgetTester tester, {required String error}) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db
        .into(db.draftReports)
        .insert(
          DraftReportsCompanion.insert(
            id: _reportId,
            tenantId: 'tenant-1',
            createdAt: DateTime.utc(2026, 1, 1),
            title: 'T',
            insertedUserId: 'user-1',
            locationId: 'loc-1',
            submissionState: const Value('failed'),
            submissionError: Value(error),
          ),
        );
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        isOnlineProvider.overrideWithValue(true),
        userSignatureApiClientProvider.overrideWithValue(const _NoSignature()),
        reportEditorProvider(_reportId).overrideWith(
          (ref) => ReportEditorNotifier(
            initialState: const ReportEditorState(
              reportId: _reportId,
              tenantId: 'tenant-1',
              insertedUserId: 'user-1',
            ),
            repo: DraftReportRepository(db),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    tester.view.physicalSize = const Size(400, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: StepRiepilogo(reportId: _reportId))),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));
  }

  // Unmount and flush drift's zero-duration stream-close timer before the test ends.
  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  }

  testWidgets('the stale-submit conflict card is shown, with no retry button to contradict it', (
    tester,
  ) async {
    await pumpFailedDraft(tester, error: kStaleSubmitConflictMessage);

    expect(find.text('Invio fallito'), findsOneWidget);
    expect(find.text(kStaleSubmitConflictMessage), findsOneWidget);
    expect(
      find.text('Riprova invio'),
      findsNothing,
      reason: 'a retry resends the same stale expectedVersion and is a guaranteed second 409',
    );

    await unmount(tester);
  });

  testWidgets('every other failed send keeps its "Riprova invio" button', (tester) async {
    // A 400 refusal: editing the draft is the way forward, and editing does not reset `failed`,
    // so the technician is still in this branch when they come back to resend.
    await pumpFailedDraft(
      tester,
      error: 'Il server ha rifiutato la richiesta: il rapportino è già in stato Inviato.',
    );

    expect(find.text('Invio fallito'), findsOneWidget);
    expect(find.text('Riprova invio'), findsOneWidget);

    await unmount(tester);
  });
}
