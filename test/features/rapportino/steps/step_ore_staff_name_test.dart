// dart format width=100
// test/features/rapportino/steps/step_ore_staff_name_test.dart
//
// _StaffTile showed the raw userId GUID whenever StaffRow.displayName was empty — which it
// always is for a row rehydrated from persistence (ReportStaffTable has no displayName column),
// including the technician auto-seeded as the first row on every new draft. Every other screen
// resolves a bare user id through colleagueNameProvider (the synced local colleagues mirror);
// this tile was the one place that skipped it, showing an opaque GUID that reads as "a random
// non-existent user" to anyone not expecting a raw id.
//
// Verifies:
//   - a staff row's userId known to the local colleagues mirror shows the resolved display name
//   - a userId unknown to the mirror (not yet synced, or a departed colleague) falls back to the
//     raw id — same fallback contract as colleagueNameProvider's other callers, never blank

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/reports/draft_report_repository.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart';
import 'package:tasktap_mobile/features/rapportino/steps/step_ore.dart';
import 'package:tasktap_mobile/presentation/providers/report_editor_providers.dart';

const _reportId = 'draft-1';

AppDatabase _makeDb() => AppDatabase(NativeDatabase.memory());

ProviderContainer _buildContainer({required AppDatabase db, required List<StaffRow> staffRows}) {
  return ProviderContainer(
    overrides: [
      appDatabaseProvider.overrideWithValue(db),
      reportEditorProvider(_reportId).overrideWith(
        (ref) => ReportEditorNotifier(
          initialState: ReportEditorState(
            reportId: _reportId,
            tenantId: 'tenant-1',
            insertedUserId: 'user-1',
            staffRows: staffRows,
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
    child: const MaterialApp(home: Scaffold(body: StepOre(reportId: _reportId))),
  );
}

void main() {
  late AppDatabase db;

  setUp(() => db = _makeDb());
  tearDown(() async => db.close());

  group('StepOre — staff tile name resolution', () {
    testWidgets('a staff row known to the colleagues mirror shows the resolved name, not the id', (
      tester,
    ) async {
      await db
          .into(db.colleagues)
          .insert(ColleaguesCompanion.insert(id: 'user-1', displayName: 'Mario Rossi'));

      final container = _buildContainer(
        db: db,
        staffRows: [const StaffRow(id: 'staff-1', userId: 'user-1')],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(_buildStep(container));
      await tester.pumpAndSettle();

      expect(find.text('Mario Rossi'), findsOneWidget);
      expect(find.text('user-1'), findsNothing);
    });

    testWidgets('a staff row unknown to the colleagues mirror falls back to the raw id', (
      tester,
    ) async {
      final container = _buildContainer(
        db: db,
        staffRows: [const StaffRow(id: 'staff-1', userId: 'user-unsynced')],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(_buildStep(container));
      await tester.pumpAndSettle();

      expect(find.text('user-unsynced'), findsOneWidget);
    });
  });
}
