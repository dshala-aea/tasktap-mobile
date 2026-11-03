import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/core/theme/app_theme.dart';
import 'package:tasktap_mobile/core/widgets/app_button.dart';
import 'package:tasktap_mobile/features/approvazioni/approval_request_card.dart';

Widget _wrap(Widget child) =>
    MaterialApp(theme: buildAppTheme(), home: Scaffold(body: child));

void main() {
  testWidgets('renders the requester, the period and the reason', (tester) async {
    await tester.pumpWidget(
      _wrap(
        ApprovalRequestCard(
          title: 'Mario Rossi',
          subtitle: 'Ferie · 12 mar – 14 mar',
          reason: 'Vacanza',
          onApprove: () {},
          onReject: () {},
        ),
      ),
    );

    expect(find.text('Mario Rossi'), findsOneWidget);
    expect(find.text('Ferie · 12 mar – 14 mar'), findsOneWidget);
    expect(find.text('Vacanza'), findsOneWidget);
  });

  testWidgets('a blank reason renders nothing', (tester) async {
    await tester.pumpWidget(
      _wrap(
        ApprovalRequestCard(
          title: 'Mario Rossi',
          subtitle: 'Smart working · 12 mar',
          reason: '   ',
          onApprove: () {},
          onReject: () {},
        ),
      ),
    );

    expect(find.text('   '), findsNothing);
  });

  testWidgets('the two actions fire their callbacks', (tester) async {
    var approved = 0;
    var rejected = 0;
    await tester.pumpWidget(
      _wrap(
        ApprovalRequestCard(
          title: 'Mario Rossi',
          subtitle: 'Ferie',
          onApprove: () => approved++,
          onReject: () => rejected++,
        ),
      ),
    );

    await tester.tap(find.text('Approva'));
    await tester.tap(find.text('Rifiuta'));

    expect(approved, 1);
    expect(rejected, 1);
  });

  testWidgets('busy disables both actions', (tester) async {
    var approved = 0;
    var rejected = 0;
    await tester.pumpWidget(
      _wrap(
        ApprovalRequestCard(
          title: 'Mario Rossi',
          subtitle: 'Ferie',
          busy: true,
          onApprove: () => approved++,
          onReject: () => rejected++,
        ),
      ),
    );

    final buttons = tester.widgetList<AppButton>(find.byType(AppButton)).toList();
    expect(buttons, hasLength(2));
    expect(buttons.every((b) => b.onPressed == null), isTrue);

    await tester.tap(find.text('Approva'), warnIfMissed: false);
    await tester.tap(find.text('Rifiuta'), warnIfMissed: false);
    expect(approved, 0);
    expect(rejected, 0);
  });
}
