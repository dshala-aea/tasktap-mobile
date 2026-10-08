import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/reports/draft_report_repository.dart';
import 'package:tasktap_mobile/domain/checklist/checklist_models.dart';
import 'package:tasktap_mobile/domain/checklist/control_type.dart';
import 'package:tasktap_mobile/features/checklist/control_answer_field.dart';
import 'package:tasktap_mobile/presentation/providers/report_editor_providers.dart';

ChecklistControl control(ControlType type, {ChecklistAnswer stored = const ChecklistAnswer(), String? options, String status = 'Pending'}) =>
    ChecklistControl(
      id: 'c1', ticketId: 't1', assetId: 'a1', templateControlId: 'tc', lineageId: 'l', groupId: 'g',
      label: 'Controllo', type: type, options: options, stored: stored, status: status,
    );

void main() {
  late AppDatabase db;

  setUp(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    db = AppDatabase(NativeDatabase.memory());
  });
  tearDown(() => db.close());

  Future<ProviderContainer> pump(WidgetTester tester, ChecklistControl c) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          reportEditorProvider('r1').overrideWith(
            (ref) => ReportEditorNotifier(
              initialState: const ReportEditorState(reportId: 'r1', tenantId: 't', insertedUserId: 'u', ticketId: 't1'),
              repo: DraftReportRepository(db),
            ),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(body: SingleChildScrollView(child: ControlAnswerField(reportId: 'r1', control: c))),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(tester.element(find.byType(ControlAnswerField)));
  }

  List<ControlloRow> rows(ProviderContainer c) => c.read(reportEditorProvider('r1')).controlloRows;

  testWidgets('Sì / No write only boolValue under the TicketControl id; tapping the active one clears', (tester) async {
    final c = await pump(tester, control(ControlType.checkbox));

    await tester.tap(find.text('Sì'));
    await tester.pumpAndSettle();
    expect(rows(c).single.id, 'ctrl-r1-c1');
    expect((rows(c).single.boolValue, rows(c).single.stringValue, rows(c).single.numberValue), (true, null, null));

    await tester.tap(find.text('No'));
    await tester.pumpAndSettle();
    expect(rows(c).single.boolValue, false, reason: 'false is an answer');

    await tester.tap(find.text('No'));
    await tester.pumpAndSettle();
    expect(rows(c), isEmpty);
    expect(await db.select(db.reportControlli).get(), isEmpty);
  });

  testWidgets('number takes a decimal comma and keeps 0; clearing the field removes the row', (tester) async {
    final c = await pump(tester, control(ControlType.number));

    await tester.enterText(find.byType(TextField).first, '12,5');
    await tester.pumpAndSettle();
    expect(rows(c).single.numberValue, 12.5);

    await tester.enterText(find.byType(TextField).first, '0');
    await tester.pumpAndSettle();
    expect(rows(c).single.numberValue, 0, reason: '0 counts as an answer');

    await tester.enterText(find.byType(TextField).first, '');
    await tester.pumpAndSettle();
    expect(rows(c), isEmpty);
  });

  testWidgets('text writes stringValue only', (tester) async {
    final c = await pump(tester, control(ControlType.text));
    await tester.enterText(find.byType(TextField).first, 'serbatoio pieno');
    await tester.pumpAndSettle();
    final r = rows(c).single;
    expect((r.stringValue, r.boolValue, r.numberValue, r.dateValue), ('serbatoio pieno', null, null, null));
  });

  testWidgets('options writes the chosen choice', (tester) async {
    final c = await pump(tester, control(ControlType.options, options: '["A","B"]'));
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('B').last);
    await tester.pumpAndSettle();
    expect(rows(c).single.stringValue, 'B');
  });

  testWidgets('an options control with no published choices degrades to free text', (tester) async {
    final c = await pump(tester, control(ControlType.options));
    await tester.enterText(find.byType(TextField).first, 'altro');
    await tester.pumpAndSettle();
    expect(rows(c).single.stringValue, 'altro');
  });

  testWidgets('a date is picked and written to dateValue only', (tester) async {
    final c = await pump(tester, control(ControlType.dateTime));
    await tester.tap(find.text('Seleziona data'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    final r = rows(c).single;
    expect(r.dateValue, isNotNull);
    expect((r.stringValue, r.boolValue, r.numberValue), (null, null, null));
  });

  testWidgets('a note is saved with the answer; clearing it with no answer removes the row', (tester) async {
    final c = await pump(tester, control(ControlType.checkbox));

    await tester.tap(find.byIcon(LucideIcons.pencil));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'perdita dalla guarnizione');
    await tester.pumpAndSettle();
    expect(rows(c).single.note, 'perdita dalla guarnizione');
    expect(rows(c).single.boolValue, isNull, reason: 'a note alone is not an answer');

    await tester.enterText(find.byType(TextField).first, '   ');
    await tester.pumpAndSettle();
    expect(rows(c), isEmpty);
  });

  testWidgets('the note field is capped at 2000 characters (the server rejects more)', (tester) async {
    await pump(tester, control(ControlType.number));
    await tester.tap(find.byIcon(LucideIcons.pencil));
    await tester.pumpAndSettle();
    final note = tester.widget<TextField>(find.byType(TextField).last);
    expect(note.maxLength, 2000);
  });

  testWidgets('a previous visit\'s answer is shown but creates no row until the technician touches it', (tester) async {
    final c = await pump(
      tester,
      control(
        ControlType.number,
        stored: const ChecklistAnswer(numberValue: 3, note: 'visita precedente'),
        status: 'Completed',
      ),
    );
    expect(find.text('3'), findsOneWidget);
    expect(rows(c), isEmpty);

    await tester.enterText(find.byType(TextField).first, '4');
    await tester.pumpAndSettle();
    expect((rows(c).single.numberValue, rows(c).single.note), (4, 'visita precedente'),
        reason: 'the stored note travels with the new answer');
  });
}
