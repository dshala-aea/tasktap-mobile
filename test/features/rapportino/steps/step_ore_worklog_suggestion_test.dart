// dart format width=100
// test/features/rapportino/steps/step_ore_worklog_suggestion_test.dart
//
// A ticket's own server-tracked labour sessions (TicketWorkLogDto) were completely disconnected
// from the rapportino's hours step — start/end/hours were entirely manual entry even when the
// ticket already had real tracked time. This suggests (never silently applies) that time as a
// small chip per matching staff row, keyed by userId so it never blends across technicians.
//
// Verifies:
//   - a single completed worklog session for a staff row's userId surfaces a chip with the
//     precise start/end/hours, and tapping it writes exactly that into the row
//   - multiple completed sessions for the same user sum to a total-hours-only suggestion (no
//     fabricated time range)
//   - a still-running session (no endTime) is never suggested
//   - no chip when the report has no ticketId, or the worklog fetch fails/returns nothing
//     (offline), or the session belongs to a different user

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/reports/draft_report_repository.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart';
import 'package:tasktap_mobile/features/rapportino/steps/step_ore.dart';
import 'package:tasktap_mobile/features/ticket/ticket_detail_api_client.dart';
import 'package:tasktap_mobile/features/ticket/ticket_providers.dart';
import 'package:tasktap_mobile/features/ticket/ticket_workflow_api_client.dart';
import 'package:tasktap_mobile/presentation/providers/report_editor_providers.dart';

const _reportId = 'draft-1';
const _ticketId = 'ticket-1';

AppDatabase _makeDb() => AppDatabase(NativeDatabase.memory());

TicketWorkLogDto _entry({
  required String userId,
  required DateTime workDate,
  required Duration startTime,
  Duration? endTime,
}) => TicketWorkLogDto(
  id: 'wl-${userId}_${startTime.inMinutes}',
  ticketId: _ticketId,
  userId: userId,
  workDate: workDate,
  startTime: startTime,
  endTime: endTime,
  isManualEntry: false,
);

ProviderContainer _buildContainer({
  required AppDatabase db,
  required List<StaffRow> staffRows,
  List<TicketWorkLogDto>? worklogEntries,
}) {
  return ProviderContainer(
    overrides: [
      appDatabaseProvider.overrideWithValue(db),
      reportEditorProvider(_reportId).overrideWith(
        (ref) => ReportEditorNotifier(
          initialState: ReportEditorState(
            reportId: _reportId,
            tenantId: 'tenant-1',
            insertedUserId: 'user-1',
            ticketId: _ticketId,
            staffRows: staffRows,
          ),
          repo: DraftReportRepository(db),
        ),
      ),
      if (worklogEntries != null)
        ticketWorklogsProvider.overrideWith((ref, ticketId) async => worklogEntries),
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

  group('StepOre — worklog hours suggestion', () {
    testWidgets('a single completed session suggests the precise range, applying writes it', (
      tester,
    ) async {
      final workDate = DateTime.utc(2026, 8, 31);
      final container = _buildContainer(
        db: db,
        staffRows: [const StaffRow(id: 'staff-1', userId: 'user-1')],
        worklogEntries: [
          _entry(
            userId: 'user-1',
            workDate: workDate,
            startTime: const Duration(hours: 8),
            endTime: const Duration(hours: 11, minutes: 45),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(_buildStep(container));
      await tester.pumpAndSettle();

      expect(find.textContaining('Da worklog:'), findsOneWidget);
      expect(find.textContaining('3,8h'), findsOneWidget);
      expect(find.textContaining('08:00–11:45'), findsOneWidget);

      await tester.tap(find.textContaining('Da worklog:'));
      await tester.pumpAndSettle();

      final row = container.read(reportEditorProvider(_reportId)).staffRows.single;
      expect(row.startTime, workDate.add(const Duration(hours: 8)));
      expect(row.endTime, workDate.add(const Duration(hours: 11, minutes: 45)));
      expect(row.hoursWorked, closeTo(3.75, 0.01));
    });

    testWidgets(
      'multiple completed sessions for the same user sum to hours only, no fabricated range',
      (tester) async {
        final workDate = DateTime.utc(2026, 8, 31);
        final container = _buildContainer(
          db: db,
          staffRows: [const StaffRow(id: 'staff-1', userId: 'user-1')],
          worklogEntries: [
            _entry(
              userId: 'user-1',
              workDate: workDate,
              startTime: const Duration(hours: 8),
              endTime: const Duration(hours: 10),
            ),
            _entry(
              userId: 'user-1',
              workDate: workDate.add(const Duration(days: 1)),
              startTime: const Duration(hours: 9),
              endTime: const Duration(hours: 10, minutes: 30),
            ),
          ],
        );
        addTearDown(container.dispose);

        await tester.pumpWidget(_buildStep(container));
        await tester.pumpAndSettle();

        expect(find.textContaining('Da worklog: 3,5h'), findsOneWidget);
        expect(find.textContaining('–'), findsNothing, reason: 'no time range for a multi-session sum');

        await tester.tap(find.textContaining('Da worklog:'));
        await tester.pumpAndSettle();

        final row = container.read(reportEditorProvider(_reportId)).staffRows.single;
        expect(row.hoursWorked, closeTo(3.5, 0.01));
        expect(row.startTime, isNull);
        expect(row.endTime, isNull);
      },
    );

    testWidgets('a still-running session is never suggested', (tester) async {
      final container = _buildContainer(
        db: db,
        staffRows: [const StaffRow(id: 'staff-1', userId: 'user-1')],
        worklogEntries: [
          _entry(userId: 'user-1', workDate: DateTime.utc(2026, 8, 31), startTime: const Duration(hours: 8)),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(_buildStep(container));
      await tester.pumpAndSettle();

      expect(find.textContaining('Da worklog:'), findsNothing);
    });

    testWidgets('no chip when the session belongs to a different user', (tester) async {
      final container = _buildContainer(
        db: db,
        staffRows: [const StaffRow(id: 'staff-1', userId: 'user-1')],
        worklogEntries: [
          _entry(
            userId: 'user-2',
            workDate: DateTime.utc(2026, 8, 31),
            startTime: const Duration(hours: 8),
            endTime: const Duration(hours: 10),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(_buildStep(container));
      await tester.pumpAndSettle();

      expect(find.textContaining('Da worklog:'), findsNothing);
    });

    testWidgets('no chip when the report has no ticketId', (tester) async {
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          reportEditorProvider(_reportId).overrideWith(
            (ref) => ReportEditorNotifier(
              initialState: ReportEditorState(
                reportId: _reportId,
                tenantId: 'tenant-1',
                insertedUserId: 'user-1',
                staffRows: const [StaffRow(id: 'staff-1', userId: 'user-1')],
              ),
              repo: DraftReportRepository(db),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(_buildStep(container));
      await tester.pumpAndSettle();

      expect(find.textContaining('Da worklog:'), findsNothing);
    });

    testWidgets('no chip (and no crash) when the worklog fetch fails — offline is not an error', (
      tester,
    ) async {
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          reportEditorProvider(_reportId).overrideWith(
            (ref) => ReportEditorNotifier(
              initialState: ReportEditorState(
                reportId: _reportId,
                tenantId: 'tenant-1',
                insertedUserId: 'user-1',
                ticketId: _ticketId,
                staffRows: const [StaffRow(id: 'staff-1', userId: 'user-1')],
              ),
              repo: DraftReportRepository(db),
            ),
          ),
          ticketWorklogsProvider.overrideWith(
            (ref, ticketId) async => throw const TicketDetailOfflineException(),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(_buildStep(container));
      await tester.pumpAndSettle();

      expect(find.textContaining('Da worklog:'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
