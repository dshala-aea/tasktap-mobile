// dart format width=100
// test/features/rapportino/steps/step_ore_timer_readout_test.dart
//
// The timer records real intervals (report_staff_segments), and the row's total is derived from
// them — but the "Ore" box beside "Km percorsi" stayed editable, so a technician could type a
// number that the next save silently reverted to the interval sum. The field and the row
// disagreed, and the row won.
//
// Verifies:
//   - a row with recorded intervals shows the interval total as a readout, with no editable Ore
//     box — the 4 h span (and the 4 h the office typed) do not outrank the 2 h actually measured
//   - Km stays editable, because a readout that takes the keyboard away must take it away from
//     one field, not the pair
//   - a row with no intervals keeps its editable Ore box (office-entered or manually corrected
//     hours are not the timer's to overwrite)
//   - the "Ore effettive" line names the interval count when the timer recorded more than one
//   - the readout is one semantics node named "Ore", like the field it replaces

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tasktap_mobile/core/widgets/widgets.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/reports/draft_report_repository.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart';
import 'package:tasktap_mobile/features/rapportino/steps/step_ore.dart';
import 'package:tasktap_mobile/presentation/providers/report_editor_providers.dart';

const _reportId = 'draft-1';

AppDatabase _makeDb() => AppDatabase(NativeDatabase.memory());

/// The editable hours box. Matched on the widget's own label rather than on the rendered label
/// text: AppFieldLabel upper-cases it, so `find.text('Ore')` would pass whether the field is
/// there or not.
final _oreField = find.byWidgetPredicate((w) => w is AppTextField && w.label == 'Ore');
final _kmField = find.byWidgetPredicate((w) => w is AppTextField && w.label == 'Km percorsi');

/// Two one-hour runs with a two-hour gap between them: the timer measured 2 h, while the
/// start→end span is 4 h and the office's typed `hoursWorked` says 4 h as well.
final _twoRuns = StaffRow(
  id: 'staff-1',
  userId: 'user-1',
  hoursWorked: 4,
  startTime: DateTime.utc(2026, 8, 31, 6),
  endTime: DateTime.utc(2026, 8, 31, 10),
  segments: [
    StaffSegment(
      id: 'seg-1',
      startUtc: DateTime.utc(2026, 8, 31, 6),
      endUtc: DateTime.utc(2026, 8, 31, 7),
    ),
    StaffSegment(
      id: 'seg-2',
      startUtc: DateTime.utc(2026, 8, 31, 8),
      endUtc: DateTime.utc(2026, 8, 31, 9),
    ),
  ],
);

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

  group('StepOre — the Ore field reads the timer', () {
    testWidgets('a technician with recorded intervals sees the timer total, not an editable Ore', (
      tester,
    ) async {
      final container = _buildContainer(db: db, staffRows: [_twoRuns]);
      addTearDown(container.dispose);

      await tester.pumpWidget(_buildStep(container));
      await tester.pumpAndSettle();

      // 2,0 h — the measured runs. Not the 4 h span, and not the 4 h the office typed.
      expect(find.text('2,0'), findsOneWidget);
      expect(find.text('Ore effettive: 2,0h · 2 intervalli'), findsOneWidget);
      // The bottom card folds effectiveHours too, so the total agrees with the row.
      expect(find.text('2.0 h'), findsOneWidget);

      expect(_oreField, findsNothing, reason: 'the hours are the timer\'s, not the keyboard\'s');
      expect(_kmField, findsOneWidget, reason: 'km is still the technician\'s to enter');
      expect(find.textContaining('Calcolate dal timer'), findsOneWidget);
    });

    testWidgets('a row with no recorded intervals keeps the editable Ore box', (tester) async {
      final container = _buildContainer(
        db: db,
        staffRows: [const StaffRow(id: 'staff-1', userId: 'user-1', hoursWorked: 3.5)],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(_buildStep(container));
      await tester.pumpAndSettle();

      expect(_oreField, findsOneWidget);
      expect(_kmField, findsOneWidget);
      expect(find.textContaining('Calcolate dal timer'), findsNothing);
    });

    testWidgets('a single recorded interval names no count', (tester) async {
      final container = _buildContainer(
        db: db,
        staffRows: [
          StaffRow(
            id: 'staff-1',
            userId: 'user-1',
            startTime: DateTime.utc(2026, 8, 31, 6),
            endTime: DateTime.utc(2026, 8, 31, 9),
            segments: [
              StaffSegment(
                id: 'seg-1',
                startUtc: DateTime.utc(2026, 8, 31, 6),
                endUtc: DateTime.utc(2026, 8, 31, 9),
              ),
            ],
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(_buildStep(container));
      await tester.pumpAndSettle();

      expect(find.text('3,0'), findsOneWidget);
      expect(find.text('Ore effettive: 3,0h'), findsOneWidget);
    });

    // AppTextField merges its label into the input's own semantics node, so "Ore" is that
    // field's name. A readout made of loose Texts would announce "ORE", then "2,0", then "h" —
    // three swipes for one value, with no name on it.
    testWidgets('the readout announces as one node named Ore, carrying the value', (tester) async {
      final handle = tester.ensureSemantics();

      final container = _buildContainer(db: db, staffRows: [_twoRuns]);
      addTearDown(container.dispose);

      await tester.pumpWidget(_buildStep(container));
      await tester.pumpAndSettle();

      final node = tester.getSemantics(find.bySemanticsLabel('Ore'));
      expect(node.label, 'Ore');
      expect(node.value, '2,0 h');
      // Disposed inline, not in a tearDown: the framework checks for leaks before tearDowns run.
      handle.dispose();
    });
  });
}
