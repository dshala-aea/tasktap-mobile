import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';
import 'package:tasktap_mobile/core/widgets/app_button.dart';
import 'package:tasktap_mobile/core/widgets/empty_state.dart';

Widget _wrap(Widget child) =>
    MaterialApp(home: Scaffold(body: child));

void main() {
  group('EmptyState', () {
    testWidgets('renders icon, title, and body', (tester) async {
      await tester.pumpWidget(_wrap(
        const EmptyState(
          icon: LucideIcons.inbox,
          title: 'Nessun rapportino',
          body: 'I rapportini che crei appariranno qui.',
        ),
      ));
      expect(find.byIcon(LucideIcons.inbox), findsOneWidget);
      expect(find.text('Nessun rapportino'), findsOneWidget);
      expect(find.text('I rapportini che crei appariranno qui.'), findsOneWidget);
    });

    testWidgets('renders without body or action (minimal)', (tester) async {
      await tester.pumpWidget(_wrap(
        const EmptyState(
          icon: LucideIcons.folderOpen,
          title: 'Vuoto',
        ),
      ));
      expect(find.byIcon(LucideIcons.folderOpen), findsOneWidget);
      expect(find.text('Vuoto'), findsOneWidget);
    });

    testWidgets('renders optional action widget', (tester) async {
      bool pressed = false;
      await tester.pumpWidget(_wrap(
        EmptyState(
          icon: LucideIcons.plusCircle,
          title: 'Nessun ticket',
          action: AppButton(
            label: 'Nuovo ticket',
            onPressed: () => pressed = true,
          ),
        ),
      ));
      expect(find.text('Nuovo ticket'), findsOneWidget);
      await tester.tap(find.text('Nuovo ticket'));
      expect(pressed, isTrue);
    });

    testWidgets('is a shadow board: cut outline, no icon disc', (tester) async {
      await tester.pumpWidget(_wrap(
        const EmptyState(
          icon: LucideIcons.inbox,
          title: 'Test',
        ),
      ));

      // The 60px grey disc is gone. An empty state is now a cut silhouette — the outline of what
      // belongs in this slot — which says "something is missing" rather than "nothing here", the
      // distinction the app's third product principle exists to protect.
      expect(find.byType(CustomPaintShadowBoard), findsOneWidget);
      expect(
        find.ancestor(
          of: find.byIcon(LucideIcons.inbox),
          matching: find.byType(Container),
        ),
        findsNothing,
        reason: 'the icon should sit directly on the board, not inside a disc',
      );
    });

    testWidgets('no action widget when action not provided', (tester) async {
      await tester.pumpWidget(_wrap(
        const EmptyState(
          icon: LucideIcons.inbox,
          title: 'Nessun elemento',
          body: 'Lista vuota.',
        ),
      ));
      expect(find.byType(AppButton), findsNothing);
    });
  });
}
