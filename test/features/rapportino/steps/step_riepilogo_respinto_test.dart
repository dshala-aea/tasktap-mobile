// dart format width=100
// test/features/rapportino/steps/step_riepilogo_respinto_test.dart
//
// A Respinto (office-rejected) report keeps `submissionState == submitted` forever — nothing
// resets it on rejection (see sync_service.dart's own note). Before this fix, the Riepilogo
// step's submit-state StreamBuilder read only `submissionState`, so reopening a rejected report
// showed the green "Rapportino inviato con successo" card — false, since the office rejected it
// — with no way forward. This proves it now reads `draft.stato` first and shows an honest,
// read-only rejection card instead.

import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/reports/draft_report_repository.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart';
import 'package:tasktap_mobile/data/users/user_signature_api_client.dart';
import 'package:tasktap_mobile/features/rapportino/steps/step_riepilogo.dart';
import 'package:tasktap_mobile/presentation/providers/report_editor_providers.dart';

const _reportId = 'draft-1';

class _FakePathProviderPlatform extends PathProviderPlatform with MockPlatformInterfaceMixin {
  late final Directory _dir = Directory.systemTemp.createTempSync('respinto_test_');

  @override
  Future<String?> getApplicationDocumentsPath() async => _dir.path;
}

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

  testWidgets(
    'a Respinto report shows an honest rejection card, not the stale "inviato con successo" one',
    (tester) async {
      // ReportEditorNotifier's hydration is a no-op when there's no matching DB row (see its
      // own doc comment) — production always has one because `createLocalDraft` inserts it
      // before navigating here, so this test needs its own row too, seeded directly as a report
      // already Respinto (`submissionState` stuck at 'submitted' — nothing resets it on
      // rejection, see sync_service.dart's own note).
      await db
          .into(db.draftReports)
          .insert(
            DraftReportsCompanion.insert(
              id: _reportId,
              tenantId: 'tenant-1',
              createdAt: DateTime.utc(2026, 6, 1),
              title: 'Rapportino respinto',
              insertedUserId: 'user-1',
              locationId: 'loc-1',
              isLocalOnly: const Value(true),
              stato: const Value('Respinto'),
              submissionState: const Value('submitted'),
            ),
          );

      container = ProviderContainer(
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

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: Scaffold(body: StepRiepilogo(reportId: _reportId))),
        ),
      );
      await tester.pumpAndSettle();

      // The screen is not auto-popped: reopening an already-Respinto report used to hit
      // _handleDraftUpdateForNavigation's toast-and-pop the instant it saw the persisted
      // submissionState == submitted, closing the sheet before the technician could read it.
      expect(find.byType(StepRiepilogo), findsOneWidget);
      expect(find.text("L'ufficio ha respinto questo rapportino."), findsOneWidget);
      expect(find.text('Rapportino inviato con successo.'), findsNothing);
      expect(find.text('Invia rapportino'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
}
