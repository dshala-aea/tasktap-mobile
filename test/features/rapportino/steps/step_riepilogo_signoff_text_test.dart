// dart format width=100
// test/features/rapportino/steps/step_riepilogo_signoff_text_test.dart
//
// Coverage for "Osservazioni cliente" on the rapportino's Riepilogo step: the customer's signoff
// text, captured next to the signatures the way the web editor captures it ("Dichiarazione
// cliente" / `Report.CustomerSignoffText`).
//
// The editor-state -> Drift link is proven here; the Drift -> outgoing `customerSignoffText`
// request field link already existed before this feature (the submission queue read the column,
// the sync wrote it) and is covered at the queue level — see submission_queue_test.dart.

import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:tasktap_mobile/core/widgets/app_text_field.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/reports/draft_report_repository.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart' show appDatabaseProvider;
import 'package:tasktap_mobile/data/users/user_signature_api_client.dart';
import 'package:tasktap_mobile/features/rapportino/steps/step_riepilogo.dart';
import 'package:tasktap_mobile/presentation/providers/report_editor_providers.dart';

const _reportId = 'draft-1';

class _FakePathProviderPlatform extends PathProviderPlatform with MockPlatformInterfaceMixin {
  late final Directory _dir = Directory.systemTemp.createTempSync('signoff_text_test_');

  @override
  Future<String?> getApplicationDocumentsPath() async => _dir.path;
}

/// Same "no saved signature" stub as the other Riepilogo tests — `initState` always asks, and this
/// file isn't exercising the pre-fill path.
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

/// `AppFieldLabel` uppercases its text and renders it through `Text.rich`, so a plain
/// `find.text('Osservazioni cliente')` matches nothing.
Finder signoffLabel() => find.text('OSSERVAZIONI CLIENTE', findRichText: true);

/// The signoff input. At rest it is the only `AppTextField` on the step — the typed-signature
/// dialog's name field is only mounted once that dialog opens.
Finder signoffInput() => find.descendant(
  of: find.byType(AppTextField),
  matching: find.byType(TextField),
);

AppTextField signoffField(WidgetTester tester) =>
    tester.widget<AppTextField>(find.byType(AppTextField));

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

  testWidgets('the field renders on the signing step, empty and optional', (tester) async {
    container = _buildContainer(db);
    await container.read(reportEditorProvider(_reportId).notifier).ready;
    await tester.pumpWidget(_buildStep(container));
    await tester.pumpAndSettle();

    // AppFieldLabel renders `Text.rich(text.toUpperCase())`, so the label matches only as rich
    // text, and only in its uppercased form.
    expect(signoffLabel(), findsOneWidget);
    // No asterisk: the customer's signature is optional to send, and so is what they are signing.
    expect(find.text('OSSERVAZIONI CLIENTE *', findRichText: true), findsNothing);
    expect(signoffField(tester).controller?.text, isEmpty);

    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
    await tester.pumpAndSettle();
  });

  testWidgets('typing persists to the local draft the submit queue reads', (tester) async {
    container = _buildContainer(db);
    await container.read(reportEditorProvider(_reportId).notifier).ready;
    await tester.pumpWidget(_buildStep(container));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byType(AppTextField));
    await tester.pumpAndSettle();
    await tester.enterText(signoffInput(), 'Confermo l\'esecuzione dei lavori');
    await tester.pumpAndSettle();

    expect(
      container.read(reportEditorProvider(_reportId)).customerSignoffText,
      'Confermo l\'esecuzione dei lavori',
    );
    final draft = await DraftReportRepository(db).getDraft(_reportId);
    expect(
      draft?.customerSignoffText,
      'Confermo l\'esecuzione dei lavori',
      reason: 'autosaved to Drift, where the submission queue builds the request from',
    );

    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
    await tester.pumpAndSettle();
  });

  testWidgets('a reopened draft shows the text it already holds', (tester) async {
    // An AI-confirmed report (or one typed on an earlier visit) keeps its acceptance sentence: the
    // editor must show it rather than presenting a blank field that the next autosave would write
    // back as null.
    await db
        .into(db.draftReports)
        .insert(
          DraftReportsCompanion.insert(
            id: _reportId,
            tenantId: 'tenant-1',
            createdAt: DateTime.utc(2026, 6, 21, 10),
            title: 'init',
            insertedUserId: 'user-1',
            locationId: 'l1',
            customerSignoffText: const Value('Il cliente accetta il lavoro.'),
          ),
        );
    container = _buildContainer(db);
    await container.read(reportEditorProvider(_reportId).notifier).ready;
    await tester.pumpWidget(_buildStep(container));
    await tester.pumpAndSettle();

    expect(signoffLabel(), findsOneWidget);
    expect(signoffField(tester).controller?.text, 'Il cliente accetta il lavoro.');

    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
    await tester.pumpAndSettle();
  });
}
