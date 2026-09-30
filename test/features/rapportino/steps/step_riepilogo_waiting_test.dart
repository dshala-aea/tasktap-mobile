// dart format width=100
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/reports/draft_report_repository.dart';
import 'package:tasktap_mobile/data/sync/connectivity_provider.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart';
import 'package:tasktap_mobile/data/users/user_signature_api_client.dart';
import 'package:tasktap_mobile/features/rapportino/steps/step_riepilogo.dart';
import 'package:tasktap_mobile/presentation/providers/report_editor_providers.dart';

import 'dart:typed_data';

const _reportId = 'draft-w';

class _NoSignature implements UserSignatureApiClient {
  const _NoSignature();
  @override
  Future<Uint8List?> fetchSavedSignatureContent() async => null;
  @override
  Future<UserSignatureUploadResult> uploadSignature(Uint8List bytes) =>
      throw UnimplementedError();
}

void main() {
  Future<void> pump(WidgetTester tester, {required bool online}) async {
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
            submissionState: const Value('readyToSubmit'),
          ),
        );
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        isOnlineProvider.overrideWithValue(online),
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

  testWidgets('a queued row while offline says it is waiting for the connection', (tester) async {
    await pump(tester, online: false);
    expect(find.text('In attesa di connessione'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('a queued row while online shows no waiting card', (tester) async {
    await pump(tester, online: true);
    expect(find.text('In attesa di connessione'), findsNothing);
    await unmount(tester);
  });
}
