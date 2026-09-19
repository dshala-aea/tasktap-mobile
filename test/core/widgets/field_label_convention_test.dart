import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/core/theme/theme.dart';
import 'package:tasktap_mobile/core/widgets/app_text_field.dart';

/// Every field labels itself the same way: static text above, never a floating Material label.
///
/// The floating label is the loudest dated tell in a Flutter app — it starts as placeholder text,
/// animates up on focus, and notches itself into the outline. It also forces the heavy box: the
/// notch needs four sides of mid-weight border to cut into, which is why every form in the app
/// used to be a column of competing rectangles.
///
/// Static labels read the same whether the field is empty, focused or full, which is what matters
/// on a form filled in a van, and they let the field itself go quiet.
void main() {
  test('no screen floats a Material label', () {
    // Includes dropdowns and date pickers: a form where the text fields label from above and the
    // dropdown beside them notches into a border reads worse than either choice made
    // consistently. AppFieldShell exists so any input can take the same treatment.
    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      if (entity.readAsStringSync().contains('labelText:')) {
        offenders.add(entity.path.replaceAll(r'\', '/'));
      }
    }

    expect(offenders, isEmpty, reason: 'label above the field — use AppTextField or AppFieldShell');
  });

  testWidgets('the label is above the input, not inside it', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: const Scaffold(
          body: Padding(
            padding: EdgeInsets.all(16),
            child: AppTextField(label: 'Cliente', hint: 'Cerca o scrivi il nome'),
          ),
        ),
      ),
    );

    final labelBottom = tester.getRect(find.byType(AppFieldLabel)).bottom;
    final fieldTop = tester.getRect(find.byType(TextFormField)).top;
    expect(labelBottom, lessThanOrEqualTo(fieldTop));
  });

  testWidgets('a required field marks itself in colour, not with one more grey character', (
    tester,
  ) async {
    // Scanning down a column of labels, a grey asterisk is invisible; the colour is the whole
    // point of marking it at all.
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: const Scaffold(
          body: Padding(
            padding: EdgeInsets.all(16),
            child: AppTextField(label: 'Cliente *'),
          ),
        ),
      ),
    );

    final label = tester.widget<Text>(
      find.descendant(of: find.byType(AppFieldLabel), matching: find.byType(Text)),
    );
    final spans = (label.textSpan! as TextSpan).children!;
    expect(spans, hasLength(1), reason: 'the asterisk is its own span');
    expect((spans.first as TextSpan).text, ' *');
    expect((spans.first as TextSpan).style?.color, isNot(equals(label.textSpan!.style?.color)));
  });

  testWidgets('the label is upper-cased and does not carry the asterisk twice', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: const Scaffold(
          body: Padding(
            padding: EdgeInsets.all(16),
            child: AppTextField(label: 'Cliente *'),
          ),
        ),
      ),
    );

    final label = tester.widget<Text>(
      find.descendant(of: find.byType(AppFieldLabel), matching: find.byType(Text)),
    );
    expect((label.textSpan! as TextSpan).text, 'CLIENTE');
  });
}
