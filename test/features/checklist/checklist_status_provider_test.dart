import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/reports/draft_report_repository.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart' show appDatabaseProvider;
import 'package:tasktap_mobile/features/checklist/checklist_providers.dart';
import 'package:tasktap_mobile/presentation/providers/report_editor_providers.dart';

import '../../support/checklist_fixtures.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    db = AppDatabase(NativeDatabase.memory());
  });
  tearDown(() => db.close());

  ProviderContainer container({String? ticketId = 't1'}) {
    final c = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWithValue(db),
      reportEditorProvider('r1').overrideWith(
        (ref) => ReportEditorNotifier(
          initialState: ReportEditorState(reportId: 'r1', tenantId: 't', insertedUserId: 'u', ticketId: ticketId),
          repo: DraftReportRepository(db),
        ),
      ),
    ]);
    addTearDown(c.dispose);
    return c;
  }

  test('counts required rows that are still empty and updates as the technician answers', () async {
    await seedBigTicket(db, assets: 2);
    final c = container();
    await c.read(ticketChecklistProvider('t1').future);

    var status = c.read(assetChecklistStatusProvider('r1'))!;
    expect((status.assetCount, status.missing.length, status.requiredTotal), (2, 10, 10));

    await c.read(reportEditorProvider('r1').notifier).upsertControllo(
          const ControlloRow(id: 'ctrl-r1-c-0-0', reportId: 'r1', controlId: 'c-0-0', boolValue: false),
        );
    status = c.read(assetChecklistStatusProvider('r1'))!;
    expect(status.missing.length, 9);
  });

  test('is null for a rapportino without a ticket', () async {
    final c = container(ticketId: null);
    expect(c.read(assetChecklistStatusProvider('r1')), isNull);
  });
}
