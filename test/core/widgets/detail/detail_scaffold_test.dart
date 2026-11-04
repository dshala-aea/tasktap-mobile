import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/core/widgets/detail/detail_hero.dart';
import 'package:tasktap_mobile/core/widgets/detail/detail_scaffold.dart';
import 'package:tasktap_mobile/core/widgets/detail/detail_section.dart';

void main() {
  testWidgets('renders the generic header, hero and sections in order', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: DetailScaffold(
          screenTitle: 'Ticket',
          hero: DetailHeroData(
            variant: DetailHeroVariant.operational,
            title: 'Perdita acqua sotto il lavello',
            status: DetailStatus(label: 'Aperto'),
          ),
          sections: [
            DetailSectionData(title: 'Attività', child: Text('attività')),
            DetailSectionData(title: 'Sintesi', child: Text('sintesi')),
          ],
        ),
      ),
    );
    expect(find.text('Ticket'), findsOneWidget);
    expect(find.text('Perdita acqua sotto il lavello'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Attività')).dy,
      lessThan(tester.getTopLeft(find.text('Sintesi')).dy),
    );
  });

  testWidgets('skips empty sections and respects max width', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: DetailScaffold(
          screenTitle: 'Cliente',
          maxWidth: 600,
          hero: DetailHeroData(
            variant: DetailHeroVariant.summary,
            title: 'Rossi Srl',
            status: DetailStatus(label: 'Attivo'),
          ),
          sections: [
            DetailSectionData(title: 'Sintesi', child: Text('sintesi')),
            DetailSectionData(
              title: 'Documenti',
              isEmpty: true,
              child: Text('vuoto'),
            ),
          ],
        ),
      ),
    );
    expect(find.text('Documenti'), findsNothing);
    final content = tester.getSize(find.byKey(const Key('detail-content')));
    expect(content.width, lessThanOrEqualTo(600));
  });

  testWidgets(
    'collapsed bar appears after the hero scrolls away and hides on return',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: DetailScaffold(
            screenTitle: 'Ticket',
            hero: DetailHeroData(
              variant: DetailHeroVariant.operational,
              title: 'Ticket lungo',
              status: DetailStatus(label: 'In corso'),
              primaryAction: DetailAction(
                label: 'Chiudi intervento',
                onPressed: () {},
              ),
            ),
            sections: [
              DetailSectionData(
                title: 'Attività',
                child: SizedBox(height: 1200, child: Text('attività')),
              ),
            ],
          ),
        ),
      );
      expect(find.byKey(const Key('detail-collapsed-bar')), findsNothing);
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -700));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('detail-collapsed-bar')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('detail-collapsed-bar')),
          matching: find.text('Chiudi intervento'),
        ),
        findsOneWidget,
      );
      await tester.drag(find.byType(CustomScrollView), const Offset(0, 700));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('detail-collapsed-bar')), findsNothing);
    },
  );
}
