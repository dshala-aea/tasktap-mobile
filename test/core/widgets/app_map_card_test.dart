import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/core/theme/app_theme.dart';
import 'package:tasktap_mobile/core/widgets/app_map_card.dart';

void main() {
  testWidgets(
    'AppMapCard has no BackdropFilter/gradient and shows the address',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: const Scaffold(body: AppMapCard(address: 'Via Roma 1, Milano')),
        ),
      );

      expect(find.byType(BackdropFilter), findsNothing);
      expect(find.text('Via Roma 1, Milano'), findsOneWidget);
    },
  );
}
