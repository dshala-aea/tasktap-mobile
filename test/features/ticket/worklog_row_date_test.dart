import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:tasktap_mobile/features/ticket/ticket_detail_screen.dart';
import 'package:tasktap_mobile/features/ticket/ticket_workflow_api_client.dart';

TicketWorkLogDto _entry(DateTime workDate) => TicketWorkLogDto(
  id: 'w1',
  ticketId: 't1',
  userId: 'u1',
  workDate: workDate,
  startTime: const Duration(hours: 8),
  endTime: const Duration(hours: 10),
  isManualEntry: false,
);

void main() {
  setUpAll(() async => initializeDateFormatting('it'));

  for (final workDate in [DateTime.utc(2026, 7, 10), DateTime(2026, 7, 10)]) {
    testWidgets('worklog row shows the 10 July label (isUtc=${workDate.isUtc})', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: TicketWorklogRow(entry: _entry(workDate))),
        ),
      );
      expect(find.textContaining(RegExp('ven 10 lug', caseSensitive: false)), findsOneWidget);
    });
  }
}
