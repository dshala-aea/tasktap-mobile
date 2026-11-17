import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/core/widgets/detail/detail_section.dart';

void main() {
  testWidgets('renders the title, trailing and child', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: DetailSection(
          data: DetailSectionData(
            title: 'Sintesi',
            trailing: Text('4 campi'),
            child: Text('Contenuto'),
          ),
        ),
      ),
    );
    expect(find.text('Sintesi'), findsOneWidget);
    expect(find.text('4 campi'), findsOneWidget);
    expect(find.text('Contenuto'), findsOneWidget);
  });

  testWidgets('empty sections render nothing', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: DetailSection(
          data: DetailSectionData(
            title: 'Documenti',
            isEmpty: true,
            child: Text('non deve apparire'),
          ),
        ),
      ),
    );
    expect(find.text('Documenti'), findsNothing);
    expect(find.text('non deve apparire'), findsNothing);
  });

  testWidgets('APRI link and tappable title are at least 44px tall', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DetailSection(
            data: DetailSectionData(
              title: 'Allegati',
              onTitleTap: () {},
              trailing: DetailSectionLink(label: 'Apri', onTap: () {}),
              child: const Text('x'),
            ),
          ),
        ),
      ),
    );
    final title = tester.getSize(find.byType(InkWell).first);
    final link = tester.getSize(find.byType(InkWell).last);
    expect(title.height, greaterThanOrEqualTo(44));
    expect(link.height, greaterThanOrEqualTo(44));
    expect(link.width, greaterThanOrEqualTo(44));
  });
}
