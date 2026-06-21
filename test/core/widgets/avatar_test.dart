import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/core/widgets/avatar.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('AppAvatar — initials', () {
    testWidgets('two-word name produces two initials', (tester) async {
      await tester.pumpWidget(_wrap(const AppAvatar(name: 'Mario Rossi')));
      await tester.pump();
      expect(find.text('MR'), findsOneWidget);
    });

    testWidgets('single word name produces one initial', (tester) async {
      await tester.pumpWidget(_wrap(const AppAvatar(name: 'Giovanni')));
      await tester.pump();
      expect(find.text('G'), findsOneWidget);
    });

    testWidgets('email address renders without error', (tester) async {
      await tester.pumpWidget(_wrap(const AppAvatar(name: 'mario@example.com')));
      await tester.pump();
      expect(tester.takeException(), isNull);
      // Splits on @, ., space — produces initials from first and last part
      // 'mario@example.com' → parts ['mario','example','com'] → 'MC'
      expect(find.text('MC'), findsOneWidget);
    });

    testWidgets('empty name shows fallback ?', (tester) async {
      await tester.pumpWidget(_wrap(const AppAvatar(name: '')));
      await tester.pump();
      expect(find.text('?'), findsOneWidget);
    });
  });

  group('AppAvatar — size', () {
    testWidgets('default size is 36', (tester) async {
      await tester.pumpWidget(_wrap(const AppAvatar(name: 'Test User')));
      await tester.pump();
      final sizedBox = tester.widget<SizedBox>(
        find.descendant(
          of: find.byType(AppAvatar),
          matching: find.byType(SizedBox),
        ).first,
      );
      expect(sizedBox.width, equals(36));
      expect(sizedBox.height, equals(36));
    });

    testWidgets('custom size 48 is respected', (tester) async {
      await tester.pumpWidget(_wrap(const AppAvatar(name: 'Test User', size: 48)));
      await tester.pump();
      final sizedBox = tester.widget<SizedBox>(
        find.descendant(
          of: find.byType(AppAvatar),
          matching: find.byType(SizedBox),
        ).first,
      );
      expect(sizedBox.width, equals(48));
      expect(sizedBox.height, equals(48));
    });
  });

  group('AppAvatar — color cycle', () {
    testWidgets('different names produce a circle avatar', (tester) async {
      for (final name in ['Alice', 'Bob', 'Carlo', 'Diana', 'Enrico', 'Francesca']) {
        await tester.pumpWidget(_wrap(AppAvatar(name: name)));
        await tester.pump();
        expect(find.byType(AppAvatar), findsOneWidget);
        expect(find.byType(DecoratedBox), findsWidgets);
      }
    });
  });
}
