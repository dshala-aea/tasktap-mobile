import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/core/widgets/lookup_field.dart';

/// One field per fact, instead of a picker plus a mode switch plus a plain field.
///
/// The rapportino used to ask the technician to decide, before typing a character, whether the
/// customer they were about to name existed in the local cache — and to press a different button
/// depending on the answer. That is the one thing they cannot know in advance, and getting it
/// wrong meant re-typing into the other control.
///
/// These tests pin the behaviour that removes the decision: type freely, pick a match if one
/// appears, keep the text if none does, and never end up holding an id that no longer matches
/// what is written in the box.
void main() {
  const items = [
    LookupItem(id: 'c1', name: 'Rossi Impianti Srl', subtitle: 'Milano'),
    LookupItem(id: 'c2', name: 'Bianchi Termotecnica'),
    LookupItem(id: 'c3', name: 'Verdi Elettrica'),
  ];

  late String? selected;
  late String? freeText;

  Future<void> pump(
    WidgetTester tester, {
    List<LookupItem> data = items,
    String? selectedId,
    String? initialText,
  }) async {
    selected = null;
    freeText = null;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppLookupField(
            label: 'Cliente',
            items: data,
            selectedId: selectedId,
            initialText: initialText,
            onSelected: (id) => selected = id,
            onFreeText: (v) => freeText = v,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> typeInto(WidgetTester tester, String text) async {
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), text);
    await tester.pumpAndSettle();
  }

  group('finding a record', () {
    testWidgets('typing narrows the cache to matches', (tester) async {
      await pump(tester);
      await typeInto(tester, 'ross');

      expect(find.text('Rossi Impianti Srl'), findsOneWidget);
      expect(find.text('Bianchi Termotecnica'), findsNothing);
    });

    testWidgets('matching is case-insensitive and matches anywhere in the name', (tester) async {
      // A technician types what they remember, which is rarely the leading word of the registered
      // company name.
      await pump(tester);
      await typeInto(tester, 'IMPIANTI');

      expect(find.text('Rossi Impianti Srl'), findsOneWidget);
    });

    testWidgets('the subtitle is searchable too', (tester) async {
      await pump(tester);
      await typeInto(tester, 'milano');

      expect(find.text('Rossi Impianti Srl'), findsOneWidget);
    });

    testWidgets('focusing with an empty field offers the list to browse', (tester) async {
      // Someone who cannot spell the name still has to be able to get to it.
      await pump(tester);
      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();

      expect(find.text('Rossi Impianti Srl'), findsOneWidget);
      expect(find.text('Verdi Elettrica'), findsOneWidget);
    });

    testWidgets('tapping a match resolves it to an id and shows its name', (tester) async {
      await pump(tester);
      await typeInto(tester, 'ross');
      await tester.tap(find.text('Rossi Impianti Srl'));
      await tester.pumpAndSettle();

      expect(selected, 'c1');
      expect(find.widgetWithText(TextField, 'Rossi Impianti Srl'), findsOneWidget);
      // The list closes once the question is answered.
      expect(find.text('Verdi Elettrica'), findsNothing);
    });
  });

  group('keeping what was typed', () {
    testWidgets('text with no match is reported as free text, not discarded', (tester) async {
      await pump(tester);
      await typeInto(tester, 'Officina nuova, non ancora in anagrafica');

      expect(freeText, 'Officina nuova, non ancora in anagrafica');
      expect(selected, isNull);
    });

    testWidgets('an empty cache is a usable text field, not a dead control', (tester) async {
      // First launch, or a technician with nothing synced. The old dropdown had nothing to show
      // and the escape hatch was a button underneath it.
      await pump(tester, data: const []);
      await typeInto(tester, 'Rossi');

      expect(freeText, 'Rossi');
      expect(tester.takeException(), isNull);
    });

    testWidgets('free text already on the draft is shown when reopened', (tester) async {
      await pump(tester, initialText: 'Nome scritto a mano');

      expect(find.widgetWithText(TextField, 'Nome scritto a mano'), findsOneWidget);
    });

    testWidgets('a resolved id is rendered as its name, never as the id', (tester) async {
      await pump(tester, selectedId: 'c2');

      expect(find.widgetWithText(TextField, 'Bianchi Termotecnica'), findsOneWidget);
      expect(find.textContaining('c2'), findsNothing);
    });
  });

  group('the id can never drift from the text', () {
    testWidgets('editing a resolved pick releases the link', (tester) async {
      // The failure this prevents: a rapportino filed against Rossi while the box reads Bianchi.
      await pump(tester, selectedId: 'c1');
      await typeInto(tester, 'Bianchi');

      expect(freeText, 'Bianchi');
      // Suggestions come back, because the field is looking for a record again.
      expect(find.text('Bianchi Termotecnica'), findsOneWidget);
    });

    testWidgets('clearing empties both the text and the link', (tester) async {
      await pump(tester, selectedId: 'c1');
      await tester.tap(find.byType(IconButton));
      await tester.pumpAndSettle();

      expect(freeText, '');
      expect(find.widgetWithText(TextField, 'Rossi Impianti Srl'), findsNothing);
    });

    testWidgets('typing a full name and moving on resolves it without a second tap', (tester) async {
      await pump(tester);
      await typeInto(tester, 'Verdi Elettrica');
      // Dismiss focus the way tapping the next field would.
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();

      expect(selected, 'c3');
    });
  });

  group('the mode switch does not come back', () {
    test('no screen offers to swap between a picker and a text field', () {
      // The copy is the tell. If either string reappears, the two-control pattern has been
      // reintroduced somewhere and the decision is back on the technician.
      final offenders = <String>[];
      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final src = entity.readAsStringSync();
        if (src.contains('testo libero)') || src.contains("'Da lista'")) {
          offenders.add(entity.path.replaceAll(r'\', '/'));
        }
      }

      expect(
        offenders,
        isEmpty,
        reason: 'one field that searches and falls back, not two controls and a mode',
      );
    });

    test('no raw identifier is interpolated into a label the technician reads', () {
      // `'Collegato al ticket ${state.ticketId}'` and `KeyVal(value: state.customerId)` both put a
      // GUID where a name belongs. Resolve it or say nothing.
      final offenders = <String>[];
      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final src = entity.readAsStringSync();
        for (final pattern in [
          RegExp(r"Text\(\s*'[^']*\$\{?state\.(ticket|cantiere|customer|location)Id"),
          RegExp(r"value:\s*state\.(ticket|cantiere|customer|location)Id"),
        ]) {
          if (pattern.hasMatch(src)) offenders.add(entity.path.replaceAll(r'\', '/'));
        }
      }

      expect(offenders, isEmpty, reason: 'a GUID identifies nothing the reader can check');
    });
  });
}
