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

import 'package:tasktap_mobile/core/time/business_time.dart';
import 'package:tasktap_mobile/core/time/business_time_providers.dart';
import 'package:tasktap_mobile/core/time/work_time.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/reports/draft_report_repository.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart';
import 'package:tasktap_mobile/data/timbratura/cantiere_worklog_api_client.dart'
    show CantiereWorkLogDto;
import 'package:tasktap_mobile/data/timbratura/worklog_api_client.dart' show UserWorkLogDto;
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
  Duration? duration,
}) => TicketWorkLogDto(
  id: 'wl-${userId}_${startTime.inMinutes}',
  ticketId: _ticketId,
  userId: userId,
  workDate: workDate,
  startTime: startTime,
  endTime: endTime,
  isManualEntry: false,
  duration: duration,
);

/// A plain [UserWorkLogDto] (StepOre's last-resort tier) with a legacy Rome-frame label.
UserWorkLogDto _plainEntry({
  required String userId,
  required DateTime workDate,
  required String startTime,
  String? endTime,
  Duration? duration,
}) => UserWorkLogDto(
  id: 'plain-${userId}_$startTime',
  userId: userId,
  workDate: workDate,
  startTime: startTime,
  endTime: endTime,
  duration: duration,
);

CantiereWorkLogDto _cantiereEntry({
  required String userId,
  required DateTime workDate,
  required String startTime,
  String? endTime,
  Duration? duration,
}) => CantiereWorkLogDto(
  id: 'c-${userId}_$startTime',
  cantiereId: 'cantiere-1',
  customerId: 'customer-1',
  userId: userId,
  workDate: workDate,
  startTime: startTime,
  endTime: endTime,
  duration: duration,
);

const _row = StaffRow(id: 'staff-1', userId: 'user-1');

ProviderContainer _buildContainer({
  required AppDatabase db,
  required List<StaffRow> staffRows,
  List<TicketWorkLogDto>? worklogEntries,
  BusinessTime? businessTime,
}) {
  return ProviderContainer(
    overrides: [
      if (businessTime != null) businessTimeProvider.overrideWithValue(businessTime),
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
    child: const MaterialApp(
      home: Scaffold(body: StepOre(reportId: _reportId)),
    ),
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

      await tester.tap(find.textContaining('Da worklog:'));
      await tester.pumpAndSettle();

      final row = container.read(reportEditorProvider(_reportId)).staffRows.single;
      // 08:00 is a Rome wall-clock label: 06:00Z in August (UTC+2), a real instant.
      expect(row.startTime, DateTime.utc(2026, 8, 31, 6));
      expect(row.endTime, DateTime.utc(2026, 8, 31, 9, 45));
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
        expect(
          find.textContaining('–'),
          findsNothing,
          reason: 'no time range for a multi-session sum',
        );

        await tester.tap(find.textContaining('Da worklog:'));
        await tester.pumpAndSettle();

        final row = container.read(reportEditorProvider(_reportId)).staffRows.single;
        expect(row.hoursWorked, closeTo(3.5, 0.01));
        expect(row.startTime, isNull);
        expect(row.endTime, isNull);
      },
    );

    // Regression: an overnight session (start 20:02, end 06:10 next day) has endTime numerically
    // smaller than startTime. The suggestion used to derive `end` as `workDate + endTime` (same
    // calendar day as start) and separately hand-subtract endTime-startTime for the multi-session
    // sum — both gave a negative duration. Now both branches use TicketWorkLogDto.duration (the
    // backend-computed value) instead of re-deriving it.
    testWidgets('an overnight session suggests the correct positive duration, not a negative one', (
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
            startTime: const Duration(hours: 20, minutes: 2),
            endTime: const Duration(hours: 6, minutes: 10),
            duration: const Duration(hours: 10, minutes: 8),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(_buildStep(container));
      await tester.pumpAndSettle();

      expect(find.textContaining('Da worklog:'), findsOneWidget);
      expect(find.textContaining('10,1h'), findsOneWidget);

      await tester.tap(find.textContaining('Da worklog:'));
      await tester.pumpAndSettle();

      final row = container.read(reportEditorProvider(_reportId)).staffRows.single;
      expect(row.hoursWorked, closeTo(10.133, 0.01));
      // The suggested end must land on the day AFTER start, not the same day.
      expect(row.endTime!.isAfter(row.startTime!), isTrue);
      expect(row.endTime!.difference(row.startTime!).isNegative, isFalse);
    });

    testWidgets('a still-running session is never suggested', (tester) async {
      final container = _buildContainer(
        db: db,
        staffRows: [const StaffRow(id: 'staff-1', userId: 'user-1')],
        worklogEntries: [
          _entry(
            userId: 'user-1',
            workDate: DateTime.utc(2026, 8, 31),
            startTime: const Duration(hours: 8),
          ),
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

  // Regression: when a ticket has no worklog of its own tied to it (and no cantiere tier either),
  // StepOre used to fall back to the last *closed* plain WorkLog in the last 30 days — attributing
  // some unrelated past day's hours to today's rapportino. The only honest fallback left is this
  // technician's own still-open punch: its start really did happen, and "now" is an honest end
  // while that clock is still running.
  group('StepOre — plain-timbratura fallback (active punch, no ticket/cantiere worklog)', () {
    ProviderContainer buildNoTicketContainer({
      required List<StaffRow> staffRows,
      required List<UserWorkLogDto> recentEntries,
      BusinessTime? businessTime,
    }) {
      return ProviderContainer(
        overrides: [
          if (businessTime != null) businessTimeProvider.overrideWithValue(businessTime),
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
          recentWorkLogProvider.overrideWith((ref, userId) async => recentEntries),
        ],
      );
    }

    testWidgets(
      'an open punch suggests its start instant and the injected clock as the end; applying '
      'writes exactly that',
      (tester) async {
        final container = buildNoTicketContainer(
          staffRows: [_row],
          recentEntries: [
            _plainEntry(
              userId: 'user-1',
              workDate: DateTime.utc(2026, 8, 31),
              startTime: '08:00:00',
            ),
          ],
          // 08:00 Rome = 06:00Z; now = 08:30Z.
          businessTime: BusinessTime('Europe/Rome', clock: () => DateTime.utc(2026, 8, 31, 8, 30)),
        );
        addTearDown(container.dispose);

        await tester.pumpWidget(_buildStep(container));
        await tester.pumpAndSettle();

        expect(find.textContaining('Da worklog:'), findsOneWidget);
        expect(find.textContaining('2,5h'), findsOneWidget);

        await tester.tap(find.textContaining('Da worklog:'));
        await tester.pumpAndSettle();

        final row = container.read(reportEditorProvider(_reportId)).staffRows.single;
        expect(row.startTime, DateTime.utc(2026, 8, 31, 6));
        expect(row.endTime, DateTime.utc(2026, 8, 31, 8, 30));
        expect(row.hoursWorked, closeTo(2.5, 0.001));
      },
    );

    testWidgets(
      'a closed session in the last 30 days is never suggested — no more "last closed worklog"',
      (tester) async {
        final container = buildNoTicketContainer(
          staffRows: [_row],
          recentEntries: [
            _plainEntry(
              userId: 'user-1',
              workDate: DateTime.utc(2026, 8, 26),
              startTime: '08:00:00',
              endTime: '11:00:00',
              duration: const Duration(hours: 3),
            ),
          ],
          businessTime: BusinessTime('Europe/Rome', clock: () => DateTime.utc(2026, 8, 31, 8, 30)),
        );
        addTearDown(container.dispose);

        await tester.pumpWidget(_buildStep(container));
        await tester.pumpAndSettle();

        expect(find.textContaining('Da worklog:'), findsNothing);
      },
    );

    testWidgets('no chip when the open punch belongs to a different user', (tester) async {
      final container = buildNoTicketContainer(
        staffRows: [const StaffRow(id: 'staff-1', userId: 'user-1')],
        recentEntries: [
          _plainEntry(userId: 'user-2', workDate: DateTime.utc(2026, 8, 31), startTime: '08:00:00'),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(_buildStep(container));
      await tester.pumpAndSettle();

      expect(find.textContaining('Da worklog:'), findsNothing);
    });
  });

  group('suggestion combiner — true instants (Rome label frame, any tenant zone)', () {
    final rome = BusinessTime('Europe/Rome', clock: () => DateTime.utc(2026, 8, 31, 12));
    final newYork = BusinessTime('America/New_York', clock: () => DateTime.utc(2026, 8, 31, 12));

    TicketWorkLogDto ticket(DateTime d, String hms, Duration dur) => _entry(
      userId: 'user-1',
      workDate: d,
      startTime: parseTimeSpan(hms)!,
      endTime: parseTimeSpan(hms)! + dur,
      duration: dur,
    );

    // (workDate, hms, expected instant). Rome frame: summer UTC+2, winter UTC+1.
    final table = <(DateTime, String, DateTime)>[
      (DateTime.utc(2026, 8, 31), '08:00:00', DateTime.utc(2026, 8, 31, 6)),
      (DateTime.utc(2026, 7, 10), '08:00:00', DateTime.utc(2026, 7, 10, 6)),
      (DateTime.utc(2026, 12, 1), '08:00:00', DateTime.utc(2026, 12, 1, 7)),
      (DateTime.utc(2026, 10, 25), '08:00:00', DateTime.utc(2026, 10, 25, 7)),
      (DateTime.utc(2027, 3, 28), '08:00:00', DateTime.utc(2027, 3, 28, 6)),
    ];

    for (final bt in [rome, newYork]) {
      for (final (date, hms, want) in table) {
        test('${bt.zoneId}: $date $hms -> $want, identical in all three tiers', () {
          const dur = Duration(hours: 1);
          final t = worklogSuggestionFor(bt, [ticket(date, hms, dur)], _row)!;
          final c = cantiereWorklogSuggestionFor(bt, [
            _cantiereEntry(
              userId: 'user-1',
              workDate: date,
              startTime: hms,
              endTime: '23:00:00',
              duration: dur,
            ),
          ], _row)!;
          final p = recentWorkLogSuggestionFor(bt, [
            _plainEntry(userId: 'user-1', workDate: date, startTime: hms),
          ], _row)!;
          expect(t.startTime, want);
          expect(c.startTime, want);
          expect(p.startTime, want);
          expect(t.endTime, want.add(dur));
          expect(c.endTime, want.add(dur));
          expect(t.startTime!.isUtc, isTrue);
        });
      }
    }

    test('a local-flagged workDate gives the same instant as a UTC-flagged one', () {
      final s = worklogSuggestionFor(newYork, [
        ticket(DateTime(2026, 7, 10), '08:00:00', const Duration(hours: 1)),
      ], _row)!;
      expect(s.startTime, DateTime.utc(2026, 7, 10, 6));
    });

    test('overnight 20:02 + 10 h 8 min ends at start + duration (all tiers)', () {
      final d = DateTime.utc(2026, 8, 31);
      const dur = Duration(hours: 10, minutes: 8);
      final t = worklogSuggestionFor(rome, [ticket(d, '20:02:00', dur)], _row)!;
      expect(t.startTime, DateTime.utc(2026, 8, 31, 18, 2));
      expect(t.endTime, DateTime.utc(2026, 9, 1, 4, 10));
      final c = cantiereWorklogSuggestionFor(rome, [
        _cantiereEntry(
          userId: 'user-1',
          workDate: d,
          startTime: '20:02:00',
          endTime: '06:10:00',
          duration: dur,
        ),
      ], _row)!;
      expect(c.endTime, DateTime.utc(2026, 9, 1, 4, 10));
    });

    test('end is instant arithmetic across the autumn DST change (25 h day)', () {
      // 2026-10-25 22:00 Rome (UTC+1) + 8 h: 06:00 next day Rome = 05:00Z, i.e. 8 real hours.
      final s = worklogSuggestionFor(rome, [
        ticket(DateTime.utc(2026, 10, 25), '22:00:00', const Duration(hours: 8)),
      ], _row)!;
      expect(s.startTime, DateTime.utc(2026, 10, 25, 21));
      expect(s.endTime, DateTime.utc(2026, 10, 26, 5));
    });

    test('a malformed or missing startTime string produces no suggestion for that entry', () {
      final d = DateTime.utc(2026, 8, 31);
      for (final bad in ['', 'abc', '8', '25:00:00', '2026-08-31T08:00:00Z']) {
        expect(
          cantiereWorklogSuggestionFor(rome, [
            _cantiereEntry(
              userId: 'user-1',
              workDate: d,
              startTime: bad,
              endTime: '10:00:00',
              duration: const Duration(hours: 2),
            ),
          ], _row),
          isNull,
          reason: 'cantiere "$bad"',
        );
        expect(
          recentWorkLogSuggestionFor(rome, [
            _plainEntry(userId: 'user-1', workDate: d, startTime: bad),
          ], _row),
          isNull,
          reason: 'plain "$bad"',
        );
      }
    });

    test('plain tier: end is the business-time clock instant; hours from the real difference', () {
      final bt = BusinessTime('America/New_York', clock: () => DateTime.utc(2026, 8, 31, 9, 15));
      final s = recentWorkLogSuggestionFor(bt, [
        _plainEntry(userId: 'user-1', workDate: DateTime.utc(2026, 8, 31), startTime: '08:00:00'),
      ], _row)!;
      expect(s.startTime, DateTime.utc(2026, 8, 31, 6));
      expect(s.endTime, DateTime.utc(2026, 8, 31, 9, 15));
      expect(s.hours, closeTo(3.25, 0.001));
    });

    test('plain tier picks the latest start by instant', () {
      final s = recentWorkLogSuggestionFor(rome, [
        _plainEntry(userId: 'user-1', workDate: DateTime.utc(2026, 8, 30), startTime: '23:00:00'),
        _plainEntry(userId: 'user-1', workDate: DateTime.utc(2026, 8, 31), startTime: '07:00:00'),
      ], _row)!;
      expect(s.startTime, DateTime.utc(2026, 8, 31, 5));
    });

    test('multi-session sum is unchanged and carries no range', () {
      final d = DateTime.utc(2026, 8, 31);
      final s = worklogSuggestionFor(newYork, [
        ticket(d, '08:00:00', const Duration(hours: 2)),
        ticket(d, '13:00:00', const Duration(hours: 1, minutes: 30)),
      ], _row)!;
      expect(s.hours, closeTo(3.5, 0.001));
      expect(s.startTime, isNull);
      expect(s.endTime, isNull);
    });
  });
}
