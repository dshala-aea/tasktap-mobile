// dart format width=100
// test/features/rapportino/steps/step_riepilogo_follow_up_test.dart
//
// Coverage for the "Serve un secondo intervento" ("Da tornare") toggle on the rapportino's
// Riepilogo step: visible only when the report is linked to a ticket (nothing for the backend
// to transition otherwise), off by default, and its value is autosaved to the same local draft
// field the submission queue reads to build the outgoing SubmitReportRequest.
//
// The toggle -> Drift field link is proven here. The Drift field -> outgoing
// `richiedeSecondoIntervento` request field link is proven separately, at the submission-queue
// level, in test/data/sync/submission_queue_test.dart ("submit carries
// richiedeSecondoIntervento=true from draft onto the request") — driving that same assertion
// through a full widget submit (real signature file I/O + the mocked upload/sign/submit calls,
// under flutter_test's fake-async test zone) proved to hang unrelated to this feature's own
// logic, so the two layers are kept separate and each fast/deterministic on its own.

import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:tasktap_mobile/core/widgets/app_toggle.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/reports/draft_report_repository.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart';
import 'package:tasktap_mobile/data/users/user_signature_api_client.dart';
import 'package:tasktap_mobile/features/rapportino/steps/step_riepilogo.dart';
import 'package:tasktap_mobile/presentation/providers/report_editor_providers.dart';

const _reportId = 'draft-1';

class _FakePathProviderPlatform extends PathProviderPlatform with MockPlatformInterfaceMixin {
  late final Directory _dir = Directory.systemTemp.createTempSync('follow_up_test_');

  @override
  Future<String?> getApplicationDocumentsPath() async => _dir.path;
}

/// Same "no saved signature" stub as step_riepilogo_signature_test.dart — `_StepRiepilogoState
/// .initState` always calls `fetchSavedSignatureContent()`, and this file isn't exercising the
/// pre-fill path.
class _StubUserSignatureApiClient implements UserSignatureApiClient {
  const _StubUserSignatureApiClient();

  @override
  Future<Uint8List?> fetchSavedSignatureContent() async => null;

  @override
  Future<UserSignatureUploadResult> uploadSignature(Uint8List bytes) {
    throw UnimplementedError('not used by this test');
  }
}

AppDatabase _makeDb() => AppDatabase(NativeDatabase.memory());

ProviderContainer _buildContainer(AppDatabase db) {
  return ProviderContainer(
    overrides: [
      appDatabaseProvider.overrideWithValue(db),
      userSignatureApiClientProvider.overrideWithValue(const _StubUserSignatureApiClient()),
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
}

Widget _buildStep(ProviderContainer container) {
  return UncontrolledProviderScope(
    container: container,
    child: const MaterialApp(home: Scaffold(body: StepRiepilogo(reportId: _reportId))),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  PathProviderPlatform.instance = _FakePathProviderPlatform();

  late AppDatabase db;
  late ProviderContainer container;

  setUp(() => db = _makeDb());
  tearDown(() async {
    container.dispose();
    await db.close();
  });

  group('visibility — gated on a linked ticket', () {
    testWidgets('hidden when the rapportino has no linked ticket', (tester) async {
      container = _buildContainer(db);
      await tester.pumpWidget(_buildStep(container));
      await tester.pumpAndSettle();

      expect(find.text('Serve un secondo intervento'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('visible, off by default, when a ticket is linked', (tester) async {
      container = _buildContainer(db);
      await container
          .read(reportEditorProvider(_reportId).notifier)
          .setTicketFromCache('ticket-1');
      await tester.pumpWidget(_buildStep(container));
      await tester.pumpAndSettle();

      expect(find.text('Serve un secondo intervento'), findsOneWidget);
      final toggle = tester.widget<AppToggle>(find.byType(AppToggle));
      expect(toggle.value, isFalse, reason: 'off by default — never assumed');
      expect(
        container.read(reportEditorProvider(_reportId)).richiedeSecondoIntervento,
        isFalse,
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  });

  group('toggling — updates and persists local draft state', () {
    testWidgets('tapping the toggle flips state and survives an autosave round-trip', (
      tester,
    ) async {
      container = _buildContainer(db);
      await container
          .read(reportEditorProvider(_reportId).notifier)
          .setTicketFromCache('ticket-1');
      await tester.pumpWidget(_buildStep(container));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(AppToggle));
      await tester.pumpAndSettle();

      expect(
        container.read(reportEditorProvider(_reportId)).richiedeSecondoIntervento,
        isTrue,
      );
      final repo = DraftReportRepository(db);
      final draft = await repo.getDraft(_reportId);
      expect(draft?.richiedeSecondoIntervento, isTrue, reason: 'autosaved to Drift');

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  });
}
