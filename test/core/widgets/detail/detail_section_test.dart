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
}
