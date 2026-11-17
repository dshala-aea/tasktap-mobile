import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/core/theme/app_theme.dart';
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
    expect(find.byTooltip('Approva la richiesta di Mario Rossi'), findsOneWidget);
    expect(find.byTooltip('Rifiuta la richiesta di Mario Rossi'), findsOneWidget);
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

  testWidgets('busy replaces both actions with a spinner', (tester) async {
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

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Approva'), findsNothing);
    expect(find.text('Rifiuta'), findsNothing);
    expect(approved, 0);
    expect(rejected, 0);
  });
}
