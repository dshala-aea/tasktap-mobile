// dart format width=100
// test/features/ticket/reference_picker_test.dart
//
// Covers ReferencePickerField — the one picker every reference entity in the ticket wizard uses.
//
// Two things are under test and they are easy to confuse:
//   1. the widget never searches on its own: opening it is not a search, and typing searches once
//      after the debounce, not once per keystroke;
//   2. whatever the search answers, the *local* rows are never taken away from the technician.

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/reference/reference_option.dart';
import 'package:tasktap_mobile/features/ticket/reference_picker.dart';

Widget _wrap(Widget child) => MaterialApp(
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

/// The key the picker derives from its label — see [ReferencePickerField.fieldKey].
const _contrattoKey = ValueKey('reference-picker-contratto');

void main() {
  testWidgets('the local mirror is offered before anything is typed', (tester) async {
    var searched = false;
    await tester.pumpWidget(
      _wrap(
        ReferencePickerField(
          label: 'Contratto',
          localItems: const [ReferenceOption(id: 'c1', label: 'Manutenzione caldaie')],
          search: (q) async {
            searched = true;
            return const [];
          },
          onSelected: (_) {},
        ),
      ),
    );

    await tester.tap(find.byKey(_contrattoKey));
    await tester.pumpAndSettle();

    expect(find.text('Manutenzione caldaie'), findsOneWidget);
    expect(searched, isFalse, reason: 'opening the picker is not a search');
  });

  testWidgets('typing searches once after the debounce, not once per keystroke', (tester) async {
    final queries = <String>[];
    await tester.pumpWidget(
      _wrap(
        ReferencePickerField(
          label: 'Contratto',
          localItems: const [],
          search: (q) async {
            queries.add(q);
            return const [];
          },
          onSelected: (_) {},
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'man');
    await tester.pump(const Duration(milliseconds: 150));
    await tester.enterText(find.byType(TextField), 'manu');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(queries, ['manu'], reason: 'the abandoned "man" keystroke must not have searched');
  });

  /// A slow answer to an abandoned query must not replace the results of the current one.
  testWidgets('a stale answer cannot overwrite a newer one', (tester) async {
    final slow = Completer<List<ReferenceOption>>();
    await tester.pumpWidget(
      _wrap(
        ReferencePickerField(
          label: 'Contratto',
          localItems: const [],
          search: (q) async =>
              q == 'man' ? slow.future : const [ReferenceOption(id: 'c2', label: 'Manu nuovo')],
          onSelected: (_) {},
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'man');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.enterText(find.byType(TextField), 'manu');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.text('Manu nuovo'), findsOneWidget);

    // The abandoned query finally answers, long after its answer stopped being wanted.
    slow.complete(const [ReferenceOption(id: 'c1', label: 'Manu vecchio')]);
    await tester.pumpAndSettle();

    expect(find.text('Manu vecchio'), findsNothing);
    expect(find.text('Manu nuovo'), findsOneWidget);
  });

  testWidgets('a failing search keeps the local rows and says so', (tester) async {
    await tester.pumpWidget(
      _wrap(
        ReferencePickerField(
          label: 'Contratto',
          localItems: const [ReferenceOption(id: 'c1', label: 'Manutenzione caldaie')],
          search: (q) async {
            throw const SocketException('offline');
          },
          onSelected: (_) {},
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'man');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(find.text('Manutenzione caldaie'), findsOneWidget);
    expect(find.textContaining('Non in linea'), findsOneWidget);
    expect(tester.takeException(), isNull, reason: 'a dead socket is not a crash');
  });

  /// A new hire, or a technician between jobs: no open work, so no customers, so every picker is
  /// empty. It must say so and invite a search, never render as a dead field.
  testWidgets('an empty mirror says so and still invites a search', (tester) async {
    await tester.pumpWidget(
      _wrap(
        ReferencePickerField(
          label: 'Contratto',
          localItems: const [],
          search: (q) async => const [ReferenceOption(id: 'c1', label: 'Trovato')],
          onSelected: (_) {},
        ),
      ),
    );

    await tester.tap(find.byKey(_contrattoKey));
    await tester.pumpAndSettle();

    expect(find.textContaining('Nessun elemento in cache'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'tro');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(find.text('Trovato'), findsOneWidget);
  });

  testWidgets('picking an option reports exactly that option', (tester) async {
    ReferenceOption? picked;
    await tester.pumpWidget(
      _wrap(
        ReferencePickerField(
          label: 'Contratto',
          localItems: const [
            ReferenceOption(id: 'c1', label: 'Manutenzione caldaie', subtitle: 'N-1'),
          ],
          search: (q) async => const [],
          onSelected: (o) => picked = o,
        ),
      ),
    );

    await tester.tap(find.byKey(_contrattoKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Manutenzione caldaie'));
    await tester.pumpAndSettle();

    expect(picked?.id, 'c1');
    expect(picked?.subtitle, 'N-1');
  });

  testWidgets('editing the text releases the picked option', (tester) async {
    final report = <String?>[];
    await tester.pumpWidget(
      _wrap(
        ReferencePickerField(
          label: 'Contratto',
          selectedId: 'c1',
          localItems: const [ReferenceOption(id: 'c1', label: 'Manutenzione caldaie')],
          search: (q) async => const [],
          onSelected: (o) => report.add(o?.id),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'Manutenzione porte');
    await tester.pump();

    expect(report, [
      null,
    ], reason: 'keeping the old id behind new text files the ticket against the wrong contract');
  });

  testWidgets('a search result joins the local rows, it does not replace them', (tester) async {
    await tester.pumpWidget(
      _wrap(
        ReferencePickerField(
          label: 'Contratto',
          localItems: const [ReferenceOption(id: 'c1', label: 'Manutenzione caldaie')],
          search: (q) async => const [ReferenceOption(id: 'c2', label: 'Manutenzione porte')],
          onSelected: (_) {},
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'manutenzione');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(find.text('Manutenzione caldaie'), findsOneWidget);
    expect(find.text('Manutenzione porte'), findsOneWidget);
  });

  /// The server matches `q` with a case-SENSITIVE `Contains`, so this query returns nothing for a
  /// contract stored as "Manutenzione caldaie". If a search replaced the list, the row the
  /// technician is looking at would vanish mid-keystroke — the one row they can still pick while
  /// offline. Merging instead keeps it, and [AppLookupField] re-filters the merged list
  /// case-insensitively.
  testWidgets('a case-mismatched search leaves the locally matching row visible', (tester) async {
    await tester.pumpWidget(
      _wrap(
        ReferencePickerField(
          label: 'Contratto',
          localItems: const [ReferenceOption(id: 'c1', label: 'Manutenzione caldaie')],
          search: (q) async => const [],
          onSelected: (_) {},
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'manutenzione');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(find.text('Manutenzione caldaie'), findsOneWidget);
  });

  testWidgets('a disabled picker does not search', (tester) async {
    var searched = false;
    await tester.pumpWidget(
      _wrap(
        ReferencePickerField(
          label: 'Contratto',
          enabled: false,
          localItems: const [ReferenceOption(id: 'c1', label: 'Manutenzione caldaie')],
          search: (q) async {
            searched = true;
            return const [];
          },
          onSelected: (_) {},
        ),
      ),
    );

    await tester.tap(find.byKey(_contrattoKey), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(searched, isFalse);
  });
}
