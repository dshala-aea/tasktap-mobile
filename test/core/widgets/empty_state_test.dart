import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons/lucide_icons.dart';
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

    testWidgets('icon container is 60x60 circle', (tester) async {
      await tester.pumpWidget(_wrap(
        const EmptyState(
          icon: LucideIcons.inbox,
          title: 'Test',
        ),
      ));
      final container = tester.widget<Container>(
        find.ancestor(
          of: find.byIcon(LucideIcons.inbox),
          matching: find.byType(Container),
        ).first,
      );
      expect(container.constraints?.maxWidth, equals(60));
      expect(container.constraints?.maxHeight, equals(60));
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
