import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';
import 'package:tasktap_mobile/core/theme/app_vetro_palette.dart';
import 'package:tasktap_mobile/core/widgets/app_button.dart';
import 'package:tasktap_mobile/core/widgets/empty_state.dart';
import 'package:tasktap_mobile/core/widgets/vetro_card.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('EmptyState', () {
    testWidgets('renders icon, title, and body', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const EmptyState(
            icon: LucideIcons.inbox,
            title: 'Nessun rapportino',
            body: 'I rapportini che crei appariranno qui.',
          ),
        ),
      );
      expect(find.byIcon(LucideIcons.inbox), findsOneWidget);
      expect(find.text('Nessun rapportino'), findsOneWidget);
      expect(find.text('I rapportini che crei appariranno qui.'), findsOneWidget);
    });

    testWidgets('renders without body or action (minimal)', (tester) async {
      await tester.pumpWidget(
        _wrap(const EmptyState(icon: LucideIcons.folderOpen, title: 'Vuoto')),
      );
      expect(find.byIcon(LucideIcons.folderOpen), findsOneWidget);
      expect(find.text('Vuoto'), findsOneWidget);
    });

    testWidgets('renders optional action widget', (tester) async {
      bool pressed = false;
      await tester.pumpWidget(
        _wrap(
          EmptyState(
            icon: LucideIcons.plusCircle,
            title: 'Nessun ticket',
            action: AppButton(label: 'Nuovo ticket', onPressed: () => pressed = true),
          ),
        ),
      );
      expect(find.text('Nuovo ticket'), findsOneWidget);
      await tester.tap(find.text('Nuovo ticket'));
      expect(pressed, isTrue);
    });

    testWidgets('is a Vetro glass card with a tint-badged icon', (tester) async {
      await tester.pumpWidget(_wrap(const EmptyState(icon: LucideIcons.inbox, title: 'Test')));

      // Was a dashed cut-silhouette (the van-racking metaphor's "shadow board") — now the same
      // glass-card language VetroCard/VetroCompartmentTile use everywhere else, with the icon in
      // a tinted circular badge rather than sitting bare or inside a grey disc.
      expect(find.byType(VetroCard), findsOneWidget);
      final badge = tester.widget<VetroStateIconBadge>(find.byType(VetroStateIconBadge));
      expect(badge.tint, AppVetroColors.tint);
    });

    testWidgets('no action widget when action not provided', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const EmptyState(icon: LucideIcons.inbox, title: 'Nessun elemento', body: 'Lista vuota.'),
        ),
      );
      expect(find.byType(AppButton), findsNothing);
    });
  });

  group('CompactEmptyState', () {
    testWidgets('names what is missing, and reads it out as one phrase', (tester) async {
      final handle = tester.ensureSemantics();

      await tester.pumpWidget(
        _wrap(
          const CompactEmptyState(
            label: 'Nessun rapportino in coda',
            reason: 'La sincronizzazione non è ancora riuscita.',
          ),
        ),
      );

      expect(find.text('Nessun rapportino in coda'), findsOneWidget);
      expect(find.text('La sincronizzazione non è ancora riuscita.'), findsOneWidget);
      expect(
        tester.getSemantics(find.byType(CompactEmptyState)),
        matchesSemantics(
          label: 'Nessun rapportino in coda. La sincronizzazione non è ancora riuscita.',
        ),
      );

      handle.dispose();
    });

    testWidgets('an ordinary empty slot states no reason', (tester) async {
      await tester.pumpWidget(_wrap(const CompactEmptyState(label: 'Nessun materiale')));

      expect(find.text('Nessun materiale'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('is a Vetro glass card, not the old dashed silhouette', (tester) async {
      await tester.pumpWidget(
        _wrap(const CompactEmptyState(label: 'Nessuno', icon: LucideIcons.inbox)),
      );

      expect(find.byType(VetroCard), findsOneWidget);
      expect(find.byType(VetroStateIconBadge), findsOneWidget);
    });
  });
}
